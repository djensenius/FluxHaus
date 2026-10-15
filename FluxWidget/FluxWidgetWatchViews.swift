//
//  FluxWidgetWatchViews.swift
//  FluxWidget
//
//  Live Activity views for every presentation: Lock Screen / StandBy, Dynamic Island,
//  and the small supplemental family used by Apple Watch Smart Stack and CarPlay.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI
import WidgetKit

// MARK: - Platform-adaptive content

/// Chooses the layout for the presentation (Lock Screen vs Watch/CarPlay).
struct FluxWidgetMultiContent: View {
    @Environment(\.activityFamily) var activityFamily
    let devices: [WidgetDevice]
    var isStale = false

    var body: some View {
        switch activityFamily {
        case .small:
            LiveActivitySmallView(devices: devices)
                .padding(10)
                .activityBackgroundTint(liveActivityBackgroundTint(for: devices))
        default:
            LiveActivityLockScreenView(devices: devices, isStale: isStale)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .activityBackgroundTint(liveActivityBackgroundTint(for: devices))
                .activitySystemActionForegroundColor(.primary)
        }
    }
}

// MARK: - Lock Screen / StandBy

/// Lock Screen layout. The Lock Screen caps Live Activities at ~160pt tall, so the
/// multi-device layout uses single-line rows and shows at most three devices.
struct LiveActivityLockScreenView: View {
    let devices: [WidgetDevice]
    var isStale = false

    var body: some View {
        if devices.isEmpty {
            LiveActivityDoneView()
        } else if devices.count == 1, let device = devices.first {
            LiveActivitySingleView(device: device, isStale: isStale)
        } else {
            LiveActivityMultiView(devices: devices, isStale: isStale)
        }
    }
}

struct LiveActivitySingleView: View {
    let device: WidgetDevice
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LiveActivityIconBubble(device: device, size: 46, iconSize: .title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(1)
                    LiveActivitySubtitle(device: device, isStale: isStale)
                }
                Spacer(minLength: 8)
                DeviceMetricText(device: device)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(liveActivityProgressColor(for: device))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            DeviceProgressBar(device: device)
        }
    }
}

struct LiveActivityMultiView: View {
    let devices: [WidgetDevice]
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(devices.prefix(3), id: \.name) { device in
                LiveActivityRow(device: device)
            }
            if devices.count > 3 || isStale {
                HStack {
                    if devices.count > 3 {
                        Text("+\(devices.count - 3) more running")
                    }
                    Spacer()
                    if isStale {
                        Label("Updating…", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// One-line row: icon, name, progress, live countdown.
struct LiveActivityRow: View {
    let device: WidgetDevice

    var body: some View {
        HStack(spacing: 10) {
            LiveActivityIconBubble(device: device, size: 30, iconSize: .subheadline)
            Text(device.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            DeviceProgressBar(device: device)
            DeviceMetricText(device: device)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(liveActivityProgressColor(for: device))
                .frame(width: 64, alignment: .trailing)
        }
    }
}

struct LiveActivitySubtitle: View {
    let device: WidgetDevice
    var isStale = false

    var body: some View {
        Group {
            if isStale {
                Label("Updating…", systemImage: "arrow.triangle.2.circlepath")
            } else if device.running, !isRobot(device.name), let end = device.endDate, end > .now {
                if let program = device.programName, !program.isEmpty {
                    Text("\(program) · done \(Text(end, style: .time))")
                } else {
                    Text("Done \(Text(end, style: .time))")
                }
            } else {
                Text(trailingSubtitle(for: device))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct LiveActivityDoneView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text("All done")
                    .font(.headline)
                Text("Nothing is running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Watch Smart Stack / CarPlay

struct LiveActivitySmallView: View {
    let devices: [WidgetDevice]

    var body: some View {
        if let device = primaryLiveActivityDevice(from: devices) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LiveActivityIconBubble(device: device, size: 26, iconSize: .caption)
                    Text(device.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if devices.count > 1 {
                        Text("+\(devices.count - 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                DeviceMetricText(device: device)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(liveActivityProgressColor(for: device))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                DeviceProgressBar(device: device)
            }
        } else {
            Label("All done", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Dynamic Island

struct IslandCompactTrailing: View {
    let devices: [WidgetDevice]

    var body: some View {
        if let device = primaryLiveActivityDevice(from: devices) {
            DeviceMetricText(device: device)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(liveActivityProgressColor(for: device))
                .frame(maxWidth: 58)
        }
    }
}

struct IslandCompactLeading: View {
    let devices: [WidgetDevice]

    var body: some View {
        if let device = primaryLiveActivityDevice(from: devices) {
            HStack(spacing: 3) {
                Image(systemName: device.icon)
                    .foregroundStyle(tintColor(for: device.name))
                if devices.count > 1 {
                    Text("\(devices.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Minimal: a progress ring around the device icon.
struct IslandMinimal: View {
    let devices: [WidgetDevice]

    var body: some View {
        if let device = primaryLiveActivityDevice(from: devices) {
            Group {
                if let interval = device.timerInterval(), device.startDate != nil {
                    ProgressView(timerInterval: interval, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: device.icon).font(.caption2)
                    }
                    .progressViewStyle(.circular)
                } else {
                    // No timing (older payloads): a determinate ring, not a spinner.
                    Gauge(value: liveActivityProgressValue(for: device)) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: device.icon).font(.caption2)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
            }
            .tint(liveActivityProgressColor(for: device))
        }
    }
}

struct IslandExpandedLeading: View {
    let devices: [WidgetDevice]

    var body: some View {
        if let device = primaryLiveActivityDevice(from: devices) {
            HStack(spacing: 8) {
                LiveActivityIconBubble(device: device, size: 36, iconSize: .headline)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(devices.count > 1 ? "\(devices.count) running" : trailingSubtitle(for: device))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4)
        }
    }
}

struct IslandExpandedTrailing: View {
    let devices: [WidgetDevice]

    var body: some View {
        if let device = primaryLiveActivityDevice(from: devices) {
            DeviceMetricText(device: device)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(liveActivityProgressColor(for: device))
                .frame(maxWidth: 120, alignment: .trailing)
                .padding(.trailing, 4)
        }
    }
}

struct IslandExpandedBottom: View {
    let devices: [WidgetDevice]

    var body: some View {
        let primary = primaryLiveActivityDevice(from: devices)
        VStack(spacing: 8) {
            if let primary {
                DeviceProgressBar(device: primary)
            }
            ForEach(devices.filter { $0.name != primary?.name }.prefix(2), id: \.name) { device in
                LiveActivityRow(device: device)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Shared subviews

struct LiveActivityIconBubble: View {
    let device: WidgetDevice
    var size: CGFloat = 38
    var iconSize: Font = .headline

    var body: some View {
        Image(systemName: device.icon)
            .font(iconSize)
            .foregroundStyle(tintColor(for: device.name))
            .frame(width: size, height: size)
            .background(Circle().fill(tintColor(for: device.name).opacity(0.18)))
            .accessibilityHidden(true)
    }
}
#endif
