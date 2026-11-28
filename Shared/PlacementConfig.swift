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
    // Physical-sensor participation is tracked separately from thermostat-associated temperature readings.
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

    /// Drops the given ids, such as thermostat-associated sensors excluded from room choices.
    func excluding(_ ids: Set<String>) -> PlacementConfig {
        PlacementConfig(
            home: home.subtracting(ids), sleep: sleep.subtracting(ids), away: away.subtracting(ids), followMe: followMe,
            thermostatHome: thermostatHome, thermostatSleep: thermostatSleep, thermostatAway: thermostatAway
        )
    }

    /// Restricts room ids to a discovered list for a request without changing the saved setup.
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

/// Signals in-process saves so every open window observes changes to its own stored account config.
@MainActor @Observable private final class PlacementConfigChanges {
    static let shared = PlacementConfigChanges()
    var revision = 0
}

enum PlacementConfigUpdateResult: Equatable { case changed, unchanged, conflict, unavailable }

struct PlacementConfigSnapshot: Equatable, Sendable {
    let config: PlacementConfig?
    let revision: String?

    static let empty = PlacementConfigSnapshot(config: nil, revision: nil)
}

/// Persists the placement config and its revision under account-specific keys.
@MainActor
struct PlacementConfigStore {
    static let keyPrefix = "sensorPlacementConfig."
    // Distinguish an updated-then-restored setup from an editor or request's older identical snapshot.
    static let revisionKeyPrefix = "sensorPlacementConfigRevision."

    let account: String
    let defaults: UserDefaults

    var key: String { Self.keyPrefix + account }
    var revisionKey: String { Self.revisionKeyPrefix + account }

    static func current(defaults: UserDefaults = .standard) -> PlacementConfigStore? {
        PlacementAccount.current().map { PlacementConfigStore(account: $0, defaults: defaults) }
    }

    func load() -> PlacementConfig? {
        snapshot().config
    }

    func snapshot() -> PlacementConfigSnapshot {
        _ = PlacementConfigChanges.shared.revision
        let config = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PlacementConfig.self, from: $0) }
        return PlacementConfigSnapshot(config: config, revision: defaults.string(forKey: revisionKey))
    }

    @discardableResult
    func save(_ config: PlacementConfig?) -> PlacementConfigSnapshot {
        let saved: PlacementConfig?
        if let config, let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
            saved = config
        } else {
            defaults.removeObject(forKey: key)
            saved = nil
        }
        let revision = UUID().uuidString
        defaults.set(revision, forKey: revisionKey)
        PlacementConfigChanges.shared.revision &+= 1
        return PlacementConfigSnapshot(config: saved, revision: revision)
    }
}

@MainActor
struct ThermostatSetupSaveState {
    let initial: PlacementConfigSnapshot
    var error: String?

    var initialConfig: PlacementConfig? { initial.config }

    mutating func save(
        _ config: PlacementConfig?,
        using onSave: (PlacementConfig?, PlacementConfigSnapshot) -> PlacementConfigUpdateResult
    ) -> Bool {
        error = ThermostatSetupView.saveFailureMessage(onSave(config, initial))
        return error == nil
    }
}

struct ThermostatSetupView: View {
    static let emptySettingNotice = "Ecobee uses the thermostat's built-in sensor if the last sensor is removed. "
        + "Check settings with no room sensors and an excluded thermostat in Ecobee; actual participation may differ."
    static let noRoomSensorsNotice = "No room sensors are listed in this analysis. Saved IDs not in the current list "
        + "keep their per-setting selections unless you change them. For a setting with no room selections, "
        + "saving selects no room sensors."
    static let thermostatReadingExplanation = "The analysis estimates the comfort average from available readings. "
        + "When an identified climate-reported thermostat temperature is available, it may serve as an approximation. "
        + "A thermostat-associated sensor isn't necessarily that reading or the physical built-in sensor."
    static let followMeExplanation = "Follow Me isn't detected. For a new setup this switch starts off; match it to "
        + "your Ecobee setting. The analysis assumes Follow Me averages occupied participating sensors; "
        + "if none are occupied, it averages all participating sensors. Actual behavior may differ."
    static let conflictNotice = "Thermostat setup changed in another window. Your draft hasn't been saved. "
        + "Review or note your changes, then cancel and reopen setup to review the latest choices."
    static let saveUnavailableNotice = "Thermostat setup can't be saved in this session. Your draft hasn't been saved."

    let sensors: [PlacementInsights.Sensor]
    let reportedSensorIDs: Set<String>
    let wasConfigured: Bool
    let thermostatParticipationNotice: String?
    let analysisNotice: String?
    let onSave: (PlacementConfig?, PlacementConfigSnapshot) -> PlacementConfigUpdateResult
    @State private var draft: PlacementConfig
    // Keep initially saved IDs visible in every setting throughout the editing session.
    @State private var saveState: ThermostatSetupSaveState
    @State private var showSaveError = false
    @Environment(\.dismiss) private var dismiss

    init(
        sensors: [PlacementInsights.Sensor], snapshot: PlacementConfigSnapshot, thermostatParticipationNotice: String?,
        analysisNotice: String? = nil,
        onSave: @escaping (PlacementConfig?, PlacementConfigSnapshot) -> PlacementConfigUpdateResult
    ) {
        let config = snapshot.config
        // Never offer a reported thermostat ID as a room, even if a duplicate entry says otherwise.
        let thermostatIDs = Set(sensors.filter(\.isThermostat).map(\.id))
        let rooms = sensors.filter { !$0.isThermostat && !thermostatIDs.contains($0.id) }
        let ids = rooms.map(\.id)
        self.sensors = rooms
        self.reportedSensorIDs = Set(sensors.map(\.id))
        self.wasConfigured = config != nil
        self.thermostatParticipationNotice = thermostatParticipationNotice
        self.analysisNotice = analysisNotice
        self.onSave = onSave
        _draft = State(initialValue: Self.initialDraft(config: config, roomIDs: ids))
        _saveState = State(initialValue: ThermostatSetupSaveState(initial: snapshot))
    }

