//
//  SensorPlacementDisplayTests.swift
//  FluxHaus Tests
//

import Foundation
import Testing
@testable import FluxHaus

private let legacySummary = "This is Ecobee's average of the sensors in the active comfort setting (what it heats "
    + "and cools to), not a room, so it isn't judged as an outlier."
private let neutralSummary = "This thermostat-associated sensor isn't identified as the comfort reading "
    + "or judged as a room."
private let currentSummary = "This thermostat-associated sensor is not known to be the selected comfort reading."

@MainActor
struct SensorPlacementDisplayTests {
    private func insights(
        name: String, summary: String? = nil, roomSummary: String? = nil, unitAssumptions: String? = nil,
        roomConsistency: String? = nil
    ) throws -> PlacementInsights {
        func summaryField(_ value: String?) throws -> String {
            guard let value else { return "" }
            let data = try JSONEncoder().encode(value)
            return ", \"verdictSummary\": \(try #require(String(data: data, encoding: .utf8)))"
        }
        let roomField = try summaryField(roomSummary)
        let consistencyField = roomConsistency.map { ", \"consistency\": \($0)" } ?? ""
        let rooms = ["bedroom", "office", "living"].map { id in
            """
            {"id": "\(id)", "name": "\(id.capitalized)", "isThermostat": false, "averageOffset": 0,
             "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 10,
             "classification": "ok"\(roomField)\(consistencyField)}
            """
        }
        let nameData = try JSONEncoder().encode(name)
        let encodedName = try #require(String(data: nameData, encoding: .utf8))
        let sensor = """
        {"id": "home", "name": \(encodedName), "isThermostat": true, "averageOffset": 0,
         "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 10,
         "classification": "ok"\(try summaryField(summary))}
        """
        let assumptionsField = unitAssumptions.map { ", \"unitAssumptions\": \($0)" } ?? ""
        let json = """
        {"generatedAt": "2026-11-26T12:00:00Z", "windowDays": 14, "unit": "°C",
         "coverage": {"start": "2026-11-12T12:00:00Z", "end": "2026-11-26T12:00:00Z",
           "hvacHistoryAvailable": true, "morningEvents": 0, "returnEvents": 0,
           "participationConfigured": true, "thermostatParticipationSupported": true\(assumptionsField)},
         "sensors": [\(([sensor] + rooms).joined(separator: ","))], "recommendations": []}
        """
        return try JSONDecoder().decode(PlacementInsights.self, from: Data(json.utf8))
    }

    @Test("An unidentified thermostat sensor retains its name and server explanation")
    func unidentifiedThermostatSensor() throws {
        let result = try insights(name: "Hallway temperature", summary: currentSummary)
        let sensor = try #require(result.sensors.first(where: { $0.isThermostat }))
        #expect(result.sensors.count == 4)
        #expect(sensor.displayName == "Hallway temperature")
        #expect(SensorPlacementView.name(sensor.id, in: result) == "Hallway temperature")
        #expect(sensor.verdictSummary == currentSummary && sensor.displayVerdictSummary == currentSummary)
        #expect(SensorPlacementDetailView.thermostatFallback(sensor) == nil)
        #expect(sensor.outlierVerdict == nil && result.thermostatIDs == ["home"])
        #expect(result.roomSensorIDs == ["bedroom", "office", "living"])
        let old = try #require(try insights(name: "Hallway temperature").sensors.first(where: { $0.isThermostat }))
        #expect(SensorPlacementDetailView.thermostatFallback(old) == neutralSummary)
    }

