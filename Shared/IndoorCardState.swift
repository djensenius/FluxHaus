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

    /// Conservative merge of a poll into a reply. The merged top-level unit is exactly the
    /// reply's, and the reply's own rooms are never changed.
    /// - A reply stating a top-level unit U takes the polled thermostat reading only when the
    ///   poll's thermostat (or top-level) unit is explicitly U, and polled rooms only when their
    ///   own (or the poll's top-level) unit is explicitly U, stamped with U.
    /// - A reply without one takes nothing, unless neither response states any unit, when
    ///   the poll fills in as it is.
    private static func carry(from polled: IndoorClimateState, into current: IndoorClimateState) -> IndoorClimateState {
        let readingsFrom = polled.thermostat.flatMap { old in
            old.available != false && old.entityId == current.thermostat?.entityId ? old : nil
        }
        let thermostat: ThermostatStatus?
        let rooms: [IndoorTemperatureSensor]
        if let unit = nonEmpty(current.reportedUnit) {
            let pollUnit = nonEmpty(polled.thermostat?.temperatureUnit) ?? nonEmpty(polled.reportedUnit)
            let replyUnit = nonEmpty(current.thermostat?.temperatureUnit) ?? unit
            let carriesReading = pollUnit.map { sameScale($0, unit) && sameScale($0, replyUnit) } ?? false
            thermostat = current.thermostat.map { carriesReading ? $0.filled(from: readingsFrom, unit: nil) : $0 }
                ?? (carriesReading ? polled.thermostat?.filled(from: nil, unit: pollUnit) : nil)
            rooms = polled.sensors.compactMap { sensor in
                guard let own = nonEmpty(sensor.unit) ?? nonEmpty(polled.reportedUnit),
                      sameScale(own, unit) else { return nil }
                return sensor.stated(in: unit)
            }
        } else if !statesAnyUnit(polled) && !statesAnyUnit(current) {
            thermostat = current.thermostat.map { $0.filled(from: readingsFrom, unit: nil) } ?? polled.thermostat
            rooms = polled.sensors
        } else {
            return current
        }
        return IndoorClimateState(
            timestamp: current.timestamp,
            unit: current.reportedUnit,
            thermostat: thermostat,
            sensors: current.sensors.isEmpty ? rooms : current.sensors,
            confirmed: current.confirmed
        )
    }

    private static func statesAnyUnit(_ state: IndoorClimateState) -> Bool {
        nonEmpty(state.thermostat?.temperatureUnit) != nil || nonEmpty(state.reportedUnit) != nil
            || state.sensors.contains { nonEmpty($0.unit) != nil }
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
