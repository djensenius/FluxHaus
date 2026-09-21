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
        let binStatus = robot.binFull == true ? " Its bin is full." : ""
        if let battery = robot.batteryLevel {
            return "\(name) is \(state) at \(battery)%.\(binStatus)"
        }
        return "\(name) is \(state).\(binStatus)"
    }

    static func dishwasher(_ response: LoginResponse, now: Date = Date()) -> String {
        guard let dishwasher = response.dishwasher else {
            return "Dishwasher status isn't available right now."
        }
        if dishwasher.operationState == .finished {
            return "The dishwasher is finished."
        }
        if dishwasher.operationState == .inactive {
            return "The dishwasher is not running."
        }

        var summary = "The dishwasher is \(dishwasher.operationState.displayText.lowercased())"
        if let program = dishwasher.activeProgram?.displayName
            ?? dishwasher.selectedProgram.map(formatApplianceDisplayText),
           !program.isEmpty {
            summary += " on the \(program) program"
        }
        summary += "."

        if let remaining = dishwasher.remainingTime, remaining > 0 {
            let minutes = durationInMinutes(value: remaining, unit: dishwasher.remainingTimeUnit)
            summary += " \(completionText(minutes: minutes, now: now))"
        }
        return summary
    }

    static func washer(_ response: LoginResponse, now: Date = Date()) -> String {
        appliance(response.washer, name: "washing machine", now: now)
    }

    static func dryer(_ response: LoginResponse, now: Date = Date()) -> String {
        appliance(response.dryer, name: "dryer", now: now)
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

    static func airPurifier(_ response: LoginResponse) -> String {
        guard let purifier = response.airPurifier else {
            return "Air purifier status isn't available right now."
        }
        guard purifier.online else {
            return "The air purifier is offline."
        }

        var sentences = [
            "The air purifier is online and the fan is \(purifier.fanOn ? "on" : "off")."
        ]
        if let mode = purifier.presetMode, !mode.isEmpty {
            sentences.append("It is in \(formatApplianceDisplayText(mode)) mode.")
        }
        if let particulate = purifier.pm25 {
            sentences.append("PM2.5 is \(Int(particulate.rounded())) micrograms per cubic meter.")
        }
        if let filterLife = purifier.filterLife {
            sentences.append("Filter life is \(Int(filterLife.rounded())) percent.")
        }
        return sentences.joined(separator: " ")
    }

    private static func appliance(
        _ appliance: WasherDryer?,
        name: String,
        now: Date
    ) -> String {
        guard let appliance else {
            return "\(name.capitalized) status isn't available right now."
        }
        if !appliance.inUse {
            if appliance.status?.localizedCaseInsensitiveContains("finished") == true {
                return "The \(name) is finished."
            }
            return "The \(name) is not running."
        }

        let state = appliance.status.map(formatApplianceDisplayText) ?? "Running"
        var summary = "The \(name) is \(state.lowercased())"
        if let program = appliance.programName.map(formatApplianceDisplayText), !program.isEmpty {
            summary += " on the \(program) program"
        }
        summary += "."

        if let step = appliance.step.map(formatApplianceDisplayText), !step.isEmpty {
            summary += " The current step is \(step)."
        }
        if let remaining = appliance.timeRemaining, remaining > 0 {
            summary += " \(completionText(minutes: remaining, now: now))"
        }
        return summary
    }

    private static func durationInMinutes(value: Int, unit: String?) -> Int {
        switch unit?.lowercased() {
        case "sec", "second", "seconds":
            return max(1, Int(ceil(Double(value) / 60)))
        case "hour", "hours", "hr", "hrs":
            return value * 60
        default:
            return value
        }
    }

    private static func completionText(minutes: Int, now: Date) -> String {
        let finishDate = now.addingTimeInterval(Double(minutes) * 60)
        let finishTime = finishDate.formatted(date: .omitted, time: .shortened)
        return "It has about \(formatDurationMinutes(minutes)) remaining and should finish around \(finishTime)."
    }
}
