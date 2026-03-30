//
//  FluxWidgetWatchViews.swift
//  FluxWidget
//
//  Watch-specific Live Activity views for the Smart Stack.
//

#if os(iOS)
import SwiftUI
import WidgetKit

// MARK: - Platform-Adaptive Content

/// Chooses the appropriate layout based on activity family (iPhone vs Watch).
struct FluxWidgetMultiContent: View {
    @Environment(\.activityFamily) var activityFamily
    let devices: [WidgetDevice]

    var body: some View {
        switch activityFamily {
        case .small:
            watchSmallView
                .padding(8)
        case .medium:
            watchMediumView
                .padding(10)
        default:
            phoneLockScreen
        }
    }

    private var phoneLockScreen: some View {
        Group {
            if devices.isEmpty {
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
            } else if devices.count == 1, let device = devices.first {
                PhoneSingleDeviceView(device: device)
                    .padding(16)
                    .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
            } else {
                PhoneMultiDeviceView(devices: devices)
                    .padding(16)
                    .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
            }
        }
    }

    // MARK: - Watch Small (single-line compact)

    private var watchSmallView: some View {
        HStack(spacing: 6) {
            if let device = devices.first {
                Image(systemName: device.icon)
                    .font(.body)
                    .foregroundStyle(tintColor(for: device.name))
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if isRobot(device.name) {
                        Text("Cleaning")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(device.shortText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(tintColor(for: device.name))
                    }
                }
                Spacer(minLength: 0)
                if devices.count > 1 {
                    Text("+\(devices.count - 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Watch Medium (multi-row list)

    private var watchMediumView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(
                Array(devices.prefix(3).enumerated()),
                id: \.element.name
            ) { _, device in
                HStack(spacing: 6) {
                    Image(systemName: device.icon)
                        .font(.caption2)
                        .foregroundStyle(tintColor(for: device.name))
                        .frame(width: 16)
                    Text(device.name)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isRobot(device.name) {
                        if let battery = device.battery {
                            Text("\(battery)%")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(device.shortText)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Phone Lock Screen Subviews (used by FluxWidgetMultiContent)

struct PhoneSingleDeviceView: View {
    let device: WidgetDevice

    var body: some View {
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
            phoneDeviceProgressBar(device: device)
        }
    }
}

struct PhoneMultiDeviceView: View {
    let devices: [WidgetDevice]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(
                Array(devices.prefix(5).enumerated()),
                id: \.element.name
            ) { _, device in
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
}

@ViewBuilder
func phoneDeviceProgressBar(device: WidgetDevice) -> some View {
    if isRobot(device.name) {
        if let battery = device.battery {
            HStack(spacing: 8) {
                Image(systemName: batteryIcon(level: battery))
                    .font(.subheadline)
                ProgressView(value: Double(battery) / 100.0)
                    .progressViewStyle(LinearProgressViewStyle())
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
                .progressViewStyle(LinearProgressViewStyle())
                .tint(tintColor(for: device.name))
            Text("\(device.progress)%")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
#endif
