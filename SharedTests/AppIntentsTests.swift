//
//  AppIntentsTests.swift
//  FluxHaus Tests
//
//  Unit tests for the pure logic in the FluxHaus App Intents layer.
//

import Testing
import Foundation
@testable import FluxHaus

struct AppIntentsTests {
    private func analyticsFixture(
        method: String = "battery_proxy",
        coverage: Double = 92,
        comparison: Bool = true
    ) throws -> CarAnalyticsResponse {
        let measured = method == "measured_kwh"
        let unit = measured ? "kWh/100 km" : "%/100 km"
        let label = measured ? "Measured efficiency" : "Battery-use estimate"
        let comparisonJSON = comparison ? """
          {
            "periodStart": "2026-07-12T00:00:00.000Z",
            "periodEnd": "2026-08-11T00:00:00.000Z",
            "distanceChangePercent": 10,
            "chargingFrequencyChangePercent": -20,
            "efficiencyChangePercent": 5,
            "previousCoveragePercent": 90,
            "previousEffectiveStart": "2026-07-12T00:05:00.000Z",
            "previousEffectiveEnd": "2026-08-10T23:55:00.000Z"
          }
        """ : "null"
        let json = """
        {
          "period": {
            "range": "30d",
            "requestedStart": "2026-08-11T00:00:00.000Z",
            "requestedEnd": "2026-09-10T00:00:00.000Z",
            "effectiveStart": "2026-08-11T00:05:00.000Z",
            "effectiveEnd": "2026-09-09T23:55:00.000Z",
            "timezone": "America/Toronto",
            "aggregationWindow": "5m"
          },
          "summary": "You charged 4 times and drove 500 km.",
          "charging": {
            "sessionCount": 4,
            "averageIntervalDays": 7.5,
            "averageSessionHours": 2.1,
            "averageChargeAddedPercent": 42,
            "sessions": [],
            "sessionsTruncated": false
          },
          "usage": {
            "distanceKm": 500,
            "energyKWh": null,
            "measuredEnergyDistanceKm": null,
            "batteryUsedPercent": 85,
            "efficiency": {
              "method": "\(method)",
              "value": 17,
              "unit": "\(unit)",
              "label": "\(label)"
            }
          },
          "weather": {
            "averageTemperatureC": 8,
            "bands": [],
            "estimatedImpactPercent": 20,
            "comparisonBands": ["cold", "mild"],
            "efficiencyMethod": "\(method)"
          },
          "comparison": \(comparisonJSON),
          "dataQuality": {
            "coveragePercent": \(coverage),
            "energyCoveragePercent": 0,
            "telemetrySamples": 7000,
            "chargingSamples": 19,
            "weatherSamples": 1000,
            "warnings": ["Efficiency is a battery-use estimate."]
          }
        }
        """
        return try JSONDecoder().decode(CarAnalyticsResponse.self, from: Data(json.utf8))
    }

    @Test("RobotChoice maps to the matching RobotKind")
    func robotChoiceMapsToKind() {
        #expect(RobotChoice.broomBot.kind == .broomBot)
        #expect(RobotChoice.mopBot.kind == .mopBot)
    }

    @Test("RobotKind exposes the expected display names")
    func robotKindDisplayNames() {
        #expect(RobotKind.broomBot.displayName == "BroomBot")
        #expect(RobotKind.mopBot.displayName == "MopBot")
    }

    @Test("SceneAppEntity is built from a HomeScene")
    func sceneEntityFromHomeScene() {
        let scene = HomeScene(entityId: "scene.movie_night", name: "Movie Night", isActive: false)
        let entity = SceneAppEntity(scene: scene)
        #expect(entity.id == "scene.movie_night")
        #expect(entity.name == "Movie Night")
    }

    @Test("IntentError provides user-facing descriptions")
    func intentErrorDescriptions() {
        #expect(IntentError.notSignedIn.errorDescription == "Please sign in to FluxHaus first.")
        #expect(IntentError.requestFailed(503).errorDescription == "The request failed (HTTP 503).")
        #expect(IntentError.invalidURL.errorDescription == "Could not build the request.")
    }

    @Test("Car analytics decodes server provenance")
    func carAnalyticsDecodesProvenance() throws {
        let analytics = try analyticsFixture()
        #expect(analytics.usage.efficiency.method == .proxy)
        #expect(analytics.dataQuality.coveragePercent == 92)
        #expect(analytics.comparison?.previousCoveragePercent == 90)
    }

    @Test("Efficiency dialog identifies a battery proxy")
    func carAnalyticsProxyDialog() throws {
        let dialog = try analyticsFixture().dialog(for: .efficiency, range: .month)
        #expect(dialog.contains("battery-based estimate"))
        #expect(dialog.contains("not measured energy efficiency"))
    }

    @Test("Efficiency dialog identifies measured energy")
    func carAnalyticsMeasuredDialog() throws {
        let analytics = try analyticsFixture(method: "measured_kwh")
        let dialog = analytics.dialog(for: .efficiency, range: .month)
        #expect(analytics.usage.efficiency.method == .measured)
        #expect(dialog.contains("Measured efficiency was 17 kWh/100 km"))
        #expect(!dialog.contains("battery-based estimate"))
    }

    @Test("Comparison dialog handles unavailable history")
    func carAnalyticsComparisonUnavailable() throws {
        let dialog = try analyticsFixture(comparison: false).dialog(for: .comparison, range: .month)
        #expect(dialog == "A previous-period comparison is unavailable for the last 30 days.")
    }

    @Test("Low analytics coverage is spoken")
    func carAnalyticsLowCoverageDialog() throws {
        let dialog = try analyticsFixture(coverage: 60).dialog(for: .charging, range: .month)
        #expect(dialog.contains("Data coverage was 60 percent"))
    }

    @Test("Car analytics range labels stay stable")
    func carAnalyticsRangeLabels() {
        #expect(CarAnalyticsRange.allCases.map(\.rawValue) == ["7d", "30d", "90d", "1y", "all"])
        #expect(CarAnalyticsRange.all.spokenLabel == "all retained history")
    }
}
