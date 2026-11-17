//
//  ThermostatTestSupport.swift
//  FluxHaus Tests
//
//  Stand-ins for the session and the server used by the thermostat controller tests.
//

import Testing
import Foundation
@testable import FluxHaus

/// Stands in for the signed-in session; tests flip it to simulate another account signing in.
final class SessionStub: @unchecked Sendable {
    private let lock = NSLock()
    private var current = true

    var isCurrent: Bool {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

@MainActor
final class CommandRecorder {
    var sent: [ThermostatCommand] = []
    var refreshes = 0
    var reply: (ThermostatCommand) throws -> IndoorClimateState? = { _ in nil }
    /// When set, each request stays in flight until `release(_:)` is called for it.
    var holdsRequests = false
    let session = SessionStub()
    /// The session check handed to the sender with each request.
    private(set) var sessionChecks: [@Sendable () -> Bool] = []
    private struct Held {
        let id: Int
        let command: ThermostatCommand
        let resume: CheckedContinuation<Void, Never>
    }
    private var held: [Held] = []
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var holds = 0
    /// How long to wait for a request to be sent before recording an issue. Generous, since CI
    /// machines can be slow; a held request is released after twice this, so a mistake fails
    /// its test instead of hanging the whole run.
    static let patience: Duration = .seconds(60)

    func makeThermostat(delay: Duration = .seconds(60)) -> Thermostat {
        let session = self.session
        return Thermostat(
            apiResponse: MockData.createApi(),
            setpointDelay: delay,
            isSessionValid: { session.isCurrent },
            send: { [unowned self] command, isStillValid in
                self.sent.append(command)
                self.sessionChecks.append(isStillValid)
                if self.holdsRequests { await self.hold(command) }
                // Like the real sender: checked right before credentials would be attached.
                guard isStillValid() else { throw IntentError.notSignedIn }
                return try self.reply(command)
            },
            refresh: { [unowned self] in self.refreshes += 1 }
        )
    }

    private func hold(_ command: ThermostatCommand) async {
        holds += 1
        let id = holds
        await withCheckedContinuation { continuation in
            held.append(Held(id: id, command: command, resume: continuation))
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: Self.patience * 2)
                guard !Task.isCancelled, let self else { return }
                Issue.record("\(command) was never released")
                self.resume(id)
            }
        }
    }

    private func resume(_ id: Int) {
        timeouts.removeValue(forKey: id)?.cancel()
        guard let index = held.firstIndex(where: { $0.id == id }) else { return }
        held.remove(at: index).resume.resume()
    }

    /// Waits for the request to be sent and held; use it before expecting a request was sent.
    func waitUntilHeld(_ command: ThermostatCommand) async {
        let deadline = ContinuousClock.now + Self.patience
        while !held.contains(where: { $0.command == command }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func waitUntilSent() async {
        let deadline = ContinuousClock.now + Self.patience
        while sent.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func release(_ command: ThermostatCommand) async {
        await waitUntilHeld(command)
        guard let hold = held.first(where: { $0.command == command }) else {
            Issue.record("\(command) was never sent")
            return
        }
        resume(hold.id)
    }

    /// Gives queued work a chance to run until nothing more is sent, then reports what has been sent.
    /// It can't tell a slow request from none, so wait for an expected request first.
    func settledSends() async -> [ThermostatCommand] {
        var count: Int
        repeat {
            count = sent.count
            try? await Task.sleep(for: .milliseconds(30))
        } while sent.count != count
        return sent
    }
}

struct SendFailure: LocalizedError {
    var errorDescription: String? { "Thermostat unavailable" }
}

/// A thermostat in `mode` (Auto unless given) reported at `timestamp`.
func autoState(
    low: Double, high: Double, target: Double? = nil, confirmed: Bool? = nil,
    mode: String = "heat_cool", at timestamp: String = "2099-01-01T00:00:00Z"
) -> IndoorClimateState {
    IndoorClimateState(
        timestamp: timestamp,
        unit: "°C",
        thermostat: ThermostatStatus(
            entityId: "climate.home", hvacMode: mode, targetTemperature: target,
            targetTemperatureLow: low, targetTemperatureHigh: high, targetTempStep: 0.5
        ),
        sensors: [],
        confirmed: confirmed
    )
}
