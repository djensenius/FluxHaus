//
//  FluxWidgetLiveActivity.swift
//  FluxWidget
//
//  Created by David Jensenius on 2024-08-01.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
import WidgetKit
#endif
import SwiftUI

#if os(iOS) && !targetEnvironment(macCatalyst)
struct FluxWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var device: WidgetDevice
    }

    var name: String
}

struct FluxWidgetMultiAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var devices: [WidgetDevice]
    }

    var name: String
}

// MARK: - Consolidated Multi-Device Live Activity

struct FluxWidgetMultiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FluxWidgetMultiAttributes.self) { context in
            // Lock Screen, StandBy, Watch Smart Stack and CarPlay
            FluxWidgetMultiContent(devices: context.state.devices, isStale: context.isStale)
                .widgetURL(URL(string: "fluxhaus://appliances"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(devices: context.state.devices)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(devices: context.state.devices)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(devices: context.state.devices)
                }
            } compactLeading: {
                IslandCompactLeading(devices: context.state.devices)
            } compactTrailing: {
                IslandCompactTrailing(devices: context.state.devices)
            } minimal: {
                IslandMinimal(devices: context.state.devices)
            }
            .widgetURL(URL(string: "fluxhaus://appliances"))
            .keylineTint(context.state.devices.first.map { tintColor(for: $0.name) })
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
#endif

// MARK: - Helpers

func tintColor(for deviceName: String) -> Color {
    switch deviceName {
    case "Dishwasher": return .blue
    case "Washer": return .cyan
    case "Dryer": return .orange
    case "Cleanbot": return .green
    default: return .accentColor
    }
}

func batteryColor(level: Int) -> Color {
    switch level {
    case 0..<20: return .red
    case 20..<40: return .orange
    default: return .green
    }
}

func isRobot(_ name: String) -> Bool {
    name == "Cleanbot"
}

func batteryIcon(level: Int) -> String {
    switch level {
    case 0..<15: return "battery.0percent"
    case 15..<40: return "battery.25percent"
    case 40..<65: return "battery.50percent"
    case 65..<90: return "battery.75percent"
    default: return "battery.100percent"
    }
}

func liveActivityBackgroundTint(for devices: [WidgetDevice]) -> Color {
    guard let device = devices.first else { return Theme.Colors.background }
    return tintColor(for: device.name).opacity(0.12)
}

func liveActivityProgressValue(for device: WidgetDevice) -> Double {
    let rawValue: Int
    if isRobot(device.name), let battery = device.battery {
        rawValue = battery
    } else {
        rawValue = device.progress
    }
    return min(max(Double(rawValue) / 100.0, 0), 1)
}

func liveActivityProgressColor(for device: WidgetDevice) -> Color {
    if isRobot(device.name), let battery = device.battery {
        return batteryColor(level: battery)
    }
    return tintColor(for: device.name)
}

func liveActivityProgressLabel(for device: WidgetDevice) -> String {
    if isRobot(device.name), let battery = device.battery {
        return "\(battery)%"
    }
    return "\(min(max(device.progress, 0), 100))%"
}

func deviceMetricText(_ device: WidgetDevice) -> String {
    if isRobot(device.name) {
        if let battery = device.battery {
            return "\(battery)%"
        }
        return "Cleaning"
    }
    if !device.shortText.isEmpty {
        return device.shortText
    }
    return liveActivityProgressLabel(for: device)
}

func trailingSubtitle(for device: WidgetDevice) -> String {
    if isRobot(device.name) {
        return "Cleaning now"
    }
    if let program = device.programName, !program.isEmpty {
        return program
    }
    return "In progress"
}

/// The device finishing soonest (by end time when known, else most progressed).
func primaryLiveActivityDevice(from devices: [WidgetDevice]) -> WidgetDevice? {
    // Earliest known end across every running device (including Cleanbot)...
    if let soonest = devices.filter({ $0.running && $0.endsAt != nil })
        .min(by: { ($0.endsAt ?? 0) < ($1.endsAt ?? 0) }) {
        return soonest
    }
    // ...otherwise the most progressed timed appliance.
    let timed = devices.filter { !isRobot($0.name) && !$0.shortText.isEmpty }
    return timed.max(by: { $0.progress < $1.progress }) ?? devices.first
}

// MARK: - Preview Data

#if os(iOS) && !targetEnvironment(macCatalyst)
extension FluxWidgetMultiAttributes {
    static var preview: FluxWidgetMultiAttributes {
        FluxWidgetMultiAttributes(name: "Appliances")
    }
}

extension FluxWidgetMultiAttributes.ContentState {
    static var singleDishwasher: FluxWidgetMultiAttributes.ContentState {
        FluxWidgetMultiAttributes.ContentState(devices: [
            WidgetDevice(
                name: "Dishwasher", progress: 50, icon: "dishwasher",
                trailingText: "Eco50 ⋅ 59m", shortText: "59m",
                running: true, programName: "Eco50",
                startedAt: Date().timeIntervalSince1970 - 59 * 60, endsAt: Date().timeIntervalSince1970 + 59 * 60
            )
        ])
    }

    static var twoDevices: FluxWidgetMultiAttributes.ContentState {
        FluxWidgetMultiAttributes.ContentState(devices: [
            WidgetDevice(
                name: "Dishwasher", progress: 50, icon: "dishwasher",
                trailingText: "Eco50 ⋅ 59m", shortText: "59m",
                running: true, programName: "Eco50"
            ),
            WidgetDevice(
                name: "Washer", progress: 35, icon: "washer",
                trailingText: "Cottons ⋅ 3:45 PM", shortText: "3:45 PM",
                running: true, programName: "Cottons"
            )
        ])
    }

    static var threeDevices: FluxWidgetMultiAttributes.ContentState {
        FluxWidgetMultiAttributes.ContentState(devices: [
            WidgetDevice(
                name: "Dishwasher", progress: 92, icon: "dishwasher",
                trailingText: "Quick45 ⋅ 4m", shortText: "4m",
                running: true, programName: "Quick45"
            ),
            WidgetDevice(
                name: "Dryer", progress: 25, icon: "dryer",
                trailingText: "Cotton ⋅ 45m", shortText: "45m",
                running: true, programName: "Cotton"
            ),
            WidgetDevice(
                name: "Cleanbot", progress: 75, icon: "robotic.vacuum.fill",
                trailingText: "Cleaning", shortText: "Cleaning",
                running: true, battery: 75
            )
        ])
    }
}

// MARK: - Previews

#Preview("Lock Screen: Single", as: .content, using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.singleDishwasher
}

#Preview("Lock Screen: Two", as: .content, using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.twoDevices
}

#Preview("Lock Screen: Three", as: .content, using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.threeDevices
}

#Preview("Expanded: Two", as: .dynamicIsland(.expanded), using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.twoDevices
}

#Preview("Compact: Single", as: .dynamicIsland(.compact), using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.singleDishwasher
}

#Preview("Compact: Multiple", as: .dynamicIsland(.compact), using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.twoDevices
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.threeDevices
}
#endif
