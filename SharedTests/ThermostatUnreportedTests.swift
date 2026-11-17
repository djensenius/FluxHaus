//
//  ThermostatUnreportedTests.swift
//  FluxHaus Tests
//
//  How the thermostat controller treats changes the thermostat accepted but hasn't reported.
//

import Testing
import Foundation
@testable import FluxHaus

extension ThermostatControllerTests {
    @Test("Choosing the reported value again after a change the thermostat hasn't reported still sends it")
    func testUndoUnreported() async {
        let recorder = CommandRecorder()
        let reported = MockData.createApi().response?.indoorClimate
        // Each change is accepted, but the thermostat keeps reporting how it was before.
        recorder.reply = { _ in
            IndoorClimateState(
                timestamp: reported?.timestamp, unit: "°C", thermostat: reported?.thermostat,
                sensors: [], confirmed: false
            )
        }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("cool")
        await thermostat.setFan("on")
        await thermostat.setPreset("away")
        #expect(thermostat.mode == "heat")
        await thermostat.setMode("heat")
        await thermostat.setFan("auto")
        await thermostat.setPreset("home")
        thermostat.nudgeTarget(by: 1)
        await thermostat.commitSetpoint()
        thermostat.nudgeTarget(by: 1)
        thermostat.nudgeTarget(by: -1)
        await thermostat.commitSetpoint()
        #expect(recorder.sent == [
            .setMode("cool"), .setFan("on"), .setPreset("away"), .setMode("heat"), .setFan("auto"),
            .setPreset("home"), .setTemperature(22), .setTemperature(21.5)
        ])

        // The last changes match what's reported, so choosing them again sends nothing.
        await thermostat.setMode("heat")
        thermostat.nudgeTarget(by: 1)
        thermostat.nudgeTarget(by: -1)
        await thermostat.commitSetpoint()
        #expect(recorder.sent.count == 8)
    }

    @Test("A confirmed preset replaces an unreported setpoint change")
    func testPresetReplacesUnreportedSetpoint() async {
        let recorder = CommandRecorder()
        let reported = MockData.createApi().response?.indoorClimate
        // The setpoint change is accepted but not reported; the preset is reported straight away.
        recorder.reply = { command in
            IndoorClimateState(
                timestamp: reported?.timestamp, unit: "°C", thermostat: reported?.thermostat,
                sensors: [], confirmed: command.isSetpoint ? false : nil
            )
        }
        let thermostat = recorder.makeThermostat()
        thermostat.nudgeTarget(by: 1)
        await thermostat.commitSetpoint()
        await thermostat.setPreset("home")
        #expect(recorder.sent == [.setTemperature(22), .setPreset("home")])

        // The preset brought back the reported setpoint, so returning to it would only place a hold.
        thermostat.nudgeTarget(by: 1)
        thermostat.nudgeTarget(by: -1)
        await thermostat.commitSetpoint()
        #expect(recorder.sent.count == 2)
    }
}
