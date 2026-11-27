//
//  IndoorCardState.swift
//  FluxHaus
//
//  The indoor state the Home Indoor card shows: the thermostat's last accepted
//  change merged with the poll, so no carried value keeps an implicit unit.
//

import Foundation

extension IndoorCardSummary {
    /// The freshest indoor state for Home: the session thermostat's last accepted change
    /// until a newer poll, else the polled snapshot. A control reply may report only
    /// settings, so the poll's online thermostat reading and rooms fill in until the next
    /// poll, but only where their unit is known (see `carry(from:into:)`).
    /// A controller from another session, even one that hasn't noticed yet, is ignored.
    @MainActor
    static func currentState(thermostat: Thermostat?, polled: IndoorClimateState?) -> IndoorClimateState? {
        guard let thermostat, thermostat.belongsToCurrentSession, let current = thermostat.state else {
            return polled
        }
        guard let polled else { return current }
        return carry(from: polled, into: current)
    }

    /// Conservative merge of a poll into a reply:
    /// - The thermostat reading is carried only when the poll states its thermostat's unit
    ///   (its own or the top-level one; a sensor's never counts) and the reply states the
    ///   same, or states no unit anywhere. A reply in another unit takes nothing.
    /// - A polled room is carried only with a unit of its own or the poll's top-level one,
    ///   and is stamped with it; rooms of unknown unit are dropped.
    /// - The reply's own rooms are never changed.
    /// - When neither states any unit, both are shown as they are.
    private static func carry(from polled: IndoorClimateState, into current: IndoorClimateState) -> IndoorClimateState {
        let readingsFrom = polled.thermostat.flatMap { old in
            old.available != false && old.entityId == current.thermostat?.entityId ? old : nil
        }
        let pollUnit = thermostatUnit(of: polled)
        let replyUnit = thermostatUnit(of: current)
        let thermostat: ThermostatStatus?
        let rooms: [IndoorTemperatureSensor]
        let unit: String?
        if !statesAnyUnit(polled) && !statesAnyUnit(current) {
            thermostat = current.thermostat.map { $0.filled(from: readingsFrom, unit: nil) } ?? polled.thermostat
            rooms = polled.sensors
            unit = nil
        } else {
            if let replyUnit, let pollUnit, !sameScale(replyUnit, pollUnit) { return current }
            let carriesReading = pollUnit != nil && (replyUnit != nil || !statesAnyUnit(current))
            thermostat = current.thermostat.map {
                carriesReading ? $0.filled(from: readingsFrom, unit: replyUnit ?? pollUnit) : $0
            } ?? (carriesReading ? polled.thermostat?.filled(from: nil, unit: pollUnit) : nil)
            rooms = polled.sensors.compactMap { sensor in
                (nonEmpty(sensor.unit) ?? nonEmpty(polled.reportedUnit)).map { sensor.stated(in: $0) }
            }
            unit = sensorUnit(of: current) ?? nonEmpty(polled.reportedUnit)
        }
        return IndoorClimateState(
            timestamp: current.timestamp,
            unit: unit,
            thermostat: thermostat,
            sensors: current.sensors.isEmpty ? rooms : current.sensors,
            confirmed: current.confirmed
        )
    }

    /// The unit a response states for its thermostat: the thermostat's own, else the
    /// response's top-level unit. A sensor's unit is never evidence for it.
    private static func thermostatUnit(of state: IndoorClimateState) -> String? {
        nonEmpty(state.thermostat?.temperatureUnit) ?? nonEmpty(state.reportedUnit)
    }

    private static func statesAnyUnit(_ state: IndoorClimateState) -> Bool {
        thermostatUnit(of: state) != nil || state.sensors.contains { nonEmpty($0.unit) != nil }
    }

    /// The unit a response gives its sensors without a unit of their own, or nil when unstated.
    private static func sensorUnit(of state: IndoorClimateState) -> String? {
        nonEmpty(state.reportedUnit) ?? state.sensors.lazy.compactMap { nonEmpty($0.unit) }.first
    }

    private static func nonEmpty(_ unit: String?) -> String? {
        unit.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func sameScale(_ first: String, _ second: String) -> Bool {
        func scale(_ unit: String) -> String {
            let unit = unit.uppercased()
            return unit.contains("F") ? "F" : unit.contains("C") ? "C" : unit
        }
        return scale(first) == scale(second)
    }
}

private extension ThermostatStatus {
    /// This status stated in `unit` unless it gives its own, with `polled`'s reading and
    /// humidity filled in where it has none.
    func filled(from polled: ThermostatStatus?, unit: String?) -> ThermostatStatus {
        ThermostatStatus(
            entityId: entityId, name: name, area: area, available: available,
            currentTemperature: currentTemperature ?? polled?.currentTemperature,
            currentHumidity: currentHumidity ?? polled?.currentHumidity,
            hvacMode: hvacMode, hvacAction: hvacAction, targetTemperature: targetTemperature,
            targetTemperatureLow: targetTemperatureLow, targetTemperatureHigh: targetTemperatureHigh,
            presetMode: presetMode, hvacModes: hvacModes, presetModes: presetModes,
            fanMode: fanMode, fanModes: fanModes, minTemp: minTemp, maxTemp: maxTemp,
            targetTempStep: targetTempStep,
            temperatureUnit: temperatureUnit.flatMap { $0.isEmpty ? nil : $0 } ?? unit
        )
    }
}

private extension IndoorTemperatureSensor {
    func stated(in unit: String?) -> IndoorTemperatureSensor {
        IndoorTemperatureSensor(
            entityId: entityId, name: name, area: area, temperature: temperature, unit: unit,
            available: available, occupied: occupied, isThermostat: isThermostat, lastUpdated: lastUpdated
        )
    }
}
