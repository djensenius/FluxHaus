//
//  PlacementConfig.swift
//  FluxHaus
//
//  The thermostat setup sent with placement insights: model, per-account persistence, editor and request.
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
    // The physical sensor is separate from the thermostat's reported temperature.
    // Missing keys in an older saved setup decode as unknown, not excluded.
    var thermostatHome: Bool?
    var thermostatSleep: Bool?
    var thermostatAway: Bool?

    /// Ecobee's default for room sensors: all included, Follow Me off; thermostat participation is unknown.
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

    func thermostat(in setting: Setting) -> Bool? {
        switch setting {
        case .home: return thermostatHome
        case .sleep: return thermostatSleep
        case .away: return thermostatAway
        }
    }

    mutating func setThermostat(_ included: Bool?, in setting: Setting) {
        switch setting {
        case .home: thermostatHome = included
        case .sleep: thermostatSleep = included
        case .away: thermostatAway = included
        }
    }

    func thermostatLabel(in setting: Setting) -> String {
        thermostat(in: setting).map { $0 ? "Included" : "Not included" } ?? "Unknown"
    }

    /// Ecobee may fall back to the thermostat sensor if no other sensor is selected.
    func needsThermostatFallbackNotice(in setting: Setting) -> Bool {
        sensors(in: setting).isEmpty && thermostat(in: setting) == false
    }

    /// Drops the given ids (e.g. the thermostat's reported temperature, which is not a room sensor).
    func excluding(_ ids: Set<String>) -> PlacementConfig {
        PlacementConfig(
            home: home.subtracting(ids), sleep: sleep.subtracting(ids), away: away.subtracting(ids), followMe: followMe,
            thermostatHome: thermostatHome, thermostatSleep: thermostatSleep, thermostatAway: thermostatAway
        )
    }

    /// Drops sensor ids the server no longer reports.
    func pruned(to known: Set<String>) -> PlacementConfig {
        PlacementConfig(
            home: home.intersection(known), sleep: sleep.intersection(known),
            away: away.intersection(known), followMe: followMe,
            thermostatHome: thermostatHome, thermostatSleep: thermostatSleep, thermostatAway: thermostatAway
        )
    }

    /// Query items in a stable order; an empty room-ID value explicitly selects no room sensors.
    var queryItems: [URLQueryItem] {
        let rooms = Setting.allCases.map {
            URLQueryItem(name: $0.rawValue, value: sensors(in: $0).sorted().joined(separator: ","))
        }
            + [URLQueryItem(name: "followMe", value: followMe ? "true" : "false")]
        let thermostat = [("thermostatHome", thermostatHome), ("thermostatSleep", thermostatSleep),
                          ("thermostatAway", thermostatAway)]
        return rooms + thermostat.compactMap { name, included in
            included.map { URLQueryItem(name: name, value: $0 ? "true" : "false") }
        }
    }
}

/// A stable, non-secret identifier for the signed-in account, so the setup survives sign-out and
/// sign-in of the same account while staying separate per account. For OIDC it is a hash of the
/// access token's `iss`/`sub` claims, or, for an opaque access token, the hash AuthManager kept from
/// the ID token (see `OIDCAccount`). The shared demo login is "demo". Nil means no stable identity.
enum PlacementAccount {
    static func current() -> String? {
        identifier(
            accessToken: AuthManager.shared.getAccessToken(),
            storedAccountID: AuthManager.shared.accountID(),
            hasDemoPassword: WhereWeAre.getPassword() != nil
        )
    }