    @Test("The legacy average name and verdict do not identify a comfort reading")
    func legacyThermostatReading() throws {
        let conservative = "This is Ecobee's average only if this sensor is the identified comfort reading."
        for summary in [nil, legacySummary, conservative] as [String?] {
            let result = try insights(name: "Thermostat (Ecobee average)", summary: summary)
            let sensor = try #require(result.sensors.first(where: { $0.isThermostat }))
            #expect(sensor.displayName == "Thermostat-associated sensor")
            #expect(SensorPlacementView.name(sensor.id, in: result) == sensor.displayName)
            #expect(sensor.verdictSummary == summary)
            #expect(sensor.displayVerdictSummary == (summary == conservative ? conservative : nil))
            #expect(SensorPlacementDetailView.thermostatFallback(sensor)
                    == (summary == conservative ? nil : neutralSummary))
            let room = try #require(result.sensors.first(where: { !$0.isThermostat }))
            #expect(room.displayName == "Bedroom" && SensorPlacementDetailView.thermostatFallback(room) == nil)
        }
        let explanation = ThermostatSetupView.thermostatReadingExplanation
        #expect(explanation.contains("identified climate-reported") && explanation.contains("isn't necessarily"))
        #expect(SensorPlacementDetailView.thermostatParticipationExplanation.hasPrefix(explanation))
        #expect(SensorPlacementDetailView.thermostatParticipationExplanation
                .contains("not necessarily this listed sensor"))
    }

    @Test("Only thermostat-associated sensors suppress the exact old server verdict")
    func oldVerdictScope() throws {
        let result = try insights(name: "Hallway temperature", summary: legacySummary, roomSummary: legacySummary)
        let thermostat = try #require(result.sensors.first(where: { $0.isThermostat }))
        let room = try #require(result.sensors.first(where: { !$0.isThermostat }))
        #expect(thermostat.displayName == "Hallway temperature")
        #expect(thermostat.verdictSummary == legacySummary && thermostat.displayVerdictSummary == nil)
        #expect(SensorPlacementDetailView.thermostatFallback(thermostat) == neutralSummary)
        #expect(room.displayVerdictSummary == legacySummary)
    }

    @Test("Heating and cooling consistency describe sampled calendar dates, including partial dates")
    func consistencyDates() throws {
        let consistency = """
        {"days": 15, "coldDays": 7, "warmDays": 2, "coolingDays": 3, "coolingColdDays": 1, "coolingWarmDays": 2}
        """
        let result = try insights(name: "Hallway temperature", roomConsistency: consistency)
        #expect(result.windowDays == 14)
        let sensor = try #require(result.sensors.first(where: { $0.id == "bedroom" }))
        #expect(SensorPlacementDetailView.patternLines(sensor, unit: result.unit) == [
            "Heating: cooler on 7 of 15 sampled calendar dates, warmer on 2 of 15; dates may be partial.",
            "Cooling: cooler on 1 of 3 sampled calendar dates, warmer on 2 of 3; dates may be partial."
        ])
    }

    @Test("Missing unit assumptions are unknown; false flags do not claim verified coverage")
    func missingAndFalseUnitAssumptions() throws {
        let unknownNotice = "The server didn't report whether historical reference-temperature or setpoint units "
            + "were assumed."
        for field in [nil, "null"] as [String?] {
            let result = try insights(name: "Hallway temperature", unitAssumptions: field)
            #expect(result.recommendations.isEmpty)
            #expect(result.coverage.unitAssumptions == nil)
            #expect(result.coverage.unitAssumptionNotices == [unknownNotice])
        }
        let flags = """
        {"reportedTemperature": false, "setpoints": false, "coolingReportedTemperature": false,
         "coolingSetpoints": false}
        """
        let result = try insights(name: "Hallway temperature", unitAssumptions: flags)
        let assumptions = try #require(result.coverage.unitAssumptions)
        #expect(!assumptions.reportedTemperature && !assumptions.setpoints)
        #expect(!assumptions.coolingReportedTemperature && !assumptions.coolingSetpoints)
        #expect(result.recommendations.isEmpty)
        #expect(result.coverage.unitAssumptionNotices.isEmpty)
        #expect(throws: DecodingError.self) {
            try insights(name: "Hallway temperature", unitAssumptions: #"{"reportedTemperature": true}"#)
        }
    }

    @Test("Unit-assumption notices distinguish each source and the analysis versus cooling window")
    func unitAssumptionWindows() throws {
        let suffix = "were assumed from Home Assistant's last-known units."
        let cases = [
            ("reportedTemperature", "Analysis window: the units of some reference temperatures \(suffix)"),
            ("setpoints", "Analysis window: the units of some setpoints \(suffix)"),
            ("coolingReportedTemperature", "Cooling window: the units of some reference temperatures \(suffix)"),
            ("coolingSetpoints", "Cooling window: the units of some setpoints \(suffix)")
        ]
        for (enabled, notice) in cases {
            let flags = Dictionary(uniqueKeysWithValues: cases.map { ($0.0, $0.0 == enabled) })
            let data = try JSONSerialization.data(withJSONObject: flags)
            let encodedFlags: String = try #require(String(data: data, encoding: .utf8))
            let result = try insights(name: "Hallway temperature", unitAssumptions: encodedFlags)
            #expect(result.recommendations.isEmpty)
            #expect(result.coverage.unitAssumptionNotices == [notice])
        }
        let mixed = """
        {"reportedTemperature": true, "setpoints": false, "coolingReportedTemperature": false,
         "coolingSetpoints": true}
        """
        let mixedResult = try insights(name: "Hallway temperature", unitAssumptions: mixed)
        #expect(mixedResult.coverage.unitAssumptionNotices == [cases[0].1, cases[3].1])
        let both = """
        {"reportedTemperature": true, "setpoints": true, "coolingReportedTemperature": true, "coolingSetpoints": true}
        """
        let result = try insights(name: "Hallway temperature", unitAssumptions: both)
        #expect(result.coverage.unitAssumptionNotices == [
            "Analysis window: the units of some reference temperatures and setpoints \(suffix)",
            "Cooling window: the units of some reference temperatures and setpoints \(suffix)"
        ])
    }
}
