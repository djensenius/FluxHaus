//
//  SensorPlacementAccountTests.swift
//  FluxHaus Tests
//
//  Account identity for the thermostat setup, stale-sensor retries and pending setup reloads.
//

import Foundation
import Testing
@testable import FluxHaus

/// Placement insights reporting the given room sensors and, by default, the thermostat ("home").
private func insights(
    rooms: [String], sensorFields: String = "", includeThermostat: Bool = true, participationConfigured: Bool = true
) throws -> PlacementInsights {
    let reported = rooms.map { ($0, false) } + (includeThermostat ? [("home", true)] : [])
    let sensors = reported.map { id, thermostat in
        """
        {"id": "\(id)", "name": "\(thermostat ? "Home" : id.capitalized)",
         "isThermostat": \(thermostat), "averageOffset": 0,
         "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 10,
         "classification": "ok"\(sensorFields)}
        """
    }
    let json = """
    {"generatedAt": "2026-11-26T12:00:00Z", "windowDays": 14, "unit": "°C",
     "coverage": {"start": "2026-11-12T12:00:00Z", "end": "2026-11-26T12:00:00Z",
       "hvacHistoryAvailable": true, "morningEvents": 0, "returnEvents": 0,
       "participationConfigured": \(participationConfigured)},
     "sensors": [\(sensors.joined(separator: ","))], "recommendations": []}
    """
    return try JSONDecoder().decode(PlacementInsights.self, from: Data(json.utf8))
}

/// An unsigned JWT with the given claims; only the payload is read for the account id.
private func jwt(_ claims: [String: Any]) throws -> String {
    let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(payload).signature"
}

/// Controls a fake fetch: while `blocked`, requests wait until cancelled.
@MainActor
private final class FetchGate {
    var blocked = true
    var started = 0
}

@MainActor
private final class AccountTestSession {
    var valid = true
}

@MainActor
private final class InventoryStatus {
    var sensorReturned = false
}

/// The keychain-held account id, simulated with AuthManager's pure rules: sign-in clears it before
/// storing new tokens, refresh keeps it, sign-out deletes it.
private struct StoredAccount {
    var id: String?

    mutating func signIn(idToken: String?) { id = OIDCAccount.storedID(current: nil, idToken: idToken) }
    mutating func refresh(idToken: String?) { id = OIDCAccount.storedID(current: id, idToken: idToken) }
    mutating func signOut() { id = nil }

    /// The placement account for an opaque (non-JWT) access token.
    var placementAccount: String? {
        PlacementAccount.identifier(accessToken: "opaque-access", storedAccountID: id, hasDemoPassword: false)
    }
}

@MainActor
struct SensorPlacementAccountTests {
    private let issuer = "https://auth.fluxhaus.io/application/o/fluxhaus-server/"

    private func defaults() -> UserDefaults {
        let suite = "SensorPlacementAccountTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func service(_ store: PlacementConfigStore?) -> SensorPlacementService {
        SensorPlacementService(sessionCheck: { true }, configStore: store, fetch: { _, _ in
            throw PlacementRequestError.invalidResponse
        })
    }

    @Test("Legacy saved setups migrate with unknown thermostat choices")
    func legacyConfigMigration() throws {
        let defaults = defaults()
        let store = PlacementConfigStore(account: "a", defaults: defaults)
        let legacy = """
        {"home": ["bedroom", "gone", "home"], "sleep": ["bedroom"], "away": [], "followMe": true}
        """
        defaults.set(Data(legacy.utf8), forKey: store.key)
        let loaded = try #require(store.load())
        #expect(loaded.home == ["bedroom", "gone", "home"])
        #expect(loaded.sleep == ["bedroom"] && loaded.away.isEmpty && loaded.followMe)
        for setting in PlacementConfig.Setting.allCases {
            #expect(loaded.thermostat(in: setting) == nil)
            #expect(loaded.thermostatLabel(in: setting) == "Unknown")
            #expect(PlacementConfig.allIncluded(["bedroom"]).thermostat(in: setting) == nil)
        }

        var migrated = loaded.pruned(to: ["bedroom", "home"]).excluding(["home"])
        store.save(migrated)
        #expect(store.load() == migrated)
        #expect(migrated.home == ["bedroom"] && migrated.sleep == ["bedroom"])
        #expect(migrated.thermostatHome == nil && migrated.thermostatSleep == nil && migrated.thermostatAway == nil)
        migrated.setThermostat(true, in: .home)
        migrated.setThermostat(false, in: .sleep)
        store.save(migrated)
        #expect(store.load() == migrated)
    }

