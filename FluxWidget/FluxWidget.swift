//
//  FluxWidget.swift
//  FluxWidget
//
//  Created by David Jensenius on 2024-08-01.
//

import WidgetKit
import SwiftUI
import os

private let widgetLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Widget")

// MARK: - Data

enum FluxWidgetNetwork {
    private static let cacheKey = "FluxWidget.cachedDevices"

    /// Fetches the latest device list. Never crashes: on any auth/network/decoding
    /// failure it falls back to the last successful result, if one exists.
    static func fetchStatus() async -> [WidgetDevice]? {
        let password = WhereWeAre.getPassword() ?? ""
        guard AuthManager.shared.authorizationHeader() != nil || !password.isEmpty else {
            widgetLogger.warning("Widget: no credentials available")
            return cachedDevices()
        }
        do {
            guard let loginData = try await getFlux(password: password) else {
                return cachedDevices()
            }
            let converted = convertLoginResponseToAppData(response: loginData)
            let devices = classifyWidgetData(devices: convertDataToWidgetDevices(fluxData: converted))
            cache(devices)
            return devices
        } catch {
            widgetLogger.error("Widget: fetch failed: \(error.localizedDescription)")
            return cachedDevices()
        }
    }

    static func cachedDevices() -> [WidgetDevice]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([WidgetDevice].self, from: data)
    }

    private static func cache(_ devices: [WidgetDevice]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    static func classifyWidgetData(devices: [WidgetDevice]) -> [WidgetDevice] {
        var constantDevices: [WidgetDevice] = []
        var timedRunningDevices: [WidgetDevice] = []
        var runningDevices: [WidgetDevice] = []
        var offDevices: [WidgetDevice] = []

        devices.forEach { device in
            switch device.name {
            case "Car", "Battery":
                constantDevices.append(device)
            case "Cleanbot":
                if device.running {
                    runningDevices.append(device)
                } else {
                    offDevices.append(device)
                }
            default:
                if device.running {
                    timedRunningDevices.append(device)
                } else {
                    offDevices.append(device)
                }
            }
        }
        timedRunningDevices = sortTimedDevices(devices: timedRunningDevices)
        var sortedDevices: [WidgetDevice] = timedRunningDevices
        sortedDevices += runningDevices
        sortedDevices += constantDevices
        sortedDevices += offDevices
        return sortedDevices
    }

    /// Most-progressed (soonest to finish) first.
    static func sortTimedDevices(devices: [WidgetDevice]) -> [WidgetDevice] {
        devices.sorted { $0.progress > $1.progress }
    }

    /// Refresh more often while an appliance is running so countdowns stay fresh,
    /// and back off when the house is idle to preserve the WidgetKit budget.
    static func nextRefresh(for devices: [WidgetDevice], from date: Date) -> Date {
        let minutes = devices.contains(where: isActive) ? 10 : 30
        return date.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

/// A device that is doing something right now (excludes always-on constants like Car).
func isActive(_ device: WidgetDevice) -> Bool {
    device.running && device.name != "Car" && device.name != "Battery"
}

// MARK: - Timeline

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), widgetDevices: staticList)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        if context.isPreview {
            return SimpleEntry(date: Date(), configuration: configuration, widgetDevices: staticList)
        }
        let devices = await FluxWidgetNetwork.fetchStatus() ?? staticList
        return SimpleEntry(date: Date(), configuration: configuration, widgetDevices: devices)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let now = Date()
        guard let devices = await FluxWidgetNetwork.fetchStatus() else {
            // Nothing fetched and nothing cached (signed out / offline first run): retry soon.
            let entry = SimpleEntry(date: now, configuration: configuration, widgetDevices: [])
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60)))
        }
        let entry = SimpleEntry(date: now, configuration: configuration, widgetDevices: devices)
        return Timeline(entries: [entry], policy: .after(FluxWidgetNetwork.nextRefresh(for: devices, from: now)))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let widgetDevices: [WidgetDevice]

    var activeDevices: [WidgetDevice] { widgetDevices.filter(isActive) }
    /// Device to feature: the soonest-finishing active appliance, else the car, else anything.
    var featured: WidgetDevice? {
        activeDevices.first ?? widgetDevices.first { $0.name == "Car" } ?? widgetDevices.first
    }
}

// MARK: - Styling helpers

/// Resolves colors for the current rendering context. In accented (tinted Home Screen)
/// and vibrant (Lock Screen / StandBy night) modes the system recolors content, so we
/// use semantic styles there and let `.widgetAccentable()` mark highlight content.
struct WidgetPalette {
    let renderingMode: WidgetRenderingMode
    let showsBackground: Bool

    private var isFullColor: Bool { renderingMode == .fullColor }

    var primary: Color { isFullColor && showsBackground ? Theme.Colors.textPrimary : .primary }
    var secondary: Color { isFullColor && showsBackground ? Theme.Colors.textSecondary : .secondary }

