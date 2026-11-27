//
//  PlacementConfig.swift
//  FluxHaus
//
//  The thermostat setup sent with placement insights: model, per-session persistence and editor.
//

import SwiftUI

/// The owner's Ecobee comfort-setting sensor participation and Follow Me choice.
/// HomeKit doesn't expose these, so they're configured in the app and sent with the request.
struct PlacementConfig: Codable, Equatable, Sendable {
    enum Setting: String, CaseIterable, Codable, Identifiable, Sendable {
        case home, sleep, away

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var home: Set<String>
    var sleep: Set<String>
    var away: Set<String>
    var followMe: Bool

    /// Ecobee's default: every sensor participates in every comfort setting, Follow Me off.
    static func allIncluded(_ sensorIDs: [String]) -> PlacementConfig {
        let ids = Set(sensorIDs)
        return PlacementConfig(home: ids, sleep: ids, away: ids, followMe: false)
    }

    func sensors(in setting: Setting) -> Set<String> {
        switch setting {
        case .home: return home
        case .sleep: return sleep
        case .away: return away
        }
    }

    mutating func set(_ included: Bool, sensor: String, in setting: Setting) {
        var ids = sensors(in: setting)
        if included { ids.insert(sensor) } else { ids.remove(sensor) }
        switch setting {
        case .home: home = ids
        case .sleep: sleep = ids
        case .away: away = ids
        }
    }

    /// Drops sensor ids the server no longer reports.
    func pruned(to known: Set<String>) -> PlacementConfig {
        PlacementConfig(
            home: home.intersection(known), sleep: sleep.intersection(known),
            away: away.intersection(known), followMe: followMe
        )
    }

    /// Query items in a stable order; an empty value means the setting explicitly has no sensors.
    var queryItems: [URLQueryItem] {
        Setting.allCases.map { URLQueryItem(name: $0.rawValue, value: sensors(in: $0).sorted().joined(separator: ",")) }
            + [URLQueryItem(name: "followMe", value: followMe ? "true" : "false")]
    }
}

/// Persists the placement config tagged with the signed-in session (see `AuthManager.widgetSessionID()`),
/// so a config is only ever returned for the session that saved it and never leaks across accounts.
struct PlacementConfigStore {
    static let key = "sensorPlacementConfig"

    private struct Record: Codable {
        let session: String
        let config: PlacementConfig
    }

    let session: String
    let defaults: UserDefaults

    static func current(defaults: UserDefaults = .standard) -> PlacementConfigStore? {
        AuthManager.shared.widgetSessionID().map { PlacementConfigStore(session: $0, defaults: defaults) }
    }

    func load() -> PlacementConfig? {
        guard let data = defaults.data(forKey: Self.key),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.session == session else { return nil }
        return record.config
    }

    func save(_ config: PlacementConfig?) {
        guard let config, let data = try? JSONEncoder().encode(Record(session: session, config: config)) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

struct ThermostatSetupView: View {
    let sensors: [PlacementInsights.Sensor]
    let wasConfigured: Bool
    let onSave: (PlacementConfig?) -> Void
    @State private var draft: PlacementConfig
    @Environment(\.dismiss) private var dismiss

    init(sensors: [PlacementInsights.Sensor], config: PlacementConfig?, onSave: @escaping (PlacementConfig?) -> Void) {
        let ids = sensors.map(\.id)
        self.sensors = sensors
        self.wasConfigured = config != nil
        self.onSave = onSave
        _draft = State(initialValue: (config ?? .allIncluded(ids)).pruned(to: Set(ids)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Match the sensors each Ecobee comfort setting uses. HomeKit doesn't share these, "
                         + "so tips can only name the sensor skewing the average when they're set here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(PlacementConfig.Setting.allCases) { setting in
                    Section(setting.title) {
                        ForEach(sensors) { sensor in
                            Toggle(sensor.displayName, isOn: Binding(
                                get: { draft.sensors(in: setting).contains(sensor.id) },
                                set: { draft.set($0, sensor: sensor.id, in: setting) }
                            ))
                        }
                    }
                }
                Section {
                    Toggle("Follow Me", isOn: $draft.followMe)
                } footer: {
                    Text("With Follow Me, Ecobee averages only the participating sensors that detect someone.")
                }
                if wasConfigured {
                    Section {
                        Button("Clear Thermostat Setup", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Thermostat setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
