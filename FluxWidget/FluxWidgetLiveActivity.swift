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
            // Lock screen/banner UI — adapts to device count and platform
            FluxWidgetMultiContent(devices: context.state.devices)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(devices: context.state.devices)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(devices: context.state.devices)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(devices: context.state.devices)
                }
            } compactLeading: {
                compactLeadingView(devices: context.state.devices)
            } compactTrailing: {
                compactTrailingView(devices: context.state.devices)
            } minimal: {
                minimalView(devices: context.state.devices)
            }
            .widgetURL(URL(string: "fluxhaus://appliances"))
        }
        .supplementalActivityFamilies([.small, .medium])
    }

    // MARK: - Lock Screen Views

    // Phone lock screen views are in FluxWidgetWatchViews.swift
    // (PhoneSingleDeviceView, PhoneMultiDeviceView, phoneDeviceProgressBar)

    private var allDoneView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("All Done")
                .font(.title3)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
    }

    private func singleDeviceLockScreen(device: WidgetDevice) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: device.icon)
                    .font(.title2)
                    .foregroundStyle(tintColor(for: device.name))
                Text(device.name)
                    .font(.title3)
                    .fontWeight(.semibold)
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
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(tintColor(for: device.name))
                }
            }
            deviceProgressBar(device: device)
        }
    }

    private func multiDeviceLockScreen(devices: [WidgetDevice]) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(devices.prefix(5).enumerated()), id: \.element.name) { _, device in
                HStack(spacing: 10) {
                    Image(systemName: device.icon)
                        .font(.body)
                        .foregroundStyle(tintColor(for: device.name))
                        .frame(width: 24)
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if isRobot(device.name) {
                        if let battery = device.battery {
                            Spacer()
                            ProgressView(value: Double(battery) / 100.0)
                                .progressViewStyle(.linear)
                                .tint(batteryColor(level: battery))
                                .frame(maxWidth: 100)
                            Text("\(battery)%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Spacer()
                        ProgressView(value: Double(device.progress) / 100.0)
                            .progressViewStyle(.linear)
                            .tint(tintColor(for: device.name))
                            .frame(maxWidth: 100)
                        Text(device.shortText)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func deviceProgressBar(device: WidgetDevice) -> some View {
        if isRobot(device.name) {
            if let battery = device.battery {
                HStack(spacing: 8) {
                    Image(systemName: batteryIcon(level: battery))
                        .font(.subheadline)
                    ProgressView(value: Double(battery) / 100.0)
                        .progressViewStyle(.linear)
                        .tint(batteryColor(level: battery))
                    Text("\(battery)%")
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
        } else if device.running {
            HStack(spacing: 8) {
                ProgressView(value: Double(device.progress) / 100.0)
                    .progressViewStyle(.linear)
                    .tint(tintColor(for: device.name))
                Text("\(device.progress)%")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    // MARK: - Dynamic Island

    private func expandedLeading(devices: [WidgetDevice]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if devices.count == 1, let device = devices.first {
                Image(systemName: device.icon)
                    .font(.title)
                    .foregroundStyle(tintColor(for: device.name))
                Text(device.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(devices.prefix(3).enumerated()), id: \.element.name) { _, device in
                        Image(systemName: device.icon)
                            .font(.subheadline)
                            .foregroundStyle(tintColor(for: device.name))
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Text("\(devices.count) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func expandedTrailing(devices: [WidgetDevice]) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if devices.count == 1, let device = devices.first {
                if isRobot(device.name) {
                    if let battery = device.battery {
                        Text("\(battery)%")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                } else {
                    Text(device.shortText)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    if let program = device.programName {
                        Text(program)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Show the device closest to finishing
                if let soonest = devices.filter({ !isRobot($0.name) }).max(by: { $0.progress < $1.progress }) {
                    Text(soonest.shortText)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(soonest.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func expandedBottom(devices: [WidgetDevice]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(devices.prefix(4).enumerated()), id: \.element.name) { _, device in
                HStack(spacing: 8) {
                    Image(systemName: device.icon)
                        .font(.caption)
                        .foregroundStyle(tintColor(for: device.name))
                        .frame(width: 20)
                    if isRobot(device.name) {
                        if let battery = device.battery {
                            ProgressView(value: Double(battery) / 100.0)
                                .progressViewStyle(.linear)
                                .tint(batteryColor(level: battery))
                            Text("\(battery)%")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    } else {
                        ProgressView(value: Double(device.progress) / 100.0)
                            .progressViewStyle(.linear)
                            .tint(tintColor(for: device.name))
                        Text(device.shortText)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compactLeadingView(devices: [WidgetDevice]) -> some View {
        if devices.count == 1, let device = devices.first {
            Image(systemName: device.icon)
                .font(.body)
                .foregroundStyle(tintColor(for: device.name))
        } else {
            HStack(spacing: 2) {
                ForEach(Array(devices.prefix(2).enumerated()), id: \.element.name) { _, device in
                    Image(systemName: device.icon)
                        .font(.caption)
                        .foregroundStyle(tintColor(for: device.name))
                }
            }
        }
    }

    @ViewBuilder
    private func compactTrailingView(devices: [WidgetDevice]) -> some View {
        if devices.count == 1, let device = devices.first {
            if isRobot(device.name) {
                if let battery = device.battery {
                    Text("\(battery)%")
                        .font(.body)
                        .monospacedDigit()
                } else {
                    Text("")
                }
            } else if !device.shortText.isEmpty {
                Text(device.shortText)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(tintColor(for: device.name))
            } else {
                ProgressView(value: Double(device.progress) / 100.0)
                    .progressViewStyle(.circular)
                    .tint(tintColor(for: device.name))
            }
        } else {
            Text("\(devices.count)")
                .font(.body)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func minimalView(devices: [WidgetDevice]) -> some View {
        if devices.count == 1, let device = devices.first {
            Image(systemName: device.icon)
                .font(.body)
                .foregroundStyle(tintColor(for: device.name))
        } else {
            Image(systemName: "house.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)
        }
    }
}
#endif

// MARK: - Helpers

func tintColor(for deviceName: String) -> Color {
    switch deviceName {
    case "Dishwasher": return .blue
    case "Washer": return .cyan
    case "Dryer": return .orange
    case "BroomBot": return .green
    case "MopBot": return .teal
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
    name == "BroomBot" || name == "MopBot"
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
                name: "BroomBot", progress: 75, icon: "fan",
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
