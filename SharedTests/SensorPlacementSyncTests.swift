//
//  SensorPlacementSyncTests.swift
//  FluxHaus Tests
//

import Foundation
import Observation
import Testing
@testable import FluxHaus

private final class SyncObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    func set() {
        lock.lock()
        defer { lock.unlock() }
        changed = true
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return changed
    }
}

@MainActor
private final class SyncTestSession {
    var valid = true
}

@MainActor
struct SensorPlacementSyncTests {
    private let original = PlacementConfig(
        home: ["bedroom", "hall", "unavailable"], sleep: ["unavailable"], away: [], followMe: true,
        thermostatHome: nil, thermostatSleep: false, thermostatAway: true
    )
    private let changed = PlacementConfig(
        home: ["bedroom", "hall", "new-unavailable"], sleep: ["new-unavailable"], away: [], followMe: false,
        thermostatHome: false, thermostatSleep: nil, thermostatAway: true
    )

    private func stores() -> (PlacementConfigStore, PlacementConfigStore) {
        let suite = "SensorPlacementSyncTests-\(UUID().uuidString)"
        let first = UserDefaults(suiteName: suite)!
        let second = UserDefaults(suiteName: suite)!
        return (PlacementConfigStore(account: "a", defaults: first),
                PlacementConfigStore(account: "a", defaults: second))
    }

    private func payload(days: Int = 14, thermostat: Bool = false) -> Data {
        let sensor = thermostat ? """
        , {"id": "hall", "name": "Hall", "isThermostat": true, "averageOffset": 0,
           "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 1, "classification": "ok"}
        """ : ""
        return Data("""
        {"generatedAt": "2026-11-26T12:00:00Z", "windowDays": \(days), "unit": "°C",
         "coverage": {"start": "2026-11-12T12:00:00Z", "end": "2026-11-26T12:00:00Z",
           "hvacHistoryAvailable": true, "morningEvents": 0, "returnEvents": 0, "participationConfigured": true},
         "sensors": [{"id": "bedroom", "name": "Bedroom", "isThermostat": false, "averageOffset": 0,
           "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 1,
           "classification": "ok"}\(sensor)], "recommendations": []}
        """.utf8)
    }

    private func insights(days: Int = 14, thermostat: Bool = false) throws -> PlacementInsights {
        try JSONDecoder().decode(PlacementInsights.self, from: payload(days: days, thermostat: thermostat))
    }

    @Test("Older saved configs without a revision remain readable and gain one on save or clear")
    func legacyRevisionMigration() throws {
        let (storeA, storeB) = stores()
        storeA.defaults.set(try JSONEncoder().encode(original), forKey: storeA.key)
        let legacy = storeB.snapshot()
        #expect(legacy.config == original && legacy.revision == nil)
        #expect(legacy.config?.thermostatHome == nil && legacy.config?.home.contains("unavailable") == true)
        let updated = storeA.save(changed)
        #expect(updated.revision != nil && storeB.snapshot() == updated)
        let cleared = storeB.save(nil)
        #expect(cleared.config == nil && cleared.revision != updated.revision && storeA.snapshot() == cleared)
    }

