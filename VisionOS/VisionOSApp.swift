//
//  VisionOSApp.swift
//  VisionOS
//
//  Created by David Jensenius on 2024-03-03.
//

import Foundation
import SwiftUI
import os

private let appLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "VisionOSApp")

@MainActor var hconn: HomeConnect?
@MainActor var miele: Miele?
@MainActor var robots: Robots?
@MainActor var battery: Battery?
@MainActor var car: Car?
@MainActor var scooter: Scooter?

@main
struct VisionOSApp: App {

    @State private var whereWeAre = WhereWeAre()
    @State var fluxHausConsts = FluxHausConsts()
    @State var apiResponse = Api()

    @Environment(\.scenePhase) private var scenePhase
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if whereWeAre.loading == true {
                    LoadingView(needLoginView: !whereWeAre.hasKeyChainPassword)
                        .onReceive(
                            NotificationCenter.default.publisher(for: Notification.Name.loginsUpdated)
                        ) { object in
                            if ((object.userInfo?["keysComplete"]) != nil) == true {
                                if object.object != nil {
                                    let configResponse = object.object! as? LoginResponse
                                    let config = FluxHausConfig(
                                        favouriteHomeKit: configResponse?.favouriteHomeKit ?? [],
                                        favouriteScenes: configResponse?.favouriteScenes ?? []
                                    )
                                    fluxHausConsts.setConfig(config: config)
                                }
                            }

                            if ((object.userInfo?["homeConnectComplete"]) != nil) == true {
                                whereWeAre.finishedLoading()
                            }

                            if (object.userInfo?["updateKeychain"]) != nil {
                                whereWeAre.setPassword(password: object.userInfo!["updateKeychain"] as? String ?? "")
                            }

                            if ((object.userInfo?["keysFailed"]) != nil) == true {
                                appLogger.warning("keysFailed received, isSignedIn=\(AuthManager.shared.isSignedIn)")
                                if !AuthManager.shared.isSignedIn {
                                    whereWeAre.deleteKeyChainPasword()
                                }
                            }

                            if (object.userInfo?["loginError"]) != nil {
                                let errMsg = object.userInfo?["loginError"] as? String ?? "unknown"
                                let isSignedIn = AuthManager.shared.isSignedIn
                                appLogger.warning("loginError: \(errMsg), isSignedIn=\(isSignedIn)")
                                if !AuthManager.shared.isSignedIn {
                                    appLogger.warning("Clearing keychain due to loginError while signed out")
                                    whereWeAre.deleteKeyChainPasword()
                                }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.dataUpdated)) { object in
                            if let response = object.userInfo?["data"] as? LoginResponse {
                                self.apiResponse.response = response
                                loadMiele()
                                loadRobots()
                                loadBattery()
                                loadCar()
                                loadScooter()
                                loadHomeConnect()
                            }
                        }
                } else {
                    guard let hconn = hconn,
                          let miele = miele,
                          let robots = robots,
                          let battery = battery,
                          let car = car,
                          let scooter = scooter else {
                        return
                    }

                    ContentView(
                        fluxHausConsts: fluxHausConsts,
                        hconn: hconn,
                        miele: miele,
                        robots: robots,
                        battery: battery,
                        car: car,
                        scooter: scooter,
                        apiResponse: self.apiResponse
                    )
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.logout)) { object in
                        if (object.userInfo?["logout"]) != nil {
                            DispatchQueue.main.async {
                                self.whereWeAre = WhereWeAre()
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.dataUpdated)) { object in
                        if let response = object.userInfo?["data"] as? LoginResponse {
                            self.apiResponse.setApiResponse(apiResponse: response)
                            robots?.setApiResponse(apiResponse: self.apiResponse)
                            hconn?.setApiResponse(apiResponse: self.apiResponse)
                            miele?.setApiResponse(apiResponse: self.apiResponse)
                            car?.setApiResponse(apiResponse: self.apiResponse)
                            scooter?.setApiResponse(apiResponse: self.apiResponse)
                        }
                    }
                    .onReceive(timer) {_ in
                        if AuthManager.shared.isSignedIn {
                            Task {
                                _ = await AuthManager.shared.ensureValidToken()
                            }
                            queryFlux(password: WhereWeAre.getPassword() ?? "")
                        }
                    }
                }
            }
            .onAppear {
                if whereWeAre.hasKeyChainPassword && whereWeAre.loading {
                    if AuthManager.shared.isSignedIn {
                        queryFlux(password: WhereWeAre.getPassword() ?? "")
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && AuthManager.shared.isSignedIn {
                    Task {
                        _ = await AuthManager.shared.ensureValidToken()
                        queryFlux(password: WhereWeAre.getPassword() ?? "")
                    }
                }
            }
            .onOpenURL { url in
                guard url.scheme == "fluxhaus" else { return }
                let section = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !section.isEmpty else { return }
                let tab = section.prefix(1).uppercased() + section.dropFirst()
                NotificationCenter.default.post(
                    name: Notification.Name("navigateToTab"),
                    object: nil,
                    userInfo: ["tab": tab]
                )
            }
        }
        .defaultSize(width: 700, height: 1050)
    }

    func loadMiele() {
        miele = Miele.init(apiResponse: self.apiResponse)
        miele?.refresh()
    }

    func loadHomeConnect() {
        hconn = HomeConnect.init(apiResponse: self.apiResponse)
    }

    func loadRobots() {
        robots = Robots()
        robots?.setApiResponse(apiResponse: self.apiResponse)
    }

    func loadBattery() {
        battery = Battery()
    }

    func loadCar() {
        car = Car()
        car?.setApiResponse(apiResponse: self.apiResponse)
    }

    func loadScooter() {
        scooter = Scooter()
        scooter?.setApiResponse(apiResponse: self.apiResponse)
    }
}
