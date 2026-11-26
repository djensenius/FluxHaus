//
//  ThermostatModelTests.swift
//  FluxHaus Tests
//
//  Thermostat request shapes, decoding, and setpoint math.
//

import Testing
import Foundation
@testable import FluxHaus

struct ThermostatCommandTests {
    @Test("Commands map to the server's thermostat routes and bodies")
    func testPathsAndBodies() {
        #expect(ThermostatCommand.setTemperature(21.5).path == "/thermostat/temperature")
        #expect(ThermostatCommand.setTemperature(21.5).body["temperature"] as? Double == 21.5)

        let range = ThermostatCommand.setRange(low: 20, high: 24)
        #expect(range.path == "/thermostat/temperature")
        #expect(range.body["targetTempLow"] as? Double == 20)
        #expect(range.body["targetTempHigh"] as? Double == 24)

        #expect(ThermostatCommand.setMode("heat_cool").path == "/thermostat/mode")
        #expect(ThermostatCommand.setMode("heat_cool").body["mode"] as? String == "heat_cool")
        #expect(ThermostatCommand.setPreset("Work From Home").body["preset"] as? String == "Work From Home")
        #expect(ThermostatCommand.setFan("on").path == "/thermostat/fan")
        #expect(ThermostatCommand.setFan("on").body["mode"] as? String == "on")
        #expect(ThermostatCommand.resumeSchedule.path == "/thermostat/resume")
        #expect(ThermostatCommand.resumeSchedule.body["resumeAll"] as? Bool == true)
    }

    @Test("Decodes the thermostat's control capabilities")
    func testDecodeCapabilities() throws {
        let json = Data("""
        {"entityId":"climate.home","hvacModes":["heat_cool","heat","cool","off"],
         "presetModes":["away","home","sleep"],"fanMode":"auto","fanModes":["on","auto"],
         "minTemp":7,"maxTemp":35,"targetTempStep":0.5,"temperatureUnit":"°C"}
        """.utf8)
        let status = try JSONDecoder().decode(ThermostatStatus.self, from: json)
        #expect(status.hvacModes == ["heat_cool", "heat", "cool", "off"])
        #expect(status.presetModes == ["away", "home", "sleep"])
        #expect(status.fanMode == "auto" && status.fanModes == ["on", "auto"])
        #expect(status.minTemp == 7 && status.maxTemp == 35 && status.targetTempStep == 0.5)
        #expect(status.temperatureUnit == "°C")

        let legacy = try JSONDecoder().decode(ThermostatStatus.self, from: Data(#"{"entityId":"climate.home"}"#.utf8))
        #expect(legacy.hvacModes == nil && legacy.targetTempStep == nil && legacy.temperatureUnit == nil)
    }

    @Test("Thermostat values use the thermostat's unit; the headline is in the home's unit")
    func testThermostatUnit() {
        let thermostat = ThermostatStatus(
            entityId: "climate.home", currentTemperature: 20, targetTemperature: 21, temperatureUnit: "°C"
        )
        let state = IndoorClimateState(unit: "°F", thermostat: thermostat, sensors: [])
        #expect(state.thermostatUnit == "°C")
        #expect(state.primaryTemperature == 68)

        let bare = ThermostatStatus(entityId: "climate.home")
        let unreported = IndoorClimateState(unit: "°F", thermostat: bare, sensors: [])
        #expect(unreported.thermostatUnit == "°F")
    }
}

struct ThermostatSetpointTests {
    @Test("Adjusting snaps to the step grid and clamps to the allowed range")
    func testAdjust() {
        #expect(ThermostatSetpoint.adjust(21.3, by: 1, step: 0.5, bounds: 7...33) == 22.0)
        #expect(ThermostatSetpoint.adjust(21.5, by: -2, step: 0.5, bounds: 7...33) == 20.5)
        #expect(ThermostatSetpoint.adjust(32.5, by: 3, step: 0.5, bounds: 7...33) == 33)
        #expect(ThermostatSetpoint.adjust(46, by: -5, step: 1, bounds: 45...92) == 45)
    }

    @Test("Step and bounds prefer the thermostat's values, else unit defaults")
    func testStepAndBounds() {
        let bare = ThermostatStatus(entityId: "climate.home")
        #expect(ThermostatSetpoint.step(for: bare, fahrenheit: false) == 0.5)
        #expect(ThermostatSetpoint.step(for: bare, fahrenheit: true) == 1)
        #expect(ThermostatSetpoint.bounds(for: bare, fahrenheit: false) == 7...33)
        #expect(ThermostatSetpoint.bounds(for: bare, fahrenheit: true) == 45...92)

        let reported = ThermostatStatus(entityId: "climate.home", minTemp: 10, maxTemp: 30, targetTempStep: 0.1)
        #expect(ThermostatSetpoint.step(for: reported, fahrenheit: false) == 0.1)
        #expect(ThermostatSetpoint.bounds(for: reported, fahrenheit: false) == 10...30)
    }

    @Test("A status reports a setpoint within 0.25°, or half a smaller change, and matching modes")
    func testReports() {
        let old = ThermostatStatus(
            entityId: "climate.home", targetTemperature: 21, targetTemperatureLow: 19, targetTemperatureHigh: 25
        )
        let new = ThermostatStatus(
            entityId: "climate.home", hvacMode: "heat_cool", targetTemperature: 21.1,
            targetTemperatureLow: 19, targetTemperatureHigh: 25.1, presetMode: "home", fanMode: "auto"
        )
        // Still showing 21 after asking for 21.1 isn't the change, though it's within 0.25°.
        #expect(!old.reports(.setTemperature(21.1), from: old) && new.reports(.setTemperature(21.1), from: old))
        #expect(old.reports(.setTemperature(21.2), from: nil) && !old.reports(.setTemperature(21.5), from: nil))
        let range = ThermostatCommand.setRange(low: 19, high: 25.1)
        #expect(new.reports(range, from: old) && !old.reports(range, from: old))
        #expect(new.reports(.setMode("heat_cool"), from: old) && !new.reports(.setMode("cool"), from: old))
        #expect(new.reports(.setPreset("home"), from: old) && !new.reports(.setPreset("away"), from: old))
        #expect(new.reports(.setFan("auto"), from: old) && !new.reports(.setFan("on"), from: old))
        #expect(!ThermostatStatus(entityId: "climate.home").reports(.setTemperature(21), from: nil))
    }

    @Test("A command awaits its report until the status shows it or moves on from where it was")
    func testAwaits() {
        let before = ThermostatStatus(
            entityId: "climate.home", hvacMode: "heat", targetTemperature: 21,
            targetTemperatureLow: 19, targetTemperatureHigh: 25, presetMode: "home"
        )
        let moved = ThermostatStatus(
            entityId: "climate.home", hvacMode: "cool", targetTemperature: 20,
            targetTemperatureLow: 18, targetTemperatureHigh: 25, presetMode: "sleep"
        )
        let commands: [ThermostatCommand] = [
            .setTemperature(21.1), .setRange(low: 19, high: 25.5), .setMode("heat_cool"), .setPreset("away")
        ]
        for command in commands {
            #expect(before.awaits(command, from: before) && !moved.awaits(command, from: before))
        }
        // One end of a range reported before the other is still waiting; one moved elsewhere isn't.
        let range = ThermostatCommand.setRange(low: 18, high: 26)
        let halfway = ThermostatStatus(entityId: "climate.home", targetTemperatureLow: 18, targetTemperatureHigh: 25)
        let elsewhere = ThermostatStatus(entityId: "climate.home", targetTemperatureLow: 18, targetTemperatureHigh: 24)
        #expect(halfway.awaits(range, from: before) && !elsewhere.awaits(range, from: before))
        #expect(before.awaits(.setTemperature(22), from: nil) && !before.awaits(.setTemperature(21), from: nil))
        #expect(!before.awaits(.resumeSchedule, from: before))
    }

    @Test("Labels read naturally and modes are shown Heat, Cool, Auto, Off")
    func testLabels() {
        #expect(ThermostatLabels.ordered(["heat_cool", "fan_only", "heat", "cool", "off"])
            == ["heat", "cool", "heat_cool", "off", "fan_only"])
        #expect(ThermostatLabels.mode("heat_cool") == "Auto")
        #expect(ThermostatLabels.preset("temp") == "Hold")
        #expect(ThermostatLabels.preset("away_indefinitely") == "Away (indefinitely)")
        #expect(ThermostatLabels.preset("Work From Home") == "Work From Home")
    }
}

struct IndoorCardSummaryTests {
    private func format(_ value: Double) -> String {
        IndoorClimateFormat.temperature(value, unit: "°C")
    }

