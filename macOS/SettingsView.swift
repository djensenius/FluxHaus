//
//  SettingsView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI
import AppKit
import Carbon

struct QuickChatShortcut: Equatable {
    private struct Payload: Codable {
        let keyCode: UInt32?
        let carbonModifiers: UInt32?
        let displayKey: String?
    }

    let keyCode: UInt32?
    let carbonModifiers: UInt32?
    let displayKey: String?

    static let defaultShortcut = QuickChatShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey),
        displayKey: "␣"
    )

    static let disabled = QuickChatShortcut(
        keyCode: nil,
        carbonModifiers: nil,
        displayKey: nil
    )

    var rawValue: String {
        guard !isDisabled else { return "disabled" }
        let payload = Payload(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers,
            displayKey: displayKey
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            return "disabled"
        }
        return "custom:\(data.base64EncodedString())"
    }

    var title: String {
        guard !isDisabled, let displayKey else { return "Disabled" }
        return "\(Self.modifierSymbols(for: carbonModifiers ?? 0))\(displayKey)"
    }

    var isDisabled: Bool {
        keyCode == nil || carbonModifiers == nil
    }

    static func fromStored(_ rawValue: String) -> QuickChatShortcut {
        switch rawValue {
        case "optionSpace":
            return defaultShortcut
        case "shiftCommandSpace":
            return QuickChatShortcut(
                keyCode: UInt32(kVK_Space),
                carbonModifiers: UInt32(shiftKey | cmdKey),
                displayKey: "␣"
            )
        case "controlSpace":
            return QuickChatShortcut(
                keyCode: UInt32(kVK_Space),
                carbonModifiers: UInt32(controlKey),
                displayKey: "␣"
            )
        case "optionCommandSpace":
            return QuickChatShortcut(
                keyCode: UInt32(kVK_Space),
                carbonModifiers: UInt32(optionKey | cmdKey),
                displayKey: "␣"
            )
        case "disabled":
            return disabled
        default:
            guard rawValue.hasPrefix("custom:"),
                  let data = Data(base64Encoded: String(rawValue.dropFirst(7))),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                return defaultShortcut
            }
            return QuickChatShortcut(
                keyCode: payload.keyCode,
                carbonModifiers: payload.carbonModifiers,
                displayKey: payload.displayKey
            )
        }
    }

    static func fromEvent(_ event: NSEvent) -> QuickChatShortcut? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return nil }
        guard let displayKey = displayKey(for: event) else { return nil }
        return QuickChatShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            displayKey: displayKey
        )
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let deviceIndependentFlags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if deviceIndependentFlags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        if deviceIndependentFlags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if deviceIndependentFlags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if deviceIndependentFlags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        return result
    }

    private static func modifierSymbols(for modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        return parts.joined()
    }

    private static func displayKey(for event: NSEvent) -> String? {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Space): "␣",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_Escape): "⎋",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_Home): "↖",
            UInt16(kVK_End): "↘",
            UInt16(kVK_PageUp): "⇞",
            UInt16(kVK_PageDown): "⇟",
            UInt16(kVK_Help): "Help",
            UInt16(kVK_F1): "F1",
            UInt16(kVK_F2): "F2",
            UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5",
            UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7",
            UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10",
            UInt16(kVK_F11): "F11",
            UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13",
            UInt16(kVK_F14): "F14",
            UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16",
            UInt16(kVK_F17): "F17",
            UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19",
            UInt16(kVK_F20): "F20"
        ]
        if let specialKey = specialKeys[event.keyCode] {
            return specialKey
        }
        if let translatedCharacter = baseDisplayKey(for: event.keyCode) {
            return translatedCharacter
        }
        guard let characters = event.charactersIgnoringModifiers?
            .folding(options: .caseInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !characters.isEmpty else {
            return nil
        }
        return characters.count == 1 ? characters.uppercased() : characters.capitalized
    }

    private static func baseDisplayKey(for keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(
                  inputSource,
                  kTISPropertyUnicodeKeyLayoutData
              ) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let keyboardLayoutData = CFDataGetBytePtr(layoutData) else {
            return nil
        }
        let keyboardLayout = keyboardLayoutData.withMemoryRebound(
            to: UCKeyboardLayout.self,
            capacity: 1
        ) { $0 }

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )

        guard status == noErr, length > 0 else {
            return nil
        }

        let string = String(utf16CodeUnits: characters, count: Int(length))
            .folding(options: .caseInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else {
            return nil
        }
        return string.count == 1 ? string.uppercased() : string.capitalized
    }
}

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcutRawValue: String

    func makeNSView(context: Context) -> ShortcutRecorderTextField {
        let textField = ShortcutRecorderTextField()
        textField.onShortcutChange = { shortcut in
            shortcutRawValue = shortcut.rawValue
        }
        textField.update(shortcut: QuickChatShortcut.fromStored(shortcutRawValue))
        return textField
    }

    func updateNSView(_ nsView: ShortcutRecorderTextField, context: Context) {
        nsView.onShortcutChange = { shortcut in
            shortcutRawValue = shortcut.rawValue
        }
        nsView.update(shortcut: QuickChatShortcut.fromStored(shortcutRawValue))
    }
}

