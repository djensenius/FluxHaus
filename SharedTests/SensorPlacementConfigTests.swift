//
//  SensorPlacementConfigTests.swift
//  FluxHaus Tests
//

import Foundation
import Testing
@testable import FluxHaus

private let configJSON = """
{
  "generatedAt": "2026-11-26T12:00:00Z", "windowDays": 14, "unit": "°C",
  "coverage": {"start": "2026-11-12T12:00:00Z", "end": "2026-11-26T12:00:00Z",
    "hvacHistoryAvailable": true, "morningEvents": 10, "returnEvents": 0,
    "participationConfigured": true, "followMe": false, "occupancyAvailable": false,
    "comfortScheduleAvailable": true, "wakeEvents": 12, "coolingFrom": "2026-04-28T00:00:00Z",
    "coolingTo": "2026-10-15T00:00:00Z", "coolingEvents": 40},
  "sensors": [
    {"id": "bedroom", "name": "Bedroom", "isThermostat": false, "averageOffset": -0.5,
     "morningOffset": -1.2, "returnOffset": null, "overshoot": null, "sampleCount": 60,
     "classification": "cold", "wakeOffset": -1.4, "coolingOffset": null,
     "participation": {"home": true, "sleep": false, "away": null}, "occupiedShare": {"wake": 0.25, "home": null},
     "verdict": "cold_outlier", "verdictSummary": "Bedroom reads cold when waking.",
     "periodOffsets": {"sleep": -0.4, "wake": -1.3, "home": null, "heatingRuns": -0.9, "cooling": null},
     "wakeOvershoot": 1.1, "coolingUndershoot": null,
     "consistency": {"days": 14, "coldDays": 12, "warmDays": 0, "coolingDays": 0},
     "recommendationIds": ["wake"]},
    {"id": "home", "name": "Home", "isThermostat": true, "averageOffset": 0.0,
     "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 60,
     "classification": "cold", "verdict": "cold_outlier", "occupiedShare": 0.3},
    {"id": "kitchen", "name": "Kitchen", "isThermostat": false, "averageOffset": 0.3,
     "morningOffset": 0.2, "returnOffset": null, "overshoot": null, "sampleCount": 60,
     "classification": "warm"}
  ],
  "recommendations": [
    {"id": "passive", "severity": "medium", "sensorId": null, "action": "none", "title": "Passive warmth",
     "detail": "Sensors aren't the cause.", "mode": "heating", "period": "home", "affectedSensorIds": [],
     "likelyCauses": ["solar gain"]},
    {"id": "future", "severity": "low", "sensorId": null, "action": "rearrange", "title": "Future",
     "detail": "Later.", "mode": "dehumidify", "period": "lunch", "comfortSetting": "vacation"},
    {"id": "cool", "severity": "medium", "sensorId": "kitchen", "action": "move", "title": "Cool",
     "detail": "Shade it.", "mode": "cooling", "period": null},
    {"id": "wake", "severity": "high", "sensorId": "bedroom", "action": "remove_from_setting",
     "title": "Wake", "detail": "Remove it.", "mode": "heating", "period": "wake", "comfortSetting": "home",
     "affectedSensorIds": ["kitchen"], "likelyCauses": ["near a window or exterior wall"]}
  ]
}
"""

@MainActor
private final class ConfigTestSession {
    var valid = true
}

@MainActor
struct SensorPlacementConfigTests {
    private func decode(_ json: String = configJSON) throws -> PlacementInsights {
        try JSONDecoder().decode(PlacementInsights.self, from: Data(json.utf8))
    }

