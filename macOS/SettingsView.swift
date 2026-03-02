//
//  SettingsView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = "account"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Account", systemImage: "person.circle", value: "account") {
                accountTab
            }
            Tab("General", systemImage: "gear", value: "general") {
                generalTab
            }
        }
        .frame(width: 400, height: 250)
    }

    private var accountTab: some View {
        VStack(spacing: 16) {
            if AuthManager.shared.isSignedIn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(Theme.Colors.success)
                Text("Signed In")
                    .font(Theme.Fonts.bodyMedium)
                if AuthManager.shared.getAccessToken() != nil {
                    Text("Authenticated via OIDC")
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                } else {
                    Text("Demo mode")
                        .font(Theme.Fonts.caption)
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
                .buttonStyle(.glass)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("Not Signed In")
                    .font(Theme.Fonts.bodyMedium)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generalTab: some View {
        Form {
            Text("General settings will appear here.")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
