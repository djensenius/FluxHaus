//
//  ThermostatTests.swift
//  FluxHaus Tests
//
//  Thermostat control: request shapes, setpoint math, labels, and the
//  optimistic/debounced controller used by the Climate section.
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
    }

    @Test("Decodes the thermostat's control capabilities")
    func testDecodeCapabilities() throws {
        let json = Data("""
        {"entityId":"climate.home","hvacModes":["heat_cool","heat","cool","off"],
         "presetModes":["away","home","sleep"],"fanMode":"auto","fanModes":["on","auto"],
         "minTemp":7,"maxTemp":35,"targetTempStep":0.5}
        """.utf8)
        let status = try JSONDecoder().decode(ThermostatStatus.self, from: json)
        #expect(status.hvacModes == ["heat_cool", "heat", "cool", "off"])
        #expect(status.presetModes == ["away", "home", "sleep"])
        #expect(status.fanMode == "auto" && status.fanModes == ["on", "auto"])
        #expect(status.minTemp == 7 && status.maxTemp == 35 && status.targetTempStep == 0.5)

        let legacy = try JSONDecoder().decode(ThermostatStatus.self, from: Data(#"{"entityId":"climate.home"}"#.utf8))
        #expect(legacy.hvacModes == nil && legacy.targetTempStep == nil)
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

    @Test("Labels read naturally and modes are shown Heat, Cool, Auto, Off")
    func testLabels() {
        #expect(ThermostatLabels.ordered(["heat_cool", "fan_only", "heat", "cool", "off"])
            == ["heat", "cool", "heat_cool", "off", "fan_only"])
        #expect(ThermostatLabels.mode("heat_cool") == "Auto")
        #expect(ThermostatLabels.preset("temp") == "Hold")
        #expect(ThermostatLabels.preset("away_indefinitely") == "Away (indefinitely)")
        #expect(ThermostatLabels.preset("Work From Home") == "Work From Home")
    }

    @Test("Shortcut dialog describes what was changed")
    func testIntentDialog() {
        let state = IndoorClimateState(unit: "°C", sensors: [])
        let target = IndoorClimateFormat.temperature(21, unit: "°C", precise: false)
        #expect(SetThermostatIntent.dialog(mode: .heat, temperature: 21, state: state)
            == "Setting the thermostat to Heat at \(target).")
        #expect(SetThermostatIntent.dialog(mode: nil, temperature: 21, state: state)
            == "Setting the thermostat to \(target).")
        #expect(SetThermostatIntent.dialog(mode: .auto, temperature: nil, state: nil)
            == "Setting the thermostat to Auto.")
        #expect(SetThermostatIntent.dialog(mode: .off, temperature: 21, state: state)
            == "Turning the thermostat off.")
    }
}

@MainActor
private final class CommandRecorder {
    var sent: [ThermostatCommand] = []
    var refreshes = 0
    var reply: (ThermostatCommand) throws -> IndoorClimateState? = { _ in nil }

    func makeThermostat(delay: Duration = .seconds(60)) -> Thermostat {
        Thermostat(
            apiResponse: MockData.createApi(),
            setpointDelay: delay,
            send: { [unowned self] command in
                self.sent.append(command)
                return try self.reply(command)
            },
            refresh: { [unowned self] in self.refreshes += 1 }
        )
    }
}

private struct SendFailure: LocalizedError {
    var errorDescription: String? { "Thermostat unavailable" }
}

private func autoState(low: Double, high: Double) -> IndoorClimateState {
    IndoorClimateState(
        timestamp: "2099-01-01T00:00:00Z",
        unit: "°C",
        thermostat: ThermostatStatus(
            entityId: "climate.home", hvacMode: "heat_cool",
            targetTemperatureLow: low, targetTemperatureHigh: high, targetTempStep: 0.5
        ),
        sensors: []
    )
}

@MainActor
struct ThermostatControllerTests {
    @Test("Repeated taps are combined into one setpoint request")
    func testDebouncedSetpoint() async {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat()
        #expect(thermostat.target == 21.5)

        thermostat.nudgeTarget(by: 1)
        thermostat.nudgeTarget(by: 1)
        #expect(thermostat.target == 22.5)
        #expect(recorder.sent.isEmpty)

        await thermostat.commitSetpoint()
        #expect(recorder.sent == [.setTemperature(22.5)])
        #expect(recorder.refreshes == 1)
        #expect(thermostat.pendingTarget == nil)
    }

    @Test("A pending setpoint is sent automatically after the delay")
    func testAutoCommit() async throws {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat(delay: .milliseconds(10))
        thermostat.nudgeTarget(by: -1)
        for _ in 0..<100 where recorder.sent.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.sent == [.setTemperature(21)])
    }

    @Test("Changing mode first sends the setpoint chosen for the old mode")
    func testModeFlushesSetpoint() async {
        let recorder = CommandRecorder()
        recorder.reply = { command in
            if case .setMode = command { return autoState(low: 20, high: 20.5) }
            return nil
        }
        let thermostat = recorder.makeThermostat()
        thermostat.nudgeTarget(by: 1)
        await thermostat.setMode("heat_cool")
        #expect(recorder.sent == [.setTemperature(22), .setMode("heat_cool")])
        #expect(thermostat.isAutoMode)

        // Low can't pass high minus one step, and vice versa.
        thermostat.nudgeLow(by: 1)
        #expect(thermostat.targetLow == 20)
        thermostat.nudgeHigh(by: -3)
        #expect(thermostat.targetHigh == 20.5)
        thermostat.nudgeHigh(by: 2)
        await thermostat.commitSetpoint()
        #expect(recorder.sent.last == .setRange(low: 20, high: 21.5))
    }

    @Test("The server's reply is shown until a newer poll arrives")
    func testPrefersLatestReply() async {
        let recorder = CommandRecorder()
        recorder.reply = { _ in autoState(low: 19, high: 25) }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")
        #expect(thermostat.mode == "heat_cool")
        #expect(thermostat.targetLow == 19)
    }

    @Test("A failed request reports the error and reverts the optimistic value")
    func testFailure() async {
        let recorder = CommandRecorder()
        recorder.reply = { _ in throw SendFailure() }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("cool")
        #expect(thermostat.mode == "heat")
        #expect(thermostat.lastError == "Thermostat unavailable")
        #expect(thermostat.isSending == false)
        #expect(recorder.refreshes == 0)
    }

    @Test("Choosing the current value sends nothing")
    func testNoOpChanges() async {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat")
        await thermostat.setPreset("home")
        await thermostat.setFan("auto")
        await thermostat.commitSetpoint()
        #expect(recorder.sent.isEmpty)
    }
}
