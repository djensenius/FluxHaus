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
    if car.vehicle.evStatusTimestamp != "" { text += "Updated \(getCarTime(strDate: car.vehicle.evStatusTimestamp))" }
    return text
}