    @Test("All true, false and unknown combinations persist and encode as optional query booleans")
    func thermostatChoicesRoundTrip() throws {
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let choices: [Bool?] = [nil, true, false]
        for home in choices {
            for sleep in choices {
                for away in choices {
                    var config = PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: false)
                    config.setThermostat(home, in: .home)
                    config.setThermostat(sleep, in: .sleep)
                    config.setThermostat(away, in: .away)
                    for (setting, value) in zip(PlacementConfig.Setting.allCases, [home, sleep, away]) {
                        #expect(config.thermostat(in: setting) == value)
                        #expect(config.thermostatLabel(in: setting)
                                == (value.map { $0 ? "Included" : "Not included" } ?? "Unknown"))
                    }
                    store.save(config)
                    #expect(store.load() == config)
                    let data = try #require(store.defaults.data(forKey: store.key))
                    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let expected = [("thermostatHome", home), ("thermostatSleep", sleep), ("thermostatAway", away)]
                    for (name, value) in expected {
                        #expect((json[name] as? Bool) == value)
                        #expect((json[name] != nil) == (value != nil))
                    }
                    let request = SensorPlacementService.request(authorization: "Basic demo", config: config)
                    let url = try #require(request.url)
                    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                    #expect(Array(items.prefix(5)).map(\.name) == ["days", "home", "sleep", "away", "followMe"])
                    let thermostatItems = expected.compactMap { name, value in
                        value.map { URLQueryItem(name: name, value: $0 ? "true" : "false") }
                    }
                    #expect(Array(items.dropFirst(5)) == thermostatItems)
                }
            }
        }
    }

    @Test("An empty room list with an excluded thermostat displays Ecobee's possible fallback")
    func emptySettingNotice() {
        for setting in PlacementConfig.Setting.allCases {
            var config = PlacementConfig.allIncluded(["gone"])
            config.setThermostat(false, in: setting)
            #expect(!config.needsThermostatFallbackNotice(in: setting))
            config = config.pruned(to: [])
            #expect(config.needsThermostatFallbackNotice(in: setting))
            #expect(config.thermostat(in: setting) == false)
            config.setThermostat(nil, in: setting)
            #expect(!config.needsThermostatFallbackNotice(in: setting))
            #expect(config.thermostatLabel(in: setting) == "Unknown")
            config.setThermostat(true, in: setting)
            #expect(!config.needsThermostatFallbackNotice(in: setting))
        }
        #expect(ThermostatSetupView.emptySettingNotice.contains("if the last sensor is removed"))
        #expect(ThermostatSetupView.emptySettingNotice.contains("actual participation may differ"))
    }

    @Test("The ID token's account hash identifies opaque access tokens; it needs both iss and sub")
    func idTokenAccount() throws {
        let idA = try #require(OIDCAccount.identifier(fromJWT: try jwt(["iss": issuer, "sub": "user-a"])))
        #expect(idA.count == 64 && !idA.contains("user-a"))
        #expect(OIDCAccount.identifier(fromJWT: try jwt(["sub": "user-a"])) == nil)
        #expect(OIDCAccount.identifier(fromJWT: try jwt(["iss": "", "sub": "user-a"])) == nil)
        #expect(OIDCAccount.identifier(fromJWT: "opaque") == nil)
        // A JWT access token wins; an opaque one falls back to the stored ID-token hash, else nothing.
        let access = try jwt(["iss": issuer, "sub": "user-b"])
        #expect(PlacementAccount.identifier(accessToken: access, storedAccountID: idA, hasDemoPassword: false)
                == OIDCAccount.identifier(fromJWT: access))
        #expect(PlacementAccount.identifier(accessToken: "opaque", storedAccountID: idA, hasDemoPassword: true) == idA)
        #expect(PlacementAccount.identifier(accessToken: "opaque", storedAccountID: nil, hasDemoPassword: true) == nil)
    }

    @Test("With opaque access tokens, accounts stay isolated and re-login restores the setup")
    func opaqueAccessAccounts() throws {
        let defaults = defaults()
        let tokenA = try jwt(["iss": issuer, "sub": "user-a", "nonce": "1"])
        let tokenB = try jwt(["iss": issuer, "sub": "user-b"])
        var keychain = StoredAccount()
        let configA = PlacementConfig(
            home: ["bedroom"], sleep: [], away: [], followMe: true,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        let configB = PlacementConfig(
            home: ["kitchen"], sleep: ["kitchen"], away: [], followMe: false,
            thermostatHome: false, thermostatSleep: nil, thermostatAway: true
        )

        keychain.signIn(idToken: tokenA)
        let accountA = try #require(keychain.placementAccount)
        #expect(service(PlacementConfigStore(account: accountA, defaults: defaults)).updateConfig(configA))
        // A refresh without an ID token keeps the same account.
        keychain.refresh(idToken: nil)
        #expect(keychain.placementAccount == accountA)

        // Sign-out hides the identity but keeps A's saved setup for its next sign-in.
        keychain.signOut()
        #expect(keychain.placementAccount == nil)
        #expect(PlacementConfigStore(account: accountA, defaults: defaults).load() == configA)

        keychain.signIn(idToken: tokenB)
        let accountB = try #require(keychain.placementAccount)
        #expect(accountB != accountA)
        let serviceB = service(PlacementConfigStore(account: accountB, defaults: defaults))
        #expect(serviceB.config == nil)
        #expect(serviceB.updateConfig(configB))

        keychain.signOut()
        keychain.signIn(idToken: try jwt(["iss": issuer, "sub": "user-a", "nonce": "2"]))
        let restored = service(keychain.placementAccount.map { PlacementConfigStore(account: $0, defaults: defaults) })
        #expect(restored.config == configA)
        #expect(PlacementConfigStore(account: accountB, defaults: defaults).load() == configB)

        // Signing in without an ID token leaves no identity, never a previous account's.
        keychain.signIn(idToken: nil)
        #expect(keychain.placementAccount == nil)
    }

    @Test("Without a stable identity, setup is unavailable instead of saving only in memory")
    func setupUnavailableWithoutAccount() {
        let unavailable = service(nil)
        #expect(!unavailable.canSaveConfig)
        #expect(!unavailable.updateConfig(PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: false)))
        #expect(unavailable.config == nil)
        #expect(!unavailable.hasPendingConfig)
        #expect(service(PlacementConfigStore(account: "a", defaults: defaults())).canSaveConfig)
    }

    @Test("Setup needs an insights response and a stable, valid account")
    func setupAvailability() throws {
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let thermostatOnly = try insights(rooms: [])
        let roomsOnly = try insights(rooms: ["bedroom"], includeThermostat: false)
        let noSensors = try insights(rooms: [], includeThermostat: false)
        func service(_ result: PlacementInsights?, _ store: PlacementConfigStore?) -> SensorPlacementService {
            SensorPlacementService(insights: result, sessionCheck: { true }, configStore: store)
        }
        #expect(service(thermostatOnly, store).canEditConfig)
        #expect(service(roomsOnly, store).canEditConfig)
        #expect(service(noSensors, store).canEditConfig)
        #expect(!service(nil, store).canEditConfig)
        #expect(!service(thermostatOnly, nil).canEditConfig)
        let session = AccountTestSession()
        let signedIn = SensorPlacementService(
            insights: thermostatOnly, sessionCheck: { session.valid }, configStore: store
        )
        #expect(signedIn.canEditConfig)
        session.valid = false
        #expect(!signedIn.canEditConfig)
    }

    @Test("Editing and saving keeps unavailable rooms, including with thermostat-only discovery")
    func editingPreservesUnavailableRooms() async throws {
        for rooms in [["bedroom"], []] {
            let result = try insights(rooms: rooms)
            let store = PlacementConfigStore(account: "a", defaults: defaults())
            let saved = PlacementConfig(
                home: ["bedroom", "missing", "home"], sleep: ["missing"], away: ["missing"], followMe: true,
                thermostatHome: nil, thermostatSleep: false, thermostatAway: true
            )
            store.save(saved)
            let service = SensorPlacementService(
                insights: result, sessionCheck: { true }, configStore: store, fetch: { _, _ in result }
            )
            let editor = ThermostatSetupView(
                sensors: result.sensors, snapshot: service.configSnapshot, thermostatParticipationNotice: nil
            ) { config, expected in service.updateConfig(config, expected: expected) }
            var draft = ThermostatSetupView.initialDraft(config: service.config, roomIDs: editor.sensors.map(\.id))
            #expect(draft == saved)
            draft.setThermostat(true, in: .home)
            #expect(editor.onSave(draft, service.configSnapshot) == .changed)
            let expected = draft.excluding(["home"])
            #expect(service.config == expected && store.load() == expected)
            #expect(expected.home == ["bedroom", "missing"])
            #expect(expected.sleep == ["missing"] && expected.away == ["missing"])
            #expect(await service.refresh())
            #expect(store.load() == expected)
            let newDraft = ThermostatSetupView.initialDraft(config: nil, roomIDs: rooms)
            #expect(newDraft.home == Set(rooms) && newDraft.thermostatHome == nil)
        }
    }

    @Test("Fresh discovery reduces a rejected request without losing saved choices, then retries them")
    func staleCacheUsesFreshSensors() async throws {
        let cached = try insights(rooms: ["bedroom", "gone"])
        let fresh = try insights(rooms: ["bedroom", "kitchen"])
        let discovery = try insights(rooms: ["bedroom", "kitchen"], participationConfigured: false)
        let recovered = try insights(rooms: ["bedroom", "gone", "kitchen"])
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let stale = PlacementConfig(
            home: ["bedroom", "gone"], sleep: ["gone"], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        store.save(stale)
        let savedData = store.defaults.data(forKey: store.key)
        let inventory = InventoryStatus()
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                if config?.home.contains("gone") == true && !inventory.sensorReturned {
                    throw PlacementRequestError.http(400)
                }
                if inventory.sensorReturned { return recovered }
                return config == nil ? discovery : fresh
            }
        )
        #expect(await service.refresh())
        let corrected = PlacementConfig(
            home: ["bedroom"], sleep: [], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        #expect(requested == [stale, nil, corrected])
        #expect(service.config == stale && store.load() == stale)
        #expect(store.defaults.data(forKey: store.key) == savedData)
        #expect(service.notice == SensorPlacementService.reducedConfigNotice)
        #expect(service.notice?.contains("weren't used") == true && service.notice?.contains("remain saved") == true)
        #expect(service.insights?.roomSensorIDs == ["bedroom", "kitchen"])
        inventory.sensorReturned = true
        #expect(await service.refresh())
        #expect(requested == [stale, nil, corrected, stale])
        #expect(service.config == stale && store.load() == stale)
        #expect(store.defaults.data(forKey: store.key) == savedData)
        #expect(service.insights?.roomSensorIDs == ["bedroom", "gone", "kitchen"])
        #expect(service.notice == nil)
    }

    @Test("An empty sensor list never prunes the setup: cached inventory is skipped, fresh retries correctly")
    func emptyCachedInventory() async throws {
        let fresh = try insights(rooms: ["bedroom", "kitchen"])
        let discovery = try insights(rooms: ["bedroom", "kitchen"], participationConfigured: false)
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let stale = PlacementConfig(home: ["bedroom", "gone"], sleep: [], away: [], followMe: false)
        store.save(stale)
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: try insights(rooms: []), sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                if config?.home.contains("gone") == true { throw PlacementRequestError.http(400) }
                return config == nil ? discovery : fresh
            }
        )
        #expect(await service.refresh())
        let corrected = PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: false)
        // Empty cached inventory doesn't determine the retry; fresh discovery does.
        #expect(requested == [stale, nil, corrected])
        #expect(service.config == stale && store.load() == stale)
        #expect(service.notice == SensorPlacementService.reducedConfigNotice)
    }

    @Test("When fresh inventory is empty too, the saved setup is kept and unconfigured insights are shown")
    func emptyFreshInventory() async throws {
        let empty = try insights(rooms: [], participationConfigured: false)
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let saved = PlacementConfig(
            home: ["bedroom"], sleep: ["kitchen"], away: [], followMe: true,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        store.save(saved)
        for cached in [nil, empty] {
            var requested: [PlacementConfig?] = []
            let service = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                    requested.append(config)
                    if config != nil { throw PlacementRequestError.http(400) }
                    return empty
                }
            )
            #expect(await service.refresh())
            #expect(requested == [saved, nil])
            #expect(service.insights != nil)
            #expect(service.config == saved)
            #expect(store.load() == saved)
            #expect(service.notice == SensorPlacementService.sensorsUnavailableNotice)
            #expect(service.error == nil)
        }
    }

    @Test("Offsets explain their baseline: house comfort average for period offsets, all sensors for legacy")
    func offsetBaselineWording() throws {
        let legacy = try #require(try insights(rooms: ["bedroom"]).sensors.first)
        #expect(legacy.periodOffsets == nil)
        #expect(SensorPlacementDetailView.offsetBaseline(legacy).contains("average of all sensors"))
        #expect(SensorPlacementDetailView.offsetRows(legacy).map(\.label) == ["Overall"])
        let fields = #", "periodOffsets": {"sleep": -0.4, "wake": null, "home": 0.2, "heatingRuns": null, "#
            + #""cooling": null}"#
        let current = try #require(try insights(rooms: ["bedroom"], sensorFields: fields).sensors.first)
        #expect(SensorPlacementDetailView.offsetBaseline(current).contains("effective comfort average"))
        #expect(!SensorPlacementDetailView.offsetBaseline(current).contains("thermostat"))
        #expect(SensorPlacementDetailView.offsetRows(current).map(\.label) == ["Overnight", "Home"])
        #expect(ThermostatSetupView.thermostatReadingExplanation.contains("approximation"))
        #expect(ThermostatSetupView.thermostatReadingExplanation.contains("identified climate-reported"))
        #expect(ThermostatSetupView.followMeExplanation.contains("assumes"))
        #expect(ThermostatSetupView.followMeExplanation.contains("if none are occupied"))
        #expect(ThermostatSetupView.followMeExplanation.contains("all participating sensors"))
    }

    @Test("A cancelled setup reload stays pending and is retried on return; success clears it")
    func cancelledReloadStaysPending() async throws {
        let result = try insights(rooms: ["bedroom", "kitchen"])
        let gate = FetchGate()
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: result, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                gate.started += 1
                if gate.blocked { try await Task.sleep(for: .seconds(60)) }
                return result
            }
        )
        #expect(!service.hasPendingConfig)
        let config = PlacementConfig(
            home: ["bedroom"], sleep: [], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        #expect(service.updateConfig(config))
        #expect(service.hasPendingConfig)

        // Leaving the screen cancels the reload mid-request.
        let reload = Task { await service.refresh() }
        while gate.started == 0 { await Task.yield() }
        reload.cancel()
        #expect(await reload.value == false)
        #expect(service.hasPendingConfig)
        #expect(service.error == nil)

        // Back on the parent, its task (whose request id was already seen) reloads because of the pending setup.
        #expect(SensorPlacementView.needsReload(hasInsights: true, requested: 1, completed: 1, pendingConfig: true))
        // A request that wasn't completed is retried as well.
        #expect(SensorPlacementView.needsReload(hasInsights: true, requested: 2, completed: 1, pendingConfig: false))
        gate.blocked = false
        #expect(await service.refresh())
        #expect(requested == [config, config])
        #expect(store.load() == config)
        #expect(!service.hasPendingConfig)
        #expect(!SensorPlacementView.needsReload(hasInsights: true, requested: 1, completed: 1, pendingConfig: false))
    }
}
