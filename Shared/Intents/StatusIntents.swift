//
//  StatusIntents.swift
//  FluxHaus
//
//  App Intents that report the current status of FluxHaus devices.
//

import AppIntents

private func fetchStatus() async throws -> LoginResponse {
    guard AuthManager.shared.isSignedIn else {
        throw IntentError.notSignedIn
    }
    guard await AuthManager.shared.ensureValidToken(),
          AuthManager.shared.authorizationHeader() != nil else {
        throw IntentError.notSignedIn
    }
    guard let response = try await getFlux(password: "") else {
        throw IntentError.requestFailed(-1)
    }
    return response
}

struct CarStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Car Status"
    static let description = IntentDescription("Get the FluxHaus car's battery, range, and lock status.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        guard let car = response.car, let evStatus = response.carEvStatus else {
            return .result(dialog: "Car status isn't available right now.")
        }
        let range = evStatus.drvDistance.first?.rangeByFuel.evModeRange.value ?? 0
        let locked = car.doorLock ? "locked" : "unlocked"
        let climate = car.airCtrlOn ? " Climate control is on." : ""
        return .result(dialog: """
        The car is at \(evStatus.batteryStatus)% with about \(Int(range)) km of range, and it's \(locked).\(climate)
        """)
    }
}

struct RobotStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Robot Status"
    static let description = IntentDescription("Get the status of the FluxHaus cleaning robots.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        return .result(dialog: "\(describe(response.broombot)) \(describe(response.mopbot))")
    }

    private func describe(_ robot: Robot) -> String {
        let name = robot.name ?? "Robot"
        let state: String
        if robot.running == true {
            state = "running"
        } else if robot.docking == true || robot.charging == true {
            state = "charging at the dock"
        } else if robot.paused == true {
            state = "paused"
        } else {
            state = "idle"
        }
        if let battery = robot.batteryLevel {
            return "\(name) is \(state) at \(battery)%."
        }
        return "\(name) is \(state)."
    }
}

struct ApplianceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Dishwasher Status"
    static let description = IntentDescription("Get the status of the FluxHaus dishwasher.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        guard let dishwasher = response.dishwasher else {
            return .result(dialog: "Dishwasher status isn't available right now.")
        }
        let state = dishwasher.operationState.rawValue
        if state == "Inactive" || state == "Finished" {
            return .result(dialog: "The dishwasher is not running.")
        }
        if let remaining = dishwasher.remainingTime, remaining > 0 {
            let minutes = remaining / 60
            return .result(dialog: "The dishwasher is \(state) with about \(minutes) minutes remaining.")
        }
        return .result(dialog: "The dishwasher is \(state).")
    }
}

struct ScooterStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Scooter Status"
    static let description = IntentDescription("Get the FluxHaus scooter's battery and range.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        guard let scooter = response.scooter else {
            return .result(dialog: "Scooter status isn't available right now.")
        }
        var parts: [String] = []
        if let battery = scooter.battery {
            parts.append("\(battery)% battery")
        }
        if let range = scooter.estimatedRange {
            parts.append("about \(Int(range)) km of range")
        }
        if parts.isEmpty {
            return .result(dialog: "Scooter status isn't available right now.")
        }
        return .result(dialog: "The scooter has \(parts.joined(separator: " and ")).")
    }
}
