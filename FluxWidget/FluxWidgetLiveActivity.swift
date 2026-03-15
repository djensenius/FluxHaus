//
//  FluxWidgetLiveActivity.swift
//  FluxWidget
//
//  Created by David Jensenius on 2024-08-01.
//

#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI

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
            // Lock screen/banner UI — adapts to device count
            let devices = context.state.devices
            if devices.isEmpty {
                allDoneView
            } else if devices.count == 1, let device = devices.first {
                singleDeviceLockScreen(device: device)
                    .padding(16)
                    .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
            } else {
                multiDeviceLockScreen(devices: devices)
                    .padding(16)
                    .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
            }
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
            } else if device.shortText.hasSuffix("m") || device.shortText.contains("h") {
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

// MARK: - Legacy Single Device Live Activity (kept for backward compat)

struct FluxWidgetLiveActivity: Widget {
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
#endif
