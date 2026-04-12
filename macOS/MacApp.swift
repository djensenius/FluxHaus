//
//  MacApp.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

// swiftlint:disable file_length

import SwiftUI
import AppKit
import Carbon
import os

private let appLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "MacApp")
private let quickChatShortcutDefaultsKey = "quickChatShortcut"
private let showMenuBarExtraDefaultsKey = "showMenuBarExtra"
private let quickChatHotKeySignature: OSType = 0x464C5848 // FLXH

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onPress: (() -> Void)?

    private init() {
        installEventHandler()
    }

    func updateRegistration(for shortcut: QuickChatShortcut) {
        unregister()
        guard let keyCode = shortcut.keyCode,
              let modifiers = shortcut.carbonModifiers else { return }
        let hotKeyID = EventHotKeyID(signature: quickChatHotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            appLogger.error("Failed to register quick chat hotkey: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                handleQuickChatHotKeyEvent(event, userData: userData)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            appLogger.error("Failed to install quick chat hotkey handler: \(status)")
        }
    }

    fileprivate func handleHotKeyPress() {
        onPress?()
    }
}

private func handleQuickChatHotKeyEvent(
    _ event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else {
        return status
    }
    guard hotKeyID.signature == quickChatHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData)
        .takeUnretainedValue()
    Task { @MainActor in
        manager.handleHotKeyPress()
    }
    return noErr
}

@MainActor
final class QuickChatWindowController: NSWindowController {
    init(chat: Chat) {
        let rootView = ChatView(chat: chat, style: .quick)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSPanel(
            contentViewController: hostingController
        )
        window.title = "Quick Chat"
        window.setContentSize(NSSize(width: 720, height: 560))
        window.minSize = NSSize(width: 560, height: 420)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.identifier = NSUserInterfaceItemIdentifier("QuickChatWindow")
        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.center()
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private weak var sharedChat: Chat?
    private var quickChatWindowController: QuickChatWindowController?
    private var observers: [NSObjectProtocol] = []
    private var shouldFullyTerminate = false

    func configure(sharedChat: Chat) {
        self.sharedChat = sharedChat
        if quickChatWindowController == nil {
            quickChatWindowController = QuickChatWindowController(chat: sharedChat)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.string(forKey: quickChatShortcutDefaultsKey) == nil {
            UserDefaults.standard.set(
                QuickChatShortcut.defaultShortcut.rawValue,
                forKey: quickChatShortcutDefaultsKey
            )
        }
        GlobalHotKeyManager.shared.onPress = { [weak self] in
            Task { @MainActor [weak self] in
                self?.presentQuickChatWindow()
            }
        }
        registerObservers()
        updateQuickChatShortcutRegistration()
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GlobalHotKeyManager.shared.unregister()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard shouldFullyTerminate || !isMenuBarResident else {
            dismissMainInterface()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        presentMainApp()
        return true
    }

    func requestFullQuit() {
        performFullQuit()
    }

    private var isMenuBarResident: Bool {
        UserDefaults.standard.object(forKey: showMenuBarExtraDefaultsKey) as? Bool ?? true
    }

    private func registerObservers() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .quickChatRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.presentQuickChatWindow()
                }
            },
            center.addObserver(
                forName: .quickChatShortcutChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateQuickChatShortcutRegistration()
                }
            },
            center.addObserver(
                forName: .fullQuitRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.performFullQuit()
                }
            },
            center.addObserver(
                forName: .openMainAppRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let section = notification.userInfo?["section"] as? String
                Task { @MainActor [weak self] in
                    self?.presentMainApp(section: section)
                }
            },
            center.addObserver(
                forName: .menuBarPreferenceChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMenuBarPreferenceChanged()
                }
            }
        ]
    }

    private func updateQuickChatShortcutRegistration() {
        let rawValue = UserDefaults.standard.string(forKey: quickChatShortcutDefaultsKey)
            ?? QuickChatShortcut.defaultShortcut.rawValue
        let shortcut = QuickChatShortcut.fromStored(rawValue)
        GlobalHotKeyManager.shared.updateRegistration(for: shortcut)
    }

    private func presentQuickChatWindow() {
        guard let sharedChat else { return }
        if quickChatWindowController == nil {
            quickChatWindowController = QuickChatWindowController(chat: sharedChat)
        }
        quickChatWindowController?.present()
    }

    private func presentMainApp(section: String? = nil) {
        restoreDockPresence()
        restorePrimaryWindows()
        NSApp.activate(ignoringOtherApps: true)
        if let section {
            NotificationCenter.default.post(
                name: Notification.Name("navigateToSection"),
                object: nil,
                userInfo: ["section": section]
            )
        }
    }

    private func handleMenuBarPreferenceChanged() {
        restoreDockPresence()
    }

    private func enterResidentMode() {
        guard isMenuBarResident else { return }
        _ = NSApp.setActivationPolicy(.accessory)
    }

    private func restoreDockPresence() {
        _ = NSApp.setActivationPolicy(.regular)
    }

    private func dismissMainInterface() {
        enterResidentMode()
        primaryWindows.forEach { window in
            window.orderOut(nil)
        }
        NSApp.deactivate()
    }

    private func restorePrimaryWindows() {
        if primaryWindows.isEmpty {
            NSApp.unhide(nil)
            return
        }
        primaryWindows.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var primaryWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.identifier?.rawValue != "QuickChatWindow"
        }
    }

    private func performFullQuit() {
        shouldFullyTerminate = true
        NSApp.terminate(nil)
    }
}

@main
struct MacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var whereWeAre = WhereWeAre()
    @State var fluxHausConsts = FluxHausConsts()
    @State private var battery = Battery()
    @State var apiResponse = Api()
    @State private var miele: Miele?
    @State private var hconn: HomeConnect?
    @State private var robots: Robots?
    @State private var car: Car?
    @State private var chat = Chat()
    @State private var scooter: Scooter?
    @AppStorage("showMenuBarExtra") private var showMenuBar = true

    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            mainContent
                .onAppear {
                    appDelegate.configure(sharedChat: chat)
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
                Button("Scooter") { postNavigation("Scooter") }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Robots") { postNavigation("Robots") }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Assistant") { postNavigation("Assistant") }
                    .keyboardShortcut("8", modifiers: .command)

                Divider()

                Button("Refresh Data") {
                    queryFlux(password: WhereWeAre.getPassword() ?? "")
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(after: .appTermination) {
                Divider()
                Button("Quit FluxHaus Completely") {
                    appDelegate.requestFullQuit()
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
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
        } else if let hconn, let miele, let robots, let car, let scooter {
            ContentView(
                fluxHausConsts: fluxHausConsts,
                hconn: hconn,
                miele: miele,
                robots: robots,
                battery: battery,
                car: car,
                scooter: scooter,
                apiResponse: apiResponse,
                chat: chat
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
                    scooter.setApiResponse(apiResponse: self.apiResponse)
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
            self.scooter = Scooter()
            self.scooter?.setApiResponse(apiResponse: self.apiResponse)
            self.hconn = HomeConnect(apiResponse: self.apiResponse)
        }
    }
}
