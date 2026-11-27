//
//  SensorPlacementConfigTests.swift
//  FluxHaus Tests
//

import Foundation
import SwiftUI
import Testing
import UIKit
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

private let unconfiguredJSON = configJSON.replacingOccurrences(
    of: "\"participationConfigured\": true", with: "\"participationConfigured\": false"
)

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

    private let sample = PlacementConfig(
        home: ["kitchen", "bedroom"], sleep: [], away: ["a+b"], followMe: true,
        thermostatHome: true, thermostatSleep: false, thermostatAway: nil
    )

    @Test("Config keeps the old query order and appends known thermostat choices")
    func queryEncoding() throws {
        let legacy = PlacementConfig(home: ["kitchen", "bedroom"], sleep: [], away: ["a+b"], followMe: true)
        let legacyRequest = SensorPlacementService.request(authorization: "Bearer x", config: legacy)
        #expect(legacyRequest.url?.absoluteString == "https://api.fluxhaus.io/climate/placement-insights"
                + "?days=14&home=bedroom,kitchen&sleep=&away=a%2Bb&followMe=true")
        let request = SensorPlacementService.request(authorization: "Bearer x", config: sample)
        let url = try #require(request.url)
        #expect(url.absoluteString == "https://api.fluxhaus.io/climate/placement-insights"
                + "?days=14&home=bedroom,kitchen&sleep=&away=a%2Bb&followMe=true"
                + "&thermostatHome=true&thermostatSleep=false")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "away" })?.value == "a+b")
        let unconfigured = SensorPlacementService.request(authorization: "Bearer x", config: nil)
        #expect(unconfigured.url?.query == "days=14")
    }

    @Test("A token refresh retries with the same room and thermostat choices")
    func fetchSendsConfig() async throws {
        var queries: [String?] = []
        _ = try await SensorPlacementService.fetchInsights(
            config: sample, sessionCheck: { true }, authorization: { "Bearer token" }, hasOIDCToken: { true },
            ensureToken: { true }, refreshToken: { true },
            send: { request in
                queries.append(request.url?.query)
                let response = HTTPURLResponse(url: request.url!, statusCode: queries.count == 1 ? 401 : 200,
                                               httpVersion: nil, headerFields: nil)!
                return (Data(configJSON.utf8), response)
            }
        )
        #expect(queries.count == 2)
        #expect(queries[0] == queries[1])
        #expect(queries.first??.contains("followMe=true") == true)
        #expect(queries.first??.contains("thermostatHome=true&thermostatSleep=false") == true)
        #expect(queries.first??.contains("thermostatAway") == false)
    }

    /// An unsigned JWT with the given claims; only the payload is read for the account id.
    private func jwt(_ claims: [String: Any]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).signature"
    }

    @Test("The account id is stable across tokens for one account, distinct per account and not the raw subject")
    func accountIdentifier() throws {
        let issuer = "https://auth.fluxhaus.io/application/o/fluxhaus-server/"
        let first = try jwt(["iss": issuer, "sub": "user-a", "exp": 1, "jti": "one"])
        let relogin = try jwt(["iss": issuer, "sub": "user-a", "exp": 2, "jti": "two"])
        let other = try jwt(["iss": issuer, "sub": "user-b", "exp": 1])
        let idA = try #require(PlacementAccount.identifier(accessToken: first, hasDemoPassword: false))
        #expect(PlacementAccount.identifier(accessToken: relogin, hasDemoPassword: false) == idA)
        #expect(PlacementAccount.identifier(accessToken: other, hasDemoPassword: false) != idA)
        #expect(!idA.contains("user-a") && !first.contains(idA))
        #expect(PlacementAccount.identifier(accessToken: "opaque-token", hasDemoPassword: true) == nil)
        #expect(PlacementAccount.identifier(accessToken: try jwt(["iss": issuer]), hasDemoPassword: false) == nil)
        // Both claims are required: a missing or empty issuer must not collapse to "|sub".
        #expect(PlacementAccount.identifier(accessToken: try jwt(["sub": "user-a"]), hasDemoPassword: false) == nil)
        let emptyIssuer = try jwt(["iss": "", "sub": "user-a"])
        #expect(PlacementAccount.identifier(accessToken: emptyIssuer, hasDemoPassword: false) == nil)
        #expect(PlacementAccount.identifier(accessToken: nil, hasDemoPassword: true) == "demo")
        #expect(PlacementAccount.identifier(accessToken: nil, hasDemoPassword: false) == nil)
    }

    @Test("Two accounts stay isolated and an account's setup is restored after sign-out and sign-in")
    func accountScopedPersistence() throws {
        let defaults = defaults()
        let issuer = "https://auth.fluxhaus.io/application/o/fluxhaus-server/"
        func store(_ sub: String, _ jti: String) throws -> PlacementConfigStore {
            let token = try jwt(["iss": issuer, "sub": sub, "jti": jti])
            let account = try #require(PlacementAccount.identifier(accessToken: token, hasDemoPassword: false))
            return PlacementConfigStore(account: account, defaults: defaults)
        }
        let accountA = try store("user-a", "session-1")
        let session = ConfigTestSession()
        let serviceA = SensorPlacementService(sessionCheck: { session.valid }, configStore: accountA, fetch: { _, _ in
            throw PlacementRequestError.invalidResponse
        })
        #expect(serviceA.updateConfig(sample))

        // Sign out, then account B signs in on the same device.
        session.valid = false
        #expect(serviceA.config == nil)
        let serviceB = SensorPlacementService(
            sessionCheck: { true }, configStore: try store("user-b", "session-2"),
            fetch: { _, _ in throw PlacementRequestError.invalidResponse }
        )
        #expect(serviceB.config == nil)
        let configB = PlacementConfig(
            home: ["kitchen"], sleep: ["kitchen"], away: [], followMe: false,
            thermostatHome: false, thermostatSleep: nil, thermostatAway: true
        )
        #expect(serviceB.updateConfig(configB))

        // Account A signs in again with a new token: its own choices come back, B's are untouched.
        let restored = SensorPlacementService(
            sessionCheck: { true }, configStore: try store("user-a", "session-3"),
            fetch: { _, _ in throw PlacementRequestError.invalidResponse }
        )
        #expect(restored.config == sample)
        #expect(try store("user-b", "session-4").load() == configB)
        accountA.save(nil)
        #expect(try store("user-a", "session-5").load() == nil)
        #expect(try store("user-b", "session-6").load() == configB)
    }

    @Test("The thermostat average is excluded from room ids without losing the built-in sensor choices")
    func thermostatExcluded() async throws {
        let result = try decode()
        #expect(result.roomSensorIDs == ["bedroom", "kitchen"])
        #expect(result.thermostatIDs == ["home"])
        let store = PlacementConfigStore(account: "first", defaults: defaults())
        let withThermostat = PlacementConfig(
            home: ["home", "bedroom"], sleep: ["home"], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        let rooms = PlacementConfig(
            home: ["bedroom"], sleep: [], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        store.save(withThermostat)
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: result, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                return result
            }
        )
        // A previously saved thermostat id is never sent and is removed from storage.
        await service.refresh()
        #expect(requested == [rooms])
        #expect(service.config == rooms)
        #expect(store.load() == rooms)
        // Saving a setup that names the thermostat stores only the room sensors.
        var edited = rooms
        edited.set(true, sensor: "home", in: .away)
        edited.set(true, sensor: "kitchen", in: .away)
        edited.setThermostat(false, in: .home)
        edited.setThermostat(true, in: .away)
        #expect(service.updateConfig(edited))
        #expect(service.config?.away == ["kitchen"])
        #expect(store.load() == edited.excluding(["home"]))
        #expect(store.load()?.thermostatHome == false)
        #expect(store.load()?.thermostatSleep == false)
        #expect(store.load()?.thermostatAway == true)
    }

    @Test("Mode badges mark heating and cooling tips; general tips still render without one")
    func modeBadges() {
        #expect(PlacementRecommendationCard.modeBadge(.heating)?.title == "Heating")
        #expect(PlacementRecommendationCard.modeBadge(.cooling)?.title == "Cooling")
        #expect(PlacementRecommendationCard.modeBadge(.unknown) == nil)
        #expect(PlacementRecommendationCard.modeBadge(nil) == nil)
    }

    @Test("The service loads, updates and hides the config with the session")
    func serviceConfig() {
        let defaults = defaults()
        let store = PlacementConfigStore(account: "first", defaults: defaults)
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

    @Test("Older servers warn without discarding choices; a supported server clears the warning")
    func thermostatCapability() async throws {
        let legacy = try decode()
        func response(_ value: String) throws -> PlacementInsights {
            try decode(configJSON.replacingOccurrences(
                of: "\"participationConfigured\": true",
                with: "\"thermostatParticipationSupported\": \(value), \"participationConfigured\": true"
            ))
        }
        let unsupported = try response("false")
        let supported = try response("true")
        #expect(legacy.coverage.thermostatParticipationSupported == nil)
        #expect(try response("null").coverage.thermostatParticipationSupported == nil)
        #expect(unsupported.coverage.thermostatParticipationSupported == false)
        #expect(supported.coverage.thermostatParticipationSupported == true)

        let store = PlacementConfigStore(account: "first", defaults: defaults())
        store.save(sample)
        let session = ConfigTestSession()
        let responses = [legacy, unsupported, supported]
        var requests: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: legacy, sessionCheck: { session.valid }, configStore: store, fetch: { config, _ in
                requests.append(config)
                return responses[requests.count - 1]
            }
        )
        let notice = try #require(service.thermostatParticipationNotice)
        #expect(notice.contains("can't use built-in thermostat sensor choices"))
        #expect(notice.contains("Saved choices are kept"))
        var edited = sample
        edited.setThermostat(false, in: .away)
        #expect(service.updateConfig(edited))
        #expect(service.thermostatParticipationNotice == notice)
        #expect(await service.refresh())
        #expect(service.thermostatParticipationNotice == notice)
        #expect(await service.refresh())
        #expect(service.thermostatParticipationNotice == notice)
        #expect(await service.refresh())
        #expect(service.thermostatParticipationNotice == nil)
        #expect(requests == [edited, edited, edited])
        #expect(service.config == edited && store.load() == edited)
        session.valid = false
        #expect(service.thermostatParticipationNotice == nil)
    }

    @Test("The setup renders with reported, unavailable and no room sensors")
    func setupViewRenders() throws {
        let result = try decode()
        let scenarios: [([PlacementInsights.Sensor], PlacementConfig?)] = [
            (result.sensors, sample), ([], sample), ([], nil)
        ]
        for (sensors, config) in scenarios {
            for notice in [nil, SensorPlacementService.thermostatUnsupportedNotice] {
                let analysisNotice = notice == nil ? nil : SensorPlacementService.setupNotUsedNotice
                let view = ThermostatSetupView(
                    sensors: sensors, config: config, thermostatParticipationNotice: notice,
                    analysisNotice: analysisNotice
                ) { _ in }
                #expect(view.sensors.map(\.id) == (sensors.isEmpty ? [] : ["bedroom", "kitchen"]))
                #expect(view.thermostatParticipationNotice == notice)
                #expect(view.analysisNotice == analysisNotice)
                let controller = UIHostingController(rootView: view)
                controller.loadViewIfNeeded()
                for size in [CGSize(width: 393, height: 852), CGSize(width: 1024, height: 768)] {
                    controller.view.frame = CGRect(origin: .zero, size: size)
                    controller.view.layoutIfNeeded()
                }
                #expect(controller.view != nil)
            }
        }
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

    @Test("Per-sensor drill-down decodes; thermostat temperature is separate; older servers degrade")
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
        #expect(thermostat.displayName == "Thermostat (reported temperature)")
        #expect(thermostat.outlierVerdict == nil)
        #expect(thermostat.occupiedShare == nil)  // superseded scalar shape is ignored
        #expect(SensorPlacementView.name("home", in: result) == "Thermostat (reported temperature)")

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

    @Test("A reduced retry preserves saved IDs until the user removes or clears them")
    func staleSensorUsesFreshRetry() async throws {
        let result = try decode()
        let unconfigured = try decode(unconfiguredJSON)
        let store = PlacementConfigStore(account: "first", defaults: defaults())
        let stale = PlacementConfig(
            home: ["bedroom", "gone"], sleep: [], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        store.save(stale)
        #expect(!result.roomSensorIDs.contains("home"))
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(
            insights: result, sessionCheck: { true }, configStore: store, fetch: { config, _ in
                requested.append(config)
                if config?.home.contains("gone") == true { throw PlacementRequestError.http(400) }
                return config == nil ? unconfigured : result
            }
        )
        #expect(await service.refresh())
        let pruned = PlacementConfig(
            home: ["bedroom"], sleep: [], away: [], followMe: false,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        #expect(requested == [stale, nil, pruned])
        #expect(service.config == stale && store.load() == stale)
        #expect(service.notice == SensorPlacementService.reducedConfigNotice)
        #expect(service.error == nil)
        var edited = stale
        edited.set(false, sensor: "gone", in: .home)
        #expect(service.updateConfig(edited))
        #expect(store.load() == pruned && service.notice == nil)
        #expect(await service.refresh())
        #expect(requested == [stale, nil, pruned, pruned])
        #expect(service.updateConfig(nil))
        #expect(store.load() == nil)
        #expect(await service.refresh())
        #expect(requested.last == .some(nil))
    }

    @Test("An unusable config falls back to unconfigured insights with a clear message")
    func rejectedConfigFallsBack() async throws {
        let result = try decode(unconfiguredJSON)
        let store = PlacementConfigStore(account: "first", defaults: defaults())
        let config = PlacementConfig(
            home: ["bedroom"], sleep: [], away: [], followMe: true,
            thermostatHome: true, thermostatSleep: false, thermostatAway: nil
        )
        store.save(config)
        var requested: [PlacementConfig?] = []
        let service = SensorPlacementService(sessionCheck: { true }, configStore: store, fetch: { config, _ in
            requested.append(config)
            if config != nil { throw PlacementRequestError.http(400) }
            return result
        })
        // Without cached insights, the fallback learns room sensors from the unconfigured response.
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
