//
//  HomeWidget.swift
//  FluxWidget
//
//  Home widget: temperature inside and out, air quality, and power draw.
//

import Charts
import SwiftUI
import WidgetKit

// MARK: - Data

struct HomeSnapshot: Codable {
    var indoorTemp: Double?
    var outdoorTemp: Double?
    var outdoorTrend: [Double]
    var aqhi: Double?
    var pm25Indoor: Double?
    var pm25Outdoor: Double?
    var powerWatts: Double?

    static let preview = HomeSnapshot(
        indoorTemp: 21.4, outdoorTemp: 7.8,
        outdoorTrend: [5, 5.4, 6, 6.8, 7.5, 8.1, 8.4, 8.2, 7.8],
        aqhi: 3, pm25Indoor: 4.2, pm25Outdoor: 11, powerWatts: 640
    )
}

enum HomeStore {
    private static let cacheKey = "FluxWidget.home"

    static func load() async -> HomeSnapshot? {
        guard WidgetCache.hasCredentials else {
            WidgetCache.clear(key: cacheKey)
            return nil
        }
        let fetched = await fetchSeries()
        let temp = fetched.temperature, air = fetched.airQuality
        let aqhiSeries = fetched.aqhi, powerSeries = fetched.power

        guard temp != nil || air != nil || aqhiSeries != nil || powerSeries != nil else {
            return WidgetCache.load(HomeSnapshot.self, key: cacheKey)
        }

        let outdoor = temp?.series.first { $0.name.lowercased() == "outside" }
        let indoor = temp?.series.first { $0.name.lowercased().contains("home") }
            ?? temp?.series.first { $0.name.lowercased() != "outside" }
        let trend = (outdoor?.points.map(\.value) ?? []).downsampled(to: 24)
        let aqhiValue = (aqhiSeries?.series.first { $0.name.lowercased().contains("canada") }
            ?? aqhiSeries?.series.first)?.points.last?.value

        let snapshot = HomeSnapshot(
            indoorTemp: indoor?.points.last?.value,
            outdoorTemp: outdoor?.points.last?.value,
            outdoorTrend: trend,
            aqhi: aqhiValue,
            pm25Indoor: air?.series.first { $0.name.lowercased() == "indoor" }?.points.last?.value,
            pm25Outdoor: air?.series.first { $0.name.lowercased() == "outdoor" }?.points.last?.value,
            powerWatts: powerSeries?.series.first?.points.last?.value
        )
        WidgetCache.save(snapshot, key: cacheKey)
        return snapshot
    }
}

extension HomeStore {
    struct FetchedSeries {
        var temperature: MetricSeriesResponse?
        var airQuality: MetricSeriesResponse?
        var aqhi: MetricSeriesResponse?
        var power: MetricSeriesResponse?
    }

    @MainActor
    static func fetchSeries() async -> FetchedSeries {
        let service = MetricsService()
        return FetchedSeries(
            temperature: await service.fetchSeries(metricId: "temperature", range: .sixHours),
            airQuality: await service.fetchSeries(metricId: "air_quality", range: .hour),
            aqhi: await service.fetchSeries(metricId: "outdoor_air_quality", range: .sixHours),
            power: await service.fetchSeries(metricId: "power_draw", range: .hour)
        )
    }
}

private extension Array where Element == Double {
    func downsampled(to count: Int) -> [Double] {
        guard self.count > count, count > 1 else { return self }
        let step = Double(self.count - 1) / Double(count - 1)
        return (0..<count).map { self[Int((Double($0) * step).rounded())] }
    }
}

func aqhiColor(_ value: Double) -> Color {
    switch value {
    case ..<4: return .green
    case ..<7: return .yellow
    case ..<10: return .orange
    default: return .red
    }
}

func aqhiLabel(_ value: Double) -> String {
    switch value {
    case ..<4: return "Low risk"
    case ..<7: return "Moderate"
    case ..<10: return "High risk"
    default: return "Very high"
    }
}

private func formatTemp(_ value: Double?) -> String {
    guard let value else { return "--" }
    return "\(value.formatted(.number.precision(.fractionLength(0))))°"
}

private func formatPower(_ watts: Double) -> String {
    watts >= 1000
        ? "\((watts / 1000).formatted(.number.precision(.fractionLength(1)))) kW"
        : "\(Int(watts.rounded())) W"
}

extension HomeSnapshot {
    var temperatureSummary: String {
        "\(formatTemp(indoorTemp)) in · \(formatTemp(outdoorTemp)) out"
    }
}

// MARK: - Timeline

