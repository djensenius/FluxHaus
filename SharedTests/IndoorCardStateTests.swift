//
//  IndoorCardStateTests.swift
//  FluxHaus Tests
//
//  How Home's Indoor card merges an accepted thermostat reply with the last poll.
//

import Testing
import Foundation
@testable import FluxHaus

struct IndoorCardMergeTests {
    private func format(_ value: Double) -> String {
        IndoorClimateFormat.temperature(value, unit: "°C")
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
        let polled = thermostatOnly(
            unit: nil, thermostatUnit: "°C", current: 21.3, timestamp: "2024-12-13T11:59:00Z"
        )
        let summary = await summaryAfterReply(thermostatOnly(unit: "°C"), polled: polled)
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

    @Test("A °F reply keeps a °F poll's reading and its rooms without their own unit, stamped °F")
    @MainActor func testSameUnitReplyStampsPolledRooms() async throws {
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
        let reply = thermostatOnly(unit: "°F")
        recorder.reply = { _ in reply }
        let thermostat = recorder.makeThermostat()
        await thermostat.setMode("heat_cool")

        let state = try #require(IndoorCardSummary.currentState(thermostat: thermostat, polled: polled))
        #expect(state.reportedUnit == "°F" && state.thermostatUnit == "°F")
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
        // Without a top-level unit the reply takes nothing from the poll, not even the
        // °C thermostat reading, so the card averages the reply's own rooms.
        #expect(state.reportedUnit == nil && state.thermostat?.currentTemperature == nil)
        #expect(summary.value == IndoorClimateFormat.temperature(70, unit: "°F"))
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
            timestamp: "2099-01-01T00:00:00Z", unit: "°C",
            thermostat: thermostatOnly(unit: nil, thermostatUnit: "°C").thermostat, sensors: []
        )
        let state = try #require(await stateAfterReply(reply, polled: polled))
        // Den could be °C or °F, so it is not shown as the reply's °C.
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

    @Test("A reply without a top-level unit never gives its own rooms the poll's household unit")
    @MainActor func testReplyRoomsNeverTakePollUnit() async throws {
        let replyRooms = [IndoorTemperatureSensor(entityId: "sensor.den", name: "Den", temperature: 20, unit: nil)]
        let reply = IndoorClimateState(
            timestamp: "2099-01-01T00:00:00Z", unit: nil,
            thermostat: thermostatOnly(unit: nil).thermostat, sensors: replyRooms
        )
        let polled = thermostatOnly(unit: "°F", current: 70, timestamp: "2024-12-13T11:59:00Z")
        let state = try #require(await stateAfterReply(reply, polled: polled))
        #expect(state.reportedUnit == nil && !state.isFahrenheit)
        #expect(state.sensors == replyRooms)
        #expect(state.thermostat?.currentTemperature == nil)
        #expect(IndoorCardSummary(state: state).value == format(20))
    }

    @Test("The merged top-level unit is exactly the reply's, never a sensor's, so it can't relabel the thermostat")
    @MainActor func testTopLevelUnitIsOnlyTheReplys() async throws {
        let replyRooms = [IndoorTemperatureSensor(entityId: "sensor.den", name: "Den", temperature: 68, unit: "°F")]
        let reply = IndoorClimateState(
            timestamp: "2099-01-01T00:00:00Z", unit: nil,
            thermostat: thermostatOnly(unit: nil).thermostat, sensors: replyRooms
        )
        let polled = thermostatOnly(unit: "°F", current: 70, timestamp: "2024-12-13T11:59:00Z")
        let state = try #require(await stateAfterReply(reply, polled: polled))
        #expect(state.reportedUnit == nil)
        #expect(state.thermostat?.temperatureUnit == nil)
        #expect(state.thermostat?.currentTemperature == nil)
        #expect(state.sensors == replyRooms)

        // A reply that states °C keeps exactly °C, whatever the poll's rooms say.
        let celsiusPoll = IndoorClimateState(
            timestamp: "2024-12-13T11:59:00Z", unit: "°C",
            thermostat: thermostatOnly(unit: nil, current: 21.3).thermostat,
            sensors: [IndoorTemperatureSensor(entityId: "sensor.attic", name: "Attic", temperature: 66, unit: "°F")]
        )
        let celsius = try #require(await stateAfterReply(thermostatOnly(unit: "°C"), polled: celsiusPoll))
        #expect(celsius.reportedUnit == "°C")
        #expect(celsius.sensors.isEmpty)
        #expect(celsius.thermostat?.currentTemperature == 21.3)
    }

    @Test("An offline thermostat's last polled reading is not shown as current after a change")
    @MainActor func testOfflineReadingNotCarried() async {
        let offline = thermostatOnly(unit: "°C", current: 21.3, available: false, timestamp: "2024-12-13T11:59:00Z")
        let summary = await summaryAfterReply(thermostatOnly(unit: "°C"), polled: offline)
        #expect(summary.value == IndoorCardSummary.placeholder)
    }
}