    func tint(for device: WidgetDevice) -> Color {
        guard isFullColor else { return .primary }
        if device.name == "Car" { return batteryColor(level: device.progress) }
        return liveActivityProgressColor(for: device)
    }

    func bubbleFill(for device: WidgetDevice, reducedLuminance: Bool) -> Color {
        guard isFullColor, !reducedLuminance else { return .primary.opacity(0.12) }
        return tint(for: device).opacity(0.18)
    }
}

private struct PaletteReader<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @ViewBuilder var content: (WidgetPalette) -> Content

    var body: some View {
        content(WidgetPalette(renderingMode: renderingMode, showsBackground: showsBackground))
    }
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

// MARK: - Building blocks

struct DeviceIcon: View {
    let device: WidgetDevice
    var size: CGFloat = 28
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        PaletteReader { palette in
            Image(systemName: device.icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(device.running || device.name == "Car" ? palette.tint(for: device) : palette.secondary)
                .widgetAccentable()
                .frame(width: size, height: size)
                .background(Circle().fill(palette.bubbleFill(for: device, reducedLuminance: isLuminanceReduced)))
                .accessibilityHidden(true)
        }
    }
}

struct DeviceProgressBar: View {
    let device: WidgetDevice

    var body: some View {
        PaletteReader { palette in
            Gauge(value: widgetProgress(for: device)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(palette.tint(for: device))
                .widgetAccentable()
        }
    }
}

/// One row: icon, name/subtitle, metric, and an optional progress bar.
struct DeviceRow: View {
    let device: WidgetDevice
    var showsProgress = true

