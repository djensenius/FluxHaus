//
//  ApplianceViewHelpers.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import Foundation
import SwiftUI

struct Appliance {
    let name: String
    let timeRunning: Int
    let timeRemaining: Int
    let timeFinish: String
    let step: String
    let programName: String
    let inUse: Bool
}

/// Formats raw appliance strings from the API into human-readable display text.
/// Identifier-style values are title-cased while existing display names keep their casing.
/// e.g. "main_wash (normal)" → "Main Wash (Normal)"
func formatApplianceDisplayText(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    let normalized = trimmed
        .replacingOccurrences(of: "_", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    let hasUppercase = normalized.contains(where: \.isUppercase)
    let hasLowercase = normalized.contains(where: \.isLowercase)
    if !trimmed.contains("_"), hasUppercase && hasLowercase {
        return normalized
    }
    return normalized.capitalized
}

extension OperationState {
    var displayText: String {
        switch self {
        case .inactive: return "Inactive"
        case .ready: return "Ready"
        case .delayedStart: return "Delayed Start"
        case .run: return "Running"
        case .pause: return "Paused"
        case .actionRequired: return "Action Required"
        case .finished: return "Finished"
        case .error: return "Error"
        case .aborting: return "Aborting"
        }
    }
}

@MainActor
func getDeviceIcon(battery: Battery) -> Image {
    if battery.model == .iPad {
        return Image(systemName: "ipad")
    } else if battery.model == .mac {
        return Image(systemName: "macbook")
    } else if battery.model == .visionPro {
        return Image(systemName: "visionpro")
    } else {
        return Image(systemName: "iphone")
    }
}

@MainActor
func carDetails(car: Car) -> String {
    var text = ""
    if car.vehicle.engine { text += "Car on | " }

    if car.vehicle.hvac { text += "Climate on | " }

    if car.vehicle.distance != 0 { text += "Range \(car.vehicle.distance) km | " }
    if car.vehicle.evStatusTimestamp != "" {
        text += "Updated \(relativeTimeString(from: car.vehicle.evStatusTimestamp))"
    }
    return text
}
