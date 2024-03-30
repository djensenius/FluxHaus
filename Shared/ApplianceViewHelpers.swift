//
//  ApplianceViewHelpers.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import Foundation
import SwiftUI

func getDeviceIcon(battery: Battery) -> Image {
    if battery.model == .iPad {
        return Image(systemName: "iPad")
    } else if battery.model == .mac {
        return Image(systemName: "macbook")
    } else if battery.model == .visionPro {
        return Image(systemName: "visionpro")
    } else {
        return Image(systemName: "iphone")
    }
}
