//
//  FluxWidgetWatchViews.swift
//  FluxWidget
//
//  Watch-specific Live Activity views for the Smart Stack.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
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
                .activityBackgroundTint(liveActivityBackgroundTint(for: devices))
        case .medium:
            watchMediumView
                .padding(10)
                .activityBackgroundTint(liveActivityBackgroundTint(for: devices))
        default:
            phoneLockScreen
        }
    }

    private var phoneLockScreen: some View {
        Group {
            if devices.isEmpty {
                LiveActivityDoneView()
                    .padding(16)
            } else if devices.count == 1, let device = devices.first {
                PhoneSingleDeviceView(device: device)
                    .padding(16)
            } else {
                PhoneMultiDeviceView(devices: devices)
                    .padding(16)
            }
        }
        .activityBackgroundTint(liveActivityBackgroundTint(for: devices))
        .activitySystemActionForegroundColor(.primary)
    }

    // MARK: - Watch Small (single-line compact)

    private var watchSmallView: some View {
        HStack(spacing: 8) {
            if let device = devices.first {
                LiveActivityIconBubble(device: device, size: 26, iconSize: .caption)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(Theme.Fonts.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(deviceMetricText(device))
                        .font(Theme.Fonts.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(tintColor(for: device.name))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if devices.count > 1 {
                    Text("+\(devices.count - 1)")
                        .font(Theme.Fonts.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Watch Medium (multi-row list)

    private var watchMediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(devices.isEmpty ? "All done" : "Running")
                    .font(Theme.Fonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if devices.count > 1 {
                    Text("\(devices.count)")
                        .font(Theme.Fonts.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(devices.prefix(3).enumerated()), id: \.element.name) { _, device in
                LiveActivityCompactRow(device: device, showProgress: false)
            }
        }
    }
}

// MARK: - Shared Lock Screen Subviews

struct LiveActivityDoneView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text("All done")
                    .font(Theme.Fonts.bodyMedium)
                    .fontWeight(.semibold)
                Text("No appliances are running")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct LiveActivityIconBubble: View {
    let device: WidgetDevice
    var size: CGFloat = 38
    var iconSize: Font = .headline

    var body: some View {
        Image(systemName: device.icon)
            .font(iconSize)
            .foregroundStyle(tintColor(for: device.name))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(tintColor(for: device.name).opacity(0.16))
            )
            .overlay(
                Circle()
                    .stroke(tintColor(for: device.name).opacity(0.25), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

struct LiveActivityMetricPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.Fonts.headerXL())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
    }
}

struct LiveActivityProgressLine: View {
    let device: WidgetDevice

    var body: some View {
        HStack(spacing: 8) {
            Gauge(value: liveActivityProgressValue(for: device)) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(liveActivityProgressColor(for: device))

            Text(liveActivityProgressLabel(for: device))
                .font(Theme.Fonts.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

struct LiveActivityCompactRow: View {
    let device: WidgetDevice
    var showProgress = true

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                LiveActivityIconBubble(device: device, size: 24, iconSize: .caption)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(Theme.Fonts.bodyMedium)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if let program = device.programName, !program.isEmpty, !isRobot(device.name) {
                        Text(program)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Text(deviceMetricText(device))
                    .font(Theme.Fonts.bodyMedium)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(liveActivityProgressColor(for: device))
            }

            if showProgress {
                LiveActivityProgressLine(device: device)
            }
        }
    }
}

// MARK: - Phone Lock Screen Subviews (used by FluxWidgetMultiContent)

struct PhoneSingleDeviceView: View {
    let device: WidgetDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LiveActivityIconBubble(device: device, size: 52, iconSize: Theme.Fonts.headerLarge())

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(Theme.Fonts.headerLarge())
                        .lineLimit(1)
                    Text(singleDeviceSubtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                LiveActivityMetricPill(
                    text: deviceMetricText(device),
                    color: liveActivityProgressColor(for: device)
                )
            }

            LiveActivityProgressLine(device: device)
        }
    }

    private var singleDeviceSubtitle: String {
        if isRobot(device.name) {
            return "Cleaning now"
        }
        if let program = device.programName, !program.isEmpty {
            return program
        }
        return "In progress"
    }
}

struct PhoneMultiDeviceView: View {
    let devices: [WidgetDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Running now")
                        .font(Theme.Fonts.headerLarge())
                    Text(summaryText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(devices.count)")
                    .font(Theme.Fonts.bodyMedium)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(.secondary.opacity(0.14), in: Capsule())
            }

            VStack(spacing: 10) {
                ForEach(Array(devices.prefix(4).enumerated()), id: \.element.name) { _, device in
                    LiveActivityCompactRow(device: device)
                }
            }

            if devices.count > 4 {
                Text("+\(devices.count - 4) more")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryText: String {
        let timedDevices = devices.filter { !isRobot($0.name) && !$0.shortText.isEmpty }
        if let soonest = timedDevices.max(by: { $0.progress < $1.progress }) {
            return "Next: \(soonest.name) in \(soonest.shortText)"
        }
        let robots = devices.filter { isRobot($0.name) }.count
        if robots == devices.count {
            return robots == 1 ? "Robot cleaning" : "Robots cleaning"
        }
        return "\(devices.count) devices active"
    }
}

@MainActor @ViewBuilder
func phoneDeviceProgressBar(device: WidgetDevice) -> some View {
    LiveActivityProgressLine(device: device)
}
#endif
