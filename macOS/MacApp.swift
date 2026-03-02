//
//  MacApp.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI
import os

private let appLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "MacApp")

@main
struct MacApp: App {
    @State private var whereWeAre = WhereWeAre()
    @State var fluxHausConsts = FluxHausConsts()
    @State private var battery = Battery()
    @State var apiResponse = Api()
    @State private var miele: Miele?
    @State private var hconn: HomeConnect?
    @State private var robots: Robots?
    @State private var car: Car?
    @AppStorage("showMenuBarExtra") private var showMenuBar = true

    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            mainContent
                .onAppear {
                    if whereWeAre.hasKeyChainPassword && whereWeAre.loading {
                        if AuthManager.shared.isSignedIn {
                            queryFlux(password: WhereWeAre.getPassword() ?? "")
                        }
                    }
                }
        }
        .defaultSize(width: 900, height: 700)

        MenuBarExtra("FluxHaus", systemImage: "house.fill", isInserted: $showMenuBar) {
            MenuBarView(
                car: car,
                robots: robots,
                miele: miele,
                hconn: hconn,
                favouriteHomeKit: fluxHausConsts.favouriteHomeKit
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if whereWeAre.loading {
            LoginView(needLoginView: !whereWeAre.hasKeyChainPassword)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: Notification.Name.loginsUpdated
                    )
                ) { object in
                    handleLoginsUpdated(object)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: Notification.Name.dataUpdated
                    )
                ) { object in
                    handleDataUpdated(object)
                }
        } else if let hconn, let miele, let robots, let car {
            ContentView(
                fluxHausConsts: fluxHausConsts,
                hconn: hconn,
                miele: miele,
                robots: robots,
                battery: battery,
                car: car,
                apiResponse: apiResponse
            )
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name.logout
                )
            ) { object in
                if (object.userInfo?["logout"]) != nil {
                    DispatchQueue.main.async {
                        self.whereWeAre = WhereWeAre()
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name.dataUpdated
                )
            ) { object in
                if let response = object.userInfo?["data"] as? LoginResponse {
                    self.apiResponse.setApiResponse(apiResponse: response)
                    robots.setApiResponse(apiResponse: self.apiResponse)
                    hconn.setApiResponse(apiResponse: self.apiResponse)
                    miele.setApiResponse(apiResponse: self.apiResponse)
                    car.setApiResponse(apiResponse: self.apiResponse)
                }
            }
            .onReceive(timer) { _ in
                if AuthManager.shared.isSignedIn {
                    Task {
                        _ = await AuthManager.shared.ensureValidToken()
                    }
                    queryFlux(password: WhereWeAre.getPassword() ?? "")
                }
            }
        }
    }

    private func handleLoginsUpdated(_ object: NotificationCenter.Publisher.Output) {
        if ((object.userInfo?["keysComplete"]) != nil) == true {
            if object.object != nil {
                let configResponse = object.object as? LoginResponse
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
            whereWeAre.setPassword(
                password: object.userInfo!["updateKeychain"] as? String ?? ""
            )
        }
        if ((object.userInfo?["keysFailed"]) != nil) == true {
            if !AuthManager.shared.isSignedIn {
                whereWeAre.deleteKeyChainPasword()
            }
        }
        if (object.userInfo?["loginError"]) != nil {
            if !AuthManager.shared.isSignedIn {
                whereWeAre.deleteKeyChainPasword()
            }
        }
    }

    private func handleDataUpdated(_ object: NotificationCenter.Publisher.Output) {
        if let response = object.userInfo?["data"] as? LoginResponse {
            self.apiResponse.response = response
            self.miele = Miele(apiResponse: self.apiResponse)
            self.robots = Robots()
            self.robots?.apiResponse = self.apiResponse
            self.car = Car()
            self.car?.setApiResponse(apiResponse: self.apiResponse)
            self.hconn = HomeConnect(apiResponse: self.apiResponse)
        }
    }
}
