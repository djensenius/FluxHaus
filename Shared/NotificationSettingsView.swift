//
//  NotificationSettingsView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-22.
//

#if os(iOS)
import SwiftUI
import ActivityKit

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            List {
                if !activitiesEnabled {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Live Activities Disabled")
                                    .font(.headline)
                                Text("Enable in Settings → FluxHaus → Live Activities")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                    Text("Live Activity Notifications")
                } footer: {
                    Text("Choose which devices show Live Activities on your Lock Screen and Dynamic Island.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
#endif