    static func identifier(accessToken: String?, storedAccountID: String? = nil, hasDemoPassword: Bool) -> String? {
        // Requests use the OIDC token when present, so the demo password never applies then.
        if let accessToken { return OIDCAccount.identifier(fromJWT: accessToken) ?? storedAccountID }
        return hasDemoPassword ? "demo" : nil
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
    static let emptySettingNotice = "Ecobee uses the thermostat's built-in sensor if the last sensor is removed. "
        + "Check settings with no room sensors and an excluded thermostat in Ecobee; actual participation may differ."
    static let thermostatReadingExplanation = "The analysis uses HomeKit's reported thermostat temperature as an "
        + "approximation of the comfort average. The built-in sensor's independent temperature isn't available."
    static let followMeExplanation = "The analysis assumes Follow Me averages occupied participating sensors; "
        + "if none are occupied, it averages all participating sensors. Actual behavior may differ."

    let sensors: [PlacementInsights.Sensor]
    let wasConfigured: Bool
    let thermostatParticipationNotice: String?
    let onSave: (PlacementConfig?) -> Void
    @State private var draft: PlacementConfig
    @Environment(\.dismiss) private var dismiss

    init(
        sensors: [PlacementInsights.Sensor], config: PlacementConfig?, thermostatParticipationNotice: String?,
        onSave: @escaping (PlacementConfig?) -> Void
    ) {
        // The reported thermostat reading is treated as an average, not a room sensor.
        let rooms = sensors.filter { !$0.isThermostat }
        let ids = rooms.map(\.id)
        self.sensors = rooms
        self.wasConfigured = config != nil
        self.thermostatParticipationNotice = thermostatParticipationNotice
        self.onSave = onSave
        _draft = State(initialValue: Self.initialDraft(config: config, roomIDs: ids))
    }

    static func initialDraft(config: PlacementConfig?, roomIDs: [String]) -> PlacementConfig {
        config ?? .allIncluded(roomIDs)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Match the room sensors each Ecobee comfort setting uses. HomeKit doesn't share these, "
                         + "so tips need your setup to identify a room sensor that may skew the estimated average.")
                        .foregroundStyle(.secondary)
                    Text("Choose the thermostat's physical built-in sensor separately from room sensors. "
                         + Self.thermostatReadingExplanation)
                        .foregroundStyle(.secondary)
                    if let thermostatParticipationNotice {
                        Label(thermostatParticipationNotice, systemImage: "exclamationmark.triangle")
                    }
                }
                ForEach(PlacementConfig.Setting.allCases) { setting in
                    Section(setting.title) {
                        ForEach(sensors) { sensor in
                            Toggle(sensor.displayName, isOn: Binding(
                                get: { draft.sensors(in: setting).contains(sensor.id) },
                                set: { draft.set($0, sensor: sensor.id, in: setting) }
                            ))
                        }
                        Picker("Thermostat built-in sensor", selection: Binding(
                            get: { draft.thermostat(in: setting) },
                            set: { draft.setThermostat($0, in: setting) }
                        )) {
                            Text("Unknown").tag(Optional<Bool>.none)
                            Text("Included").tag(Optional.some(true))
                            Text("Not included").tag(Optional.some(false))
                        }
                        .accessibilityLabel("Thermostat built-in sensor for \(setting.title)")
                        .accessibilityHint("Choose whether the physical built-in sensor is used in this setting.")
                        if draft.needsThermostatFallbackNotice(in: setting) {
                            Text(Self.emptySettingNotice)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Toggle("Follow Me", isOn: $draft.followMe)
                } footer: {
                    Text(Self.followMeExplanation)
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

// MARK: - Request

extension SensorPlacementService {
    static func request(authorization: String, config: PlacementConfig? = nil) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/climate/placement-insights"
        components.queryItems = [URLQueryItem(name: "days", value: "14")] + (config?.queryItems ?? [])
        // URLComponents leaves "+" unescaped, which servers may read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        // The fixed URL components above always form a valid URL.
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    static func decode(data: Data, response: URLResponse) throws -> PlacementInsights {
        guard let response = response as? HTTPURLResponse else { throw PlacementRequestError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw PlacementRequestError.http(response.statusCode) }
        return try JSONDecoder().decode(PlacementInsights.self, from: data)
    }

    static func fetchInsights(
        config: PlacementConfig? = nil,
        sessionCheck: @escaping SessionCheck,
        authorization: @MainActor () -> String? = { AuthManager.shared.authorizationHeader() },
        hasOIDCToken: @MainActor () -> Bool = { AuthManager.shared.getAccessToken() != nil },
        ensureToken: @MainActor () async -> Bool = { await AuthManager.shared.ensureValidToken() },
        refreshToken: @MainActor () async -> Bool = { await AuthManager.shared.refreshTokenIfNeeded() },
        send: @MainActor (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) async throws -> PlacementInsights {
        try checkSession(sessionCheck)
        if hasOIDCToken() {
            _ = await ensureToken()
            try checkSession(sessionCheck)
        }
        guard let header = authorization() else { throw PlacementRequestError.unauthorized }
        try checkSession(sessionCheck)
        var (data, response) = try await send(request(authorization: header, config: config))
        try checkSession(sessionCheck)
        if (response as? HTTPURLResponse)?.statusCode == 401, hasOIDCToken() {
            let refreshed = await refreshToken()
            try checkSession(sessionCheck)
            guard refreshed, let newHeader = authorization() else { throw PlacementRequestError.unauthorized }
            try checkSession(sessionCheck)
            (data, response) = try await send(request(authorization: newHeader, config: config))
            try checkSession(sessionCheck)
        }
        return try decode(data: data, response: response)
    }

    private static func checkSession(_ check: SessionCheck) throws {
        try Task.checkCancellation()
        guard check() else { throw PlacementRequestError.sessionChanged }
    }
}
