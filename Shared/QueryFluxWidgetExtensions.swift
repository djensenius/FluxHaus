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
    /// UNIX epoch seconds when the current cycle started (optional, sent by newer servers).
    var startedAt: Double?
    /// UNIX epoch seconds when the current cycle is expected to finish.
    var endsAt: Double?

    var startDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0) } }
    var endDate: Date? { endsAt.map { Date(timeIntervalSince1970: $0) } }

    /// A live interval for `Text(timerInterval:)` / `ProgressView(timerInterval:)`, if the
    /// cycle is running and its end is still in the future.
    func timerInterval(now: Date = Date()) -> ClosedRange<Date>? {
        guard running, let end = endDate, end > now else { return nil }
        let start = min(startDate ?? now, now)
        return start...end
    }

    // Timing fields are derived from "now" on every fetch; exclude them from equality so
    // change detection (widget reloads, Live Activity updates) only reacts to real changes.
    static func == (lhs: WidgetDevice, rhs: WidgetDevice) -> Bool {
        lhs.name == rhs.name && lhs.progress == rhs.progress && lhs.icon == rhs.icon
            && lhs.trailingText == rhs.trailingText && lhs.shortText == rhs.shortText
            && lhs.running == rhs.running && lhs.battery == rhs.battery
            && lhs.programName == rhs.programName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(progress)
        hasher.combine(shortText)
        hasher.combine(running)
    }
}

/// Miele statuses during which the remaining time actually ticks down.
func isCountingStatus(_ status: String?) -> Bool {
    guard let status = status?.lowercased(), !status.isEmpty else { return true }
    return status == "in use" || status == "running" || status == "in_use"
}

/// Remaining-time sensors can retain their last value after a cycle ends.
/// Match the server's inactive statuses so foreground refreshes cannot resurrect it.
func isMieleCycleActive(status: String?, remainingMinutes: Int) -> Bool {
    let normalized = status?.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased().replacingOccurrences(of: "_", with: " ") ?? ""
    let inactive = [
        "off", "not connected", "on", "idle", "end programmed", "program ended",
        "finished", "programmed", "waiting to start", "delayed start"
    ]
    return remainingMinutes > 0 && !inactive.contains(normalized)
}

/// Start/end epoch seconds for a running cycle from elapsed/remaining seconds.
func cycleTiming(
    elapsedSeconds: Double?,
    remainingSeconds: Double?,
    now: Date = Date()
) -> (startedAt: Double?, endsAt: Double?) {
    let nowSeconds = now.timeIntervalSince1970
    let endsAt = remainingSeconds.flatMap { $0 > 0 ? (nowSeconds + $0).rounded() : nil }
    // Zero elapsed is a valid start (just started); only negative values are rejected.
    let startedAt = elapsedSeconds.flatMap { $0 >= 0 ? (nowSeconds - $0).rounded() : nil }
    return (startedAt, endsAt)
}

