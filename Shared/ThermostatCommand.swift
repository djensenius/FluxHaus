//
//  ThermostatCommand.swift
//  FluxHaus
//
//  Thermostat control requests for the server's `/thermostat/*` routes.
//

import Foundation

/// A control request for the server's `/thermostat/*` routes.
public enum ThermostatCommand: Equatable, Sendable {
    case setTemperature(Double)
    case setRange(low: Double, high: Double)
    case setMode(String)
    case setPreset(String)
    case setFan(String)
    case resumeSchedule

    var path: String {
        switch self {
        case .setTemperature, .setRange: return "/thermostat/temperature"
        case .setMode: return "/thermostat/mode"
        case .setPreset: return "/thermostat/preset"
        case .setFan: return "/thermostat/fan"
        case .resumeSchedule: return "/thermostat/resume"
        }
    }

    var body: [String: Any] {
        switch self {
        case .setTemperature(let temperature): return ["temperature": temperature]
        case let .setRange(low, high): return ["targetTempLow": low, "targetTempHigh": high]
        case .setMode(let mode): return ["mode": mode]
        case .setPreset(let preset): return ["preset": preset]
        case .setFan(let mode): return ["mode": mode]
        // Clears every hold, not just the latest, so the schedule really resumes.
        case .resumeSchedule: return ["resumeAll": true]
        }
    }

    /// Setpoints are chosen for the mode the thermostat is in.
    var isSetpoint: Bool {
        switch self {
        case .setTemperature, .setRange: return true
        case .setMode, .setPreset, .setFan, .resumeSchedule: return false
        }
    }

    /// Whether the command can change the thermostat's setpoints.
    var movesSetpoints: Bool {
        if case .setFan = self { return false }
        return true
    }
}
