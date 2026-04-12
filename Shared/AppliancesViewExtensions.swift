//
//  AppliancesViewExtensions.swift
//  FluxHaus
//
//  Created by Copilot on 2025-12-11.
//

import SwiftUI

extension Appliances {
    func getIconColor(type: String, index: Int) -> Color {
        switch type {
        case "Miele":
            return getApplianceIconColor(appliances: miele.appliances, index: index)
        case "MopBot":
            return getRobotIconColor(robot: robots.mopBot)
        case "BroomBot":
            return getRobotIconColor(robot: robots.broomBot)
        case "Battery":
            return getBatteryIconColor()
        case "Car":
            return getCarIconColor()
        case "Scooter":
            return getScooterIconColor()
        default: // HomeConnect
            return getApplianceIconColor(appliances: hconn.appliances, index: index)
        }
    }

    private func getRobotIconColor(robot: Robot) -> Color {
        if robot.running == true {
            return Theme.Colors.accent
        } else if robot.charging == true {
            return Theme.Colors.success
        } else if robot.binFull == true {
            return Theme.Colors.error
        }
        return Theme.Colors.textSecondary
    }

    private func getBatteryIconColor() -> Color {
        if battery.state == .charging || battery.state == .full {
            return Theme.Colors.success
        } else if battery.percent <= 20 {
            return Theme.Colors.error
        }
        return Theme.Colors.textSecondary
    }

    private func getCarIconColor() -> Color {
        if car.vehicle.pluggedIn || car.vehicle.batteryCharge {
            return Theme.Colors.success
        } else if car.vehicle.hvac || car.vehicle.engine {
            return Theme.Colors.accent
        }
        return Theme.Colors.textSecondary
    }

    private func getScooterIconColor() -> Color {
        return Theme.Colors.textSecondary
    }

    private func getApplianceIconColor(appliances: [Appliance], index: Int) -> Color {
        if appliances.count > index {
            if appliances[index].inUse {
                return Theme.Colors.accent
            } else if appliances[index].timeRemaining == 0 && appliances[index].programName != "" {
                return Theme.Colors.success
            }
        }
        return Theme.Colors.textSecondary
    }

    func getIcon(type: String, index: Int) -> Image {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            return Image(systemName: "humidifier.and.droplets")
        } else if type == "BroomBot" {
            return Image(systemName: "fan")
        } else if type == "Battery" {
            return getDeviceIcon(battery: battery)
        } else if type == "Car" {
            return Image(systemName: "car")
        } else if type == "Scooter" {
            return Image(systemName: "scooter")
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            var emoji = Image(systemName: "dryer")
            if tAppliance[index].name == "Washing machine" {
                emoji = Image(systemName: "washer")
            } else if tAppliance[index].name == "Dishwasher" {
                emoji = Image(systemName: "dishwasher")
            }
            return emoji
        }
        return Image(systemName: "network")
    }

    func getApplianceName(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            return "MopBot"
        } else if type == "BroomBot" {
            return "BroomBot"
        } else if type == "Battery" {
            if battery.model == .iPad {
                return "iPad"
            } else if battery.model == .mac {
                return "Computer"
            } else if battery.model == .visionPro {
                return "Vision Pro"
            } else {
                return "Phone"
            }
        } else if type == "Car" {
            return "Car"
        } else if type == "Scooter" {
            return "GT3 Pro"
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            let text = "\(tAppliance[index].name)"
            return text
        }
        return "Fetching"
    }

    func tApplianceValue(tAppliance: [Appliance], index: Int) -> String {
        if tAppliance[index].inUse == false {
            return ""
        }
        if tAppliance.count > index && tAppliance[index].programName != "" {
            let step = formatApplianceProgramName(tAppliance[index].step)
            let programName = formatApplianceProgramName(tAppliance[index].programName)
            if step.isEmpty {
                return programName
            }
            return "\(step) (\(programName))"
        } else if tAppliance.count > index {
            return formatApplianceProgramName(tAppliance[index].step)
        }
        return ""
    }

    func getProgram(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
           return getMopBotText()
        } else if type == "BroomBot" {
           return getBroomBotText()
        } else if type == "Battery" {
            if battery.state == .charging {
                return "Charging"
            } else if battery.state == .unknown {
                return "Battery state unknown"
            }
            return ""
        } else if type == "Car" {
            return carDetails(car: car)
        } else if type == "Scooter" {
            return scooterDetails()
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            return tApplianceValue(tAppliance: tAppliance, index: index)
        }
        return ""
    }

    func getMopBotText() -> String {
        var text = ""
        if robots.mopBot.running == true && robots.mopBot.timeStarted != nil {
            text = "Started at \(clockTimeString(from: robots.mopBot.timeStarted!)) "
        }
        if robots.mopBot.batteryLevel != nil && robots.mopBot.batteryLevel! < 100 {
            text += robots.mopBot.charging! ?
                "Charging (\(robots.mopBot.batteryLevel!)%)" : "Battery (\(robots.mopBot.batteryLevel!)%)"
        }
        return text
    }

    func getBroomBotText() -> String {
        var text = ""
        if robots.broomBot.running == true && robots.broomBot.timeStarted != nil {
            text = "Started at \(clockTimeString(from: robots.broomBot.timeStarted!)) "
        }
        if robots.broomBot.batteryLevel != nil && robots.broomBot.batteryLevel! < 100 {
            text += robots.broomBot.charging! ?
                "Charging (\(robots.broomBot.batteryLevel!)%)" : "Battery (\(robots.broomBot.batteryLevel!)%)"
        }
        return text
    }

    func tApplianceTimeRemaining(tAppliance: [Appliance], index: Int) -> String {
        if tAppliance.count == 0 { return "" }
        if tAppliance[index].inUse == false {
            return "Off"
        }
        return formatTimeRemaining(minutes: tAppliance[index].timeRemaining)
    }

    func getTimeRemaining(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            return robotStatus(robots.mopBot)
        } else if type == "BroomBot" {
            return robotStatus(robots.broomBot)
        } else if type == "Battery" {
            return "\(battery.percent)%"
        } else if type == "Car" {
            return "\(car.vehicle.batteryLevel)%"
        } else if type == "Scooter" {
            if let battery = apiResponse.response?.scooter?.battery {
                return "\(battery)%"
            }
            return "—"
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            return tApplianceTimeRemaining(tAppliance: tAppliance, index: index)
        }
        return ""
    }

    private func robotStatus(_ robot: Robot) -> String {
        if robot.running == true || robot.paused == true {
            return "On"
        } else if robot.running == false {
            return "Off"
        }
        return "Lost"
    }

    private func scooterDetails() -> String {
        guard let scooter = apiResponse.response?.scooter else { return "" }
        var text = ""
        if let range = scooter.estimatedRange {
            text += "Range \(String(format: "%.0f", range)) km"
        }
        if let timestamp = scooter.timestamp {
            if !text.isEmpty { text += " | " }
            text += "Updated \(relativeTimeString(from: timestamp))"
        }
        return text
    }
}
