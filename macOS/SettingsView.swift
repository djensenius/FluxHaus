//
//  SettingsView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI
import Carbon

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
            Toggle("Show in Menu Bar", isOn: $showMenuBar)
            Picker("Quick Chat Shortcut", selection: $quickChatShortcutRawValue) {
                ForEach(QuickChatShortcut.allCases) { shortcut in
                    Text(shortcut.title).tag(shortcut.rawValue)
                }
            }
            Text(
                "Use the quick chat shortcut to open a lightweight assistant window "
                    + "while FluxHaus stays available in the menu bar."
            )
            .font(Theme.Fonts.caption)
            .foregroundColor(Theme.Colors.textSecondary)
            Button("Open Quick Chat") {
                NotificationCenter.default.post(name: .quickChatRequested, object: nil)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
