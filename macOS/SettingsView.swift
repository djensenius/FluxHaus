//
//  SettingsView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = "general"
    @AppStorage("showMenuBarExtra") private var showMenuBar = true

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gear", value: "general") {
                generalTab
            }
            Tab("Account", systemImage: "person.circle", value: "account") {
                accountTab
            }
        }
        .frame(width: 420, height: 200)
    }

    private var generalTab: some View {
        Form {
            Toggle("Show in Menu Bar", isOn: $showMenuBar)
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
