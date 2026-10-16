// swiftlint:disable file_length
//
//  FluxWidget.swift
//  FluxWidget
//
//  Appliances widget: "when is it done?" Features the appliance that finishes next,
//  with self-updating countdowns, and a calm idle state when nothing is running.
//
//  Created by David Jensenius on 2024-08-01.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), snapshot: .preview)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        if context.isPreview {
            return SimpleEntry(date: Date(), configuration: configuration, snapshot: .preview)
        }
        let snapshot = await FluxWidgetNetwork.fetchSnapshot()
        return SimpleEntry(date: Date(), configuration: configuration, snapshot: snapshot)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let now = Date()
        guard let snapshot = await FluxWidgetNetwork.fetchSnapshot() else {
            // Signed out or nothing cached yet: show the sign-in state and retry later.
            let entry = SimpleEntry(date: now, configuration: configuration, snapshot: nil)
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60)))
        }
        let refresh = FluxWidgetNetwork.nextRefresh(for: snapshot.devices, from: now)
        let dates = [now] + FluxWidgetNetwork.transitionDates(for: snapshot.devices, from: now, until: refresh)
        let entries = dates.map { SimpleEntry(date: $0, configuration: configuration, snapshot: snapshot) }
        return Timeline(entries: entries, policy: .after(refresh))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let snapshot: FluxSnapshot?

    var widgetDevices: [WidgetDevice] { snapshot?.devices ?? [] }
    var activeDevices: [WidgetDevice] { widgetDevices.filter(isActive) }
    var car: WidgetDevice? { widgetDevices.first { $0.name == "Car" } }

    /// The device to feature. Automatic: the soonest-finishing active appliance, or nil
    /// when the house is idle. A configured device is always featured.
    var featured: WidgetDevice? {
        if let name = configuration.device.deviceName {
            return widgetDevices.first { $0.name == name }
        }
        return activeDevices.first
    }

    var others: [WidgetDevice] {
        widgetDevices.filter { $0.name != featured?.name }
    }

    /// Most recent appliance finish, for the idle state.
    var lastFinished: (name: String, date: Date)? {
        guard let latest = snapshot?.finishedAt.max(by: { $0.value < $1.value }) else { return nil }
        guard date.timeIntervalSince(latest.value) < 12 * 3600 else { return nil }
        return (latest.key, latest.value)
    }

    /// Smart Stack / StandBy rotation: surface when something is about to finish.
    var relevance: TimelineEntryRelevance? {
        let soonest = activeDevices.compactMap(\.endDate).filter { $0 > date }.min()
        if let soonest, soonest.timeIntervalSince(date) <= 15 * 60 {
            return TimelineEntryRelevance(score: 100, duration: soonest.timeIntervalSince(date) + 300)
        }
        if lastFinished.map({ date.timeIntervalSince($0.date) < 30 * 60 }) == true {
            return TimelineEntryRelevance(score: 60, duration: 30 * 60)
        }
        if !activeDevices.isEmpty { return TimelineEntryRelevance(score: 40) }
        return TimelineEntryRelevance(score: 1)
    }

    var backgroundTint: Color? {
        featured.map { $0.name == "Car" ? batteryColor(level: $0.progress) : tintColor(for: $0.name) }
    }
}

// MARK: - Hero (featured device)

/// Big, glanceable featured device: icon + name, large countdown, program, progress.
struct HeroView: View {
    let device: WidgetDevice
    let date: Date
    var extraCount = 0
    var metricSize: CGFloat = 34

    var body: some View {
        PaletteReader { palette in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    DeviceIcon(device: device, size: 28)
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if extraCount > 0 {
                        Text("+\(extraCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.secondary)
                    }
                }
                Spacer(minLength: 0)
                DeviceMetricText(device: device, date: date)
                    .font(.system(size: metricSize, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                heroSubtitle
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                if isLive(device) {
                    DeviceProgressBar(device: device, date: date)
                }
            }
        }
    }

    /// "Cotton · done 4:12 PM" when the finish time is known.
    private var heroSubtitle: Text {
        guard device.running, !isRobot(device.name), let end = device.endDate, end > date else {
            return Text(widgetSubtitle(for: device))
        }
        if let program = device.programName, !program.isEmpty {
            return Text("\(program) · done \(Text(end, style: .time))")
        }
        return Text("Done \(Text(end, style: .time))")
    }
}

// MARK: - Idle state

struct IdleView: View {
    let entry: SimpleEntry
    var showsCar = true

