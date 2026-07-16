//
//  FluxStatusText.swift
//  FluxHaus
//
//  Shared, side-effect-free helpers that turn a LoginResponse into the spoken
//  status strings used by the status App Intents. Extracted so both the
//  per-device status intents and the generic DeviceStatusIntent can reuse them.
//

import Foundation

enum FluxStatusText {
    static func car(_ response: LoginResponse) -> String {
        guard let car = response.car, let evStatus = response.carEvStatus else {
            return "Car status isn't available right now."
        }
        let range = evStatus.drvDistance.first?.rangeByFuel.evModeRange.value ?? 0
        let locked = car.doorLock ? "locked" : "unlocked"
        let climate = car.airCtrlOn ? " Climate control is on." : ""
        return """
        The car is at \(evStatus.batteryStatus)% with about \(Int(range)) km of range, and it's \(locked).\(climate)
        """
    }

    static func robots(_ response: LoginResponse) -> String {
        "\(robot(response.broombot)) \(robot(response.mopbot))"
    }

    static func robot(_ robot: Robot) -> String {
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

    static func dishwasher(_ response: LoginResponse) -> String {
        guard let dishwasher = response.dishwasher else {
            return "Dishwasher status isn't available right now."
        }
        let state = dishwasher.operationState.rawValue
        if state == "Inactive" || state == "Finished" {
            return "The dishwasher is not running."
        }
        if let remaining = dishwasher.remainingTime, remaining > 0 {
            let minutes = remaining / 60
            return "The dishwasher is \(state) with about \(minutes) minutes remaining."
        }
        return "The dishwasher is \(state)."
    }

    static func scooter(_ response: LoginResponse) -> String {
        guard let scooter = response.scooter else {
            return "Scooter status isn't available right now."
        }
        var parts: [String] = []
        if let battery = scooter.battery {
            parts.append("\(battery)% battery")
        }
        if let range = scooter.estimatedRange {
            parts.append("about \(Int(range)) km of range")
        }
        if parts.isEmpty {
            return "Scooter status isn't available right now."
        }
        return "The scooter has \(parts.joined(separator: " and "))."
    }
}
