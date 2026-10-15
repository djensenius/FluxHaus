//
//  WidgetShared.swift
//  FluxWidget
//
//  Styling and building blocks shared by every FluxHaus widget.
//

import SwiftUI
import WidgetKit

// MARK: - Palette

/// Resolves colors for the current rendering context. In accented (tinted Home Screen)
/// and vibrant (Lock Screen / StandBy night) modes the system recolors content, so we
/// use semantic styles there and let `.widgetAccentable()` mark highlight content.
struct WidgetPalette {
    let renderingMode: WidgetRenderingMode
    let showsBackground: Bool
    let reducedLuminance: Bool

    var isFullColor: Bool { renderingMode == .fullColor }

    var primary: Color { isFullColor && showsBackground ? Theme.Colors.textPrimary : .primary }
    var secondary: Color { isFullColor && showsBackground ? Theme.Colors.textSecondary : .secondary }

    func tint(_ color: Color) -> Color { isFullColor ? color : .primary }

    func tint(for device: WidgetDevice) -> Color {
        if device.name == "Car" { return tint(batteryColor(level: device.progress)) }
        return tint(tintColor(for: device.name))
    }

    func fill(_ color: Color) -> Color {
        guard isFullColor, !reducedLuminance else { return .primary.opacity(0.12) }
        return color.opacity(0.18)
    }
}

struct PaletteReader<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @ViewBuilder var content: (WidgetPalette) -> Content

    var body: some View {
        content(WidgetPalette(
            renderingMode: renderingMode,
            showsBackground: showsBackground,
            reducedLuminance: isLuminanceReduced
        ))
    }
}

/// Subtle device-tinted wash behind the content when the system shows our background.
struct WidgetBackground: View {
    var tint: Color?

    var body: some View {
        ZStack {
            Theme.Colors.background
            if let tint {
                LinearGradient(
                    colors: [tint.opacity(0.22), tint.opacity(0.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

// MARK: - Device text helpers

func isLive(_ device: WidgetDevice) -> Bool {
    device.running || device.name == "Car"
}

func widgetProgress(for device: WidgetDevice) -> Double {
    if device.name == "Car" {
        return min(max(Double(device.progress) / 100, 0), 1)
    }
    return liveActivityProgressValue(for: device)
}

func widgetMetric(for device: WidgetDevice) -> String {
    if device.name == "Car" { return "\(device.progress)%" }
    if !device.running { return "Off" }
    return deviceMetricText(device)
}

func widgetSubtitle(for device: WidgetDevice) -> String {
    if device.name == "Car" { return device.shortText }
    if !device.running { return "Off" }
    if isRobot(device.name) {
        return device.trailingText.isEmpty ? "Cleaning" : device.trailingText
    }
    if let program = device.programName, !program.isEmpty { return program }
    return "Running"
}

// MARK: - Live timing

/// The device's remaining time. Uses a self-updating countdown ("24:13", "1:20:13") when
/// timing is known, so it stays exact without widget reloads; otherwise falls back to the
/// fetched short text. Past the expected end it reads "Finishing".
/// (A clock time like "15:27" is avoided here: in 24-hour locales it reads like a countdown.)
struct DeviceMetricText: View {
    let device: WidgetDevice
    var date: Date = .now

    var body: some View {
        if device.name != "Car", device.running, let end = device.endDate {
            if end <= date {
                Text("Finishing")
            } else if let interval = device.timerInterval(now: date) {
                Text(timerInterval: interval, countsDown: true, showsHours: true)
                    .monospacedDigit()
            } else {
                Text(widgetMetric(for: device))
            }
        } else {
            Text(widgetMetric(for: device))
        }
    }
}

/// Linear progress that advances on its own when timing is available.
struct DeviceProgressBar: View {
    let device: WidgetDevice
    var date: Date = .now

    var body: some View {
        PaletteReader { palette in
            Group {
                if device.name != "Car", let interval = device.timerInterval(now: date), device.startDate != nil {
                    ProgressView(timerInterval: interval, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                } else {
                    ProgressView(value: widgetProgress(for: device))
                        .progressViewStyle(.linear)
                }
            }
            .tint(palette.tint(for: device))
            .widgetAccentable()
        }
    }
}

// MARK: - Building blocks

struct DeviceIcon: View {
    let device: WidgetDevice
    var size: CGFloat = 28

    var body: some View {
        PaletteReader { palette in
            Image(systemName: device.icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(isLive(device) ? palette.tint(for: device) : palette.secondary)
                .widgetAccentable()
                .frame(width: size, height: size)
                .background(Circle().fill(palette.fill(palette.tint(for: device))))
                .accessibilityHidden(true)
        }
    }
}

struct SymbolBubble: View {
    let systemName: String
    var color: Color = .accentColor
    var size: CGFloat = 28

    var body: some View {
        PaletteReader { palette in
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(palette.tint(color))
                .widgetAccentable()
                .frame(width: size, height: size)
                .background(Circle().fill(palette.fill(color)))
                .accessibilityHidden(true)
        }
    }
}

struct EmptyStateView: View {
    var message = "Open FluxHaus to sign in"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.title2)
                .widgetAccentable()
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cache

/// Small JSON cache in the extension's own defaults, used when a fetch fails.
enum WidgetCache {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// True when the user is signed in (OIDC token or demo password).
    static var hasCredentials: Bool {
        AuthManager.shared.authorizationHeader() != nil || !(WhereWeAre.getPassword() ?? "").isEmpty
    }
}
