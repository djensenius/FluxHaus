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
    /// settings, so the poll's rooms and online thermostat reading fill in until the next
    /// poll, but only when the reply's unit is the poll's or the reply gives none.
    /// A controller from another session, even one that hasn't noticed yet, is ignored.
    @MainActor
    static func currentState(thermostat: Thermostat?, polled: IndoorClimateState?) -> IndoorClimateState? {
        guard let thermostat, thermostat.belongsToCurrentSession, let current = thermostat.state else {
            return polled
        }
        guard let polled else { return current }
        let pollUnit = polled.thermostatUnit
        if let replyUnit = statedUnit(of: current), !sameScale(replyUnit, pollUnit) { return current }

        let readingsFrom = polled.thermostat.flatMap { old in
            old.available != false && old.entityId == current.thermostat?.entityId ? old : nil
        }
        return IndoorClimateState(
            timestamp: current.timestamp,
            unit: current.reportedUnit ?? polled.unit,
            thermostat: current.thermostat.map {
                $0.filled(from: readingsFrom, unit: statedUnit(of: current) ?? pollUnit)
            } ?? polled.thermostat?.filled(from: nil, unit: pollUnit),
            sensors: current.sensors.isEmpty
                ? polled.sensors.map { $0.stated(in: $0.unit.flatMap { $0.isEmpty ? nil : $0 } ?? polled.unit) }
                : current.sensors,
            confirmed: current.confirmed
        )
    }

    /// The unit a response gives for its thermostat (its own, the response's, then its
    /// first sensor's), or nil when it gives none.
    static func statedUnit(of state: IndoorClimateState) -> String? {
        let candidates = [state.thermostat?.temperatureUnit, state.reportedUnit] + state.sensors.map(\.unit)
        return candidates.lazy.compactMap { $0 }.first { !$0.isEmpty }
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
    func filled(from polled: ThermostatStatus?, unit: String) -> ThermostatStatus {
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
    func stated(in unit: String) -> IndoorTemperatureSensor {
        IndoorTemperatureSensor(
            entityId: entityId, name: name, area: area, temperature: temperature, unit: unit,
            available: available, occupied: occupied, isThermostat: isThermostat, lastUpdated: lastUpdated
        )
    }
}
