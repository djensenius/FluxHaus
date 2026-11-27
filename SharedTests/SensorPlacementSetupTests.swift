//
//  SensorPlacementSetupTests.swift
//  FluxHaus Tests
//

import Foundation
import Testing
@testable import FluxHaus

private func setupInsights(
    rooms: [String], includeThermostat: Bool = true, sensorFields: String = "",
    participationConfigured: Bool? = true, thermostatParticipationSupported: Bool? = nil
) throws -> PlacementInsights {
    let reported = rooms.map { ($0, false) } + (includeThermostat ? [("thermostat", true)] : [])
    let sensors = reported.map { id, thermostat in
        """
        {"id": "\(id)", "name": "\(id)", "isThermostat": \(thermostat), "averageOffset": 0,
         "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 1,
         "classification": "ok"\(sensorFields)}
        """
    }
    let participation = participationConfigured.map { ", \"participationConfigured\": \($0)" } ?? ""
    let thermostatSupport = thermostatParticipationSupported
        .map { ", \"thermostatParticipationSupported\": \($0)" } ?? ""
    let json = """
    {"generatedAt": "2026-11-26T12:00:00Z", "windowDays": 14, "unit": "°C",
     "coverage": {"start": "2026-11-12T12:00:00Z", "end": "2026-11-26T12:00:00Z",
       "hvacHistoryAvailable": true, "morningEvents": 0, "returnEvents": 0\(participation)\(thermostatSupport)},
     "sensors": [\(sensors.joined(separator: ","))], "recommendations": []}
    """
    return try JSONDecoder().decode(PlacementInsights.self, from: Data(json.utf8))
}

@MainActor
private final class SetupTestSession {
    var valid = true
}

@MainActor
struct SensorPlacementSetupTests {
    private func store() -> PlacementConfigStore {
        let defaults = UserDefaults(suiteName: "SensorPlacementSetupTests-\(UUID().uuidString)")!
        return PlacementConfigStore(account: "test-account", defaults: defaults)
    }

    @Test("An empty history permits setup, save and clear only for a valid stable account")
    func emptyHistorySetup() throws {
        let result = try setupInsights(rooms: [], includeThermostat: false)
        let store = store()
        let session = SetupTestSession()
        let service = SensorPlacementService(
            insights: result, sessionCheck: { session.valid }, configStore: store, fetch: { _, _ in result }
        )
        #expect(service.canEditConfig)
        #expect(!SensorPlacementService(sessionCheck: { true }, configStore: store).canEditConfig)
        #expect(!SensorPlacementService(insights: result, sessionCheck: { true }, configStore: nil).canEditConfig)
        let editor = ThermostatSetupView(
            sensors: result.sensors, snapshot: service.configSnapshot, thermostatParticipationNotice: nil
        ) { config, expected in service.updateConfig(config, expected: expected) }
        #expect(editor.sensors.isEmpty && !editor.wasConfigured)
        let empty = ThermostatSetupView.initialDraft(config: nil, roomIDs: editor.sensors.map(\.id))
        for setting in PlacementConfig.Setting.allCases {
            #expect(empty.sensors(in: setting).isEmpty)
            #expect(empty.thermostat(in: setting) == nil)
        }
        #expect(!empty.followMe)
        #expect(empty.queryItems.prefix(3).map(\.value) == ["", "", ""])
        #expect(!empty.queryItems.contains { $0.name.hasPrefix("thermostat") })
        #expect(ThermostatSetupView.noRoomSensorsNotice.contains("listed in this analysis"))
        #expect(ThermostatSetupView.noRoomSensorsNotice.contains("saving selects no room sensors"))
        #expect(ThermostatSetupView.followMeExplanation.contains("isn't detected"))
        #expect(ThermostatSetupView.followMeExplanation.contains("starts off"))
        #expect(ThermostatSetupView.followMeExplanation.contains("match it to your Ecobee setting"))
        #expect(editor.onSave(empty, service.configSnapshot) == .changed)
        #expect(store.load() == empty && service.canEditConfig)

        var thermostatOnly = empty
        thermostatOnly.setThermostat(true, in: .home)
        #expect(service.updateConfig(thermostatOnly))
        #expect(store.load() == thermostatOnly)
        #expect(thermostatOnly.thermostatSleep == nil && thermostatOnly.thermostatAway == nil)
        let savedEditor = ThermostatSetupView(
            sensors: result.sensors, snapshot: service.configSnapshot, thermostatParticipationNotice: nil
        ) { config, expected in service.updateConfig(config, expected: expected) }
        #expect(savedEditor.wasConfigured && savedEditor.sensors.isEmpty)
        #expect(savedEditor.onSave(nil, service.configSnapshot) == .changed)
        #expect(store.load() == nil && service.canEditConfig)
        session.valid = false
        #expect(!service.canEditConfig && !service.updateConfig(empty))
        #expect(service.config == nil && store.load() == nil)
    }

