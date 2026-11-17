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

/// Stands in for the signed-in session; tests flip it to simulate another account signing in.
private final class SessionStub: @unchecked Sendable {
    private let lock = NSLock()
    private var current = true

    var isCurrent: Bool {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

@MainActor
private final class CommandRecorder {
    var sent: [ThermostatCommand] = []
    var refreshes = 0
    var reply: (ThermostatCommand) throws -> IndoorClimateState? = { _ in nil }
    /// When set, each request stays in flight until `release(_:)` is called for it.
    var holdsRequests = false
    let session = SessionStub()
    /// The session check handed to the sender with each request.
    private(set) var sessionChecks: [@Sendable () -> Bool] = []
    private var held: [(command: ThermostatCommand, resume: CheckedContinuation<Void, Never>)] = []

    func makeThermostat(delay: Duration = .seconds(60)) -> Thermostat {
        let session = self.session
        return Thermostat(
            apiResponse: MockData.createApi(),
            setpointDelay: delay,
            isSessionValid: { session.isCurrent },
            send: { [unowned self] command, isStillValid in
                self.sent.append(command)
                self.sessionChecks.append(isStillValid)
                if self.holdsRequests {
                    await withCheckedContinuation { self.held.append((command, $0)) }
                }
                // Like the real sender: checked right before credentials would be attached.
                guard isStillValid() else { throw IntentError.notSignedIn }
                return try self.reply(command)
            },
            refresh: { [unowned self] in self.refreshes += 1 }
        )
    }

    func waitUntilHeld(_ command: ThermostatCommand) async {
        for _ in 0..<200 where !held.contains(where: { $0.command == command }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release(_ command: ThermostatCommand) async {
        await waitUntilHeld(command)
        guard let index = held.firstIndex(where: { $0.command == command }) else {
            Issue.record("\(command) was never sent")
            return
        }
        held.remove(at: index).resume.resume()
    }

    /// Gives queued work a chance to run, then reports what has been sent.
    func settledSends() async -> [ThermostatCommand] {
        try? await Task.sleep(for: .milliseconds(30))
        return sent
    }
}

private struct SendFailure: LocalizedError {
    var errorDescription: String? { "Thermostat unavailable" }
}

private func autoState(low: Double, high: Double, target: Double? = nil) -> IndoorClimateState {
    IndoorClimateState(
        timestamp: "2099-01-01T00:00:00Z",
        unit: "°C",
        thermostat: ThermostatStatus(
            entityId: "climate.home", hvacMode: "heat_cool", targetTemperature: target,
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
        #expect(thermostat.usesSetpointRange)

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

    @Test("Edits made before a mode change are sent first, one request at a time")
    func testInFlightSetpoint() async {
        let recorder = CommandRecorder()
        recorder.holdsRequests = true
        let thermostat = recorder.makeThermostat()
        thermostat.nudgeTarget(by: 1)
        let firstCommit = Task { await thermostat.commitSetpoint() }
        await recorder.waitUntilHeld(.setTemperature(22))

        thermostat.nudgeTarget(by: 1)
        let modeChange = Task { await thermostat.setMode("cool") }
        let leaving = Task { await thermostat.commitSetpoint() }
        #expect(await recorder.settledSends() == [.setTemperature(22)])

        await recorder.release(.setTemperature(22))
        await recorder.release(.setTemperature(22.5))
        await recorder.release(.setMode("cool"))
        await firstCommit.value
        await modeChange.value
        await leaving.value
        #expect(recorder.sent == [.setTemperature(22), .setTemperature(22.5), .setMode("cool")])
    }

    @Test("Edits made after choosing a mode are sent after the mode change")
    func testEditDuringModeChange() async {
        let recorder = CommandRecorder()
        recorder.holdsRequests = true
        let thermostat = recorder.makeThermostat()
        thermostat.nudgeTarget(by: 1)
        let modeChange = Task { await thermostat.setMode("cool") }
        await recorder.waitUntilHeld(.setTemperature(22))
        #expect(thermostat.mode == "cool")

        thermostat.nudgeTarget(by: 1)
        let leaving = Task { await thermostat.commitSetpoint() }
        await recorder.release(.setTemperature(22))
        await recorder.release(.setMode("cool"))
        await recorder.release(.setTemperature(22.5))
        await modeChange.value
        await leaving.value
        #expect(recorder.sent == [.setTemperature(22), .setMode("cool"), .setTemperature(22.5)])
    }

    @Test("A temperature set while an Auto range is still on its way is sent as a temperature")
    func testTargetAfterRange() async {
        let recorder = CommandRecorder()
        recorder.reply = { $0 == .setMode("heat_cool") ? autoState(low: 20, high: 24, target: 22) : nil }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")
        recorder.holdsRequests = true
        thermostat.nudgeLow(by: -1)
        let heat = Task { await thermostat.setMode("heat") }
        await recorder.waitUntilHeld(.setRange(low: 19.5, high: 24))

        thermostat.nudgeTarget(by: 1)
        let leaving = Task { await thermostat.commitSetpoint() }
        await recorder.release(.setRange(low: 19.5, high: 24))
        await recorder.release(.setMode("heat"))
        await recorder.release(.setTemperature(22.5))
        await heat.value
        await leaving.value
        #expect(recorder.sent == [
            .setMode("heat_cool"), .setRange(low: 19.5, high: 24), .setMode("heat"), .setTemperature(22.5)
        ])
    }

    @Test("Quick selections are applied one at a time in the order chosen")
    func testSerializedSelections() async {
        let recorder = CommandRecorder()
        recorder.holdsRequests = true
        let thermostat = recorder.makeThermostat()
        let cool = Task { await thermostat.setMode("cool") }
        let off = Task { await thermostat.setMode("off") }
        let fan = Task { await thermostat.setFan("on") }
        #expect(await recorder.settledSends() == [.setMode("cool")])
        #expect(thermostat.mode == "off")
        #expect(thermostat.isSending)

        await recorder.release(.setMode("cool"))
        #expect(await recorder.settledSends() == [.setMode("cool"), .setMode("off")])
        #expect(thermostat.mode == "off")
        await recorder.release(.setMode("off"))
        await recorder.release(.setFan("on"))
        await cool.value
        await off.value
        await fan.value
        #expect(recorder.sent == [.setMode("cool"), .setMode("off"), .setFan("on")])
        #expect(thermostat.isSending == false)
    }

    @Test("Re-selecting the current comfort preset after an edit still applies it")
    func testPresetAfterEdit() async {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat()
        #expect(thermostat.preset == "home")
        thermostat.nudgeTarget(by: 1)
        await thermostat.setPreset("home")
        #expect(recorder.sent == [.setTemperature(22), .setPreset("home")])
    }

    @Test("A comfort preset is sent after the pending setpoint")
    func testPresetFlushesSetpoint() async {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat()
        thermostat.nudgeTarget(by: 1)
        await thermostat.setPreset("away")
        await thermostat.commitSetpoint()
        #expect(recorder.sent == [.setTemperature(22), .setPreset("away")])
    }

    @Test("Resuming the schedule discards an unsent setpoint")
    func testResumeDiscardsSetpoint() async {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat()
        thermostat.nudgeTarget(by: 1)
        await thermostat.resumeSchedule()
        await thermostat.commitSetpoint()
        #expect(recorder.sent == [.resumeSchedule])
        #expect(thermostat.target == 21.5)
    }

    @Test("An older reply doesn't replace a newer one")
    func testOlderReply() async {
        let recorder = CommandRecorder()
        recorder.reply = { command in
            let older = command == .setFan("on")
            return IndoorClimateState(
                timestamp: older ? "2099-01-01T00:00:01Z" : "2099-01-01T00:00:02Z",
                unit: "°C",
                thermostat: ThermostatStatus(
                    entityId: "climate.home", hvacMode: "heat", targetTemperature: 21,
                    presetMode: older ? "home" : "away", fanMode: "on"
                ),
                sensors: []
            )
        }
        let thermostat = recorder.makeThermostat()
        await thermostat.setPreset("away")
        await thermostat.setFan("on")
        #expect(thermostat.preset == "away")
        #expect(thermostat.state?.timestamp == "2099-01-01T00:00:02Z")
    }

    @Test("Only heat_cool uses separate heat and cool setpoints")
    func testRangeOnlyInHeatCool() async {
        let recorder = CommandRecorder()
        recorder.reply = { _ in
            IndoorClimateState(
                timestamp: "2099-01-01T00:00:00Z", unit: "°C",
                thermostat: ThermostatStatus(entityId: "climate.home", hvacMode: "auto", targetTemperature: 21),
                sensors: []
            )
        }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("auto")
        #expect(thermostat.usesSetpointRange == false)
        #expect(thermostat.target == 21)
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

    @Test("Changes queued before another account signs in are discarded, not sent")
    func testSessionChangeDiscardsQueue() async {
        let recorder = CommandRecorder()
        recorder.holdsRequests = true
        let thermostat = recorder.makeThermostat()
        let cool = Task { await thermostat.setMode("cool") }
        let off = Task { await thermostat.setMode("off") }
        #expect(await recorder.settledSends() == [.setMode("cool")])
        thermostat.nudgeTarget(by: 1)
        #expect(thermostat.mode == "off")
        #expect(thermostat.target == 22)

        recorder.session.isCurrent = false
        await recorder.release(.setMode("cool"))
        await cool.value
        await off.value
        await thermostat.commitSetpoint()
        #expect(recorder.sent == [.setMode("cool")])
        #expect(thermostat.mode == "heat")
        #expect(thermostat.target == 21.5)
        #expect(thermostat.lastError == nil)
        #expect(thermostat.isSending == false)
        #expect(thermostat.canControl == false)
        #expect(recorder.refreshes == 0)
    }

    @Test("The sender's credential check follows the session that queued the request")
    func testSenderSessionCheck() async throws {
        let recorder = CommandRecorder()
        recorder.holdsRequests = true
        let thermostat = recorder.makeThermostat()
        let fan = Task { await thermostat.setFan("on") }
        await recorder.waitUntilHeld(.setFan("on"))
        let isStillValid = try #require(recorder.sessionChecks.first)
        #expect(isStillValid())

        recorder.session.isCurrent = false
        #expect(isStillValid() == false)
        await recorder.release(.setFan("on"))
        await fan.value
        // Refused for the old account, so the new one sees no error.
        #expect(thermostat.lastError == nil)
        #expect(thermostat.fan == "auto")
    }

    @Test("Data refreshes keep the session's controller, so queued changes survive polls")
    func testRefreshReusesController() async {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat()
        thermostat.nudgeTarget(by: 1)
        let api = MockData.createApi()
        let reused = Thermostat.forCurrentSession(reusing: thermostat, apiResponse: api)
        #expect(reused === thermostat && reused.apiResponse === api && reused.target == 22)
        recorder.session.isCurrent = false
        #expect(Thermostat.forCurrentSession(reusing: thermostat, apiResponse: api) !== thermostat)
        #expect(thermostat.canControl == false)
        await thermostat.commitSetpoint()
        #expect(recorder.sent.isEmpty)
    }

    @Test("Signing out cancels an unsent setpoint and disables the controls")
    func testInvalidateCancelsDebounce() async throws {
        let recorder = CommandRecorder()
        let thermostat = recorder.makeThermostat(delay: .milliseconds(10))
        thermostat.nudgeTarget(by: 1)
        thermostat.invalidate()
        try await Task.sleep(for: .milliseconds(50))
        await thermostat.setMode("cool")
        await thermostat.commitSetpoint()
        #expect(recorder.sent.isEmpty)
        #expect(thermostat.target == 21.5)
        #expect(thermostat.canControl == false)
    }
}
