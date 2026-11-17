//
//  Thermostat.swift
//  FluxHaus
//
//  Thermostat control: request building, display labels, and an observable
//  controller with optimistic updates for the Climate section.
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

// MARK: - Controller

/// One controller is shared by every Climate screen of a signed-in session, so all
/// changes go through the same queue. It is bound to that session: once another
/// account signs in (or the user signs out), nothing still queued is sent.
@MainActor
@Observable final class Thermostat {
    /// Sends a command. `isStillValid` must be checked right before credentials are
    /// attached so a request never goes out under a different account.
    typealias Sender = @MainActor (
        ThermostatCommand, _ isStillValid: @escaping @Sendable () -> Bool
    ) async throws -> IndoorClimateState?

    var apiResponse: Api?

    /// Status returned by the last successful control request; preferred until a
    /// newer `GET /` payload arrives.
    private(set) var latest: IndoorClimateState?
    /// Commands queued or on the wire.
    private var inFlight = 0
    var isSending: Bool { inFlight > 0 }
    /// The last command's error, else a notice until the newest snapshot shows its change.
    var lastError: String? {
        guard failure == nil, let unreported else { return failure }
        return status?.reports(unreported.command, from: unreported.before) == true ? nil : Self.unconfirmed
    }
    private var failure: String?
    /// The last command and the status it was sent from, if the thermostat hadn't reported
    /// its change when it was accepted.
    private var unreported: (command: ThermostatCommand, before: ThermostatStatus?)?
    /// Set once the session this controller belongs to has ended.
    private(set) var isInvalidated = false

    // Optimistic values shown while a request is pending.
    private(set) var pendingTarget: Double?
    private(set) var pendingLow: Double?
    private(set) var pendingHigh: Double?
    private(set) var pendingMode: String?
    private(set) var pendingPreset: String?
    private(set) var pendingFan: String?

    /// Debounce timer for unsent setpoint edits.
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    /// The kind of setpoint edited since it was last queued. A range still on its way
    /// can outlive a switch to a single-setpoint mode, so the edit decides what is sent.
    @ObservationIgnored private var unsentSetpoint: SetpointKind?
    /// Ties setpoints to the mode switch they were chosen after. It moves on with each switch,
    /// and after a failed one, so edits made once the failure is shown aren't tied to it.
    @ObservationIgnored private var modeGeneration = 0
    /// The most recent mode switch that failed; setpoints chosen for it are dropped.
    @ObservationIgnored private var failedModeGeneration: Int?
    /// Numbers each optimistic edit per field, so a finished request clears a value only
    /// if no newer edit has replaced it, even one that happens to match.
    @ObservationIgnored private var editCount = 0
    @ObservationIgnored private var latestEdits: [PendingField: Int] = [:]
    /// The last queued command. Commands run one at a time in the order the user
    /// made them, so the thermostat ends up in the last state chosen.
    @ObservationIgnored private var queueTail: Task<Void, Never>?
    private let setpointDelay: Duration
    private let isSessionValid: @Sendable () -> Bool
    private let send: Sender
    private let refresh: @MainActor () -> Void

    /// `isSessionValid` defaults to a check bound to the account signed in now.
    init(
        apiResponse: Api? = nil,
        setpointDelay: Duration = .milliseconds(1200),
        isSessionValid: @escaping @Sendable () -> Bool = Thermostat.currentSessionCheck(),
        send: @escaping Sender = { try await FluxIntentActions.controlThermostat($0, isStillValid: $1) },
        refresh: @escaping @MainActor () -> Void = { queryFlux(password: WhereWeAre.getPassword() ?? "") }
    ) {
        self.apiResponse = apiResponse
        self.setpointDelay = setpointDelay
        self.isSessionValid = isSessionValid
        self.send = send
        self.refresh = refresh
    }

    static let unconfirmed = "Sent, but the thermostat hasn't reported the change yet."

    /// True only while the session signed in when this is called is still the current one.
    nonisolated static func currentSessionCheck() -> @Sendable () -> Bool {
        let origin = AuthManager.shared.widgetSessionID()
        return { origin != nil && AuthManager.shared.widgetSessionID() == origin }
    }

    var state: IndoorClimateState? {
        let polled = apiResponse?.response?.indoorClimate
        guard let latest else { return polled }
        guard let polled else { return latest }
        // ISO-8601 timestamps from the same server sort lexically.
        return (polled.timestamp ?? "") > (latest.timestamp ?? "") ? polled : latest
    }