    @Test("Missing IDs appear in every setting and can be added, removed and restored")
    func mixedUnavailableSelections() throws {
        // A duplicate room entry must not make a reported thermostat ID selectable as a room.
        let result = try setupInsights(rooms: ["bedroom", "thermostat"])
        let saved = PlacementConfig(
            home: ["bedroom", "missing-b", "missing-a", "thermostat"],
            sleep: ["missing-b", "thermostat"], away: ["missing-a"], followMe: true,
            thermostatHome: nil, thermostatSleep: false, thermostatAway: true
        )
        let store = store()
        store.save(saved)
        let service = SensorPlacementService(
            insights: result, sessionCheck: { true }, configStore: store, fetch: { _, _ in result }
        )
        let editor = ThermostatSetupView(
            sensors: result.sensors, snapshot: service.configSnapshot, thermostatParticipationNotice: nil
        ) { config, expected in service.updateConfig(config, expected: expected) }
        #expect(editor.sensors.map(\.id) == ["bedroom"])
        #expect(editor.reportedSensorIDs == ["bedroom", "thermostat"])
        let unavailable = ThermostatSetupView.unavailableSensorIDs(
            config: saved, reportedIDs: editor.reportedSensorIDs
        )
        #expect(unavailable == ["missing-a", "missing-b"])
        #expect(unavailable.map { saved.sensors(in: .home).contains($0) } == [true, true])
        #expect(unavailable.map { saved.sensors(in: .sleep).contains($0) } == [false, true])
        #expect(unavailable.map { saved.sensors(in: .away).contains($0) } == [true, false])
        let first = ThermostatSetupView.unavailableSensorLabel("missing-a")
        let second = ThermostatSetupView.unavailableSensorLabel("missing-b")
        #expect(first != second && first.contains("missing-a") && second.contains("missing-b"))
        #expect(first.contains("Unavailable saved ID in current sensor list"))

        var draft = ThermostatSetupView.initialDraft(config: saved, roomIDs: editor.sensors.map(\.id))
        draft.set(false, sensor: "missing-a", in: .home)
        #expect(!draft.home.contains("missing-a") && draft.away.contains("missing-a"))
        #expect(unavailable.contains("missing-a"))
        draft.set(true, sensor: "missing-a", in: .home)
        #expect(draft == saved)
        draft.set(true, sensor: "missing-a", in: .sleep)
        #expect(draft.sleep == ["missing-a", "missing-b", "thermostat"] && draft.home == saved.home)
        draft.set(false, sensor: "missing-a", in: .sleep)
        #expect(draft == saved)
        // Cancelling leaves storage unchanged; save a removal and an addition in different settings.
        #expect(store.load() == saved)
        draft.set(false, sensor: "missing-a", in: .home)
        draft.set(true, sensor: "missing-a", in: .sleep)
        #expect(editor.onSave(draft, service.configSnapshot) == .changed)
        let expected = draft.excluding(["thermostat"])
        #expect(service.config == expected && store.load() == expected)
        #expect(expected.home == ["bedroom", "missing-b"])
        #expect(expected.sleep == ["missing-a", "missing-b"] && expected.away == ["missing-a"])
        #expect(expected.thermostatHome == nil && expected.thermostatSleep == false && expected.thermostatAway == true)
    }