    @Test("Live services observe setup updates and clears before refreshing")
    func updateAndClear() async throws {
        let cached = try insights()
        for (initial, replacement) in [(original, changed), (original, nil), (nil, changed)]
            as [(PlacementConfig?, PlacementConfig?)] {
            let (storeA, storeB) = stores()
            storeA.save(initial)
            let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
            var requests: [PlacementConfig?] = []
            let reader = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, _ in
                    requests.append(config)
                    return cached
                }
            )
            let observed = SyncObservationFlag()
            withObservationTracking {
                _ = reader.config
                _ = reader.pendingInsightsNotice
            } onChange: {
                observed.set()
            }
            #expect(writer.updateConfig(replacement))
            #expect(observed.value)
            #expect(reader.config == replacement && storeB.load() == replacement)
            #expect(reader.hasPendingConfig)
            #expect(reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
            #expect(await reader.refresh())
            #expect(requests == [replacement])
            #expect(reader.config == replacement && !reader.hasPendingConfig)
            #expect(reader.pendingInsightsNotice == nil)
        }
    }

    @Test("A refresh re-reads storage even when the change did not use the store")
    func unannouncedChange() async throws {
        let cached = try insights()
        for replacement in [changed, nil] as [PlacementConfig?] {
            let (storeA, storeB) = stores()
            storeA.save(original)
            var requests: [PlacementConfig?] = []
            let reader = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, _ in
                    requests.append(config)
                    return cached
                }
            )
            if let replacement {
                storeA.defaults.set(try JSONEncoder().encode(replacement), forKey: storeA.key)
            } else {
                storeA.defaults.removeObject(forKey: storeA.key)
            }
            #expect(reader.config == replacement && reader.hasPendingConfig)
            #expect(await reader.refresh())
            #expect(requests == [replacement])
            #expect(reader.config == replacement && storeB.load() == replacement && !reader.hasPendingConfig)
        }
    }

    @Test("An outdated response cannot publish or clean up a newer setup")
    func staleResponseAndCleanup() async throws {
        let cached = try insights()
        let stale = try insights(days: 30, thermostat: true)
        for replacement in [changed, nil] as [PlacementConfig?] {
            let (storeA, storeB) = stores()
            storeA.save(original)
            let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
            var continuation: CheckedContinuation<PlacementInsights, Never>?
            var requests: [PlacementConfig?] = []
            let reader = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, _ in
                    requests.append(config)
                    if requests.count == 1 {
                        return await withCheckedContinuation { continuation = $0 }
                    }
                    return cached
                }
            )
            let load = Task { await reader.refresh() }
            while continuation == nil { await Task.yield() }
            #expect(writer.updateConfig(replacement))
            #expect(reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
            continuation?.resume(returning: stale)
            #expect(await load.value == false)
            #expect(storeB.load() == replacement && reader.config == replacement)
            #expect(reader.insights?.windowDays == 14)
            #expect(reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
            #expect(await reader.refresh())
            #expect(requests == [original, replacement])
            #expect(storeA.load() == replacement && !reader.hasPendingConfig)
        }
    }

    @Test("A changed setup stops discovery and reduced retries of an outdated request")
    func staleBadRequestRetry() async throws {
        let (storeA, storeB) = stores()
        storeA.save(original)
        let cached = try insights()
        let discovered = try insights(thermostat: true)
        let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
        var continuation: CheckedContinuation<PlacementInsights, Error>?
        var requests: [PlacementConfig?] = []
        let reader = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, _ in
                requests.append(config)
                if requests.count == 1 {
                    return try await withCheckedThrowingContinuation { continuation = $0 }
                }
                return discovered
            }
        )
        let load = Task { await reader.refresh() }
        while continuation == nil { await Task.yield() }
        #expect(writer.updateConfig(changed))
        continuation?.resume(throwing: PlacementRequestError.http(400))
        #expect(await load.value == false)
        #expect(requests == [original])
        #expect(storeB.load() == changed && reader.config == changed)
        #expect(reader.error == nil && reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
    }

    @Test("A setup change during discovery prevents the stale reduced retry")
    func changedDuringDiscovery() async throws {
        let cached = try insights()
        let discovered = try insights(thermostat: true)
        for replacement in [changed, nil] as [PlacementConfig?] {
            let (storeA, storeB) = stores()
            storeA.save(original)
            let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
            var continuation: CheckedContinuation<PlacementInsights, Never>?
            var requests: [PlacementConfig?] = []
            let reader = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, _ in
                    requests.append(config)
                    if requests.count == 1 { throw PlacementRequestError.http(400) }
                    return await withCheckedContinuation { continuation = $0 }
                }
            )
            let load = Task { await reader.refresh() }
            while continuation == nil { await Task.yield() }
            #expect(writer.updateConfig(replacement))
            continuation?.resume(returning: discovered)
            #expect(await load.value == false)
            #expect(requests == [original, nil])
            #expect(storeB.load() == replacement && reader.config == replacement)
            #expect(reader.error == nil && reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
        }
    }

    @Test("A stale reduced response cannot publish or clean up a newer setup")
    func changedDuringReducedRetry() async throws {
        let cached = try insights()
        let discovered = try insights(thermostat: true)
        let reduced = original.excluding(["hall"]).pruned(to: ["bedroom"])
        for replacement in [changed, nil] as [PlacementConfig?] {
            let (storeA, storeB) = stores()
            storeA.save(original)
            let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
            var continuation: CheckedContinuation<PlacementInsights, Never>?
            var requests: [PlacementConfig?] = []
            let reader = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, _ in
                    requests.append(config)
                    if requests.count == 1 { throw PlacementRequestError.http(400) }
                    if requests.count == 2 { return discovered }
                    return await withCheckedContinuation { continuation = $0 }
                }
            )
            let load = Task { await reader.refresh() }
            while continuation == nil { await Task.yield() }
            #expect(writer.updateConfig(replacement))
            continuation?.resume(returning: discovered)
            #expect(await load.value == false)
            #expect(requests == [original, nil, reduced])
            #expect(storeB.load() == replacement && reader.config == replacement)
            #expect(reader.error == nil && reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
        }
    }

    @Test("A changed setup stops an outdated request's token-refresh retry")
    func staleAuthenticationRetry() async throws {
        let (storeA, storeB) = stores()
        storeA.save(original)
        let cached = try insights()
        let responseData = payload()
        let replacement = changed
        let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
        var requests: [URLRequest] = []
        let reader = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, check in
                try await SensorPlacementService.fetchInsights(
                    config: config, sessionCheck: check, authorization: { "Bearer synthetic" },
                    hasOIDCToken: { true }, ensureToken: { true },
                    refreshToken: { _ = writer.updateConfig(replacement); return true },
                    send: { request in
                        requests.append(request)
                        let response = HTTPURLResponse(
                            url: request.url!, statusCode: requests.count == 1 ? 401 : 200,
                            httpVersion: nil, headerFields: nil
                        )!
                        return (responseData, response)
                    }
                )
            }
        )
        #expect(await reader.refresh() == false)
        #expect(requests.count == 1)
        #expect(storeB.load() == changed && reader.config == changed)
        #expect(reader.error == nil && reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
    }

    @Test("A stale editor cannot overwrite another window's update or clear")
    func staleEditor() async throws {
        let cached = try insights()
        for (initial, replacement) in [(original, changed), (original, nil), (nil, changed)]
            as [(PlacementConfig?, PlacementConfig?)] {
            for refreshBeforeSave in [false, true] {
                let (storeA, storeB) = stores()
                storeA.save(initial)
                let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
                let reader = SensorPlacementService(
                    insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { _, _ in cached }
                )
                let editor = ThermostatSetupView(
                    sensors: cached.sensors, snapshot: reader.configSnapshot, thermostatParticipationNotice: nil
                ) { config, expected in reader.updateConfig(config, expected: expected) }
                var draft = ThermostatSetupView.initialDraft(config: initial, roomIDs: ["bedroom"])
                draft.setThermostat(true, in: .home)
                let expectedDraft = draft
                var editing = ThermostatSetupSaveState(initial: reader.configSnapshot)
                #expect(writer.updateConfig(replacement))
                if refreshBeforeSave { #expect(await reader.refresh()) }
                let saved = editing.save(draft, using: editor.onSave)
                #expect(!saved && editing.error == ThermostatSetupView.conflictNotice)
                let cleared = editing.save(nil, using: editor.onSave)
                #expect(!cleared && editing.error == ThermostatSetupView.conflictNotice)
                #expect(storeA.load() == replacement)
                #expect(draft == expectedDraft && draft.thermostatHome == true)
                #expect(initial == nil || draft.home.contains("unavailable"))
                var freshEditor = ThermostatSetupSaveState(initial: reader.configSnapshot)
                let accepted = freshEditor.save(replacement, using: editor.onSave)
                #expect(accepted)
                #expect(freshEditor.error == nil && storeA.load() == replacement)
            }
        }
        #expect(ThermostatSetupView.conflictNotice.contains("another window"))
        #expect(ThermostatSetupView.conflictNotice.contains("Your draft hasn't been saved"))
        #expect(ThermostatSetupView.saveFailureMessage(.changed) == nil)
        #expect(ThermostatSetupView.saveFailureMessage(.unchanged) == nil)
        #expect(ThermostatSetupView.saveFailureMessage(.unavailable) == ThermostatSetupView.saveUnavailableNotice)
    }

    @Test("A successful thermostat-ID cleanup notifies the other window without losing choices")
    func cleanupPropagation() async throws {
        let (storeA, storeB) = stores()
        storeA.save(original)
        let cached = try insights()
        let identified = try insights(thermostat: true)
        let writer = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: storeA, fetch: { _, _ in identified }
        )
        let reader = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeB)
        #expect(await writer.refresh())
        let cleaned = original.excluding(["hall"])
        #expect(storeA.load() == cleaned && writer.config == cleaned && !writer.hasPendingConfig)
        #expect(reader.config == cleaned && reader.hasPendingConfig)
        #expect(reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
        #expect(cleaned.home.contains("unavailable") && cleaned.thermostatHome == nil)
    }

    @Test("A save during response publication cannot be overwritten by thermostat-ID cleanup")
    func changedDuringPublication() async throws {
        let (storeA, storeB) = stores()
        storeA.save(original)
        let cached = try insights()
        let identified = try insights(days: 30, thermostat: true)
        let replacement = changed
        let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
        let reader = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { _, _ in identified }
        )
        withObservationTracking {
            _ = reader.insights
        } onChange: {
            MainActor.assumeIsolated { _ = writer.updateConfig(replacement) }
        }
        #expect(await reader.refresh() == false)
        #expect(storeB.load() == replacement && reader.config == replacement)
        #expect(reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
    }

    @Test("An update or clear followed by restoration still invalidates old requests and drafts")
    func restoredSetupIsNotTheOriginalSnapshot() async throws {
        let cached = try insights()
        let stale = try insights(days: 30, thermostat: true)
        for intermediate in [changed, nil] as [PlacementConfig?] {
            let (storeA, storeB) = stores()
            storeA.save(original)
            let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
            var continuation: CheckedContinuation<PlacementInsights, Never>?
            let reader = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { _, _ in
                    await withCheckedContinuation { continuation = $0 }
                }
            )
            let originalSnapshot = reader.configSnapshot
            let editor = ThermostatSetupView(
                sensors: cached.sensors, snapshot: originalSnapshot, thermostatParticipationNotice: nil
            ) { config, expected in reader.updateConfig(config, expected: expected) }
            var editing = ThermostatSetupSaveState(initial: originalSnapshot)
            var draft = original
            draft.setThermostat(true, in: .home)
            let load = Task { await reader.refresh() }
            while continuation == nil { await Task.yield() }
            #expect(writer.updateConfig(intermediate) && writer.updateConfig(original))
            #expect(reader.config == original && reader.configSnapshot != originalSnapshot)
            #expect(reader.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
            continuation?.resume(returning: stale)
            #expect(await load.value == false)
            #expect(reader.insights?.windowDays == 14 && storeA.load() == original)
            let saved = editing.save(draft, using: editor.onSave)
            #expect(!saved && editing.error == ThermostatSetupView.conflictNotice)
            #expect(storeB.load() == original && draft.thermostatHome == true)
        }
    }

    @Test("Changes in another account do not affect its selections or pending state")
    func accountIsolation() async throws {
        let (storeA, _) = stores()
        let storeB = PlacementConfigStore(account: "b", defaults: storeA.defaults)
        let (otherSuite, _) = stores()
        storeA.save(original)
        storeB.save(changed)
        otherSuite.save(original)
        let cached = try insights()
        let writer = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: storeA)
        var requests: [PlacementConfig?] = []
        let other = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: storeB, fetch: { config, _ in
                requests.append(config)
                return cached
            }
        )
        let isolated = SensorPlacementService(insights: cached, sessionCheck: { true }, configStore: otherSuite)
        #expect(writer.updateConfig(changed))
        #expect(other.config == changed && !other.hasPendingConfig && other.pendingInsightsNotice == nil)
        #expect(isolated.config == original && !isolated.hasPendingConfig)
        #expect(await other.refresh())
        #expect(requests == [changed] && storeB.load() == changed)
    }
}