struct HomeEntry: TimelineEntry {
    let date: Date
    let home: HomeSnapshot?

    var relevance: TimelineEntryRelevance? {
        if let aqhi = home?.aqhi, aqhi >= 7 { return TimelineEntryRelevance(score: 80) }
        return TimelineEntryRelevance(score: 5)
    }
}

struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: Date(), home: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HomeEntry) -> Void) {
        if context.isPreview {
            completion(HomeEntry(date: Date(), home: .preview))
            return
        }
        Task { completion(HomeEntry(date: Date(), home: await HomeStore.load())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HomeEntry>) -> Void) {
        Task {
            let entry = HomeEntry(date: Date(), home: await HomeStore.load())
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(30 * 60))))
        }
    }
}

// MARK: - Views

private let homeTint = Color(red: 0.55, green: 0.80, blue: 0.62)

struct MetricChip: View {
    let icon: String
    let text: String
    var color: Color?

    var body: some View {
        PaletteReader { palette in
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color.map { palette.tint($0) } ?? palette.secondary)
                    .widgetAccentable()
                Text(text)
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.semibold))
        }
    }
}

struct HomeTemperatureBlock: View {
    let home: HomeSnapshot
    var size: CGFloat = 34

    var body: some View {
        PaletteReader { palette in
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTemp(home.indoorTemp))
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .contentTransition(.numericText())
                Text("Inside · \(formatTemp(home.outdoorTemp)) out")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct HomeSmallView: View {
    let home: HomeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SymbolBubble(systemName: "house.fill", color: homeTint, size: 28)
            Spacer(minLength: 0)
            HomeTemperatureBlock(home: home)
            HStack(spacing: 10) {
                if let aqhi = home.aqhi {
                    MetricChip(icon: "aqi.medium", text: "AQHI \(Int(aqhi.rounded()))", color: aqhiColor(aqhi))
                }
                if let power = home.powerWatts {
                    MetricChip(icon: "bolt.fill", text: formatPower(power), color: .yellow)
                }
            }
        }
    }
}

struct HomeMediumView: View {
    let home: HomeSnapshot

    var body: some View {
        PaletteReader { palette in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        SymbolBubble(systemName: "house.fill", color: homeTint, size: 28)
                        Text("Home")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer(minLength: 0)
                    HomeTemperatureBlock(home: home, size: 38)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    if home.outdoorTrend.count > 1 {
                        Chart(Array(home.outdoorTrend.enumerated()), id: \.offset) { point in
                            LineMark(x: .value("Time", point.offset), y: .value("°C", point.element))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(palette.tint(.orange))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .widgetAccentable()
                        .frame(maxHeight: 44)
                    }
                    if let aqhi = home.aqhi {
                        MetricChip(
                            icon: "aqi.medium",
                            text: "AQHI \(Int(aqhi.rounded())) · \(aqhiLabel(aqhi))",
                            color: aqhiColor(aqhi)
                        )
                    }
                    if let pm25 = home.pm25Indoor {
                        MetricChip(icon: "wind", text: "PM2.5 \(Int(pm25.rounded())) in")
                    }
                    if let power = home.powerWatts {
                        MetricChip(icon: "bolt.fill", text: formatPower(power), color: .yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct HomeWidgetEntryView: View {
    let entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let home = entry.home {
                switch family {
                case .systemMedium:
                    HomeMediumView(home: home)
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Label(home.temperatureSummary, systemImage: "house.fill")
                            .font(.headline)
                            .widgetAccentable()
                        if let aqhi = home.aqhi {
                            Text("AQHI \(Int(aqhi.rounded())) · \(aqhiLabel(aqhi))")
                                .font(.caption)
                        }
                        if let power = home.powerWatts {
                            Text("Using \(formatPower(power))")
                                .font(.caption)
                        }
                    }
                case .accessoryInline:
                    Label(home.temperatureSummary, systemImage: "house")
                default:
                    HomeSmallView(home: home)
                }
            } else if family.isSystem {
                EmptyStateView()
            } else {
                Image(systemName: "house")
            }
        }
        .widgetURL(URL(string: "fluxhaus://metrics"))
    }
}

struct FluxHomeWidget: Widget {
    let kind = "FluxHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeProvider()) { entry in
            HomeWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(tint: homeTint)
                }
        }
        .configurationDisplayName("Home")
        .description("Temperature, air quality, and power at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemMedium) {
    FluxHomeWidget()
} timeline: {
    HomeEntry(date: .now, home: .preview)
}

#Preview(as: .systemSmall) {
    FluxHomeWidget()
} timeline: {
    HomeEntry(date: .now, home: .preview)
}
