//
//  NotificationSettingsView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-22.
//

#if os(iOS)
import SwiftUI
import ActivityKit

struct NotificationSettingsSection: View {
    @State private var subscribedTypes: Set<String> = LiveActivityManager.shared.subscribedDeviceTypes

    private let deviceTypes: [(name: String, icon: String)] = [
        ("Dishwasher", "dishwasher"),
        ("Washer", "washer"),
        ("Dryer", "dryer"),
        ("BroomBot", "fan"),
        ("MopBot", "humidifier.and.droplets")
    ]

    private var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var body: some View {
        if !activitiesEnabled {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live Activities Disabled")
                            .font(Theme.Fonts.bodyMedium)
                            .fontWeight(.semibold)
                        Text("Enable in Settings → FluxHaus → Live Activities")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
        }

        Section {
            ForEach(deviceTypes, id: \.name) { device in
                Toggle(isOn: binding(for: device.name)) {
                    Label(device.name, systemImage: device.icon)
                }
                .tint(Theme.Colors.accent)
                .disabled(!activitiesEnabled)
            }
        } header: {
            Text("Live Activity & Push Notifications")
        } footer: {
            Text("Choose which devices show Live Activities and send push notifications when finished.")
        }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { subscribedTypes.contains(name) },
            set: { enabled in
                if enabled {
                    subscribedTypes.insert(name)
                } else {
                    subscribedTypes.remove(name)
                }
                LiveActivityManager.shared.subscribedDeviceTypes = subscribedTypes
            }
        )
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            NotificationSettingsSection()

            Section {
                Button(role: .destructive) {
                    AuthManager.shared.signOut()
                    NotificationCenter.default.post(
                        name: Notification.Name.logout,
                        object: nil,
                        userInfo: ["logout": true]
                    )
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                    Label {
                        Text("Weather data provided by \(Image(systemName: "apple.logo")) Weather")
                    } icon: {
                        Image(systemName: "cloud.sun")
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
    }
}
#endif
