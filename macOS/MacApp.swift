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
                            Task {
                                _ = await AuthManager.shared.ensureValidToken()
                                queryFlux(password: WhereWeAre.getPassword() ?? "")
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    NotificationCenter.default.post(
                        name: Notification.Name("newConversation"),
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Navigate") {
                Button("Dashboard") { postNavigation("Dashboard") }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Weather") { postNavigation("Weather") }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Scenes") { postNavigation("Scenes") }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Appliances") { postNavigation("Appliances") }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Car") { postNavigation("Car") }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Robots") { postNavigation("Robots") }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Assistant") { postNavigation("Assistant") }
                    .keyboardShortcut("7", modifiers: .command)

                Divider()

                Button("Refresh Data") {
                    queryFlux(password: WhereWeAre.getPassword() ?? "")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra("FluxHaus", systemImage: "house.fill", isInserted: $showMenuBar) {
            MenuBarView(
                car: car,
                robots: robots,
                miele: miele,
                hconn: hconn,
                favouriteScenes: fluxHausConsts.favouriteScenes
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
                        queryFlux(password: WhereWeAre.getPassword() ?? "")
                    }
                }
            }
        }
    }

    private func handleLoginsUpdated(_ object: NotificationCenter.Publisher.Output) {
        if ((object.userInfo?["keysComplete"]) != nil) == true {
            if object.object != nil {
                let configResponse = object.object as? LoginResponse
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

    private func postNavigation(_ section: String) {
        NotificationCenter.default.post(
            name: Notification.Name("navigateToSection"),
            object: nil,
            userInfo: ["section": section]
        )
    }

    private func handleDeepLink(_ url: URL) {
        // fluxhaus://assistant, fluxhaus://weather, etc.
        guard url.scheme == "fluxhaus" else { return }
        let section = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !section.isEmpty else { return }
        let capitalized = section.prefix(1).uppercased() + section.dropFirst()
        appLogger.info("Deep link: \(capitalized)")
        postNavigation(capitalized)
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
