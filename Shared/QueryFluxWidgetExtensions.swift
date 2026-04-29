//
//  QueryFluxWidgetExtensions.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

struct WidgetDevice: Codable, Equatable, Hashable {
    var name: String
    var progress: Int
    var icon: String
    var trailingText: String
    var shortText: String
    var running: Bool
    var battery: Int?
    var programName: String?
}

/// Format a time remaining value (in minutes) as a human-readable string.
/// Under 60 minutes: "30m". 60+ minutes: "2h 36m".
func formatTimeRemaining(minutes: Int) -> String {
    if minutes < 60 {
        return "\(minutes)m"
    }
    let finishDate = Date().addingTimeInterval(Double(minutes) * 60)
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: finishDate)
}

/// Format a duration in minutes for display in appliance views.
/// Under 60 minutes: "30 min". 60+ minutes: "2h 36 min".
func formatDurationMinutes(_ minutes: Int) -> String {
    if minutes < 60 {
        return "\(minutes) min"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if remainingMinutes == 0 {
        return "\(hours)h"
    }
    return "\(hours)h \(remainingMinutes) min"
}

// swiftlint:disable:next function_body_length
func convertDataToWidgetDevices(fluxData: FluxData) -> [WidgetDevice] {
    var returnValue: [WidgetDevice] = []

    let dishwasherMinutes = (fluxData.dishwasher?.remainingTime ?? 0) / 60
    let dishWasherReminingTime = formatTimeRemaining(minutes: dishwasherMinutes)
    let dishwasherDisplayName = fluxData.dishwasher?.activeProgram?.displayName
    var dishwasherTrailingText = dishWasherReminingTime
    if let programName = dishwasherDisplayName {
        dishwasherTrailingText = "\(programName) ⋅ \(dishwasherTrailingText)"
    }
    if fluxData.dishwasher != nil && fluxData.dishwasher?.operationState.rawValue != "Run" {
        dishwasherTrailingText = fluxData.dishwasher!.operationState.rawValue + " ⋅ \(dishwasherTrailingText)"
    }

    if fluxData.dishwasher?.operationState.rawValue == "Finished" {
        returnValue.append(
            WidgetDevice(
                name: "Dishwasher",
                progress: 0,
                icon: "dishwasher",
                trailingText: "",
                shortText: "",
                running: false,
                programName: dishwasherDisplayName
            )
        )
    } else {
        returnValue.append(
            WidgetDevice(
                name: "Dishwasher",
                progress: Int(fluxData.dishwasher?.programProgress ?? 0),
                icon: "dishwasher",
                trailingText: dishwasherTrailingText,
                shortText: dishWasherReminingTime,
                running: fluxData.dishwasher?.programProgress ?? 0 > 0,
                programName: dishwasherDisplayName
            )
        )
    }

    let washerTimeRunning = fluxData.washer?.timeRunning ?? 0
    let washerTimeRemaining = fluxData.washer?.timeRemaining ?? 0
    var washerProrgress = 0
    if washerTimeRunning > 0 {
        washerProrgress = Int(Double(washerTimeRunning) / Double(washerTimeRemaining + washerTimeRunning) * 100)
    }

    let washerReminingTime = formatTimeRemaining(minutes: fluxData.washer?.timeRemaining ?? 0)
    var washerTrailingText = washerReminingTime
    if let programName = fluxData.washer?.programName,
       !programName.trimmingCharacters(in: .whitespaces).isEmpty {
        washerTrailingText = "\(formatApplianceProgramName(programName)) ⋅ \(washerTrailingText)"
    }
    if fluxData.washer != nil && fluxData.washer?.status != "In use",
       let status = fluxData.washer?.status {
        washerTrailingText = "\(status) ⋅ \(washerTrailingText)"
    }

    returnValue.append(
        WidgetDevice(
            name: "Washer",
            progress: washerProrgress,
            icon: "washer",
            trailingText: washerTrailingText,
            shortText: washerReminingTime,
            running: fluxData.washer?.timeRemaining ?? 0 > 0,
            programName: fluxData.washer?.programName.map { formatApplianceProgramName($0) }
        )
    )

    let dryerTimeRunning = fluxData.dryer?.timeRunning ?? 0
    let dryerTimeRemaining = fluxData.dryer?.timeRemaining ?? 1
    var dryerProgress = 0
    if dryerTimeRunning  > 0 {
        dryerProgress = Int(Double(dryerTimeRunning) / Double(dryerTimeRemaining + dryerTimeRunning) * 100)
    }
    let dryerReminingTime = formatTimeRemaining(minutes: fluxData.dryer?.timeRemaining ?? 0)
    var dryerTrailingText = dryerReminingTime
    if let programName = fluxData.dryer?.programName,
       !programName.trimmingCharacters(in: .whitespaces).isEmpty {
        dryerTrailingText = "\(formatApplianceProgramName(programName)) ⋅ \(dryerTrailingText)"
    }
    if fluxData.dryer != nil && fluxData.dryer?.status != "In use",
       let status = fluxData.dryer?.status {
        dryerTrailingText = "\(status) ⋅ \(dryerTrailingText)"
    }

    returnValue.append(
        WidgetDevice(
            name: "Dryer",
            progress: dryerProgress,
            icon: "dryer",
            trailingText: dryerTrailingText,
            shortText: dryerReminingTime,
            running: fluxData.dryer?.timeRemaining ?? 0 > 0,
            programName: fluxData.dryer?.programName.map { formatApplianceProgramName($0) }
        )
    )

    returnValue.append(
        WidgetDevice(
            name: "BroomBot",
            progress: fluxData.broomBot?.batteryLevel ?? 0,
            icon: "fan",
            trailingText: fluxData.broomBot?.running ?? false ? "On" : "Off",
            shortText: fluxData.broomBot?.running ?? false ? "On" : "Off",
            running: fluxData.broomBot?.running ?? false,
            battery: fluxData.broomBot?.batteryLevel
        )
    )

    returnValue.append(
        WidgetDevice(
            name: "MopBot",
            progress: fluxData.mopBot?.batteryLevel ?? 0,
            icon: "humidifier.and.droplets",
            trailingText: fluxData.mopBot?.running ?? false ? "On" : "Off",
            shortText: fluxData.mopBot?.running ?? false ? "On" : "Off",
            running: fluxData.mopBot?.running ?? false,
            battery: fluxData.mopBot?.batteryLevel
        )
    )

    if let car = fluxData.car {
        returnValue.append(
            WidgetDevice(
                name: "Car",
                progress: car.batteryLevel,
                icon: "car",
                trailingText: "Range \(car.distance) km ⋅ \(car.batteryLevel)% ",
                shortText: "\(car.distance) km",
                running: false
            )
        )
    }

    return returnValue
}
