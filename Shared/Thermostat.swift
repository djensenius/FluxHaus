//
//  Thermostat.swift
//  FluxHaus
//
//  Thermostat control: request building, setpoint math, display labels, and an
//  observable controller with optimistic updates for the Climate section.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Thermostat")

// MARK: - Commands

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
        case .resumeSchedule: return ["resumeAll": false]
        }
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

// MARK: - Setpoint math

enum ThermostatSetpoint {
    /// Step used for ± buttons: the thermostat's reported step, else 0.5 °C / 1 °F.
    static func step(for thermostat: ThermostatStatus, fahrenheit: Bool) -> Double {
        if let step = thermostat.targetTempStep, step > 0 { return step }
        return fahrenheit ? 1 : 0.5
    }

    /// Allowed setpoints: the thermostat's reported range, else Ecobee's defaults.
    static func bounds(for thermostat: ThermostatStatus, fahrenheit: Bool) -> ClosedRange<Double> {
        let low = thermostat.minTemp ?? (fahrenheit ? 45 : 7)
        let high = thermostat.maxTemp ?? (fahrenheit ? 92 : 33)
        return low <= high ? low...high : high...low
    }

    /// Moves `value` by `steps`, snapping to the step grid and clamping to `bounds`.
    static func adjust(_ value: Double, by steps: Int, step: Double, bounds: ClosedRange<Double>) -> Double {
        let snapped = (value / step).rounded() * step
        let moved = snapped + Double(steps) * step
        return min(max(moved, bounds.lowerBound), bounds.upperBound)
    }
}

// MARK: - Controller

@MainActor
@Observable final class Thermostat {
    var apiResponse: Api?

    /// Status returned by the last successful control request; preferred until a
    /// newer `GET /` payload arrives.
    private(set) var latest: IndoorClimateState?
    private var inFlight = 0
    var isSending: Bool { inFlight > 0 }
    var lastError: String?

    // Optimistic values shown while a request is pending.
    private(set) var pendingTarget: Double?
    private(set) var pendingLow: Double?
    private(set) var pendingHigh: Double?
    private(set) var pendingMode: String?
    private(set) var pendingPreset: String?
    private(set) var pendingFan: String?

    @ObservationIgnored private var commitTask: Task<Void, Never>?
    private let setpointDelay: Duration
    private let send: @MainActor (ThermostatCommand) async throws -> IndoorClimateState?
    private let refresh: @MainActor () -> Void

    init(
        apiResponse: Api? = nil,
        setpointDelay: Duration = .milliseconds(1200),
        send: @escaping @MainActor (ThermostatCommand) async throws -> IndoorClimateState? = {
            try await FluxIntentActions.controlThermostat($0)
        },
        refresh: @escaping @MainActor () -> Void = { queryFlux(password: WhereWeAre.getPassword() ?? "") }
    ) {
        self.apiResponse = apiResponse
        self.setpointDelay = setpointDelay
        self.send = send
        self.refresh = refresh
    }

    var state: IndoorClimateState? {
        let polled = apiResponse?.response?.indoorClimate
        guard let latest else { return polled }
        guard let polled else { return latest }
        // ISO-8601 timestamps from the same server sort lexically.
        return (polled.timestamp ?? "") > (latest.timestamp ?? "") ? polled : latest
    }

    var status: ThermostatStatus? { state?.thermostat }
    var isFahrenheit: Bool { state?.isFahrenheit ?? false }
    var canControl: Bool { status != nil && status?.available != false }

    var mode: String? { pendingMode ?? status?.hvacMode }
    var preset: String? { pendingPreset ?? status?.presetMode }
    var fan: String? { pendingFan ?? status?.fanMode }
    var isAutoMode: Bool { ["heat_cool", "auto"].contains(mode?.lowercased() ?? "") }

    var target: Double? { pendingTarget ?? status?.targetTemperature }
    var targetLow: Double? { pendingLow ?? status?.targetTemperatureLow }
    var targetHigh: Double? { pendingHigh ?? status?.targetTemperatureHigh }

    var modes: [String] {
        let reported = status?.hvacModes ?? []
        return ThermostatLabels.ordered(reported.isEmpty ? ThermostatLabels.defaultModes : reported)
    }

