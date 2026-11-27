//
//  PlacementConfig.swift
//  FluxHaus
//
//  The thermostat setup sent with placement insights: model, per-session persistence and editor.
//

import CryptoKit
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

    /// Drops the given sensor ids (e.g. the thermostat, which is Ecobee's average rather than a sensor).
    func excluding(_ ids: Set<String>) -> PlacementConfig {
        PlacementConfig(
            home: home.subtracting(ids), sleep: sleep.subtracting(ids), away: away.subtracting(ids), followMe: followMe
        )
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

/// A stable, non-secret identifier for the signed-in account, so the setup survives sign-out and
/// sign-in of the same account while staying separate per account. For OIDC it is a SHA-256 hash of
/// the access token's `iss` and `sub` claims (read locally, never stored); the shared demo login is "demo".
enum PlacementAccount {
    static func current() -> String? {
        identifier(accessToken: AuthManager.shared.getAccessToken(), hasDemoPassword: WhereWeAre.getPassword() != nil)
    }

    static func identifier(accessToken: String?, hasDemoPassword: Bool) -> String? {
        // Requests use the OIDC token when present, so an unreadable (opaque) token means no stable id.
        if let accessToken { return subject(ofJWT: accessToken).map(hash) }
        return hasDemoPassword ? "demo" : nil
    }

    private static func subject(ofJWT token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let iss = claims["iss"] as? String, !iss.isEmpty,
              let sub = claims["sub"] as? String, !sub.isEmpty else { return nil }
        return "\(iss)|\(sub)"
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Persists the placement config per account (see `PlacementAccount`), one key per account.
struct PlacementConfigStore {
    static let keyPrefix = "sensorPlacementConfig."

    let account: String
    let defaults: UserDefaults

    var key: String { Self.keyPrefix + account }

    static func current(defaults: UserDefaults = .standard) -> PlacementConfigStore? {
        PlacementAccount.current().map { PlacementConfigStore(account: $0, defaults: defaults) }
    }

    func load() -> PlacementConfig? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PlacementConfig.self, from: $0) }
    }

    func save(_ config: PlacementConfig?) {
        guard let config, let data = try? JSONEncoder().encode(config) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

struct ThermostatSetupView: View {
    let sensors: [PlacementInsights.Sensor]
    let wasConfigured: Bool
    let onSave: (PlacementConfig?) -> Void
    @State private var draft: PlacementConfig
    @Environment(\.dismiss) private var dismiss

    init(sensors: [PlacementInsights.Sensor], config: PlacementConfig?, onSave: @escaping (PlacementConfig?) -> Void) {
        // The thermostat reading is Ecobee's comfort average, not a sensor that can participate.
        let rooms = sensors.filter { !$0.isThermostat }
        let ids = rooms.map(\.id)
        self.sensors = rooms
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
