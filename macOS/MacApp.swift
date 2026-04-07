//
//  MacApp.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI
import AppKit
import Carbon
import os

private let appLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "MacApp")
private let quickChatShortcutDefaultsKey = "quickChatShortcut"
private let showMenuBarExtraDefaultsKey = "showMenuBarExtra"
private let quickChatHotKeySignature: OSType = 0x464C5848 // FLXH

enum QuickChatShortcut: String, CaseIterable, Identifiable {
    case optionSpace
    case shiftCommandSpace
    case controlSpace
    case optionCommandSpace
    case disabled

    static let defaultShortcut: QuickChatShortcut = .optionSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace:
            "Option+Space"
        case .shiftCommandSpace:
            "Shift+Command+Space"
        case .controlSpace:
            "Control+Space"
        case .optionCommandSpace:
            "Option+Command+Space"
        case .disabled:
            "Disabled"
        }
    }

    var keyCode: UInt32? {
        guard self != .disabled else { return nil }
        return UInt32(kVK_Space)
    }

    var carbonModifiers: UInt32? {
        switch self {
        case .optionSpace:
            UInt32(optionKey)
        case .shiftCommandSpace:
            UInt32(shiftKey | cmdKey)
        case .controlSpace:
            UInt32(controlKey)
        case .optionCommandSpace:
            UInt32(optionKey | cmdKey)
        case .disabled:
            nil
        }
    }

    static func fromStored(_ rawValue: String) -> QuickChatShortcut {
        QuickChatShortcut(rawValue: rawValue) ?? .defaultShortcut
    }
}

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onPress: (() -> Void)?

    private init() {
        installEventHandler()
    }

    deinit {
        unregister()
    }

    func updateRegistration(for shortcut: QuickChatShortcut) {
        unregister()
        guard let keyCode = shortcut.keyCode,
              let modifiers = shortcut.carbonModifiers else { return }
        var hotKeyID = EventHotKeyID(signature: quickChatHotKeySignature, id: 1)
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
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Quick Chat"
        window.setContentSize(NSSize(width: 720, height: 560))
        window.minSize = NSSize(width: 560, height: 420)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
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
            self?.presentQuickChatWindow()
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
            sender.hide(nil)
            return .terminateCancel
        }
        return .terminateNow
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
                self?.presentQuickChatWindow()
            },
            center.addObserver(
                forName: .quickChatShortcutChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateQuickChatShortcutRegistration()
            },
            center.addObserver(
                forName: .fullQuitRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.performFullQuit()
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
