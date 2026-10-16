//
//  AppIntent.swift
//  FluxWidget
//
//  Created by David Jensenius on 2024-08-01.
//

import WidgetKit
import AppIntents

enum WidgetDeviceChoice: String, AppEnum {
    case automatic
    case dishwasher
    case washer
    case dryer
    case cleanbot
    case car

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Device"

    static let caseDisplayRepresentations: [WidgetDeviceChoice: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Automatic", subtitle: "Whatever finishes next"),
        .dishwasher: "Dishwasher",
        .washer: "Washer",
        .dryer: "Dryer",
        .cleanbot: "Cleanbot",
        .car: "Car"
    ]

    /// Matches `WidgetDevice.name`.
    var deviceName: String? {
        switch self {
        case .automatic: return nil
        case .dishwasher: return "Dishwasher"
        case .washer: return "Washer"
        case .dryer: return "Dryer"
        case .cleanbot: return "Cleanbot"
        case .car: return "Car"
        }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Appliances"
    static let description = IntentDescription("Choose which device the widget features.")

    @Parameter(title: "Featured Device", default: .automatic)
    var device: WidgetDeviceChoice

    init() {}

    init(device: WidgetDeviceChoice) {
        self.device = device
    }
}