    @Test("All saved rooms remain individually available for editing without room discovery")
    func allUnavailableSelections() throws {
        let saved = PlacementConfig(home: ["missing-b", "missing-a", "thermostat"], sleep: ["missing-b"],
                                    away: ["missing-a"], followMe: false)
        for hasThermostat in [true, false] {
            let result = try setupInsights(rooms: [], includeThermostat: hasThermostat)
            let editor = ThermostatSetupView(
                sensors: result.sensors, snapshot: .init(config: saved, revision: nil),
                thermostatParticipationNotice: nil
            ) { _, _ in .unchanged }
            #expect(editor.sensors.isEmpty && editor.wasConfigured)
            let unavailable = ThermostatSetupView.unavailableSensorIDs(
                config: saved, reportedIDs: editor.reportedSensorIDs
            )
            #expect(unavailable == (hasThermostat
                                    ? ["missing-a", "missing-b"] : ["missing-a", "missing-b", "thermostat"]))
            var draft = ThermostatSetupView.initialDraft(config: saved, roomIDs: [])
            draft.set(false, sensor: "missing-b", in: .sleep)
            #expect(draft.sleep.isEmpty && draft.home == saved.home && draft.away == saved.away)
            draft.set(true, sensor: "missing-b", in: .sleep)
            #expect(draft == saved)
            draft.set(true, sensor: "missing-b", in: .away)
            #expect(draft.away == ["missing-a", "missing-b"] && unavailable.contains("missing-b"))
            draft.set(false, sensor: "missing-b", in: .away)
            #expect(draft == saved)
            if !hasThermostat {
                let store = store()
                store.save(saved)
                let service = SensorPlacementService(
                    insights: result, sessionCheck: { true }, configStore: store, fetch: { _, _ in result }
                )
                draft.setThermostat(true, in: .home)
                #expect(service.updateConfig(draft))
                #expect(store.load()?.home.contains("thermostat") == true)
                #expect(ThermostatSetupView.unavailableSensorLabel("thermostat")
                        == "Unavailable saved ID in current sensor list: thermostat")
            }
        }
    }

    @Test("A fresh retry includes a returned sensor that the cached list missed")
    func freshDiscoveryIncludesReturnedSensor() async throws {
        let cached = try setupInsights(rooms: ["bedroom"])
        let fresh = try setupInsights(rooms: ["bedroom", "returned"])
        let discovery = try setupInsights(rooms: ["bedroom", "returned"], participationConfigured: false)
        let saved = PlacementConfig(
            home: ["bedroom", "returned", "removed"], sleep: ["returned"], away: ["removed"], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        let reduced = PlacementConfig(
            home: ["bedroom", "returned"], sleep: ["returned"], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        let store = store()
        store.save(saved)
        let savedData = store.defaults.data(forKey: store.key)
        var requests: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requests.append(config)
                if config?.home.contains("removed") == true { throw PlacementRequestError.http(400) }
                return config == nil ? discovery : fresh
            }
        )
        #expect(await service.refresh())
        #expect(requests == [saved, nil, reduced])
        #expect(service.config == saved && store.load() == saved)
        #expect(store.defaults.data(forKey: store.key) == savedData)
        #expect(service.insights?.roomSensorIDs == ["bedroom", "returned"])
        #expect(service.notice == SensorPlacementService.reducedConfigNotice)
    }

    @Test("Freshly identified thermostat IDs are excluded while missing room IDs remain saved")
    func freshDiscoveryExcludesThermostat() async throws {
        let cached = try setupInsights(rooms: [], includeThermostat: false)
        let fresh = try setupInsights(rooms: ["bedroom"], participationConfigured: false)
        let reducedResponse = try setupInsights(rooms: ["bedroom"], includeThermostat: false)
        let recovered = try setupInsights(rooms: ["bedroom", "missing"], includeThermostat: false)
        let saved = PlacementConfig(
            home: ["bedroom", "missing", "thermostat"], sleep: ["thermostat"], away: [], followMe: true,
            thermostatHome: nil, thermostatSleep: false, thermostatAway: true
        )
        let retained = saved.excluding(["thermostat"])
        let reduced = retained.pruned(to: ["bedroom"])
        let store = store()
        store.save(saved)
        var requests: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: cached, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requests.append(config)
                switch requests.count {
                case 1: throw PlacementRequestError.http(400)
                case 2: return fresh
                case 3: return reducedResponse
                default: return recovered
                }
            }
        )
        #expect(await service.refresh())
        #expect(requests == [saved, nil, reduced])
        #expect(service.config == retained && store.load() == retained)
        #expect(service.notice == SensorPlacementService.reducedConfigNotice)
        #expect(await service.refresh())
        #expect(requests == [saved, nil, reduced, retained])
        #expect(service.config == retained && store.load() == retained && service.notice == nil)
    }

    @Test("Dropping only an identified thermostat does not claim saved room selections were omitted")
    func thermostatOnlyReduction() async throws {
        let cached = try setupInsights(rooms: [], includeThermostat: false)
        let discovery = try setupInsights(rooms: ["bedroom"], participationConfigured: false)
        let saved = PlacementConfig(home: ["bedroom", "thermostat"], sleep: [], away: [], followMe: false)
        let retained = saved.excluding(["thermostat"])
        for configured in [nil, false, true] as [Bool?] {
            let fresh = try setupInsights(rooms: ["bedroom"], participationConfigured: configured)
            let store = store()
            store.save(saved)
            var requests: [PlacementConfig?] = []
            let service = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                    requests.append(config)
                    if config?.home.contains("thermostat") == true { throw PlacementRequestError.http(400) }
                    return config == nil ? discovery : fresh
                }
            )
            #expect(await service.refresh())
            #expect(requests == [saved, nil, retained])
            #expect(service.config == retained && store.load() == retained)
            #expect(service.notice == (configured == true ? nil : SensorPlacementService.setupNotUsedNotice))
        }
    }

    @Test("A rejected reduced retry leaves the saved setup and explains unconfigured tips")
    func rejectedReducedRetry() async throws {
        let fresh = try setupInsights(rooms: ["bedroom"], participationConfigured: false)
        let recovered = try setupInsights(rooms: ["bedroom"])
        let saved = PlacementConfig(home: ["bedroom", "missing"], sleep: ["missing"], away: [], followMe: false)
        let reduced = saved.pruned(to: ["bedroom"])
        let store = store()
        store.save(saved)
        let savedData = store.defaults.data(forKey: store.key)
        var requests: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: fresh, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requests.append(config)
                if config != nil && requests.count <= 3 { throw PlacementRequestError.http(400) }
                return config == nil ? fresh : recovered
            }
        )
        #expect(await service.refresh())
        #expect(requests == [saved, nil, reduced])
        #expect(service.config == saved && store.load() == saved)
        #expect(store.defaults.data(forKey: store.key) == savedData)
        #expect(service.notice == SensorPlacementService.rejectedNotice)
        #expect(service.notice?.contains("saved setup is kept") == true)
        #expect(await service.refresh())
        #expect(requests == [saved, nil, reduced, saved])
        #expect(service.config == saved && store.load() == saved && service.notice == nil)
        #expect(store.defaults.data(forKey: store.key) == savedData)
    }

    @Test("Period offset explanations do not assume a thermostat reading is present")
    func sourceNeutralBaseline() throws {
        let fields = #", "periodOffsets": {"sleep": -0.5, "wake": null, "home": null, "heatingRuns": null, "#
            + #""cooling": null}"#
        let result = try setupInsights(rooms: ["bedroom"], includeThermostat: false, sensorFields: fields)
        let sensor = try #require(result.sensors.first)
        #expect(result.thermostatIDs.isEmpty)
        #expect(SensorPlacementDetailView.offsetBaseline(sensor)
                == "Positive means warmer than the estimated effective comfort average; negative means cooler.")
        #expect(ThermostatSetupView.thermostatReadingExplanation.contains("identified climate-reported"))
    }

    @Test("Zero cooling events describe available history only when there is no complete window")
    func noCoolingHistoryNotice() throws {
        let json = """
        {"start": "2026-03-06T12:00:00Z", "end": "2026-03-20T12:00:00Z", "hvacHistoryAvailable": true,
         "hvacEarliestStateAt": "2026-03-01T12:00:00Z", "morningEvents": 0, "returnEvents": 0, "coolingEvents": 0}
        """
        func notice(_ json: String) throws -> String? {
            let coverage = try JSONDecoder().decode(PlacementInsights.Coverage.self, from: Data(json.utf8))
            return SensorPlacementView.noCoolingHistoryNotice(coverage)
        }
        let expected = "No cooling activity was found in the available history; there are no cooling tips."
        #expect(try notice(json) == expected)
        #expect(try notice(json.replacingOccurrences(of: "true", with: "false")) == expected)
        #expect(try notice(json.replacingOccurrences(
            of: "\"coolingEvents\": 0", with: "\"coolingEvents\": null"
        )) == nil)
        #expect(try notice(json.replacingOccurrences(of: "\"coolingEvents\": 0", with: "\"coolingEvents\": 1")) == nil)
        let start = "\"coolingFrom\": \"2026-03-01T00:00:00Z\""
        let end = "\"coolingTo\": \"2026-03-19T00:00:00Z\""
        func window(_ fields: String) -> String {
            json.replacingOccurrences(of: "\"coolingEvents\": 0", with: "\"coolingEvents\": 0, \(fields)")
        }
        #expect(try notice(window(start + ", " + end)) == nil)
        #expect(try notice(window(start)) == expected)
        #expect(try notice(window(end)) == expected)
    }
}