/// Format a time remaining value (in minutes) as a human-readable finish time.
/// Under 60 minutes: "30m". 60+ minutes: "2:36 PM" (localized clock time).
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
    let dishwasherRemainingTime = formatTimeRemaining(minutes: dishwasherMinutes)
    let dishwasherDisplayName = fluxData.dishwasher?.activeProgram?.displayName
    var dishwasherTrailingText = dishwasherRemainingTime
    if let programName = dishwasherDisplayName {
        dishwasherTrailingText = "\(programName) ⋅ \(dishwasherTrailingText)"
    }
    if fluxData.dishwasher != nil && fluxData.dishwasher?.operationState.rawValue != "Run" {
        dishwasherTrailingText = fluxData.dishwasher!.operationState.displayText
            + " ⋅ \(dishwasherTrailingText)"
    }

    let dishwasherProgress = fluxData.dishwasher?.programProgress ?? 0
    let dishwasherRunning = ["Run", "Pause", "ActionRequired", "Error", "Aborting"]
        .contains(fluxData.dishwasher?.operationState.rawValue ?? "")
    // Only count down while actually running (not paused / delayed).
    let dishwasherCounting = dishwasherRunning && fluxData.dishwasher?.operationState.rawValue == "Run"
    let dishwasherRemainingSeconds = Double(fluxData.dishwasher?.remainingTime ?? 0)
    let dishwasherTiming = cycleTiming(
        elapsedSeconds: dishwasherProgress > 0 && dishwasherProgress < 100
            ? dishwasherRemainingSeconds * dishwasherProgress / (100 - dishwasherProgress)
            : nil,
        remainingSeconds: dishwasherRemainingSeconds
    )

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
                shortText: dishwasherRemainingTime,
                running: dishwasherRunning,
                programName: dishwasherDisplayName,
                startedAt: dishwasherCounting ? dishwasherTiming.startedAt : nil,
                endsAt: dishwasherCounting ? dishwasherTiming.endsAt : nil
            )
        )
    }

    let washerTimeRunning = fluxData.washer?.timeRunning ?? 0
    let washerTimeRemaining = fluxData.washer?.timeRemaining ?? 0
    var washerProgress = 0
    if washerTimeRunning > 0 {
        washerProgress = Int(Double(washerTimeRunning) / Double(washerTimeRemaining + washerTimeRunning) * 100)
    }

    let washerRemainingTime = formatTimeRemaining(minutes: fluxData.washer?.timeRemaining ?? 0)
    var washerTrailingText = washerRemainingTime
    if let programName = fluxData.washer?.programName,
       !programName.trimmingCharacters(in: .whitespaces).isEmpty {
        washerTrailingText = "\(formatApplianceDisplayText(programName)) ⋅ \(washerTrailingText)"
    }
    if fluxData.washer != nil && fluxData.washer?.status != "In use",
       let status = fluxData.washer?.status {
        washerTrailingText = "\(formatApplianceDisplayText(status)) ⋅ \(washerTrailingText)"
    }

    let washerRunning = isMieleCycleActive(
        status: fluxData.washer?.status, remainingMinutes: washerTimeRemaining
    )
    let washerCounting = washerRunning && isCountingStatus(fluxData.washer?.status)
    let washerTiming = cycleTiming(
        elapsedSeconds: fluxData.washer?.timeRunning.map { Double($0) * 60 },
        remainingSeconds: fluxData.washer?.timeRemaining.map { Double($0) * 60 }
    )
    returnValue.append(
        WidgetDevice(
            name: "Washer",
            progress: washerProgress,
            icon: "washer",
            trailingText: washerTrailingText,
            shortText: washerRemainingTime,
            running: washerRunning,
            programName: fluxData.washer?.programName.map { formatApplianceDisplayText($0) },
            startedAt: washerCounting ? washerTiming.startedAt : nil,
            endsAt: washerCounting ? washerTiming.endsAt : nil
        )
    )

    let dryerTimeRunning = fluxData.dryer?.timeRunning ?? 0
    let dryerTimeRemaining = fluxData.dryer?.timeRemaining ?? 1
    var dryerProgress = 0
    if dryerTimeRunning  > 0 {
        dryerProgress = Int(Double(dryerTimeRunning) / Double(dryerTimeRemaining + dryerTimeRunning) * 100)
    }
    let dryerRemainingTime = formatTimeRemaining(minutes: fluxData.dryer?.timeRemaining ?? 0)
    var dryerTrailingText = dryerRemainingTime
    if let programName = fluxData.dryer?.programName,
       !programName.trimmingCharacters(in: .whitespaces).isEmpty {
        dryerTrailingText = "\(formatApplianceDisplayText(programName)) ⋅ \(dryerTrailingText)"
    }
    if fluxData.dryer != nil && fluxData.dryer?.status != "In use",
       let status = fluxData.dryer?.status {
        dryerTrailingText = "\(formatApplianceDisplayText(status)) ⋅ \(dryerTrailingText)"
    }

    let dryerRunning = isMieleCycleActive(
        status: fluxData.dryer?.status, remainingMinutes: fluxData.dryer?.timeRemaining ?? 0
    )
    let dryerCounting = dryerRunning && isCountingStatus(fluxData.dryer?.status)
    let dryerTiming = cycleTiming(
        elapsedSeconds: fluxData.dryer?.timeRunning.map { Double($0) * 60 },
        remainingSeconds: fluxData.dryer?.timeRemaining.map { Double($0) * 60 }
    )
    returnValue.append(
        WidgetDevice(
            name: "Dryer",
            progress: dryerProgress,
            icon: "dryer",
            trailingText: dryerTrailingText,
            shortText: dryerRemainingTime,
            running: dryerRunning,
            programName: fluxData.dryer?.programName.map { formatApplianceDisplayText($0) },
            startedAt: dryerCounting ? dryerTiming.startedAt : nil,
            endsAt: dryerCounting ? dryerTiming.endsAt : nil
        )
    )

    let cleanbotCleaning = fluxData.cleanBot?.running ?? false
    let cleanbotPaused = fluxData.cleanBot?.paused ?? false
    let cleanbotDocking = fluxData.cleanBot?.docking ?? false
    let cleanbotRunning = cleanbotCleaning || cleanbotPaused || cleanbotDocking
    let cleanbotStatus = cleanbotDocking ? "Returning to dock" : (cleanbotPaused ? "Paused" : "Off")
    let cleanbotProgress = fluxData.cleanBot?.progressPercent.map { Int($0.rounded()) }
    let cleanbotTime = fluxData.cleanBot?.estimatedRemainingMinutes.map { "~\(Int($0.rounded())) min" }
    let cleanbotRoom = fluxData.cleanBot?.currentRoom
    let cleanbotTiming = cycleTiming(
        elapsedSeconds: fluxData.cleanBot?.elapsedMinutes.map { $0 * 60 },
        remainingSeconds: fluxData.cleanBot?.estimatedRemainingMinutes.map { $0 * 60 }
    )
    let cleanbotDetail = [cleanbotTime, cleanbotRoom].compactMap { $0 }.joined(separator: " ⋅ ")
    returnValue.append(
        WidgetDevice(
            name: "Cleanbot",
            progress: cleanbotProgress ?? 0,
            icon: "robotic.vacuum.fill",
            trailingText: cleanbotCleaning
                ? (cleanbotDetail.isEmpty ? "Cleaning" : cleanbotDetail)
                : cleanbotStatus,
            shortText: cleanbotCleaning ? cleanbotProgress.map { "\($0)%" } ?? "Cleaning" : cleanbotStatus,
            running: cleanbotRunning,
            battery: fluxData.cleanBot?.batteryLevel,
            startedAt: cleanbotCleaning ? cleanbotTiming.startedAt : nil,
            endsAt: cleanbotCleaning ? cleanbotTiming.endsAt : nil
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
