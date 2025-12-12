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
            let step = tAppliance[index].step
            let programName = tAppliance[index].programName.trimmingCharacters(in: NSCharacterSet.whitespaces)
            return "\(step) (\(programName))"
        } else if tAppliance.count > index {
            return "\(tAppliance[index].step)"
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
            text = "Started \(getCarTime(strDate: robots.mopBot.timeStarted!)) "
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
            text = "Started \(getCarTime(strDate: robots.broomBot.timeStarted!)) "
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
        if tAppliance[index].timeRemaining > 60 {
            return tAppliance[index].timeFinish
        }
        return "\(tAppliance[index].timeRemaining)m"
    }

    func getTimeRemaining(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            if robots.mopBot.running != nil && (robots.mopBot.running == true || robots.mopBot.paused == true) {
                return "On"
            } else if robots.mopBot.running != nil && robots.mopBot.running == false {
                return "Off"
            } else {
                return "Lost"
            }
        } else if type == "BroomBot" {
            if robots.broomBot.running != nil && (robots.broomBot.running == true || robots.broomBot.paused == true) {
                return "On"
            } else if robots.broomBot.running != nil && robots.broomBot.running == false {
                return "Off"
            } else {
                return "Lost"
            }
        } else if type == "Battery" {
            return "\(battery.percent)%"
        } else if type == "Car" {
            return "\(car.vehicle.batteryLevel)%"
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            return tApplianceTimeRemaining(tAppliance: tAppliance, index: index)
        }
        return ""
    }
}
