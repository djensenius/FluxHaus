//
//  CarWidget.swift
//  FluxWidget
//
//  Car widget: "can I leave?" Battery, range, lock and climate at a glance,
//  with interactive Lock and Climate buttons.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Optimistic state

/// The car's reported state lags behind commands, so after a widget button is tapped
/// we show the expected state for a few minutes instead of the stale one.
struct CarOverride: Codable {
    var locked: Bool?
    var climateOn: Bool?
    var expires: Date

    private static let key = "FluxWidget.carOverride"

    static func current(now: Date = Date()) -> CarOverride? {
        guard let value = WidgetCache.load(CarOverride.self, key: key), value.expires > now else { return nil }
        return value
    }

    static func set(locked: Bool? = nil, climateOn: Bool? = nil) {
        var value = current() ?? CarOverride(expires: Date())
        if let locked { value.locked = locked }
        if let climateOn { value.climateOn = climateOn }
        value.expires = Date().addingTimeInterval(3 * 60)
        WidgetCache.save(value, key: key)
    }

    func apply(to car: CarSnapshot) -> CarSnapshot {
        var car = car
        if let locked { car.locked = locked }
        if let climateOn { car.climateOn = climateOn }
        return car
    }
}

// MARK: - Intents

struct CarWidgetLockIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Car"
    static let description = IntentDescription("Lock the FluxHaus car.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await FluxIntentActions.lockCar()
        CarOverride.set(locked: true)
        return .result()
    }
}

struct CarWidgetClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Car Climate"
    static let description = IntentDescription("Start or stop the FluxHaus car's climate control.")
    static let isDiscoverable = false

    @Parameter(title: "On")
    var turnOn: Bool

    init() {}

    init(turnOn: Bool) {
        self.turnOn = turnOn
    }

    func perform() async throws -> some IntentResult {
        if turnOn {
            try await FluxIntentActions.startCarClimate(defrost: false, heatedFeatures: false, temperature: nil)
        } else {
            try await FluxIntentActions.stopCarClimate()
        }
        CarOverride.set(climateOn: turnOn)
        return .result()
    }
}

// MARK: - Timeline

struct CarEntry: TimelineEntry {
    let date: Date
    let car: CarSnapshot?
    let signedIn: Bool

    var relevance: TimelineEntryRelevance? {
        guard let car else { return nil }
        if !car.locked || !car.openings.isEmpty || car.climateOn { return TimelineEntryRelevance(score: 70) }
        if car.battery < 20 { return TimelineEntryRelevance(score: 50) }
        return TimelineEntryRelevance(score: 5)
    }
}

struct CarProvider: TimelineProvider {
    private static let preview = CarSnapshot(
        battery: 72, range: 310, locked: true, climateOn: false, pluggedIn: true, charging: true
    )

    func placeholder(in context: Context) -> CarEntry {
        CarEntry(date: Date(), car: Self.preview, signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CarEntry) -> Void) {
        if context.isPreview {
            completion(CarEntry(date: Date(), car: Self.preview, signedIn: true))
            return
        }
        Task {
            completion(await Self.entry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CarEntry>) -> Void) {
        Task {
            let entry = await Self.entry()
            let minutes = entry.car?.climateOn == true || CarOverride.current() != nil ? 5 : 30
            var next = entry.date.addingTimeInterval(TimeInterval(minutes * 60))
            if let expires = CarOverride.current()?.expires {
                // Re-check the real car state as soon as the optimistic override lapses.
                next = min(next, expires.addingTimeInterval(1))
            }
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private static func entry() async -> CarEntry {
        let snapshot = await FluxWidgetNetwork.fetchSnapshot()
        let car = snapshot?.car.map { CarOverride.current()?.apply(to: $0) ?? $0 }
        return CarEntry(date: Date(), car: car, signedIn: snapshot != nil)
    }
}

// MARK: - Views

private let carTint = Color(red: 0.36, green: 0.62, blue: 0.98)

struct CarStatusIcons: View {
    let car: CarSnapshot

    var body: some View {
        PaletteReader { palette in
            HStack(spacing: 6) {
                Image(systemName: car.locked ? "lock.fill" : "lock.open.fill")
                    .foregroundStyle(car.locked ? palette.secondary : palette.tint(.orange))
                if car.climateOn {
                    Image(systemName: "fan.fill")
                        .foregroundStyle(palette.tint(carTint))
                }
                if car.charging {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(palette.tint(.green))
                } else if car.pluggedIn {
                    Image(systemName: "powerplug.fill")
                        .foregroundStyle(palette.secondary)
                }
                if !car.openings.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.tint(.orange))
                }
            }
            .font(.caption.weight(.semibold))
            .widgetAccentable()
        }
    }
}

struct CarActionButton: View {
    let car: CarSnapshot
    let kind: Kind
    var showsLabel = false

    enum Kind { case lock, climate }