    @Test("The Indoor card shows the thermostat, its status and the warmest and coolest rooms")
    @MainActor func testSummaryFromMockData() throws {
        let state = try #require(MockData.loginResponse.indoorClimate)
        let summary = IndoorCardSummary(state: state)
        #expect(summary.value == format(21.3))
        #expect(summary.activity == .heating)
        #expect(summary.isActive)
        let status = try #require(summary.status)
        #expect(status.hasPrefix("Heating"))
        #expect(summary.extremes == "Warmest Kitchen \(format(22.6)) · Coolest Main Bedroom \(format(19.8))")
        #expect(summary.detail == "\(status)\n\(summary.extremes ?? "")")
    }

    @Test("Without a thermostat or sensors the Indoor card is a muted placeholder")
    func testSummaryWithoutReadings() {
        for state in [nil, IndoorClimateState(sensors: [])] {
            let summary = IndoorCardSummary(state: state)
            #expect(summary.value == IndoorCardSummary.placeholder)
            #expect(!summary.hasReadings && !summary.isActive)
            #expect(summary.status == nil && summary.extremes == nil)
            #expect(summary.detail == IndoorCardSummary.noReadings)
        }
    }

    @Test("Sensors alone give a reading; equal or offline rooms give no extremes")
    func testSummaryWithoutThermostat() {
        let rooms = [
            IndoorTemperatureSensor(entityId: "sensor.a", name: "A", temperature: 20),
            IndoorTemperatureSensor(entityId: "sensor.b", name: "B", temperature: 20),
            IndoorTemperatureSensor(entityId: "sensor.c", name: "C", temperature: 25, available: false)
        ]
        let summary = IndoorCardSummary(state: IndoorClimateState(unit: "°C", sensors: rooms))
        #expect(summary.value == format(20))
        #expect(summary.status == nil && summary.activity == nil && !summary.isActive)
        #expect(summary.extremes == nil)
        #expect(summary.detail.isEmpty)
    }

    @Test("An idle thermostat isn't sorted with running devices")
    func testIdleThermostatIsInactive() {
        let thermostat = ThermostatStatus(
            entityId: "climate.home", currentTemperature: 20, hvacMode: "heat",
            hvacAction: "idle", targetTemperature: 19
        )
        let summary = IndoorCardSummary(state: IndoorClimateState(unit: "°C", thermostat: thermostat, sensors: []))
        #expect(summary.activity == .idle)
        #expect(!summary.isActive)
        #expect(summary.value == format(20))
    }
}
