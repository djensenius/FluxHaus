//
//  SensorPlacementSetupTests.swift
//  FluxHaus Tests
//

import Foundation
import Testing
@testable import FluxHaus

private func setupInsights(
    rooms: [String], includeThermostat: Bool = true, sensorFields: String = ""
) throws -> PlacementInsights {
    let reported = rooms.map { ($0, false) } + (includeThermostat ? [("thermostat", true)] : [])
    let sensors = reported.map { id, thermostat in
        """
        {"id": "\(id)", "name": "\(id)", "isThermostat": \(thermostat), "averageOffset": 0,
         "morningOffset": null, "returnOffset": null, "overshoot": null, "sampleCount": 1,
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
            sensors: result.sensors, config: service.config, thermostatParticipationNotice: nil
        ) { _ = service.updateConfig($0) }
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
        editor.onSave(empty)
        #expect(store.load() == empty && service.canEditConfig)

        var thermostatOnly = empty
        thermostatOnly.setThermostat(true, in: .home)
        #expect(service.updateConfig(thermostatOnly))
        #expect(store.load() == thermostatOnly)
        #expect(thermostatOnly.thermostatSleep == nil && thermostatOnly.thermostatAway == nil)
        let savedEditor = ThermostatSetupView(
            sensors: result.sensors, config: service.config, thermostatParticipationNotice: nil
        ) { _ = service.updateConfig($0) }
        #expect(savedEditor.wasConfigured && savedEditor.sensors.isEmpty)
        savedEditor.onSave(nil)
        #expect(store.load() == nil && service.canEditConfig)
        session.valid = false
        #expect(!service.canEditConfig && !service.updateConfig(empty))
        #expect(service.config == nil && store.load() == nil)
    }

    @Test("Missing IDs are distinct, setting-specific and restorable before saving")
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
            sensors: result.sensors, config: service.config, thermostatParticipationNotice: nil
        ) { _ = service.updateConfig($0) }
        #expect(editor.sensors.map(\.id) == ["bedroom"])
        #expect(editor.reportedSensorIDs == ["bedroom", "thermostat"])
        func unavailable(_ setting: PlacementConfig.Setting) -> [String] {
            ThermostatSetupView.unavailableSensorIDs(in: setting, config: saved, reportedIDs: editor.reportedSensorIDs)
        }
        #expect(unavailable(.home) == ["missing-a", "missing-b"])
        #expect(unavailable(.sleep) == ["missing-b"])
        #expect(unavailable(.away) == ["missing-a"])
        let first = ThermostatSetupView.unavailableSensorLabel("missing-a")
        let second = ThermostatSetupView.unavailableSensorLabel("missing-b")
        #expect(first != second && first.contains("missing-a") && second.contains("missing-b"))
        #expect(first.contains("Unavailable saved ID in current sensor list"))

        var draft = ThermostatSetupView.initialDraft(config: saved, roomIDs: editor.sensors.map(\.id))
        draft.set(false, sensor: "missing-a", in: .home)
        #expect(!draft.home.contains("missing-a") && draft.away.contains("missing-a"))
        #expect(unavailable(.home).contains("missing-a"))
        draft.set(true, sensor: "missing-a", in: .home)
        #expect(draft == saved)
        // Cancelling leaves storage unchanged; saving a removal affects only that setting.
        #expect(store.load() == saved)
        draft.set(false, sensor: "missing-a", in: .home)
        editor.onSave(draft)
        let expected = draft.excluding(["thermostat"])
        #expect(service.config == expected && store.load() == expected)
        #expect(expected.home == ["bedroom", "missing-b"])
        #expect(expected.sleep == ["missing-b"] && expected.away == ["missing-a"])
        #expect(expected.thermostatHome == nil && expected.thermostatSleep == false && expected.thermostatAway == true)
    }

    @Test("All saved rooms remain individually available for editing without room discovery")
    func allUnavailableSelections() throws {
        let saved = PlacementConfig(home: ["missing-b", "missing-a", "thermostat"], sleep: ["missing-b"],
                                    away: ["missing-a"], followMe: false)
        for hasThermostat in [true, false] {
            let result = try setupInsights(rooms: [], includeThermostat: hasThermostat)
            let editor = ThermostatSetupView(
                sensors: result.sensors, config: saved, thermostatParticipationNotice: nil
            ) { _ in }
            #expect(editor.sensors.isEmpty && editor.wasConfigured)
            let home = ThermostatSetupView.unavailableSensorIDs(
                in: .home, config: saved, reportedIDs: editor.reportedSensorIDs
            )
            let sleep = ThermostatSetupView.unavailableSensorIDs(
                in: .sleep, config: saved, reportedIDs: editor.reportedSensorIDs
            )
            let away = ThermostatSetupView.unavailableSensorIDs(
                in: .away, config: saved, reportedIDs: editor.reportedSensorIDs
            )
            #expect(home == (hasThermostat ? ["missing-a", "missing-b"] : ["missing-a", "missing-b", "thermostat"]))
            #expect(sleep == ["missing-b"] && away == ["missing-a"])
            var draft = ThermostatSetupView.initialDraft(config: saved, roomIDs: [])
            draft.set(false, sensor: "missing-b", in: .sleep)
            #expect(draft.sleep.isEmpty && draft.home == saved.home && draft.away == saved.away)
            draft.set(true, sensor: "missing-b", in: .sleep)
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

    @Test("Period offset explanations do not assume a thermostat reading is present")
    func sourceNeutralBaseline() throws {
        let fields = #", "periodOffsets": {"sleep": -0.5, "wake": null, "home": null, "heatingRuns": null, "#
            + #""cooling": null}"#
        let result = try setupInsights(rooms: ["bedroom"], includeThermostat: false, sensorFields: fields)
        let sensor = try #require(result.sensors.first)
        #expect(result.thermostatIDs.isEmpty)
        #expect(SensorPlacementDetailView.offsetBaseline(sensor)
                == "Positive means warmer than the estimated effective comfort average; negative means cooler.")
        #expect(ThermostatSetupView.thermostatReadingExplanation.contains("When HomeKit reports"))
    }
}