@MainActor
struct SensorPlacementCompatibilityTests {
    private let setup = PlacementConfig(
        home: ["bedroom"], sleep: ["office"], away: ["living"], followMe: true,
        thermostatHome: true, thermostatSleep: false, thermostatAway: nil
    )

    private func store(_ config: PlacementConfig?) -> PlacementConfigStore {
        let defaults = UserDefaults(suiteName: "SensorPlacementCompatibilityTests-\(UUID().uuidString)")!
        let store = PlacementConfigStore(account: "test-account", defaults: defaults)
        store.save(config)
        return store
    }

    @Test("A four-sensor legacy response warns that the whole saved setup was ignored until supported")
    func legacyAndRecovery() async throws {
        let rooms = ["bedroom", "office", "living"]
        let legacy = try setupInsights(rooms: rooms, participationConfigured: nil)
        let unsupported = try setupInsights(
            rooms: rooms, participationConfigured: false, thermostatParticipationSupported: true
        )
        let supported = try setupInsights(
            rooms: rooms, participationConfigured: true, thermostatParticipationSupported: true
        )
        #expect(legacy.sensors.count == 4)
        #expect(legacy.coverage.participationConfigured == nil)
        #expect(legacy.coverage.thermostatParticipationSupported == nil)
        let request = SensorPlacementService.request(authorization: "Bearer synthetic", config: setup)
        let query = try #require(request.url?.query)
        #expect(query == "days=14&home=bedroom&sleep=office&away=living&followMe=true"
                + "&thermostatHome=true&thermostatSleep=false")
        let store = store(setup)
        let savedData = store.defaults.data(forKey: store.key)
        let session = SetupTestSession()
        var requests: [PlacementConfig?] = []
        let service = SensorPlacementService(sessionCheck: { session.valid }, configStore: store, fetch: { config, _ in
            requests.append(config)
            switch requests.count {
            case 1, 2: return legacy
            case 3: throw PlacementRequestError.http(503)
            case 4: return unsupported
            default: return supported
            }
        })
        for _ in 0..<2 {
            #expect(await service.refresh())
            let notice = try #require(service.notice)
            #expect(notice == SensorPlacementService.setupNotUsedNotice)
            #expect(notice.contains("don't account") && notice.contains("room sensor choices"))
            #expect(notice.contains("built-in sensor choices") && notice.contains("Follow Me"))
            #expect(notice.contains("remains saved") && notice.contains("retried on refresh"))
            #expect(service.thermostatParticipationNotice == SensorPlacementService.thermostatUnsupportedNotice)
            #expect(service.config == setup && store.load() == setup)
            #expect(store.defaults.data(forKey: store.key) == savedData)
        }
        var edited = setup
        edited.setThermostat(false, in: .away)
        #expect(service.updateConfig(edited))
        let editedData = store.defaults.data(forKey: store.key)
        #expect(service.notice == SensorPlacementService.setupNotUsedNotice && service.hasPendingConfig)
        #expect(await service.refresh() == false)
        #expect(service.error == "Could not load sensor placement (HTTP 503).")
        #expect(service.notice == SensorPlacementService.setupNotUsedNotice)
        #expect(service.pendingInsightsNotice == SensorPlacementService.pendingConfigNotice)
        #expect(store.load() == edited && store.defaults.data(forKey: store.key) == editedData)
        let editor = ThermostatSetupView(
            sensors: legacy.sensors, snapshot: service.configSnapshot,
            thermostatParticipationNotice: service.thermostatParticipationNotice, analysisNotice: service.notice
        ) { _, _ in .unchanged }
        #expect(editor.analysisNotice == SensorPlacementService.setupNotUsedNotice)
        #expect(editor.thermostatParticipationNotice == SensorPlacementService.thermostatUnsupportedNotice)
        session.valid = false
        #expect(service.notice == nil && service.thermostatParticipationNotice == nil && service.config == nil)
        #expect(store.load() == edited)
        session.valid = true
        #expect(await service.refresh())
        #expect(service.notice == SensorPlacementService.setupNotUsedNotice)
        #expect(service.thermostatParticipationNotice == nil)
        #expect(service.updateConfig(nil))
        #expect(service.notice == nil && store.load() == nil)
        #expect(service.updateConfig(edited))
        #expect(service.notice == SensorPlacementService.setupNotUsedNotice && store.load() == edited)
        let restoredData = store.defaults.data(forKey: store.key)
        #expect(await service.refresh())
        #expect(service.notice == nil && service.thermostatParticipationNotice == nil)
        #expect(requests == [setup, setup, edited, edited, edited])
        #expect(service.config == edited && store.load() == edited && !service.hasPendingConfig)
        #expect(store.defaults.data(forKey: store.key) == restoredData)
    }

    @Test("A genuinely unconfigured request does not warn that a saved setup was ignored")
    func unconfiguredRequests() async throws {
        for configured in [nil, false, true] as [Bool?] {
            let result = try setupInsights(rooms: ["bedroom"], participationConfigured: configured)
            let store = store(nil)
            var requests: [PlacementConfig?] = []
            let service = SensorPlacementService(sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requests.append(config)
                return result
            })
            #expect(await service.refresh())
            #expect(requests == [nil] && service.config == nil && store.load() == nil)
            #expect(service.notice == nil)
            #expect(service.thermostatParticipationNotice == SensorPlacementService.thermostatUnsupportedNotice)
        }
    }

    @Test("Reduced replies warn accurately and a later refresh retries every saved choice")
    func reducedRepliesAndRecovery() async throws {
        let cached = try setupInsights(rooms: ["bedroom"], includeThermostat: false)
        let discovery = try setupInsights(rooms: ["bedroom", "office"], participationConfigured: false)
        let recovered = try setupInsights(
            rooms: ["bedroom", "office", "removed"], thermostatParticipationSupported: true
        )
        let saved = PlacementConfig(
            home: ["bedroom", "removed"], sleep: ["office"], away: ["removed"], followMe: true,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        let reduced = saved.pruned(to: ["bedroom", "office"])
        for configured in [nil, false, true] as [Bool?] {
            let response = try setupInsights(
                rooms: ["bedroom", "office"], participationConfigured: configured,
                thermostatParticipationSupported: true
            )
            let store = store(saved)
            let savedData = store.defaults.data(forKey: store.key)
            var requests: [PlacementConfig?] = []
            let service = SensorPlacementService(
                insights: cached, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                    requests.append(config)
                    switch requests.count {
                    case 1: throw PlacementRequestError.http(400)
                    case 2: return discovery
                    case 3: return response
                    default: return recovered
                    }
                }
            )
            #expect(await service.refresh())
            #expect(requests == [saved, nil, reduced])
            #expect(service.config == saved && store.load() == saved)
            #expect(store.defaults.data(forKey: store.key) == savedData)
            #expect(service.notice == (configured == true
                ? SensorPlacementService.reducedConfigNotice : SensorPlacementService.setupNotUsedNotice))
            #expect(service.thermostatParticipationNotice == nil)
            #expect(await service.refresh())
            #expect(requests == [saved, nil, reduced, saved])
            #expect(service.config == saved && store.load() == saved && service.notice == nil)
            #expect(store.defaults.data(forKey: store.key) == savedData)
        }
    }
}