    private func defaults() -> UserDefaults {
        let suite = "SensorPlacementConfigTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let sample = PlacementConfig(home: ["kitchen", "bedroom"], sleep: [], away: ["a+b"], followMe: true)

    @Test("Config is sent as sorted comma-separated ids, empty for none, plus Follow Me")
    func queryEncoding() throws {
        let request = SensorPlacementService.request(authorization: "Bearer x", config: sample)
        let url = try #require(request.url)
        #expect(url.absoluteString == "https://api.fluxhaus.io/climate/placement-insights"
                + "?days=14&home=bedroom,kitchen&sleep=&away=a%2Bb&followMe=true")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "away" })?.value == "a+b")
        let unconfigured = SensorPlacementService.request(authorization: "Bearer x", config: nil)
        #expect(unconfigured.url?.query == "days=14")
    }

    @Test("fetchInsights sends the config")
    func fetchSendsConfig() async throws {
        var queries: [String?] = []
        _ = try await SensorPlacementService.fetchInsights(
            config: sample, sessionCheck: { true }, authorization: { "Basic demo" }, hasOIDCToken: { false },
            send: { request in
                queries.append(request.url?.query)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(configJSON.utf8), response)
            }
        )
        #expect(queries.first??.contains("followMe=true") == true)
    }

    @Test("Persistence is scoped to the session that saved it")
    func persistenceScoping() {
        let defaults = defaults()
        let first = PlacementConfigStore(session: "first", defaults: defaults)
        first.save(sample)
        #expect(first.load() == sample)
        #expect(PlacementConfigStore(session: "first", defaults: defaults).load() == sample)
        #expect(PlacementConfigStore(session: "second", defaults: defaults).load() == nil)
        first.save(nil)
        #expect(first.load() == nil)
    }

    @Test("The service loads, updates and hides the config with the session")
    func serviceConfig() {
        let defaults = defaults()
        let store = PlacementConfigStore(session: "first", defaults: defaults)
        store.save(sample)
        let session = ConfigTestSession()
        let service = SensorPlacementService(sessionCheck: { session.valid }, configStore: store, fetch: { _, _ in
            throw PlacementRequestError.invalidResponse
        })
        #expect(service.config == sample)
        #expect(!service.updateConfig(sample))
        var changed = sample
        changed.followMe = false
        #expect(service.updateConfig(changed))
        #expect(store.load() == changed)
        #expect(service.updateConfig(nil))
        #expect(store.load() == nil)
        session.valid = false
        #expect(service.config == nil)
        #expect(!service.updateConfig(sample))
        #expect(store.load() == nil)
    }

    @Test("New fields decode and unknown enum values fall back instead of failing")
    func decodingNewFields() throws {
        let result = try decode()
        let coverage = result.coverage
        #expect(coverage.participationConfigured == true)
        #expect(coverage.followMe == false)
        #expect(coverage.occupancyAvailable == false)
        #expect(coverage.comfortScheduleAvailable == true)
        #expect(coverage.wakeEvents == 12)
        #expect(coverage.coolingFrom == "2026-04-28T00:00:00Z")
        #expect(coverage.coolingEvents == 40)
        let bedroom = try #require(result.sensors.first)
        #expect(bedroom.wakeOffset == -1.4)
        #expect(bedroom.coolingOffset == nil)
        #expect(bedroom.participation == PlacementInsights.Participation(home: true, sleep: false, away: nil))
        #expect(bedroom.occupiedShare == PlacementInsights.OccupiedShare(wake: 0.25, home: nil))
        #expect(result.sensors.last?.participation == nil)
        #expect(result.sensors.last?.verdict == nil)
        #expect(result.sensors.last?.outlierVerdict == .warmOutlier)
        let future = try #require(result.recommendations.first(where: { $0.id == "future" }))
        #expect(future.mode == .unknown)
        #expect(future.period == .unknown)
        #expect(future.comfortSetting == .unknown)
        #expect(future.affectedSensorIds.isEmpty)
        #expect(SensorPlacementView.actionLabel(future.action) == nil)
        let wake = try #require(result.recommendations.last)
        #expect(wake.mode == .heating)
        #expect(wake.period == .wake)
        #expect(wake.comfortSetting == .home)
        #expect(wake.affectedSensorIds == ["kitchen"])
        #expect(wake.likelyCauses == ["near a window or exterior wall"])
        #expect(result.recommendations[2].period == nil)
        #expect(SensorPlacementView.actionLabel("none") == "No sensor change needed")
        #expect(SensorPlacementView.actionLabel(wake.action, setting: wake.comfortSetting)
                == "Consider removing from the Home comfort setting")
        #expect(SensorPlacementView.actionLabel("add_to_setting", setting: .sleep)
                == "Consider adding to the Sleep comfort setting")
        #expect(SensorPlacementView.periodLabel(.wake) == "When waking")
        let groups = SensorPlacementView.groups(result.rankedRecommendations)
        #expect(groups.map(\.mode) == [.heating, .cooling, nil])
        #expect(groups.map { $0.items.map(\.id) } == [["wake", "passive"], ["cool"], ["future"]])
    }

    @Test("Invalid new coverage or sensor values are rejected")
    func invalidNewFields() {
        let invalid = [
            configJSON.replacingOccurrences(of: "\"wake\": 0.25", with: "\"wake\": 1.5"),
            configJSON.replacingOccurrences(of: "\"coldDays\": 12", with: "\"coldDays\": -1"),
            configJSON.replacingOccurrences(of: "\"wakeEvents\": 12", with: "\"wakeEvents\": -1"),
            configJSON.replacingOccurrences(of: "\"coolingTo\": \"2026-10-15T00:00:00Z\"", with: "\"coolingTo\": \"x\"")
        ]
        for json in invalid {
            #expect(throws: DecodingError.self) { try decode(json) }
        }
    }

    @Test("Per-sensor drill-down decodes; the thermostat is the Ecobee average; older servers degrade")
    func drillDown() throws {
        let result = try decode()
        let bedroom = try #require(result.sensors.first)
        #expect(bedroom.verdict == .coldOutlier)
        #expect(bedroom.outlierVerdict == .coldOutlier)
        #expect(bedroom.verdictSummary == "Bedroom reads cold when waking.")
        #expect(bedroom.periodOffsets?.wake == -1.3)
        #expect(bedroom.periodOffsets?.home == nil)
        #expect(bedroom.wakeOvershoot == 1.1)
        #expect(bedroom.consistency?.coldDays == 12)
        #expect(bedroom.consistency?.coolingWarmDays == nil)
        #expect(bedroom.relatedRecommendations(in: result).map(\.id) == ["wake"])
        #expect(SensorPlacementDetailView.offsetRows(bedroom).map(\.label)
                == ["Overnight", "Waking", "While heating"])
        #expect(SensorPlacementDetailView.patternLines(bedroom, unit: "°C").contains(
            "Heating: cooler on 12 of 14 days, warmer on 0 of 14 days"))
        #expect(!SensorPlacementDetailView.patternLines(bedroom, unit: "°C").contains { $0.hasPrefix("Cooling:") })

        let thermostat = try #require(result.sensors.first(where: { $0.isThermostat }))
        #expect(thermostat.displayName == "Thermostat (Ecobee average)")
        #expect(thermostat.outlierVerdict == nil)
        #expect(thermostat.occupiedShare == nil)  // superseded scalar shape is ignored
        #expect(SensorPlacementView.name("home", in: result) == "Thermostat (Ecobee average)")

        let kitchen = try #require(result.sensors.first(where: { $0.id == "kitchen" }))
        #expect(kitchen.displayName == "Kitchen")
        #expect(kitchen.verdict == nil && kitchen.periodOffsets == nil && kitchen.consistency == nil)
        #expect(kitchen.recommendationIds == nil)
        #expect(kitchen.relatedRecommendations(in: result).map(\.id) == ["wake", "cool"])
        #expect(SensorPlacementDetailView.offsetRows(kitchen).map(\.label) == ["Overall", "Morning"])
        #expect(SensorPlacementDetailView.patternLines(kitchen, unit: "°C").isEmpty)

        let future = configJSON.replacingOccurrences(of: "\"verdict\": \"cold_outlier\", \"verdictSummary\"",
                                                     with: "\"verdict\": \"lukewarm\", \"verdictSummary\"")
        #expect(try decode(future).sensors.first?.outlierVerdict == .unknown)
    }

    @Test("A rejected config drops unknown sensors and retries, persisting the pruned config")
    func staleSensorIsPruned() async throws {
        let result = try decode()
        let store = PlacementConfigStore(session: "first", defaults: defaults())
        let stale = PlacementConfig(home: ["bedroom", "gone"], sleep: [], away: [], followMe: false)
        store.save(stale)
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: result, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                if config?.home.contains("gone") == true { throw PlacementRequestError.http(400) }
                return result
            }
        )
        await service.refresh()
        let pruned = PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: false)
        #expect(requested == [stale, pruned])
        #expect(service.config == pruned)
        #expect(store.load() == pruned)
        #expect(service.notice == SensorPlacementService.prunedNotice)
        #expect(service.error == nil)
    }

    @Test("An unusable config falls back to unconfigured insights with a clear message")
    func rejectedConfigFallsBack() async throws {
        let result = try decode()
        let store = PlacementConfigStore(session: "first", defaults: defaults())
        let config = PlacementConfig(home: ["bedroom"], sleep: [], away: [], followMe: true)
        store.save(config)
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(sessionCheck: { true }, configStore: store, fetch: { config, _ in
            requested.append(config)
            if config != nil { throw PlacementRequestError.http(400) }
            return result
        })
        await service.refresh()
        #expect(requested == [config, nil])
        #expect(service.insights != nil)
        #expect(service.config == config)
        #expect(service.notice == SensorPlacementService.rejectedNotice)
        #expect(service.error == nil)
        #expect(service.updateConfig(nil))
        await service.refresh()
        #expect(requested.last == .some(nil))
        #expect(service.notice == nil)
    }
}
