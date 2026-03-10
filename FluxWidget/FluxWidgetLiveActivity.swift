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
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: context.state.device.icon)
                            .font(.title2)
                            .foregroundStyle(tintColor(for: context.state.device.name))

                        Text(context.state.device.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if isRobot(context.state.device.name) {
                            if let battery = context.state.device.battery {
                                Text("\(battery)%")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                Image(systemName: batteryIcon(level: battery))
                                    .font(.caption)
                                    .foregroundStyle(batteryColor(level: battery))
                            }
                        } else {
                            Text(context.state.device.shortText)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            if let program = context.state.device.programName {
                                Text(program)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if isRobot(context.state.device.name) {
                        VStack(spacing: 6) {
                            if let battery = context.state.device.battery {
                                ProgressView(value: Double(battery) / 100.0)
                                    .progressViewStyle(.linear)
                                    .tint(batteryColor(level: battery))
                            }
                            HStack {
                                Text("Cleaning")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    } else {
                        VStack(spacing: 6) {
                            ProgressView(value: Double(context.state.device.progress) / 100.0)
                                .progressViewStyle(.linear)
                                .tint(tintColor(for: context.state.device.name))
                            HStack {
                                Text("\(context.state.device.progress)%")
                                    .font(.caption)
                                    .monospacedDigit()
                                Spacer()
                                Text(context.state.device.trailingText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                } else if context.state.device.shortText.hasSuffix("m") {
                    Text(context.state.device.shortText)
                        .font(.caption)
                        .foregroundStyle(tintColor(for: context.state.device.name))
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

private func batteryColor(level: Int) -> Color {
    switch level {
    case 0..<20: return .red
    case 20..<40: return .orange
    default: return .green
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
    fileprivate static var preview: FluxWidgetAttributes { FluxWidgetAttributes(name: "World") }
}

extension FluxWidgetAttributes.ContentState {
    // MARK: - Dishwasher States
    fileprivate static var dishwasherRunning: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "Dishwasher",
                progress: 50,
                icon: "dishwasher",
                trailingText: "Eco50 ⋅ 59m",
                shortText: "59m",
                running: true,
                programName: "Eco50"
            )
        )
    }

    fileprivate static var dishwasherEarly: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "Dishwasher",
                progress: 10,
                icon: "dishwasher",
                trailingText: "Intensiv70 ⋅ 1h 45m",
                shortText: "1h 45m",
                running: true,
                programName: "Intensiv70"
            )
        )
    }

    fileprivate static var dishwasherAlmostDone: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "Dishwasher",
                progress: 92,
                icon: "dishwasher",
                trailingText: "Quick45 ⋅ 4m",
                shortText: "4m",
                running: true,
                programName: "Quick45"
            )
        )
    }

    fileprivate static var dishwasherFinished: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "Dishwasher",
                progress: 0,
                icon: "dishwasher",
                trailingText: "",
                shortText: "",
                running: false
            )
        )
    }

    // MARK: - Washer States
    fileprivate static var washerRunning: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "Washer",
                progress: 35,
                icon: "washer",
                trailingText: "Cottons ⋅ 1h 12m",
                shortText: "1h 12m",
                running: true,
                programName: "Cottons"
            )
        )
    }

    // MARK: - Dryer States
    fileprivate static var dryerRunning: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "Dryer",
                progress: 25,
                icon: "dryer",
                trailingText: "Cotton ⋅ 45m",
                shortText: "45m",
                running: true,
                programName: "Cotton"
            )
        )
    }

    fileprivate static var dryerAlmostDone: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "Dryer",
                progress: 88,
                icon: "dryer",
                trailingText: "Cotton ⋅ 8m",
                shortText: "8m",
                running: true,
                programName: "Cotton"
            )
        )
    }

    // MARK: - Robot States
    fileprivate static var broomBotCleaning: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
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

    fileprivate static var broomBotLowBattery: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "BroomBot",
                progress: 40,
                icon: "fan",
                trailingText: "Cleaning",
                shortText: "Cleaning",
                running: true,
                battery: 12
            )
        )
    }

    fileprivate static var mopBotCleaning: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device: WidgetDevice(
                name: "MopBot",
                progress: 30,
                icon: "humidifier.and.droplets",
                trailingText: "Cleaning",
                shortText: "Cleaning",
                running: true,
                battery: 90
            )
        )
    }
}

// MARK: - Lock Screen / Banner Previews

#Preview("Lock Screen: Dishwasher Running", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherRunning
}

#Preview("Lock Screen: Dishwasher Early", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherEarly
}

#Preview("Lock Screen: Dishwasher Almost Done", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherAlmostDone
}

#Preview("Lock Screen: Dishwasher Finished", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherFinished
}

#Preview("Lock Screen: Washer", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.washerRunning
}

#Preview("Lock Screen: Dryer", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dryerRunning
}

#Preview("Lock Screen: BroomBot", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.broomBotCleaning
}

#Preview("Lock Screen: BroomBot Low Battery", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.broomBotLowBattery
}

#Preview("Lock Screen: MopBot", as: .content, using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.mopBotCleaning
}

// MARK: - Dynamic Island Expanded Previews

#Preview("Expanded: Dishwasher Running", as: .dynamicIsland(.expanded), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherRunning
}

#Preview("Expanded: Dishwasher Almost Done", as: .dynamicIsland(.expanded), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherAlmostDone
}

#Preview("Expanded: Washer", as: .dynamicIsland(.expanded), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.washerRunning
}

#Preview("Expanded: Dryer", as: .dynamicIsland(.expanded), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dryerRunning
}

#Preview("Expanded: BroomBot", as: .dynamicIsland(.expanded), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.broomBotCleaning
}

#Preview("Expanded: BroomBot Low Battery", as: .dynamicIsland(.expanded), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.broomBotLowBattery
}

// MARK: - Dynamic Island Compact Previews

#Preview("Compact: Dishwasher", as: .dynamicIsland(.compact), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherRunning
}

#Preview("Compact: Dishwasher > 1h", as: .dynamicIsland(.compact), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherEarly
}

#Preview("Compact: Dryer", as: .dynamicIsland(.compact), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dryerRunning
}

#Preview("Compact: BroomBot", as: .dynamicIsland(.compact), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.broomBotCleaning
}

// MARK: - Dynamic Island Minimal Previews

#Preview("Minimal: Dishwasher", as: .dynamicIsland(.minimal), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasherRunning
}

#Preview("Minimal: BroomBot", as: .dynamicIsland(.minimal), using: FluxWidgetAttributes.preview) {
    FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.broomBotCleaning
}
#endif
