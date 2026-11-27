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
        #expect(summary.warmest == "Warmest Kitchen \(format(22.6))")
        #expect(summary.coolest == "Coolest Main Bedroom \(format(19.8))")
        // One fact per line, so the card's narrow detail column never splits a room from its reading.
        #expect(summary.detail.components(separatedBy: "\n") == [
            status, "Warmest Kitchen \(format(22.6))", "Coolest Main Bedroom \(format(19.8))"
        ])
    }

    @Test("Without a thermostat or sensors the Indoor card is a muted placeholder")
    func testSummaryWithoutReadings() {
        for state in [nil, IndoorClimateState(sensors: [])] {
            let summary = IndoorCardSummary(state: state)
            #expect(summary.value == IndoorCardSummary.placeholder)
            #expect(!summary.hasReadings && !summary.isActive)
            #expect(summary.status == nil && summary.warmest == nil && summary.coolest == nil)
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
        #expect(summary.warmest == nil && summary.coolest == nil)
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

    @Test("Home shows the thermostat's accepted change before the next poll, keeping the polled rooms")
    @MainActor func testSummaryPrefersAcceptedChange() async throws {
        let polled = try #require(MockData.loginResponse.indoorClimate)
        #expect(IndoorCardSummary(state: IndoorCardSummary.currentState(thermostat: nil, polled: polled))
            .status?.hasPrefix("Heating") == true)

        let recorder = CommandRecorder()
        recorder.reply = { _ in autoState(low: 19, high: 24) }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")

        let current = IndoorCardSummary(
            state: IndoorCardSummary.currentState(thermostat: thermostat, polled: polled)
        )
        #expect(current.status?.hasPrefix("Auto") == true)
        #expect(current.activity == .idle && !current.isActive)
        // The reply has no reading or rooms, so the polled thermostat reading and rooms are kept.
        #expect(current.value == format(21.3))
        #expect(current.warmest == "Warmest Kitchen \(format(22.6))")
        #expect(current.coolest == "Coolest Main Bedroom \(format(19.8))")

        // Once the session ends, its controller's replies are dropped and Home shows the poll.
        thermostat.invalidate()
        let afterSignOut = IndoorCardSummary(
            state: IndoorCardSummary.currentState(thermostat: thermostat, polled: polled)
        )
        #expect(afterSignOut.status?.hasPrefix("Heating") == true)
    }

    @Test("A thermostat-only home keeps its polled reading when the accepted reply has none")
    @MainActor func testThermostatOnlyHomeKeepsReading() async throws {
        let mock = try #require(MockData.loginResponse.indoorClimate)
        let polled = IndoorClimateState(
            timestamp: mock.timestamp, unit: mock.unit, thermostat: mock.thermostat, sensors: []
        )
        let recorder = CommandRecorder()
        recorder.reply = { _ in autoState(low: 19, high: 24) }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")

        let current = IndoorCardSummary(
            state: IndoorCardSummary.currentState(thermostat: thermostat, polled: polled)
        )
        #expect(current.value == format(21.3))
        #expect(current.status?.hasPrefix("Auto") == true)
    }

    @Test("A reply from an account that is no longer signed in is never shown or mixed with the new poll")
    @MainActor func testAccountSwitchShowsOnlyNewPoll() async throws {
        let polled = try #require(MockData.loginResponse.indoorClimate)
        let recorder = CommandRecorder()
        recorder.reply = { _ in autoState(low: 19, high: 24) }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")
        #expect(IndoorCardSummary(state: IndoorCardSummary.currentState(thermostat: thermostat, polled: polled))
            .status?.hasPrefix("Auto") == true)

        // The credentials change without a sign-out event reaching this controller.
        recorder.session.isCurrent = false
        let current = IndoorCardSummary(
            state: IndoorCardSummary.currentState(thermostat: thermostat, polled: polled)
        )
        #expect(current.status?.hasPrefix("Heating") == true)
        #expect(current.value == format(21.3))
        // Rendering must not change the controller; only its own session checks may invalidate it.
        #expect(!thermostat.isInvalidated)
    }

    /// The Indoor card after the thermostat accepts a change whose reply is `reply`, before the next poll of `polled`.
    @MainActor private func summaryAfterReply(
        _ reply: IndoorClimateState, polled: IndoorClimateState
    ) async -> IndoorCardSummary {
        let recorder = CommandRecorder()
        recorder.reply = { _ in reply }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")
        return IndoorCardSummary(state: IndoorCardSummary.currentState(thermostat: thermostat, polled: polled))
    }

    @MainActor private func stateAfterReply(
        _ reply: IndoorClimateState, polled: IndoorClimateState
    ) async -> IndoorClimateState? {
        let recorder = CommandRecorder()
        recorder.reply = { _ in reply }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")
        return IndoorCardSummary.currentState(thermostat: thermostat, polled: polled)
    }

    private func thermostatOnly(
        unit: String?, thermostatUnit: String? = nil, current: Double? = nil,
        available: Bool = true, timestamp: String = "2099-01-01T00:00:00Z"
    ) -> IndoorClimateState {
        IndoorClimateState(
            timestamp: timestamp, unit: unit,
            thermostat: ThermostatStatus(
                entityId: "climate.home", available: available, currentTemperature: current,
                hvacMode: "heat_cool", targetTemperatureLow: 19, targetTemperatureHigh: 24,
                temperatureUnit: thermostatUnit
            ),
            sensors: []
        )
    }

    @Test("The polled reading is kept when each response states the same unit in a different place")
    @MainActor func testReadingKeptWhenUnitsResolveTheSame() async {
        let polled = thermostatOnly(unit: "°C", current: 21.3, timestamp: "2024-12-13T11:59:00Z")
        let summary = await summaryAfterReply(thermostatOnly(unit: nil, thermostatUnit: "°C"), polled: polled)
        #expect(summary.value == format(21.3))
        #expect(summary.status?.hasPrefix("Auto") == true)
    }

    @Test("A polled reading is dropped unless both responses definitely give it the reply's unit")
    @MainActor func testReadingDroppedWhenUnitsUnknownOrDiffer() async {
        // The poll names no unit at all, so its 21.3 could be °C; it must not become 21.3 °F.
        let unknown = thermostatOnly(unit: nil, current: 21.3, timestamp: "2024-12-13T11:59:00Z")
        let afterUnknown = await summaryAfterReply(thermostatOnly(unit: "°F"), polled: unknown)
        #expect(afterUnknown.value == IndoorCardSummary.placeholder)
        #expect(afterUnknown.status?.hasPrefix("Auto") == true)

        let celsius = thermostatOnly(unit: "°C", current: 21.3, timestamp: "2024-12-13T11:59:00Z")
        let afterMismatch = await summaryAfterReply(thermostatOnly(unit: nil, thermostatUnit: "°F"), polled: celsius)
        #expect(afterMismatch.value == IndoorCardSummary.placeholder)
    }

    @Test("A reply that gives no unit keeps the polled reading and rooms, all stated in the poll's unit")
    @MainActor func testReplyWithoutUnitInheritsPollUnit() async throws {
        let rooms = [
            IndoorTemperatureSensor(entityId: "sensor.den", name: "Den", temperature: 72, unit: nil),
            IndoorTemperatureSensor(entityId: "sensor.attic", name: "Attic", temperature: 66, unit: nil)
        ]
        let fahrenheit = try #require(thermostatOnly(unit: "°F", current: 70, timestamp: "2024-12-13T11:59:00Z")
            .thermostat)
        let polled = IndoorClimateState(
            timestamp: "2024-12-13T11:59:00Z", unit: "°F", thermostat: fahrenheit, sensors: rooms
        )
        let recorder = CommandRecorder()
        let reply = thermostatOnly(unit: nil)
        recorder.reply = { _ in reply }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")

        let state = try #require(IndoorCardSummary.currentState(thermostat: thermostat, polled: polled))
        #expect(state.thermostat?.temperatureUnit == "°F")
        #expect(state.sensors.map(\.unit) == ["°F", "°F"])
        let summary = IndoorCardSummary(state: state)
        #expect(summary.value == IndoorClimateFormat.temperature(70, unit: "°F"))
        #expect(summary.warmest == "Warmest Den \(IndoorClimateFormat.temperature(72, unit: "°F"))")
        #expect(summary.status?.hasPrefix("Auto") == true)
    }

    @Test("A °F reply never takes over a °C poll's readings or its rooms without their own unit")
    @MainActor func testDifferentReplyUnitCarriesNothing() async {
        let rooms = [
            IndoorTemperatureSensor(entityId: "sensor.den", name: "Den", temperature: 22, unit: nil),
            IndoorTemperatureSensor(entityId: "sensor.attic", name: "Attic", temperature: 19, unit: nil)
        ]
        let polled = IndoorClimateState(
            timestamp: "2024-12-13T11:59:00Z", unit: "°C",
            thermostat: thermostatOnly(unit: "°C", current: 21.3).thermostat, sensors: rooms
        )
        let summary = await summaryAfterReply(thermostatOnly(unit: "°F"), polled: polled)
        #expect(summary.value == IndoorCardSummary.placeholder)
        #expect(summary.warmest == nil && summary.coolest == nil)
        #expect(summary.status?.hasPrefix("Auto") == true)
    }

    @Test("A °C reply never adopts a reading from a poll that states no unit, though the poll alone still shows it")
    @MainActor func testStatedReplyIgnoresUnstatedPoll() async {
        let unstated = thermostatOnly(unit: nil, current: 21.3, timestamp: "2024-12-13T11:59:00Z")
        #expect(IndoorCardSummary(state: IndoorCardSummary.currentState(thermostat: nil, polled: unstated))
            .value == format(21.3))

        let summary = await summaryAfterReply(thermostatOnly(unit: "°C"), polled: unstated)
        #expect(summary.value == IndoorCardSummary.placeholder)
        #expect(summary.status?.hasPrefix("Auto") == true)
    }

    @Test("A reply's own rooms keep its sensors' scale even when it states no top-level unit")
    @MainActor func testReplyRoomsKeepTheirOwnScale() async throws {
        let polled = IndoorClimateState(
            timestamp: "2024-12-13T11:59:00Z", unit: "°C",
            thermostat: thermostatOnly(unit: nil, thermostatUnit: "°C", current: 21.3).thermostat,
            sensors: [IndoorTemperatureSensor(entityId: "sensor.hall", name: "Hall", temperature: 20, unit: "°C")]
        )
        let rooms = [
            IndoorTemperatureSensor(entityId: "sensor.den", name: "Den", temperature: 68, unit: "°F"),
            IndoorTemperatureSensor(entityId: "sensor.attic", name: "Attic", temperature: 72, unit: nil)
        ]
        let reply = IndoorClimateState(
            timestamp: "2099-01-01T00:00:00Z", unit: nil,
            thermostat: thermostatOnly(unit: nil, thermostatUnit: "°C").thermostat, sensors: rooms
        )
        let recorder = CommandRecorder()
        recorder.reply = { _ in reply }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")

        let state = try #require(IndoorCardSummary.currentState(thermostat: thermostat, polled: polled))
        #expect(state.sensors == rooms)
        #expect(state.isFahrenheit)
        let summary = IndoorCardSummary(state: state)
        #expect(summary.warmest == "Warmest Attic \(IndoorClimateFormat.temperature(72, unit: "°F"))")
        #expect(summary.coolest == "Coolest Den \(IndoorClimateFormat.temperature(68, unit: "°F"))")
        // The °C thermostat reading carried from the poll is shown in the reply's °F.
        #expect(summary.value == IndoorClimateFormat.temperature(21.3 * 9 / 5 + 32, unit: "°F"))
    }

    @Test("Polled rooms of unknown unit are dropped; the rest keep their own unit")
    @MainActor func testUnknownUnitRoomsDropped() async throws {
        let polled = IndoorClimateState(
            timestamp: "2024-12-13T11:59:00Z", unit: nil,
            thermostat: thermostatOnly(unit: nil, thermostatUnit: "°C", current: 21.3).thermostat,
            sensors: [
                IndoorTemperatureSensor(entityId: "sensor.den", name: "Den", temperature: 22, unit: nil),
                IndoorTemperatureSensor(entityId: "sensor.hall", name: "Hall", temperature: 20, unit: "°C")
            ]
        )
        let reply = IndoorClimateState(
            timestamp: "2099-01-01T00:00:00Z", unit: "°F",
            thermostat: thermostatOnly(unit: nil, thermostatUnit: "°C").thermostat, sensors: []
        )
        let state = try #require(await stateAfterReply(reply, polled: polled))
        // Den could be °C or °F, so it is not shown as the reply's °F.
        #expect(state.sensors.map(\.entityId) == ["sensor.hall"])
        #expect(state.sensors.map(\.unit) == ["°C"])
        #expect(state.thermostat?.currentTemperature == 21.3)
    }

    @Test("A sensor's unit is never taken as the polled thermostat's unit")
    @MainActor func testSensorUnitIsNotThermostatUnit() async throws {
        let polled = IndoorClimateState(
            timestamp: "2024-12-13T11:59:00Z", unit: nil,
            thermostat: thermostatOnly(unit: nil, current: 21.3).thermostat,
            sensors: [IndoorTemperatureSensor(entityId: "sensor.hall", name: "Hall", temperature: 20, unit: "°C")]
        )
        let state = try #require(await stateAfterReply(thermostatOnly(unit: "°C"), polled: polled))
        #expect(state.thermostat?.currentTemperature == nil)
        // The room states its own unit, so it is still shown.
        #expect(IndoorCardSummary(state: state).value == format(20))
    }

    @Test("When neither response states a unit, both are shown as they are")
    @MainActor func testUnstatedResponsesShownAsTheyAre() async throws {
        let rooms = [IndoorTemperatureSensor(entityId: "sensor.den", name: "Den", temperature: 22, unit: nil)]
        let polled = IndoorClimateState(
            timestamp: "2024-12-13T11:59:00Z", unit: nil,
            thermostat: thermostatOnly(unit: nil, current: 21.3).thermostat, sensors: rooms
        )
        let state = try #require(await stateAfterReply(thermostatOnly(unit: nil), polled: polled))
        #expect(state.thermostat?.currentTemperature == 21.3)
        #expect(state.thermostat?.temperatureUnit == nil)
        #expect(state.sensors == rooms)
        #expect(IndoorCardSummary(state: state).status?.hasPrefix("Auto") == true)
    }

    @Test("An offline thermostat's last polled reading is not shown as current after a change")
    @MainActor func testOfflineReadingNotCarried() async {
        let offline = thermostatOnly(unit: "°C", current: 21.3, available: false, timestamp: "2024-12-13T11:59:00Z")
        let summary = await summaryAfterReply(thermostatOnly(unit: "°C"), polled: offline)
        #expect(summary.value == IndoorCardSummary.placeholder)
    }
}

struct AdaptiveHomeLayoutTests {
    @Test("Only a regular-width iPad window wide enough gets the full-width Home dashboard")
    func testWideHomeDecision() {
        // Full-screen iPads, landscape and portrait.
        #expect(AdaptiveLayout.usesWideHome(width: 1366, isPad: true, isRegularWidth: true))
        #expect(AdaptiveLayout.usesWideHome(width: 834, isPad: true, isRegularWidth: true))
        // Split View / dual-screen halves are compact, and narrow regular windows too small.
        #expect(!AdaptiveLayout.usesWideHome(width: 507, isPad: true, isRegularWidth: false))
        #expect(!AdaptiveLayout.usesWideHome(width: 694, isPad: true, isRegularWidth: true))
        // A large iPhone in landscape is regular width and wide, but keeps the compact Home.
        #expect(!AdaptiveLayout.usesWideHome(width: 956, isPad: false, isRegularWidth: true))
        #expect(!AdaptiveLayout.usesWideHome(width: 440, isPad: false, isRegularWidth: false))
    }
}
