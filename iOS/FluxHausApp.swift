//
//  FluxHausApp.swift
//  Shared
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI
import UIKit
import UserNotifications
import os

private let appLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "FluxHausApp")

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Store APNs device token for deferred registration
    static var pendingApnsToken: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Request notification permission — required for push notifications and live activities
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                appLogger.error("Notification authorization error: \(error)")
            }
            appLogger.info("Notification authorization granted: \(granted)")
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        appLogger.info("Registered for remote notifications: \(token.prefix(8))...")
        AppDelegate.pendingApnsToken = token
        Task { await AppDelegate.registerApnsTokenIfReady() }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        appLogger.error("Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        appLogger.info("Received background remote notification")

        // When woken by a silent push, refresh data and update Live Activities
        guard AuthManager.shared.isSignedIn else {
            completionHandler(.noData)
            return
        }

        Task {
            _ = await AuthManager.shared.ensureValidToken()
            queryFlux(password: WhereWeAre.getPassword() ?? "")
            completionHandler(.newData)
        }
    }

    /// Register the stored APNs token with the server. Called on token receipt and after auth.
    static func registerApnsTokenIfReady() async {
        guard let token = pendingApnsToken,
              AuthManager.shared.authorizationHeader() != nil else { return }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/push-tokens/apns"

        guard let url = components.url else { return }

        let csrfToken = await fetchCsrfToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let authHeader = AuthManager.shared.authorizationHeader() {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        if let csrfToken = csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }

        do {
            let name = await MainActor.run { UIDevice.current.name }
            let body: [String: String] = [
                "token": token,
                "deviceName": name
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let session = URLSession(configuration: .default)
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                pendingApnsToken = nil
                appLogger.info("APNs token registered with server")
            }
        } catch {
            appLogger.error("Failed to register APNs token: \(error)")
        }
    }
}

@MainActor var hconn: HomeConnect?
@MainActor var miele: Miele?
@MainActor var robots: Robots?
@MainActor var battery: Battery?
@MainActor var car: Car?
@MainActor var scooter: Scooter?

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
                                // Register APNs token now that auth is available
                                Task { await AppDelegate.registerApnsTokenIfReady() }
                                // Retry any deferred push-to-start token registration
                                #if !targetEnvironment(macCatalyst)
                                LiveActivityManager.shared.retryPendingTokenRegistration()
                                #endif
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
                                    // Only clear keychain for auth-related failures, not network errors
                                    let isAuthFailure = errMsg.lowercased().contains("password") ||
                                                       errMsg.lowercased().contains("incorrect") ||
                                                       errMsg.lowercased().contains("unauthorized") ||
                                                       errMsg.lowercased().contains("failed to load data")
                                    if isAuthFailure {
                                        appLogger.warning("Clearing keychain due to auth failure: \(errMsg)")
                                        whereWeAre.deleteKeyChainPasword()
                                    } else {
                                        appLogger.warning("Not clearing keychain for transient error: \(errMsg)")
                                    }
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
                } else if let hconn, let miele, let robots, let car, let scooter {
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
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.dataUpdated)) { object in
                        if let response = object.userInfo?["data"] as? LoginResponse {
                            guard AuthManager.shared.isSignedIn else { return }
                            self.apiResponse.setApiResponse(apiResponse: response)
                            robots.setApiResponse(apiResponse: self.apiResponse)
                            hconn.setApiResponse(apiResponse: self.apiResponse)
                            miele.setApiResponse(apiResponse: self.apiResponse)
                            car.setApiResponse(apiResponse: self.apiResponse)
                            scooter.setApiResponse(apiResponse: self.apiResponse)
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
            .onReceive(
                NotificationCenter.default.publisher(for: .authDidSignOut)
            ) { _ in
                self.whereWeAre = WhereWeAre()
                hconn = nil
                miele = nil
                robots = nil
                car = nil
                scooter = nil
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    guard !AuthManager.shared.isCompletingOIDCLogin else { return }
                    Task {
                        _ = await AuthManager.shared.ensureValidToken()
                        if AuthManager.shared.isSignedIn {
                            queryFlux(password: WhereWeAre.getPassword() ?? "")
                        }
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
                Button("Scooter") { postNavigation("scooter") }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Appliances") { postNavigation("appliances") }
                    .keyboardShortcut("6", modifiers: .command)

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

    func loadScooter() {
        scooter = Scooter()
        scooter?.setApiResponse(apiResponse: self.apiResponse)
    }

    func updateLiveActivities(response: LoginResponse) {
        #if !targetEnvironment(macCatalyst)
        let fluxData = convertLoginResponseToAppData(response: response)
        let devices = convertDataToWidgetDevices(fluxData: fluxData)
        Task { await LiveActivityManager.shared.reconcile(devices: devices) }
        #endif
    }

    private func postNavigation(_ section: String) {
        NotificationCenter.default.post(
            name: Notification.Name("navigateToSection"),
            object: nil,
            userInfo: ["section": section]
        )
    }
}