    var body: some View {
        PaletteReader { palette in
            switch kind {
            case .lock:
                if car.locked {
                    label(icon: "lock.fill", text: "Locked", active: true, palette: palette)
                } else {
                    Button(intent: CarWidgetLockIntent()) {
                        label(icon: "lock.open.fill", text: "Lock", active: false, palette: palette)
                    }
                    .buttonStyle(.plain)
                }
            case .climate:
                Button(intent: CarWidgetClimateIntent(turnOn: !car.climateOn)) {
                    label(
                        icon: car.climateOn ? "fan.fill" : "fan",
                        text: car.climateOn ? "Stop" : "Climate",
                        active: car.climateOn,
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(icon: String, text: String, active: Bool, palette: WidgetPalette) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .widgetAccentable()
            if showsLabel {
                Text(text)
                    .lineLimit(1)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(active ? palette.tint(carTint) : palette.primary)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(
            Capsule().fill(active ? palette.fill(carTint) : palette.secondary.opacity(0.15))
        )
        .accessibilityLabel(text)
    }
}

struct CarSmallView: View {
    let car: CarSnapshot

    var body: some View {
        PaletteReader { palette in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SymbolBubble(systemName: "car.fill", color: carTint, size: 28)
                    Spacer()
                    CarStatusIcons(car: car)
                }
                Spacer(minLength: 0)
                Text("\(car.battery)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                    .contentTransition(.numericText())
                Text("\(car.range) km range")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 6) {
                    CarActionButton(car: car, kind: .lock)
                    CarActionButton(car: car, kind: .climate)
                }
            }
        }
    }
}

struct CarMediumView: View {
    let car: CarSnapshot

    var body: some View {
        PaletteReader { palette in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        SymbolBubble(systemName: "car.fill", color: carTint, size: 28)
                        Text("Car")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                        Spacer(minLength: 0)
                        CarStatusIcons(car: car)
                    }
                    Spacer(minLength: 0)
                    Text("\(car.battery)%")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                    ProgressView(value: Double(car.battery) / 100)
                        .tint(palette.tint(batteryColor(level: car.battery)))
                        .widgetAccentable()
                }
                VStack(spacing: 8) {
                    CarActionButton(car: car, kind: .lock, showsLabel: true)
                    CarActionButton(car: car, kind: .climate, showsLabel: true)
                }
                .frame(width: 118)
            }
        }
    }

    private var statusLine: String {
        var parts = ["\(car.range) km"]
        if car.charging { parts.append("Charging") } else if car.pluggedIn { parts.append("Plugged in") }
        if !car.openings.isEmpty { parts.append("\(car.openings.joined(separator: ", ")) open") }
        return parts.joined(separator: " · ")
    }
}

struct CarWidgetEntryView: View {
    let entry: CarEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let car = entry.car {
                switch family {
                case .systemMedium:
                    CarMediumView(car: car)
                case .accessoryCircular:
                    Gauge(value: Double(car.battery) / 100) {
                        Image(systemName: "car.fill")
                    } currentValueLabel: {
                        Text("\(car.battery)")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetAccentable()
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "car.fill").widgetAccentable()
                            Text(car.locked ? "Locked" : "Unlocked")
                            if car.climateOn { Image(systemName: "fan.fill") }
                            if car.charging { Image(systemName: "bolt.fill") }
                        }
                        .font(.caption.weight(.semibold))
                        Text("\(car.battery)% · \(car.range) km")
                            .font(.headline)
                        ProgressView(value: Double(car.battery) / 100)
                            .widgetAccentable()
                    }
                case .accessoryInline:
                    Label("\(car.battery)% · \(car.range) km", systemImage: car.locked ? "car.fill" : "lock.open")
                default:
                    CarSmallView(car: car)
                }
            } else if family.isSystem {
                EmptyStateView(message: entry.signedIn ? "No car data" : "Open FluxHaus to sign in")
            } else {
                Image(systemName: "car")
            }
        }
        .widgetURL(URL(string: "fluxhaus://car"))
    }
}

struct FluxCarWidget: Widget {
    let kind = "FluxCarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarProvider()) { entry in
            CarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(tint: carTint)
                }
        }
        .configurationDisplayName("Car")
        .description("Battery, range, and lock status, with quick Lock and Climate buttons.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

#Preview(as: .systemSmall) {
    FluxCarWidget()
} timeline: {
    CarEntry(
        date: .now,
        car: CarSnapshot(battery: 72, range: 310, locked: true, climateOn: false, pluggedIn: true, charging: true),
        signedIn: true
    )
    CarEntry(
        date: .now,
        car: CarSnapshot(battery: 18, range: 64, locked: false, climateOn: true, pluggedIn: false, charging: false),
        signedIn: true
    )
}

#Preview(as: .systemMedium) {
    FluxCarWidget()
} timeline: {
    CarEntry(
        date: .now,
        car: CarSnapshot(battery: 72, range: 310, locked: false, climateOn: true, pluggedIn: true, charging: true),
        signedIn: true
    )
}
