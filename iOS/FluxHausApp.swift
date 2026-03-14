//
//  FluxHausApp.swift
//  Shared
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI
import UIKit
import os

private let appLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "FluxHausApp")

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        appLogger.info("Registered for remote notifications: \(token.prefix(8))...")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        appLogger.error("Failed to register for remote notifications: \(error)")
    }
}

@MainActor var hconn: HomeConnect?
@MainActor var miele: Miele?
@MainActor var robots: Robots?
@MainActor var battery: Battery?
@MainActor var car: Car?

@main
struct FluxHausApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var whereWeAre = WhereWeAre()
    @State var fluxHausConsts = FluxHausConsts()
    @State private var battery = Battery()
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
                                loadHomeConnect()
                            }
                        }
                } else if let hconn, let miele, let robots, let car {
                    ContentView(
                        fluxHausConsts: fluxHausConsts,
                        hconn: hconn,
                        miele: miele,
                        robots: robots,
                        battery: battery,
                        car: car,
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
                            robots.setApiResponse(apiResponse: self.apiResponse)
                            hconn.setApiResponse(apiResponse: self.apiResponse)
                            miele.setApiResponse(apiResponse: self.apiResponse)
                            car.setApiResponse(apiResponse: self.apiResponse)
                            updateLiveActivities(response: response)
                        }
                    }
                    .onReceive(timer) {_ in
                        if AuthManager.shared.isSignedIn {
                            Task {
                                _ = await AuthManager.shared.ensureValidToken()
                                queryFlux(password: WhereWeAre.getPassword() ?? "")
                            }
                        }
                    }
                }
            }
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        _ = await AuthManager.shared.ensureValidToken()
                    }
                }
            }
            .onOpenURL { url in
                guard url.scheme == "fluxhaus" else { return }
                let section = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !section.isEmpty else { return }
                postNavigation(section.prefix(1).uppercased() + section.dropFirst())
            }
        }
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
                Button("Home") { postNavigation("home") }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Weather") { postNavigation("weather") }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Assistant") { postNavigation("assistant") }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Car") { postNavigation("car") }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Appliances") { postNavigation("appliances") }
                    .keyboardShortcut("5", modifiers: .command)

                Divider()

                Button("Refresh Data") {
                    queryFlux(password: WhereWeAre.getPassword() ?? "")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    func loadMiele() {
        miele = Miele.init(apiResponse: self.apiResponse)
    }

    func loadHomeConnect() {
        hconn = HomeConnect.init(apiResponse: self.apiResponse)
    }

    func loadRobots() {
        robots = Robots()
        robots?.apiResponse = self.apiResponse
    }

    func loadBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func loadCar() {
        car = Car()
        car?.setApiResponse(apiResponse: self.apiResponse)
    }

    func updateLiveActivities(response: LoginResponse) {
        let fluxData = convertLoginResponseToAppData(response: response)
        let devices = convertDataToWidgetDevices(fluxData: fluxData)
        LiveActivityManager.shared.reconcile(devices: devices)
    }

    private func postNavigation(_ section: String) {
        NotificationCenter.default.post(
            name: Notification.Name("navigateToSection"),
            object: nil,
            userInfo: ["section": section]
        )
    }
}