    var presets: [String] { status?.presetModes ?? [] }
    var fanModes: [String] { status?.fanModes ?? [] }

    private var step: Double {
        guard let status else { return isFahrenheit ? 1 : 0.5 }
        return ThermostatSetpoint.step(for: status, fahrenheit: isFahrenheit)
    }

    private var bounds: ClosedRange<Double> {
        guard let status else { return isFahrenheit ? 45...92 : 7...33 }
        return ThermostatSetpoint.bounds(for: status, fahrenheit: isFahrenheit)
    }

    // MARK: Setpoints (debounced so repeated taps send one request)

    func nudgeTarget(by steps: Int) {
        guard canControl, let current = target else { return }
        pendingTarget = ThermostatSetpoint.adjust(current, by: steps, step: step, bounds: bounds)
        scheduleSetpointCommit()
    }

    func nudgeLow(by steps: Int) {
        guard canControl, let low = targetLow, let high = targetHigh else { return }
        let ceiling = max(bounds.lowerBound, high - step)
        pendingLow = ThermostatSetpoint.adjust(low, by: steps, step: step, bounds: bounds.lowerBound...ceiling)
        pendingHigh = high
        scheduleSetpointCommit()
    }

    func nudgeHigh(by steps: Int) {
        guard canControl, let low = targetLow, let high = targetHigh else { return }
        let floor = min(bounds.upperBound, low + step)
        pendingHigh = ThermostatSetpoint.adjust(high, by: steps, step: step, bounds: floor...bounds.upperBound)
        pendingLow = low
        scheduleSetpointCommit()
    }

    private func scheduleSetpointCommit() {
        commitTask?.cancel()
        let delay = setpointDelay
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sendPendingSetpoint()
        }
    }

    /// Sends any pending setpoint immediately (e.g. when the view disappears).
    func commitSetpoint() async {
        commitTask?.cancel()
        await sendPendingSetpoint()
    }

    private func sendPendingSetpoint() async {
        commitTask = nil
        if let low = pendingLow, let high = pendingHigh {
            await perform(.setRange(low: low, high: high))
        } else if let target = pendingTarget {
            await perform(.setTemperature(target))
        }
    }

    // MARK: Modes

    func setMode(_ mode: String) async {
        guard canControl, mode != self.mode else { return }
        // Setpoints only make sense for the mode they were chosen in.
        await commitSetpoint()
        pendingMode = mode
        await perform(.setMode(mode))
    }

    func setPreset(_ preset: String) async {
        guard canControl, preset != self.preset else { return }
        pendingPreset = preset
        await perform(.setPreset(preset))
    }

    func setFan(_ fan: String) async {
        guard canControl, fan != self.fan else { return }
        pendingFan = fan
        await perform(.setFan(fan))
    }

    func resumeSchedule() async {
        guard canControl else { return }
        await perform(.resumeSchedule)
    }

    // MARK: Sending

    private func perform(_ command: ThermostatCommand) async {
        inFlight += 1
        lastError = nil
        defer {
            inFlight -= 1
            clearPending(sentBy: command)
        }
        do {
            if let updated = try await send(command) {
                latest = updated
            }
            refresh()
        } catch {
            logger.error("Thermostat command \(command.path) failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Clears only the optimistic values this command carried, so a newer edit made
    /// while the request was in flight stays pending.
    private func clearPending(sentBy command: ThermostatCommand) {
        switch command {
        case .setTemperature(let value):
            pendingTarget = Self.cleared(pendingTarget, sent: value)
        case let .setRange(low, high):
            guard pendingLow == low, pendingHigh == high else { return }
            pendingLow = nil
            pendingHigh = nil
        case .setMode(let mode):
            pendingMode = Self.cleared(pendingMode, sent: mode)
        case .setPreset(let preset):
            pendingPreset = Self.cleared(pendingPreset, sent: preset)
        case .setFan(let fan):
            pendingFan = Self.cleared(pendingFan, sent: fan)
        case .resumeSchedule:
            break
        }
    }

    private static func cleared<Value: Equatable>(_ pending: Value?, sent: Value) -> Value? {
        pending == sent ? nil : pending
    }
}