extension SensorPlacementSyncTests {
    @Test("An outdated or cancelled first load offers a retry for the current setup")
    func initialLoadOffersRetry() async throws {
        let stale = try insights(days: 30, thermostat: true)
        let latest = try insights(thermostat: true)
        let cases: [(PlacementConfig?, Bool)] = [(changed, false), (nil, false), (changed, true), (nil, true)]
        for (replacement, cancelled) in cases {
            let (storeA, storeB) = stores()
            storeA.save(original)
            let writer = SensorPlacementService(sessionCheck: { true }, configStore: storeA)
            var continuation: CheckedContinuation<PlacementInsights, Never>?
            var requests: [PlacementConfig?] = []
            let session = SyncTestSession()
            let reader = SensorPlacementService(
                sessionCheck: { session.valid }, configStore: storeB, fetch: { config, _ in
                    requests.append(config)
                    if requests.count == 1 {
                        return await withCheckedContinuation { continuation = $0 }
                    }
                    return latest
                }
            )
            let first = Task { await reader.refresh() }
            while continuation == nil { await Task.yield() }
            #expect(writer.updateConfig(replacement))
            #expect(reader.isLoading && reader.error == nil)
            let observed = SyncObservationFlag()
            withObservationTracking {
                _ = reader.error
            } onChange: {
                observed.set()
            }
            if cancelled { first.cancel() }
            continuation?.resume(returning: stale)
            #expect(await first.value == false)
            #expect(reader.insights == nil && !reader.isLoading && reader.hasPendingConfig)
            #expect(observed.value)
            #expect(reader.error == "Thermostat setup changed while loading. Retry to load the latest setup.")
            #expect(storeB.load() == replacement)
            session.valid = false
            #expect(reader.error == nil && reader.insights == nil && !reader.hasPendingConfig)
            session.valid = true

            #expect(await reader.refresh())
            #expect(requests == [original, replacement])
            #expect(reader.insights?.windowDays == 14 && reader.error == nil && !reader.hasPendingConfig)
            #expect(storeB.load() == replacement?.excluding(["hall"]))
        }
    }
}
