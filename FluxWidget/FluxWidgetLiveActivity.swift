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

struct FluxWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FluxWidgetAttributes.self) { context in
            // Lock screen/banner UI
            HStack(spacing: 12) {
                Image(systemName: context.state.device.icon)
                    .font(.title2)
                    .foregroundStyle(tintColor(for: context.state.device.name))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.device.name)
                        .font(.headline)

                    if isRobot(context.state.device.name),
                       let battery = context.state.device.battery {
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(level: battery))
                                .font(.caption)
                            Text("\(battery)%")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isRobot(context.state.device.name) {
                    Text("Cleaning")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: Double(context.state.device.progress) / 100.0)
                            .progressViewStyle(.linear)
                            .tint(tintColor(for: context.state.device.name))
                            .frame(width: 80)

                        Text(context.state.device.shortText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.8))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.device.icon)
                        .font(.title2)
                        .foregroundStyle(tintColor(for: context.state.device.name))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isRobot(context.state.device.name) {
                        if let battery = context.state.device.battery {
                            Text("\(battery)%")
                                .font(.headline)
                        }
                    } else {
                        Text(context.state.device.shortText)
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if isRobot(context.state.device.name) {
                        HStack {
                            Text(context.state.device.name)
                            Spacer()
                            Text("Cleaning")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    } else {
                        ProgressView(value: Double(context.state.device.progress) / 100.0) {
                            Text(context.state.device.name)
                                .font(.subheadline)
                        } currentValueLabel: {
                            Text(context.state.device.trailingText)
                                .font(.caption)
                        }
                        .tint(tintColor(for: context.state.device.name))
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            } compactTrailing: {
                if isRobot(context.state.device.name) {
                    if let battery = context.state.device.battery {
                        Text("\(battery)%")
                            .font(.caption)
                    }
                } else {
                    ProgressView(value: Double(context.state.device.progress) / 100.0)
                        .progressViewStyle(.circular)
                        .tint(tintColor(for: context.state.device.name))
                }
            } minimal: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            }
            .widgetURL(URL(string: "fluxhaus://appliances"))
        }
    }
}

private func tintColor(for deviceName: String) -> Color {
    switch deviceName {
    case "Dishwasher": return .blue
    case "Washer": return .cyan
    case "Dryer": return .orange
    case "BroomBot": return .green
    case "MopBot": return .teal
    default: return .accentColor
    }
}

private func isRobot(_ name: String) -> Bool {
    name == "BroomBot" || name == "MopBot"
}

private func batteryIcon(level: Int) -> String {
    switch level {
    case 0..<15: return "battery.0percent"
    case 15..<40: return "battery.25percent"
    case 40..<65: return "battery.50percent"
    case 65..<90: return "battery.75percent"
    default: return "battery.100percent"
    }
}

extension FluxWidgetAttributes {
    fileprivate static var preview: FluxWidgetAttributes {
        FluxWidgetAttributes(name: "World")
    }
}

extension FluxWidgetAttributes.ContentState {
    fileprivate static var dishwasher: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device:
                WidgetDevice(
                    name: "Dishwasher",
                    progress: 50,
                    icon: "dishwasher",
                    trailingText: "Auto2 · 59m",
                    shortText: "59m",
                    running: true
                )
        )
     }

     fileprivate static var dryer: FluxWidgetAttributes.ContentState {
         FluxWidgetAttributes.ContentState(
            device:
                WidgetDevice(
                    name: "Dryer",
                    progress: 25,
                    icon: "dryer",
                    trailingText: "Cottons · 45m",
                    shortText: "45m",
                    running: true
                )
         )
     }

    fileprivate static var broomBot: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device:
                WidgetDevice(
                    name: "BroomBot",
                    progress: 75,
                    icon: "fan",
                    trailingText: "Cleaning",
                    shortText: "Cleaning",
                    running: true,
                    battery: 75
                )
        )
    }
}

#Preview("Notification", as: .content, using: FluxWidgetAttributes.preview) {
   FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasher
    FluxWidgetAttributes.ContentState.dryer
    FluxWidgetAttributes.ContentState.broomBot
}
#endif
