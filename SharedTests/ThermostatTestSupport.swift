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
    /// Someone waiting for a request to be sent or held; resumed as soon as it is.
    private struct Waiter {
        let id: Int
        let isMet: () -> Bool
        let resume: CheckedContinuation<Void, Never>
    }
    private var waiters: [Waiter] = []
    private var waits = 0
    /// Every suite using a recorder runs under a five-minute `timeLimit`, which cancels the waits.
    /// A held request is released after longer than that, so a test that forgets to release one
    /// fails instead of hanging the whole run, without racing a slow but passing test. Keep this
    /// longer than every such suite's time limit.
    static let releaseHeldAfter: Duration = .seconds(6 * 60)

    func makeThermostat(delay: Duration = .seconds(60)) -> Thermostat {
        let session = self.session
        return Thermostat(
            apiResponse: MockData.createApi(),
            setpointDelay: delay,
            isSessionValid: { session.isCurrent },
            send: { [unowned self] command, isStillValid in
                self.sent.append(command)
                self.sessionChecks.append(isStillValid)
                self.wakeWaiters()
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
            wakeWaiters()
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: Self.releaseHeldAfter)
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

    // The wait helpers have no deadline of their own: they return only once the request
    // arrives or the waiting task is cancelled. Call them only from a suite with a
    // `.timeLimit`, and keep `releaseHeldAfter` longer than that limit.

    /// Waits for the request to be sent and held; use it before expecting a request was sent.
    /// Only bounded by the calling suite's time limit.
    func waitUntilHeld(_ command: ThermostatCommand) async {
        await wait { self.held.contains { $0.command == command } }
    }

    /// Waits for a request to be sent. Only bounded by the calling suite's time limit.
    func waitUntilSent() async {
        await wait { !self.sent.isEmpty }
    }

    /// Returns once `isMet` holds, rechecking whenever a request is sent or held, or when the
    /// waiting task is cancelled (e.g. by the test's time limit).
    private func wait(until isMet: @escaping () -> Bool) async {
        guard !isMet() else { return }
        waits += 1
        let id = waits
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !isMet(), !Task.isCancelled else { return continuation.resume() }
                waiters.append(Waiter(id: id, isMet: isMet, resume: continuation))
            }
        } onCancel: {
            Task { @MainActor in self.stopWaiting(id) }
        }
    }

    private func wakeWaiters() {
        for waiter in waiters where waiter.isMet() { stopWaiting(waiter.id) }
    }

    private func stopWaiting(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).resume.resume()
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
