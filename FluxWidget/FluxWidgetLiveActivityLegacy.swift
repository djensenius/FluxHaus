//
//  FluxWidgetLiveActivityLegacy.swift
//  FluxWidget
//
//  Legacy single-device Live Activity kept for backward compatibility
//  with existing push-to-start tokens. New installs use FluxWidgetMultiLiveActivity.
//

#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Legacy Single Device Live Activity

struct FluxWidgetLiveActivityLegacy: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FluxWidgetAttributes.self) { context in
            let device = context.state.device
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: device.icon)
                        .font(.title3)
                        .foregroundStyle(tintColor(for: device.name))

                    Text(device.name)
                        .font(.headline)

                    if let program = device.programName {
                        Text(program)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isRobot(device.name) {
                        Text("Cleaning")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if !device.shortText.isEmpty {
                        Text(device.shortText)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(tintColor(for: device.name))
                    }
                }

                if isRobot(device.name) {
                    if let battery = device.battery {
                        HStack(spacing: 6) {
                            Image(systemName: batteryIcon(level: battery))
                                .font(.caption)
                            ProgressView(value: Double(battery) / 100.0)
                                .progressViewStyle(.linear)
                                .tint(batteryColor(level: battery))
                            Text("\(battery)%")
                                .font(.caption)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                } else if device.running {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(device.progress) / 100.0)
                            .progressViewStyle(.linear)
                            .tint(tintColor(for: device.name))

                        Text("\(device.progress)%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.8))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("")
                }
            } compactLeading: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            } compactTrailing: {
                Text("")
            } minimal: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            }
        }
    }
}

// MARK: - Preview Data

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
                running: true, programName: "Eco50"
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
                trailingText: "Cottons ⋅ 1h 12m", shortText: "1h 12m",
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
                name: "BroomBot", progress: 75, icon: "fan",
                trailingText: "Cleaning", shortText: "Cleaning",
                running: true, battery: 75
            )
        ])
    }

    static var allRunning: FluxWidgetMultiAttributes.ContentState {
        FluxWidgetMultiAttributes.ContentState(devices: [
            WidgetDevice(
                name: "Dishwasher", progress: 40, icon: "dishwasher",
                trailingText: "Intensiv70 ⋅ 1h 20m", shortText: "1h 20m",
                running: true, programName: "Intensiv70"
            ),
            WidgetDevice(
                name: "Washer", progress: 60, icon: "washer",
                trailingText: "Cottons ⋅ 30m", shortText: "30m",
                running: true, programName: "Cottons"
            ),
            WidgetDevice(
                name: "Dryer", progress: 88, icon: "dryer",
                trailingText: "Cotton ⋅ 8m", shortText: "8m",
                running: true, programName: "Cotton"
            ),
            WidgetDevice(
                name: "BroomBot", progress: 50, icon: "fan",
                trailingText: "Cleaning", shortText: "Cleaning",
                running: true, battery: 50
            ),
            WidgetDevice(
                name: "MopBot", progress: 30, icon: "humidifier.and.droplets",
                trailingText: "Cleaning", shortText: "Cleaning",
                running: true, battery: 90
            )
        ])
    }
}

// MARK: - Consolidated Previews

#Preview("Lock Screen: Single Dishwasher", as: .content, using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.singleDishwasher
}

#Preview("Lock Screen: Two Devices", as: .content, using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.twoDevices
}

#Preview("Lock Screen: Three Devices", as: .content, using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.threeDevices
}

#Preview("Lock Screen: All Running", as: .content, using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.allRunning
}

#Preview("Expanded: Two Devices", as: .dynamicIsland(.expanded), using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.twoDevices
}

#Preview("Expanded: Three Devices", as: .dynamicIsland(.expanded), using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.threeDevices
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

#Preview("Minimal: Multiple", as: .dynamicIsland(.minimal), using: FluxWidgetMultiAttributes.preview) {
    FluxWidgetMultiLiveActivity()
} contentStates: {
    FluxWidgetMultiAttributes.ContentState.threeDevices
}
#endif