    static func initialDraft(config: PlacementConfig?, roomIDs: [String]) -> PlacementConfig {
        config ?? .allIncluded(roomIDs)
    }

    static func unavailableSensorIDs(config: PlacementConfig?, reportedIDs: Set<String>) -> [String] {
        guard let config else { return [] }
        let savedIDs = PlacementConfig.Setting.allCases.reduce(into: Set<String>()) { ids, setting in
            ids.formUnion(config.sensors(in: setting))
        }
        return savedIDs.subtracting(reportedIDs).sorted()
    }

    static func unavailableSensorLabel(_ id: String) -> String {
        "Unavailable saved ID in current sensor list: \(id)"
    }

    static func saveFailureMessage(_ result: PlacementConfigUpdateResult) -> String? {
        switch result {
        case .changed, .unchanged: return nil
        case .conflict: return conflictNotice
        case .unavailable: return saveUnavailableNotice
        }
    }

    private func save(_ config: PlacementConfig?) {
        if saveState.save(config, using: onSave) {
            dismiss()
        } else {
            showSaveError = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError = saveState.error {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                    }
                }
                Section {
                    Text("Match the room sensors each Ecobee comfort setting uses. HomeKit doesn't share these, "
                         + "so tips need your setup to identify a room sensor that may skew the estimated average.")
                        .foregroundStyle(.secondary)
                    Text("Choose the thermostat's physical built-in sensor separately from room sensors. "
                         + Self.thermostatReadingExplanation)
                        .foregroundStyle(.secondary)
                    if sensors.isEmpty {
                        Text(Self.noRoomSensorsNotice)
                            .foregroundStyle(.secondary)
                    }
                    if let analysisNotice {
                        Label(analysisNotice, systemImage: "exclamationmark.triangle")
                    }
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
                        ForEach(
                            Self.unavailableSensorIDs(config: saveState.initialConfig, reportedIDs: reportedSensorIDs),
                            id: \.self
                        ) { id in
                            Toggle(Self.unavailableSensorLabel(id), isOn: Binding(
                                get: { draft.sensors(in: setting).contains(id) },
                                set: { draft.set($0, sensor: id, in: setting) }
                            ))
                            .accessibilityLabel("\(Self.unavailableSensorLabel(id)), \(setting.title)")
                            .accessibilityHint(
                                "Turn on to include this saved ID in this setting, or off to remove it."
                            )
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
                if saveState.initialConfig != nil {
                    Section {
                        Button("Clear Thermostat Setup", role: .destructive) {
                            save(nil)
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
                        save(draft)
                    }
                }
            }
            .alert("Thermostat setup not saved", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveState.error ?? Self.saveUnavailableNotice)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}

// MARK: - Request

extension SensorPlacementService {
    /// Retry with fresh discovery only while the original saved setup and session are still current.
    static func load(
        config: PlacementConfig?, sessionCheck: @escaping SessionCheck, fetch: Fetch
    ) async throws -> Outcome {
        func checkCurrent() throws {
            try Task.checkCancellation()
            guard sessionCheck() else { throw PlacementRequestError.sessionChanged }
        }
        func checkedFetch(_ config: PlacementConfig?) async throws -> PlacementInsights {
            try checkCurrent()
            do {
                let result = try await fetch(config, sessionCheck)
                try checkCurrent()
                return result
            } catch {
                try checkCurrent()
                throw error
            }
        }

        do {
            let insights = try await checkedFetch(config)
            let notice = config != nil && insights.coverage.participationConfigured != true ? setupNotUsedNotice : nil
            return Outcome(insights: insights, thermostatIDs: insights.thermostatIDs, notice: notice)
        } catch PlacementRequestError.http(400) where config != nil {
            guard let config else { throw PlacementRequestError.http(400) }
            // Cached inventory may omit a returned sensor, so only fresh discovery selects the retry.
            let fresh = try await checkedFetch(nil)
            let available = fresh.roomSensorIDs.subtracting(fresh.thermostatIDs)
            guard !available.isEmpty else {
                return Outcome(insights: fresh, thermostatIDs: fresh.thermostatIDs, notice: sensorsUnavailableNotice)
            }
            let reduced = config.excluding(fresh.thermostatIDs).pruned(to: available)
            if reduced != config {
                do {
                    let insights = try await checkedFetch(reduced)
                    let thermostatIDs = fresh.thermostatIDs.union(insights.thermostatIDs)
                    let saved = config.excluding(thermostatIDs)
                    let reducedNotice = reduced.excluding(thermostatIDs) == saved ? nil : reducedConfigNotice
                    let notice = insights.coverage.participationConfigured == true ? reducedNotice : setupNotUsedNotice
                    return Outcome(insights: insights, thermostatIDs: thermostatIDs, notice: notice)
                } catch PlacementRequestError.http(400) {
                    // The unconfigured response is still usable when the reduced request is rejected.
                }
            }
            return Outcome(insights: fresh, thermostatIDs: fresh.thermostatIDs, notice: rejectedNotice)
        }
    }

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