    var body: some View {
        PaletteReader { palette in
            VStack(alignment: .leading, spacing: 4) {
                SymbolBubble(systemName: "checkmark", color: Theme.Colors.success, size: 28)
                Spacer(minLength: 0)
                Text("All quiet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let finished = entry.lastFinished {
                    Text("\(finished.name) finished \(finished.date, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                } else {
                    Text("Nothing running")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                }
                if showsCar, let car = entry.car {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                            .widgetAccentable()
                        Text("\(car.progress)% · \(car.shortText)")
                            .monospacedDigit()
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Rows

/// Compact one-line row used beside the hero: icon, name, live metric.
struct CompactRow: View {
    let device: WidgetDevice
    let date: Date

    var body: some View {
        PaletteReader { palette in
            HStack(spacing: 6) {
                DeviceIcon(device: device, size: 22)
                Text(device.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isLive(device) ? palette.primary : palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                DeviceMetricText(device: device, date: date)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isLive(device) ? palette.primary : palette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Full row with progress bar, used in the large layouts.
struct DeviceRow: View {
    let device: WidgetDevice
    let date: Date

    var body: some View {
        PaletteReader { palette in
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    DeviceIcon(device: device, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isLive(device) ? palette.primary : palette.secondary)
                        if isLive(device) {
                            Text(widgetSubtitle(for: device))
                                .font(.caption2)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    DeviceMetricText(device: device, date: date)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isLive(device) ? palette.primary : palette.secondary)
                        .lineLimit(1)
                }
                if isLive(device) {
                    DeviceProgressBar(device: device, date: date)
                }
            }
        }
    }
}

// MARK: - Families

struct ApplianceSmallView: View {
    let entry: SimpleEntry

    var body: some View {
        if let device = entry.featured {
            HeroView(
                device: device,
                date: entry.date,
                extraCount: entry.activeDevices.filter { $0.name != device.name }.count
            )
        } else {
            IdleView(entry: entry)
        }
    }
}

struct ApplianceMediumView: View {
    let entry: SimpleEntry

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let device = entry.featured {
                    HeroView(device: device, date: entry.date)
                } else {
                    IdleView(entry: entry, showsCar: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.others.prefix(4), id: \.name) { device in
                    CompactRow(device: device, date: entry.date)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ApplianceLargeView: View {
    let entry: SimpleEntry

    var body: some View {
        PaletteReader { palette in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("FluxHaus")
                        .font(.headline)
                        .foregroundStyle(palette.primary)
                    Spacer()
                    Text(entry.activeDevices.isEmpty ? "All quiet" : "\(entry.activeDevices.count) running")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.secondary)
                }
                Group {
                    if let device = entry.featured {
                        HeroView(device: device, date: entry.date, metricSize: 44)
                    } else {
                        IdleView(entry: entry, showsCar: false)
                    }
                }
                .frame(height: 110)
                Divider()
                VStack(spacing: 8) {
                    ForEach(entry.others.prefix(4), id: \.name) { device in
                        DeviceRow(device: device, date: entry.date)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct ApplianceExtraLargeView: View {
    let entry: SimpleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Group {
                if let device = entry.featured {
                    HeroView(device: device, date: entry.date, metricSize: 56)
                } else {
                    IdleView(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 14) {
                ForEach(entry.others, id: \.name) { device in
                    DeviceRow(device: device, date: entry.date)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Accessory families

struct ApplianceCircularView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let device = entry.featured ?? entry.car {
                // Date-relative ProgressView doesn't support the circular style, so use a
                // capacity gauge at the entry's progress (entries advance it every 5 min).
                Gauge(value: widgetProgress(for: device, at: entry.date)) {
                    Image(systemName: device.icon)
                } currentValueLabel: {
                    Image(systemName: device.icon)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            } else {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.semibold))
                    .widgetAccentable()
            }
        }
    }
}

struct ApplianceRectangularView: View {
    let entry: SimpleEntry

    var body: some View {
        if let device = entry.featured {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: device.icon)
                        .widgetAccentable()
                    Text(device.name)
                    let extra = entry.activeDevices.filter { $0.name != device.name }.count
                    if extra > 0 {
                        Spacer(minLength: 0)
                        Text("+\(extra)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.semibold))
                DeviceMetricText(device: device, date: entry.date)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                DeviceProgressBar(device: device, date: entry.date)
            }
        } else if entry.snapshot == nil {
            Label("Open FluxHaus", systemImage: "house")
                .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("All quiet", systemImage: "checkmark.circle")
                    .font(.headline)
                    .widgetAccentable()
                if let finished = entry.lastFinished {
                    Text("\(finished.name) finished \(finished.date, format: .relative(presentation: .named))")
                        .font(.caption)
                        .lineLimit(2)
                } else if let car = entry.car {
                    Text("Car \(car.progress)% · \(car.shortText)")
                        .font(.caption)
                }
            }
        }
    }
}

struct ApplianceInlineView: View {
    let entry: SimpleEntry

    var body: some View {
        if let device = entry.featured, device.running, let end = device.endDate, end > entry.date {
            Label {
                Text("\(device.name) done \(Text(end, style: .time))")
            } icon: {
                Image(systemName: device.icon)
            }
        } else if let device = entry.featured {
            Label("\(device.name) \(widgetMetric(for: device))", systemImage: device.icon)
        } else {
            Label("All quiet", systemImage: "checkmark.circle")
        }
    }
}

// MARK: - Entry view

struct FluxWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        content
            .widgetURL(URL(string: "fluxhaus://appliances"))
    }

    @ViewBuilder
    private var content: some View {
        if entry.snapshot == nil, family.isSystem {
            EmptyStateView()
        } else if family.isSystem {
            LevelOfDetailSwitch {
                systemContent
            } glance: {
                ApplianceGlanceView(entry: entry)
            }
        } else {
            switch family {
            case .systemSmall: ApplianceSmallView(entry: entry)
            case .systemMedium: ApplianceMediumView(entry: entry)
            case .systemLarge: ApplianceLargeView(entry: entry)
            case .systemExtraLarge: ApplianceExtraLargeView(entry: entry)
            case .accessoryCircular: ApplianceCircularView(entry: entry)
            case .accessoryRectangular: ApplianceRectangularView(entry: entry)
            #if !os(visionOS)
            case .accessoryInline: ApplianceInlineView(entry: entry)
            #endif
            default: EmptyView()
            }
        }
    }
}

extension FluxWidgetEntryView {
    @ViewBuilder
    fileprivate var systemContent: some View {
        switch family {
        case .systemSmall: ApplianceSmallView(entry: entry)
        case .systemMedium: ApplianceMediumView(entry: entry)
        case .systemLarge: ApplianceLargeView(entry: entry)
        default: ApplianceExtraLargeView(entry: entry)
        }
    }
}

/// Simplified (distance) view for visionOS.
struct ApplianceGlanceView: View {
    let entry: SimpleEntry

    var body: some View {
        if let device = entry.featured {
            GlanceView(systemName: device.icon, color: tintColor(for: device.name), label: device.name) {
                DeviceMetricText(device: device, date: entry.date)
            }
        } else {
            GlanceView(systemName: "checkmark.circle.fill", color: .green, label: "Nothing running") {
                Text("All quiet")
            }
        }
    }
}

extension WidgetFamily {
    var isSystem: Bool {
        switch self {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: return true
        default: return false
        }
    }
}

struct FluxWidget: Widget {
    let kind: String = "FluxWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            FluxWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(tint: entry.backgroundTint)
                }
        }
        .configurationDisplayName("Appliances")
        .description("What finishes next, with a live countdown.")
        .supportedFamilies(Self.families)
        .fluxPlatformStyle()
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
         .accessoryInline, .accessoryCircular, .accessoryRectangular]
        #elseif os(visionOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #endif
    }
}

// MARK: - Grid widget

struct GridGauge: View {
    let item: WidgetDevice
    let date: Date

    var body: some View {
        PaletteReader { palette in
            // Robots are labelled with battery, so the ring shows battery too.
            Gauge(value: isRobot(item.name) ? widgetProgress(for: item) : widgetProgress(for: item, at: date)) {
                Image(systemName: item.icon)
            } currentValueLabel: {
                Text(shortLabel)
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(palette.tint(for: item))
            .widgetAccentable()
            .opacity(isLive(item) ? 1 : 0.55)
        }
    }

    private var shortLabel: String {
        if item.name == "Car" { return "\(item.progress)%" }
        if !item.running { return "Off" }
        if isRobot(item.name) { return item.battery.map { "\($0)%" } ?? "On" }
        if let end = item.endDate {
            guard end > date else { return "Done" }
            let minutes = Int(end.timeIntervalSince(date) / 60)
            return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
        }
        return item.shortText.isEmpty ? "\(item.progress)%" : item.shortText
    }
}

struct GridEntryView: View {
    var entry: Provider.Entry

    /// Up to four devices, with a configured featured device always included first.
    private var gridDevices: [WidgetDevice] {
        guard entry.configuration.device != .automatic, let featured = entry.featured else {
            return Array(entry.widgetDevices.prefix(4))
        }
        return Array(([featured] + entry.widgetDevices.filter { $0.name != featured.name }).prefix(4))
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Group {
            if entry.widgetDevices.isEmpty {
                EmptyStateView()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(gridDevices, id: \.name) { item in
                        GridGauge(item: item, date: entry.date)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .widgetURL(URL(string: "fluxhaus://appliances"))
    }
}

struct FluxWidgetOtherSmall: Widget {
    let kind: String = "FluxWidgetSmall"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            GridEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Device Grid")
        .description("Up to four devices as compact gauges.")
        .supportedFamilies([.systemSmall])
        .fluxPlatformStyle()
    }
}

// MARK: - Preview data

extension FluxSnapshot {
    static var preview: FluxSnapshot {
        let now = Date().timeIntervalSince1970
        return FluxSnapshot(
            fetchedAt: Date(),
            devices: [
                WidgetDevice(
                    name: "Dryer", progress: 75, icon: "dryer",
                    trailingText: "Cotton ⋅ 25m", shortText: "25m", running: true,
                    programName: "Cotton", startedAt: now - 75 * 60, endsAt: now + 25 * 60
                ),
                WidgetDevice(
                    name: "Washer", progress: 45, icon: "washer",
                    trailingText: "Cottons ⋅ 4:12 PM", shortText: "4:12 PM", running: true,
                    programName: "Cottons", startedAt: now - 60 * 60, endsAt: now + 80 * 60
                ),
                WidgetDevice(
                    name: "Cleanbot", progress: 60, icon: "robotic.vacuum.fill",
                    trailingText: "~12 min ⋅ Kitchen", shortText: "60%", running: true, battery: 85
                ),
                WidgetDevice(
                    name: "Car", progress: 72, icon: "car",
                    trailingText: "Range 310 km ⋅ 72%", shortText: "310 km", running: false
                ),
                WidgetDevice(
                    name: "Dishwasher", progress: 0, icon: "dishwasher",
                    trailingText: "", shortText: "", running: false
                )
            ],
            car: CarSnapshot(battery: 72, range: 310, locked: true, climateOn: false, pluggedIn: true, charging: true),
            finishedAt: ["Dishwasher": Date().addingTimeInterval(-2 * 3600)]
        )
    }

    static var idlePreview: FluxSnapshot {
        var snapshot = preview
        snapshot.devices = snapshot.devices.map {
            var device = $0
            if device.name != "Car" { device.running = false }
            return device
        }
        return snapshot
    }
}

#Preview(as: .systemSmall) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .preview)
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .idlePreview)
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: nil)
}

#Preview(as: .systemMedium) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .preview)
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .idlePreview)
}

#Preview(as: .systemLarge) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .preview)
}

#if os(iOS)
#Preview(as: .accessoryRectangular) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .preview)
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .idlePreview)
}

#Preview(as: .accessoryCircular) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .preview)
}
#endif

#Preview(as: .systemSmall) {
    FluxWidgetOtherSmall()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: .preview)
}
