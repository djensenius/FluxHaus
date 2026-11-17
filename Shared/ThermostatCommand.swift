//
//  ThermostatCommand.swift
//  FluxHaus
//
//  Thermostat control requests for the server's `/thermostat/*` routes, and
//  display labels for thermostat values.
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

// MARK: - Labels

enum ThermostatLabels {
    static let defaultModes = ["heat", "cool", "heat_cool", "off"]

    /// Heat, Cool, Auto, Off first, then anything else in the order reported.
    static func ordered(_ modes: [String]) -> [String] {
        let preferred = ["heat", "cool", "heat_cool", "auto", "off"]
        let rank = { (mode: String) in preferred.firstIndex(of: mode.lowercased()) ?? preferred.count }
        return modes.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    static func mode(_ raw: String) -> String {
        switch raw.lowercased() {
        case "heat_cool", "auto": return "Auto"
        case "fan_only": return "Fan"
        case "off": return "Off"
        default: return titled(raw)
        }
    }

    static func modeIcon(_ raw: String) -> String {
        switch raw.lowercased() {
        case "heat": return "flame"
        case "cool": return "snowflake"
        case "heat_cool", "auto": return "arrow.up.arrow.down"
        case "off": return "power"
        case "fan_only": return "fan"
        case "dry": return "humidity"
        default: return "thermometer.medium"
        }
    }

    static func preset(_ raw: String) -> String {
        switch raw.lowercased() {
        case "temp": return "Hold"
        case "away_indefinitely": return "Away (indefinitely)"
        default: return titled(raw)
        }
    }

    static func fan(_ raw: String) -> String { titled(raw) }

    private static func titled(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
