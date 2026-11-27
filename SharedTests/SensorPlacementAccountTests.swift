//
//  SensorPlacementAccountTests.swift
//  FluxHaus Tests
//
//  Account identity for the thermostat setup, stale-sensor retries and pending setup reloads.
//

import Foundation
import Testing
@testable import FluxHaus

/// Placement insights reporting the given room sensors plus the thermostat ("home").
private func insights(rooms: [String], sensorFields: String = "") throws -> PlacementInsights {
    let sensors = (rooms.map { ($0, false) } + [("home", true)]).map { id, thermostat in
        """
        {"id": "\(id)", "name": "\(id.capitalized)", "isThermostat": \(thermostat), "averageOffset": 0,
         "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 10,
         "classification": "ok"\(sensorFields)}
        """
    }
    let json = """
    {"generatedAt": "2026-11-26T12:00:00Z", "windowDays": 14, "unit": "°C",
     "coverage": {"start": "2026-11-12T12:00:00Z", "end": "2026-11-26T12:00:00Z",
       "hvacHistoryAvailable": true, "morningEvents": 0, "returnEvents": 0},
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
        let configA = PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: true)
        let configB = PlacementConfig(home: ["kitchen"], sleep: ["kitchen"], away: [], followMe: false)

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

    @Test("A sensor the cache still lists but the fresh response doesn't is pruned and persisted")
    func staleCacheUsesFreshSensors() async throws {
        let cached = try insights(rooms: ["bedroom", "gone"])
        let fresh = try insights(rooms: ["bedroom", "kitchen"])
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let stale = PlacementConfig(home: ["bedroom", "gone"], sleep: ["gone"], away: [], followMe: false)
        store.save(stale)
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                if config?.home.contains("gone") == true { throw PlacementRequestError.http(400) }
                return fresh
            }
        )
        #expect(await service.refresh())
        let corrected = PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: false)
        #expect(requested == [stale, nil, corrected])
        #expect(service.config == corrected)
        #expect(store.load() == corrected)
        #expect(service.notice == SensorPlacementService.prunedNotice)
        #expect(service.insights?.roomSensorIDs == ["bedroom", "kitchen"])
    }

    @Test("An empty sensor list never prunes the setup: cached inventory is skipped, fresh retries correctly")
    func emptyCachedInventory() async throws {
        let fresh = try insights(rooms: ["bedroom", "kitchen"])
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let stale = PlacementConfig(home: ["bedroom", "gone"], sleep: [], away: [], followMe: false)
        store.save(stale)
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: try insights(rooms: []), sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                if config?.home.contains("gone") == true { throw PlacementRequestError.http(400) }
                return fresh
            }
        )
        #expect(await service.refresh())
        let corrected = PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: false)
        // No request with an emptied setup, which the server would accept and the app would persist.
        #expect(requested == [stale, nil, corrected])
        #expect(store.load() == corrected)
    }

    @Test("When fresh inventory is empty too, the saved setup is kept and unconfigured insights are shown")
    func emptyFreshInventory() async throws {
        let empty = try insights(rooms: [])
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let saved = PlacementConfig(home: ["bedroom"], sleep: ["kitchen"], away: [], followMe: true)
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
        #expect(SensorPlacementDetailView.offsetRows(current).map(\.label) == ["Overnight", "Home"])
    }

    @Test("A cancelled setup reload stays pending and is retried on return; success clears it")
    func cancelledReloadStaysPending() async throws {
        let result = try insights(rooms: ["bedroom", "kitchen"])
        let gate = FetchGate()
        let store = PlacementConfigStore(account: "a", defaults: defaults())
        let service = SensorPlacementService(
            insights: result, sessionCheck: { true }, configStore: store, fetch: { _, _ in
                gate.started += 1
                if gate.blocked { try await Task.sleep(for: .seconds(60)) }
                return result
            }
        )
        #expect(!service.hasPendingConfig)
        #expect(service.updateConfig(PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: false)))
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
        #expect(!service.hasPendingConfig)
        #expect(!SensorPlacementView.needsReload(hasInsights: true, requested: 1, completed: 1, pendingConfig: false))
    }
}
