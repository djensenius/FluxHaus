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
            #if !os(visionOS)
            // On visionOS the system glass texture is the background; only add the tint.
            Theme.Colors.background
            #endif
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

// MARK: - Level of detail (visionOS)

/// On visionOS, widgets seen from across the room switch to a simplified level of detail.
/// Shows `glance` then; everywhere else (and up close) shows `full`.
struct LevelOfDetailSwitch<Full: View, Glance: View>: View {
    @ViewBuilder var full: () -> Full
    @ViewBuilder var glance: () -> Glance
    #if os(visionOS)
    @Environment(\.levelOfDetail) private var levelOfDetail
    #endif

    var body: some View {
        #if os(visionOS)
        if levelOfDetail == .simplified {
            glance()
        } else {
            full()
        }
        #else
        full()
        #endif
    }
}

/// Distance-readable layout: one icon, one big value, one short label.
struct GlanceView<Value: View>: View {
    let systemName: String
    let color: Color
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        PaletteReader { palette in
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(palette.tint(color))
                    .widgetAccentable()
                value()
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(palette.primary)
                Text(label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Platform presentation

extension WidgetConfiguration {
    /// Per-platform presentation. On visionOS widgets live on walls and surfaces: allow
    /// both elevated (on a surface) and recessed (set into a wall) mounting, with a glass
    /// texture that picks up the room.
    func fluxPlatformStyle() -> some WidgetConfiguration {
        #if os(visionOS)
        self
            .supportedMountingStyles([.elevated, .recessed])
            .widgetTexture(.glass)
        #else
        self
        #endif
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
    // Untimed but "running" usually means paused, needs action, or an error; the status
    // is carried in trailingText ("Paused ⋅ Cotton ⋅ 25m"), so keep it visible.
    if device.endsAt == nil, !device.trailingText.isEmpty { return device.trailingText }
    if let program = device.programName, !program.isEmpty { return program }
    return "Running"
}

/// Progress at `date`, advancing with the clock when timing is known (for gauges that
/// can't animate on their own).
func widgetProgress(for device: WidgetDevice, at date: Date) -> Double {
    guard device.name != "Car", device.running, let end = device.endDate else {
        return widgetProgress(for: device)
    }
    guard let start = device.startDate, end > start else { return widgetProgress(for: device) }
    return min(max(date.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
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
                if device.name != "Car", device.running, let end = device.endDate, end <= date {
                    // Expected end reached: stay full until fresh data arrives.
                    ProgressView(value: 1.0)
                        .progressViewStyle(.linear)
                } else if device.name != "Car", device.startDate != nil,
                          let interval = device.timerInterval(now: date) {
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
/// Every record is tagged with the auth session it was written under (see
/// `AuthManager.widgetSessionID()`), and is only ever returned for that same session,
/// so nothing cached before a sign-out or account switch can be shown afterwards.
enum WidgetCache {
    private struct Record<Value: Codable>: Codable {
        let session: String
        let value: Value
    }

    /// The current session, refreshing an expiring OIDC token first. Nil when signed out.
    static func currentSession() async -> String? {
        await AuthManager.shared.reconcileWithStoredCredentials()
        // Also restores in-memory auth state (incl. demo sign-in after the extension
        // launched signed out), which App Intents rely on.
        _ = await AuthManager.shared.ensureValidToken()
        return AuthManager.shared.widgetSessionID()
    }

    /// True if `session` is still the signed-in session (checked after awaiting requests).
    static func isCurrent(_ session: String) -> Bool {
        AuthManager.shared.widgetSessionID() == session
    }

    static func load<Value: Codable>(_ type: Value.Type, key: String, session: String) -> Value? {
        guard isCurrent(session),
              let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(Record<Value>.self, from: data),
              record.session == session else { return nil }
        return record.value
    }

    static func save<Value: Codable>(_ value: Value, key: String, session: String) {
        guard isCurrent(session),
              let data = try? JSONEncoder().encode(Record(session: session, value: value)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Synchronous variants for short-lived state (optimistic overrides) in the current session.
    static func loadCurrent<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        AuthManager.shared.widgetSessionID().flatMap { load(type, key: key, session: $0) }
    }

    static func saveCurrent<Value: Codable>(_ value: Value, key: String) {
        guard let session = AuthManager.shared.widgetSessionID() else { return }
        save(value, key: key, session: session)
    }

    /// Runs a command for the current session. The session is captured before the command
    /// is sent so optimistic state is only recorded if that same account is still signed in
    /// when it completes. Returns that session (nil if it changed meanwhile).
    /// The command receives a validity check to pass to the request layer, so it can
    /// refuse to send if the account changes while the request is being prepared.
    static func runCommand(
        expecting origin: String = "",
        _ command: (_ isStillValid: @escaping @Sendable () -> Bool) async throws -> Void
    ) async throws -> String? {
        let session = await currentSession()
        // An empty origin means "the current account" (Control Center actions).
        guard let expected = origin.isEmpty ? session : origin, isCurrent(expected) else {
            throw IntentError.notSignedIn
        }
        try await command { isCurrent(expected) }
        guard isCurrent(expected) else { return nil }
        return expected
    }

    static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Short-lived optimistic value shown after a widget/control command, because device
/// state reported by the server lags behind commands.
struct PendingValue<Value: Codable>: Codable {
    let value: Value
    let expires: Date

    static func current(key: String, now: Date = Date()) -> Value? {
        guard let pending = WidgetCache.loadCurrent(PendingValue.self, key: key), pending.expires > now else {
            return nil
        }
        return pending.value
    }

    static func set(_ value: Value, key: String, session: String, for duration: TimeInterval = 180) {
        let pending = PendingValue(value: value, expires: Date().addingTimeInterval(duration))
        WidgetCache.save(pending, key: key, session: session)
    }
}
