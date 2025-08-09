//
//  VisionOSApp.swift
//  VisionOS
//
//  Created by David Jensenius on 2024-03-03.
//

import Foundation
import SwiftUI

@MainActor var hconn: HomeConnect?
@MainActor var miele: Miele?
@MainActor var robots: Robots?
@MainActor var battery: Battery?
@MainActor var car: Car?

@main
struct VisionOSApp: App {

    @State private var whereWeAre = WhereWeAre()
    @State var fluxHausConsts = FluxHausConsts()
    @State var apiResponse = Api()

    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            if whereWeAre.loading == true {
                LoadingView(needLoginView: !whereWeAre.hasKeyChainPassword)
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.loginsUpdated)) { object in
                        if ((object.userInfo?["keysComplete"]) != nil) == true {
                            if object.object != nil {
                                let configResponse = object.object! as? LoginResponse
                                let config = FluxHausConfig(
                                    favouriteHomeKit: configResponse?.favouriteHomeKit ?? []
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
                            whereWeAre.deleteKeyChainPasword()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.dataUpdated)) { object in
                        if let response = object.userInfo?["data"] as? LoginResponse {
                            self.apiResponse.response = response
                            loadMiele()
                            loadRobots()
                            loadBattery()
                            loadCar()
                            loadHomeConnect()
                        }
                    }
            } else {
                ContentView(
                    fluxHausConsts: fluxHausConsts,
                    hconn: hconn!,
                    miele: miele!,
                    robots: robots!,
                    battery: battery!,
                    car: car!,
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
                    }
                }
                .onReceive(timer) {_ in
                    let password = WhereWeAre.getPassword()
                    queryFlux(password: password!, user: nil)
                }
            }
        }
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
}