    var body: some View {
        PaletteReader { palette in
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    DeviceIcon(device: device, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(device.running || device.name == "Car" ? palette.primary : palette.secondary)
                        if device.running || device.name == "Car" {
                            Text(widgetSubtitle(for: device))
                                .font(.caption2)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(widgetMetric(for: device))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(device.running || device.name == "Car" ? palette.primary : palette.secondary)
                        .lineLimit(1)
                }
                if showsProgress && (device.running || device.name == "Car") {
                    DeviceProgressBar(device: device)
                }
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.title2)
                .widgetAccentable()
            Text("Open FluxHaus to sign in")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - System families

/// systemSmall: one featured device, big and glanceable (great in StandBy).
struct SmallFeaturedView: View {
    let entry: SimpleEntry

    var body: some View {
        if let device = entry.featured {
            PaletteReader { palette in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        DeviceIcon(device: device, size: 30)
                        Spacer()
                        let others = entry.activeDevices.filter { $0.name != device.name }.count
                        if others > 0 {
                            Text("+\(others)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                    Text(widgetMetric(for: device))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text(widgetSubtitle(for: device))
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                    DeviceProgressBar(device: device)
                }
            }
        } else {
            EmptyStateView()
        }
    }
}

/// systemSmall (grid variant): up to four circular gauges.
struct SmallDeviceGridView: View {
    let items: [WidgetDevice]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        if items.isEmpty {
            EmptyStateView()
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items.prefix(4), id: \.name) { item in
                    SingleView(item: item, multipleLines: false)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// systemMedium / systemLarge: list of rows.
struct DeviceListView: View {
    let entry: SimpleEntry
    let limit: Int
    var showsHeader = false

    var body: some View {
        if entry.widgetDevices.isEmpty {
            EmptyStateView()
        } else {
            PaletteReader { palette in
                VStack(alignment: .leading, spacing: 8) {
                    if showsHeader {
                        HStack {
                            Text("FluxHaus")
                                .font(.headline)
                                .foregroundStyle(palette.primary)
                            Spacer()
                            Text(headerSummary)
                                .font(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    ForEach(entry.widgetDevices.prefix(limit), id: \.name) { device in
                        DeviceRow(device: device)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var headerSummary: String {
        let count = entry.activeDevices.count
        return count == 0 ? "All quiet" : "\(count) running"
    }
}

/// systemExtraLarge (iPad): two columns of rows.
struct DeviceColumnsView: View {
    let entry: SimpleEntry

    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        if entry.widgetDevices.isEmpty {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("FluxHaus")
                    .font(.title3.weight(.semibold))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(entry.widgetDevices, id: \.name) { device in
                        DeviceRow(device: device)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Accessory families

struct InlineView: View {
    let entry: SimpleEntry

    var body: some View {
        if let item = entry.featured {
            Label(
                "\(item.name) \(widgetMetric(for: item))",
                systemImage: item.icon
            )
        } else {
            Label("FluxHaus", systemImage: "house")
        }
    }
}

struct SingleView: View {
    var item: WidgetDevice
    var multipleLines = true

    var body: some View {
        PaletteReader { palette in
            VStack(spacing: 2) {
                Gauge(value: widgetProgress(for: item)) {
                    Image(systemName: item.icon)
                } currentValueLabel: {
                    Text(multipleLines ? "\(Int(widgetProgress(for: item) * 100))%" : shortLabel)
                        .minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(palette.tint(for: item))
                .widgetAccentable()
                if multipleLines {
                    Text(shortLabel)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var shortLabel: String {
        if item.name == "Car" { return "\(item.progress)%" }
        if !item.running { return "Off" }
        if isRobot(item.name) { return item.battery.map { "\($0)%" } ?? "On" }
        return item.shortText.isEmpty ? "\(item.progress)%" : item.shortText
    }
}

struct AccessoryCircularView: View {
    let entry: SimpleEntry

    var body: some View {
        if let item = entry.featured {
            ZStack {
                AccessoryWidgetBackground()
                SingleView(item: item, multipleLines: false)
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "house.fill")
            }
        }
    }
}

struct AccessoryRectangularView: View {
    var items: [WidgetDevice]

    var body: some View {
        if items.isEmpty {
            Label("Open FluxHaus", systemImage: "house")
                .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.prefix(3), id: \.name) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.caption)
                            .frame(width: 16)
                            .widgetAccentable()
                        if item.running || item.name == "Car" {
                            Gauge(value: widgetProgress(for: item)) { EmptyView() }
                                .gaugeStyle(.accessoryLinearCapacity)
                            Text(widgetMetric(for: item))
                                .font(.caption)
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                        } else {
                            Text("\(item.name) off")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Entry view

struct FluxWidgetEntryView: View {
    var entry: Provider.Entry
    var grid = false
    @Environment(\.widgetFamily) var family

    var body: some View {
        content
            .widgetURL(URL(string: "fluxhaus://appliances"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            if grid {
                SmallDeviceGridView(items: entry.widgetDevices)
            } else {
                SmallFeaturedView(entry: entry)
            }
        case .systemMedium:
            DeviceListView(entry: entry, limit: 3)
        case .systemLarge:
            DeviceListView(entry: entry, limit: 6, showsHeader: true)
        case .systemExtraLarge:
            DeviceColumnsView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(items: entry.widgetDevices)
        case .accessoryInline:
            InlineView(entry: entry)
        default:
            EmptyView()
        }
    }
}

struct FluxWidget: Widget {
    let kind: String = "FluxWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            FluxWidgetEntryView(entry: entry)
                .containerBackground(Theme.Colors.background, for: .widget)
        }
        .configurationDisplayName("FluxHaus")
        .description("Appliance progress, Cleanbot, and car battery at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct FluxWidgetOtherSmall: Widget {
    let kind: String = "FluxWidgetSmall"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            FluxWidgetEntryView(entry: entry, grid: true)
                .containerBackground(Theme.Colors.background, for: .widget)
        }
        .configurationDisplayName("FluxHaus Grid")
        .description("Up to four devices as compact gauges.")
        .supportedFamilies([
            .systemSmall
        ])
    }
}

// MARK: - Preview data

let staticList = [
    WidgetDevice(
        name: "Dryer",
        progress: 75,
        icon: "dryer",
        trailingText: "Cotton ⋅ 25m",
        shortText: "25m",
        running: true,
        programName: "Cotton"
    ),
    WidgetDevice(
        name: "Washer",
        progress: 45,
        icon: "washer",
        trailingText: "Cottons ⋅ 4:12 PM",
        shortText: "4:12 PM",
        running: true,
        programName: "Cottons"
    ),
    WidgetDevice(
        name: "Cleanbot",
        progress: 60,
        icon: "robotic.vacuum.fill",
        trailingText: "~12 min ⋅ Kitchen",
        shortText: "60%",
        running: true,
        battery: 85
    ),
    WidgetDevice(
        name: "Car",
        progress: 45,
        icon: "car",
        trailingText: "Range 200 km ⋅ 45%",
        shortText: "200 km",
        running: false
    ),
    WidgetDevice(
        name: "Dishwasher",
        progress: 0,
        icon: "dishwasher",
        trailingText: "",
        shortText: "",
        running: false
    )
]

private let previewEntry = SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), widgetDevices: staticList)
private let emptyEntry = SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), widgetDevices: [])

#Preview(as: .systemSmall) {
    FluxWidget()
} timeline: {
    previewEntry
    emptyEntry
}

#Preview(as: .systemSmall) {
    FluxWidgetOtherSmall()
} timeline: {
    previewEntry
}

#Preview(as: .systemMedium) {
    FluxWidget()
} timeline: {
    previewEntry
}

#Preview(as: .systemLarge) {
    FluxWidget()
} timeline: {
    previewEntry
}

#Preview(as: .systemExtraLarge) {
    FluxWidget()
} timeline: {
    previewEntry
}

#Preview(as: .accessoryCircular) {
    FluxWidget()
} timeline: {
    previewEntry
}

#Preview(as: .accessoryRectangular) {
    FluxWidget()
} timeline: {
    previewEntry
}

#Preview(as: .accessoryInline) {
    FluxWidget()
} timeline: {
    previewEntry
}