    var status: ThermostatStatus? { state?.thermostat }
    var isFahrenheit: Bool { state?.thermostatUnit.uppercased().contains("F") ?? false }
    var canControl: Bool { !isInvalidated && status != nil && status?.available != false }

    var mode: String? { pendingMode ?? status?.hvacMode }
    var preset: String? { pendingPreset ?? status?.presetMode }
    var fan: String? { pendingFan ?? status?.fanMode }
    /// Separate heat and cool setpoints; the server only accepts a range in `heat_cool`.
    var usesSetpointRange: Bool { mode?.lowercased() == "heat_cool" }

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
        scheduleSetpointCommit(.single)
    }

    func nudgeLow(by steps: Int) {
        guard canControl, let low = targetLow, let high = targetHigh else { return }
        let ceiling = max(bounds.lowerBound, high - step)
        pendingLow = ThermostatSetpoint.adjust(low, by: steps, step: step, bounds: bounds.lowerBound...ceiling)
        pendingHigh = high
        scheduleSetpointCommit(.range)
    }

    func nudgeHigh(by steps: Int) {
        guard canControl, let low = targetLow, let high = targetHigh else { return }
        let floor = min(bounds.upperBound, low + step)
        pendingHigh = ThermostatSetpoint.adjust(high, by: steps, step: step, bounds: floor...bounds.upperBound)
        pendingLow = low
        scheduleSetpointCommit(.range)
    }

    private func scheduleSetpointCommit(_ kind: SetpointKind) {
        edited(kind == .single ? .target : .range)
        unsentSetpoint = kind
        commitTask?.cancel()
        let delay = setpointDelay
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.queueSetpoint()
        }
    }

    /// Queues the unsent setpoint, capturing its current values.
    private func queueSetpoint() {
        commitTask?.cancel()
        commitTask = nil
        guard let kind = unsentSetpoint else { return }
        unsentSetpoint = nil
        switch kind {
        case .range:
            if let low = pendingLow, let high = pendingHigh { enqueue(.setRange(low: low, high: high)) }
        case .single:
            if let target = pendingTarget { enqueue(.setTemperature(target)) }
        }
    }

    /// Sends any unsent setpoint now (e.g. when the view disappears) and waits
    /// for every command queued so far.
    func commitSetpoint() async {
        queueSetpoint()
        await queueTail?.value
    }

    /// Whether a setpoint edit hasn't reached the thermostat yet.
    private var hasSetpointEdit: Bool { pendingTarget != nil || pendingLow != nil || pendingHigh != nil }

    // MARK: Modes

    func setMode(_ mode: String) async {
        guard canControl, mode != self.mode else { return }
        // Edits made so far belong to the current mode, so they go first; edits
        // made after the switch are queued behind it.
        queueSetpoint()
        pendingMode = mode
        edited(.mode)
        await enqueue(.setMode(mode)).value
    }

    func setPreset(_ preset: String) async {
        // A setpoint edit creates a hold, so re-selecting the current preset still applies it.
        guard canControl, preset != self.preset || hasSetpointEdit else { return }
        queueSetpoint()
        pendingPreset = preset
        edited(.preset)
        await enqueue(.setPreset(preset)).value
    }

    func setFan(_ fan: String) async {
        guard canControl, fan != self.fan else { return }
        pendingFan = fan
        edited(.fan)
        await enqueue(.setFan(fan)).value
    }

    func resumeSchedule() async {
        guard canControl else { return }
        // An unsent setpoint would create a new hold right after resuming.
        commitTask?.cancel()
        commitTask = nil
        unsentSetpoint = nil
        pendingTarget = nil
        pendingLow = nil
        pendingHigh = nil
        await enqueue(.resumeSchedule).value
    }

    // MARK: Sending

    @discardableResult
    private func enqueue(_ command: ThermostatCommand) -> Task<Void, Never> {
        if case .setMode = command { modeGeneration += 1 }
        let generation = modeGeneration
        let edit = Self.field(changedBy: command).flatMap { latestEdits[$0] }
        let previous = queueTail
        inFlight += 1
        let request = Task {
            await previous?.value
            await self.perform(command, generation: generation, edit: edit)
            self.inFlight -= 1
        }
        queueTail = request
        return request
    }

    private func perform(_ command: ThermostatCommand, generation: Int, edit: Int?) async {
        // Checked before every command, so nothing queued under a previous account is sent.
        guard isSessionCurrent() else { return }
        if command.isSetpoint, generation == failedModeGeneration {
            // Chosen for a mode the thermostat didn't switch to; that error stays shown.
            clearPending(sentBy: command, edit: edit)
            return
        }
        failure = nil
        unreported = nil
        defer { clearPending(sentBy: command, edit: edit) }
        let before = status
        do {
            let updated = try await send(command, isSessionValid)
            guard isSessionCurrent() else { return }
            // A poll can land between commands; keep the newest snapshot.
            if let updated, Self.isNewer(updated, than: latest) {
                latest = updated
            }
            // Resuming a schedule that matches the hold changes nothing the thermostat can report.
            if updated?.confirmed == false, command != .resumeSchedule { unreported = (command, before) }
            refresh()
        } catch {
            // A request refused because the account changed isn't the new account's error.
            guard isSessionCurrent() else { return }
            // Server-supplied error text stays out of device logs; it's only shown in the UI.
            let kind = String(reflecting: type(of: error))
            logger.error("Thermostat command \(command.path, privacy: .public) failed: \(kind, privacy: .public)")
            failure = error.localizedDescription
            if case .setMode = command { dropSetpoints(chosenFor: generation) }
        }
    }

    /// After a mode switch fails, drops the setpoints chosen for that mode: queued ones are
    /// skipped, and an unsent one is discarded unless another mode was chosen since.
    private func dropSetpoints(chosenFor generation: Int) {
        failedModeGeneration = generation
        guard generation == modeGeneration else { return }
        modeGeneration += 1
        commitTask?.cancel()
        commitTask = nil
        switch unsentSetpoint {
        case .single:
            pendingTarget = nil
        case .range:
            pendingLow = nil
            pendingHigh = nil
        case nil:
            break
        }
        unsentSetpoint = nil
    }

    /// The controller to use after a data refresh. Polls arrive every few seconds, so the
    /// existing one is kept while its session is signed in; replacing it would drop queued
    /// and debounced changes.
    static func forCurrentSession(reusing existing: Thermostat?, apiResponse: Api) -> Thermostat {
        if let existing, existing.isSessionCurrent() {
            existing.apiResponse = apiResponse
            return existing
        }
        return Thermostat(apiResponse: apiResponse)
    }

    /// Whether commands may still be sent; invalidates the controller once its session has ended.
    func isSessionCurrent() -> Bool {
        if !isInvalidated, !isSessionValid() {
            logger.info("Signed-in session changed; discarding queued thermostat commands")
            invalidate()
        }
        return !isInvalidated
    }

    /// Ends this controller's session: cancels the debounced setpoint, discards every
    /// queued command without sending it, and clears what was shown for that account.
    func invalidate() {
        isInvalidated = true
        commitTask?.cancel()
        commitTask = nil
        unsentSetpoint = nil
        pendingTarget = nil
        pendingLow = nil
        pendingHigh = nil
        pendingMode = nil
        pendingPreset = nil
        pendingFan = nil
        latest = nil
        failure = nil
        unreported = nil
    }

    private func edited(_ field: PendingField) {
        editCount += 1
        latestEdits[field] = editCount
    }

    /// Clears the optimistic value this command carried, unless a newer edit (queued or
    /// still unsent) has replaced it since the command was queued.
    private func clearPending(sentBy command: ThermostatCommand, edit: Int?) {
        guard let field = Self.field(changedBy: command), let edit, latestEdits[field] == edit else { return }
        switch field {
        case .target:
            pendingTarget = nil
        case .range:
            pendingLow = nil
            pendingHigh = nil
        case .mode:
            pendingMode = nil
        case .preset:
            pendingPreset = nil
        case .fan:
            pendingFan = nil
        }
    }

    private static func field(changedBy command: ThermostatCommand) -> PendingField? {
        switch command {
        case .setTemperature: return .target
        case .setRange: return .range
        case .setMode: return .mode
        case .setPreset: return .preset
        case .setFan: return .fan
        case .resumeSchedule: return nil
        }
    }

    private static func isNewer(_ candidate: IndoorClimateState, than current: IndoorClimateState?) -> Bool {
        guard let current else { return true }
        // ISO-8601 timestamps from the same server sort lexically.
        return (candidate.timestamp ?? "") >= (current.timestamp ?? "")
    }

    private enum SetpointKind { case single, range }
    private enum PendingField { case target, range, mode, preset, fan }
}
