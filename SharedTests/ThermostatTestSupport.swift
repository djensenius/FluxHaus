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
    private var held: [(command: ThermostatCommand, resume: CheckedContinuation<Void, Never>)] = []

    func makeThermostat(delay: Duration = .seconds(60)) -> Thermostat {
        let session = self.session
        return Thermostat(
            apiResponse: MockData.createApi(),
            setpointDelay: delay,
            isSessionValid: { session.isCurrent },
            send: { [unowned self] command, isStillValid in
                self.sent.append(command)
                self.sessionChecks.append(isStillValid)
                if self.holdsRequests {
                    await withCheckedContinuation { self.held.append((command, $0)) }
                }
                // Like the real sender: checked right before credentials would be attached.
                guard isStillValid() else { throw IntentError.notSignedIn }
                return try self.reply(command)
            },
            refresh: { [unowned self] in self.refreshes += 1 }
        )
    }

    func waitUntilHeld(_ command: ThermostatCommand) async {
        for _ in 0..<200 where !held.contains(where: { $0.command == command }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release(_ command: ThermostatCommand) async {
        await waitUntilHeld(command)
        guard let index = held.firstIndex(where: { $0.command == command }) else {
            Issue.record("\(command) was never sent")
            return
        }
        held.remove(at: index).resume.resume()
    }

    /// Gives queued work a chance to run, then reports what has been sent.
    func settledSends() async -> [ThermostatCommand] {
        try? await Task.sleep(for: .milliseconds(30))
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