@MainActor
final class ShortcutRecorderTextField: NSTextField {
    var onShortcutChange: ((QuickChatShortcut) -> Void)?
    private var currentShortcut = QuickChatShortcut.defaultShortcut
    private var isRecording = false {
        didSet {
            updateAppearance()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = true
        drawsBackground = true
        backgroundColor = .controlBackgroundColor
        focusRingType = .default
        alignment = .center
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        lineBreakMode = .byTruncatingMiddle
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }
        guard let shortcut = QuickChatShortcut.fromEvent(event) else {
            NSSound.beep()
            return
        }
        currentShortcut = shortcut
        onShortcutChange?(shortcut)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    func update(shortcut: QuickChatShortcut) {
        currentShortcut = shortcut
        updateAppearance()
    }

    private func updateAppearance() {
        stringValue = isRecording ? "Type shortcut" : currentShortcut.title
    }
}

struct SettingsView: View {
    @State private var selectedTab = "general"
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    @AppStorage("quickChatShortcut") private var quickChatShortcutRawValue =
        QuickChatShortcut.defaultShortcut.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gear", value: "general") {
                generalTab
            }
            Tab("Account", systemImage: "person.circle", value: "account") {
                accountTab
            }
        }
        .frame(width: 460, height: 280)
    }

    private var generalTab: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show in Menu Bar", isOn: $showMenuBar)
                Text("Keep FluxHaus available from the menu bar when the main window is closed.")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Section("Quick Chat") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Global Shortcut")
                        .font(Theme.Fonts.bodySmall)
                    ShortcutRecorderField(shortcutRawValue: $quickChatShortcutRawValue)
                        .frame(width: 240, height: 28)
                    HStack {
                        Button("Reset to Default") {
                            quickChatShortcutRawValue = QuickChatShortcut.defaultShortcut.rawValue
                        }
                        Button("Disable Shortcut") {
                            quickChatShortcutRawValue = QuickChatShortcut.disabled.rawValue
                        }
                    }
                }
                Text(
                    "Click the field, then press any modifier-based key combination to record "
                        + "a global shortcut for Quick Chat. Shifted keys keep their unshifted symbol."
                )
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                Button("Open Quick Chat") {
                    NotificationCenter.default.post(name: .quickChatRequested, object: nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: showMenuBar) {
            NotificationCenter.default.post(name: .menuBarPreferenceChanged, object: nil)
        }
        .onChange(of: quickChatShortcutRawValue) {
            let normalized = QuickChatShortcut.fromStored(quickChatShortcutRawValue).rawValue
            if normalized != quickChatShortcutRawValue {
                quickChatShortcutRawValue = normalized
                return
            }
            NotificationCenter.default.post(name: .quickChatShortcutChanged, object: nil)
        }
    }

    private var accountTab: some View {
        VStack(spacing: 16) {
            if AuthManager.shared.isSignedIn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(Theme.Colors.success)
                Text("Signed In")
                    .font(Theme.Fonts.bodyMedium)
                    .fontWeight(.semibold)
                if AuthManager.shared.getAccessToken() != nil {
                    Text("Authenticated via OIDC")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundColor(Theme.Colors.textSecondary)
                } else {
                    Text("Demo mode")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Button("Sign Out") {
                    AuthManager.shared.signOut()
                    NotificationCenter.default.post(
                        name: Notification.Name.logout,
                        object: nil,
                        userInfo: ["logout": true]
                    )
                }
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("Not Signed In")
                    .font(Theme.Fonts.bodyMedium)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
