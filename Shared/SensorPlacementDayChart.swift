//
//  SensorPlacementDayChart.swift
//  FluxHaus
//

import SwiftUI
import Charts

struct PlacementDayChartPoint: Identifiable {
    let id: String
    let time: Date
    let value: Double
}

struct PlacementDayChartSegment: Identifiable {
    let id: String
    let name: String
    let isSetpoint: Bool
    let isAverage: Bool
    let points: [PlacementDayChartPoint]
}

struct PlacementDayChartBand: Identifiable {
    enum Kind: Equatable {
        case hvac, comfort, occupancy
    }

    let id: String
    let start: Date
    let end: Date
    let row: Int
    let trackName: String
    let kind: Kind
    let value: String
}

enum PlacementDayChartBuilder {
    static func segments(for insights: PlacementDayInsights) -> [PlacementDayChartSegment] {
        let lower = PlacementInsights.isoDate(insights.wake?.context.from ?? insights.coverage.start)
        let upper = PlacementInsights.isoDate(insights.wake?.context.end ?? insights.coverage.end)
        guard let lower, let upper, lower < upper else { return [] }
        let points = insights.timeline.compactMap { point -> (PlacementDayTimelinePoint, Date)? in
            guard let date = point.date, date >= lower, date < upper else { return nil }
            return (point, date)
        }
        var result: [PlacementDayChartSegment] = []
        for sensor in insights.sensors where !sensor.isThermostat {
            result += split(
                seriesID: sensor.id,
                name: sensor.name,
                times: points.map(\.1),
                values: points.map { $0.0.rooms[sensor.id] ?? nil }
            )
        }
        result += split(
            seriesID: "average",
            name: "Thermostat / aggregate reading",
            times: points.map(\.1),
            values: points.map { $0.0.average },
            isAverage: true
        )
        result += split(
            seriesID: "setpoint",
            name: "Thermostat setpoint",
            times: points.map(\.1),
            values: points.map { $0.0.setpoint },
            isSetpoint: true
        )
        return result
    }

    static func contextBands(for insights: PlacementDayInsights) -> [PlacementDayChartBand] {
        let lowerString = insights.wake?.context.from ?? insights.coverage.start
        let upperString = insights.wake?.context.end ?? insights.coverage.end
        guard let lower = PlacementInsights.isoDate(lowerString),
              let upper = PlacementInsights.isoDate(upperString), lower < upper else {
            return []
        }
        let points = insights.timeline.compactMap { point -> (PlacementDayTimelinePoint, Date)? in
            guard let date = point.date, date >= lower, date < upper else { return nil }
            return (point, date)
        }
        let roomSensors = insights.sensors.filter { !$0.isThermostat }
        var bands: [PlacementDayChartBand] = []
        var intervalIndex = 0

        func appendInterval(start: Date, end: Date, point: PlacementDayTimelinePoint?) {
            guard start < end else { return }
            let intervalID = intervalIndex
            intervalIndex += 1
            bands.append(PlacementDayChartBand(
                id: "hvac-\(intervalID)", start: start, end: end, row: 0,
                trackName: "HVAC action", kind: .hvac,
                value: point?.hvacAction.map { $0.capitalized } ?? "Unknown"
            ))
            bands.append(PlacementDayChartBand(
                id: "comfort-\(intervalID)", start: start, end: end, row: 1,
                trackName: "Comfort setting", kind: .comfort,
                value: point?.comfortSetting.map { $0.capitalized } ?? "Unknown"
            ))
            for (index, sensor) in roomSensors.enumerated() {
                let occupied = point?.occupied[sensor.id] ?? nil
                bands.append(PlacementDayChartBand(
                    id: "occupancy-\(sensor.id)-\(intervalID)", start: start, end: end,
                    row: index + 2, trackName: "\(sensor.name) occupancy", kind: .occupancy,
                    value: occupied.map { $0 ? "Occupied" : "Unoccupied" } ?? "Unknown"
                ))
            }
        }

        var cursor = lower
        for (index, item) in points.enumerated() {
            let (point, time) = item
            if time > cursor {
                appendInterval(start: cursor, end: time, point: nil)
            }
            let nextTime = points.dropFirst(index + 1).first?.1 ?? upper
            let end = min(time.addingTimeInterval(15 * 60), min(nextTime, upper))
            appendInterval(start: time, end: end, point: point)
            cursor = max(cursor, end)
        }
        if cursor < upper {
            appendInterval(start: cursor, end: upper, point: nil)
        }
        return bands
    }

    static func split(
        seriesID: String,
        name: String,
        times: [Date],
        values: [Double?],
        isSetpoint: Bool = false,
        isAverage: Bool = false
    ) -> [PlacementDayChartSegment] {
        guard times.count == values.count else { return [] }
        var segments: [PlacementDayChartSegment] = []
        var current: [PlacementDayChartPoint] = []
        var segmentIndex = 0
        var previousTime: Date?

        func finishSegment() {
            guard !current.isEmpty else { return }
            segments.append(PlacementDayChartSegment(
                id: "\(seriesID)-\(segmentIndex)",
                name: name,
                isSetpoint: isSetpoint,
                isAverage: isAverage,
                points: current
            ))
            current.removeAll()
            segmentIndex += 1
        }

        for (time, value) in zip(times, values) {
            if let previousTime, time.timeIntervalSince(previousTime) > 15 * 60 + 0.1 {
                finishSegment()
            }
            previousTime = time
            guard let value else {
                finishSegment()
                continue
            }
            current.append(PlacementDayChartPoint(
                id: "\(seriesID)-\(segmentIndex)-\(current.count)",
                time: time,
                value: value
            ))
        }
        finishSegment()
        return segments
    }
}

struct PlacementDayChartView: View {
    let insights: PlacementDayInsights

    private var timeZone: TimeZone? { TimeZone(identifier: insights.timeZone) }
    private var segments: [PlacementDayChartSegment] { PlacementDayChartBuilder.segments(for: insights) }
    private var contextBands: [PlacementDayChartBand] { PlacementDayChartBuilder.contextBands(for: insights) }
    private var trackCount: Int { 2 + insights.sensors.filter { !$0.isThermostat }.count }
    private var colorMap: [String: Color] {
        MetricSeriesPalette.colorMap(for: insights.sensors.filter { !$0.isThermostat }.map(\.name))
    }
    private var range: ClosedRange<Date>? {
        let from = insights.wake?.context.from ?? insights.coverage.start
        let end = insights.wake?.context.end ?? insights.coverage.end
        guard let lower = PlacementInsights.isoDate(from), let upper = PlacementInsights.isoDate(end),
              lower < upper else {
            return nil
        }
        return lower...upper
    }
    private var temperatureDomain: ClosedRange<Double> {
        let values = segments.flatMap { $0.points.map(\.value) }
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        if minimum == maximum {
            let padding = max(abs(minimum) * 0.05, 0.5)
            return (minimum - padding)...(maximum + padding)
        }
        let padding = (maximum - minimum) * 0.1
        return (minimum - padding)...(maximum + padding)
    }
    private var contextRowHeight: Double {
        max((temperatureDomain.upperBound - temperatureDomain.lowerBound) * 0.08, 0.2)
    }
    private var yDomain: ClosedRange<Double> {
        (temperatureDomain.lowerBound - Double(trackCount) * contextRowHeight)...temperatureDomain.upperBound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insights.wake == nil ? "Daily room temperatures" : "Wake-window temperatures")
                .font(Theme.Fonts.headerLarge())
                .accessibilityAddTraits(.isHeader)
            if (segments.isEmpty && contextBands.isEmpty) || range == nil || timeZone == nil {
                Text("No temperature or activity samples are available in this period.")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
                    .frame(height: CGFloat(220 + trackCount * 16))
                    .accessibilityLabel("Room temperatures, thermostat setpoint, and activity bands")
                    .accessibilityValue(accessibilitySummary)
                    .accessibilityElement(children: .ignore)
                legend
                contextLegend
            }
        }
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.cornerRadius)
    }

    private var chart: some View {
        Chart {
            ForEach(contextBands) { band in
                if let verticalRange = bandYRange(band) {
                    RectangleMark(
                        xStart: .value("Context start", band.start),
                        xEnd: .value("Context end", band.end),
                        yStart: .value("Context lower", verticalRange.lowerBound),
                        yEnd: .value("Context upper", verticalRange.upperBound)
                    )
                    .foregroundStyle(contextColor(for: band))
                    .opacity(band.value == "Unknown" ? 0.3 : 0.72)
                }
            }
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("House-local time", point.time),
                        y: .value(insights.unit, point.value),
                        series: .value("Segment", segment.id)
                    )
                    .foregroundStyle(color(for: segment))
                    .lineStyle(lineStyle(for: segment))
                    .interpolationMethod(.linear)
                }
                if segment.points.count == 1, let point = segment.points.first {
                    PointMark(
                        x: .value("House-local time", point.time),
                        y: .value(insights.unit, point.value)
                    )
                    .foregroundStyle(color(for: segment))
                    .symbolSize(50)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
        .chartXScale(domain: range!)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self), let timeZone {
                        Text(PlacementDayCalendar.timeLabel(date, in: timeZone))
                    }
                }
            }
        }
    }

    private func bandYRange(_ band: PlacementDayChartBand) -> ClosedRange<Double>? {
        guard band.row >= 0, band.row < trackCount else { return nil }
        let top = temperatureDomain.lowerBound - Double(band.row) * contextRowHeight
        return (top - contextRowHeight * 0.8)...top
    }

    private var axisDates: [Date] {
        guard let timeZone else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = Array(Set(segments.flatMap { $0.points.map(\.time) }
            .filter { calendar.component(.minute, from: $0) == 0 })).sorted()
        return values.isEmpty ? [range!.lowerBound, range!.upperBound] : values
    }

    private var legend: some View {
        let names = Array(Set(segments.map(\.name))).sorted()
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading) {
            ForEach(names, id: \.self) { name in
                let segment = segments.first { $0.name == name }
                HStack(spacing: 5) {
                    Capsule()
                        .fill(segment.map(color(for:)) ?? MetricSeriesPalette.outside)
                        .frame(width: 14, height: 3)
                    Text(name)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var contextLegend: some View {
        VStack(alignment: .leading, spacing: 5) {
            let rows = ["HVAC action", "Comfort setting"]
                + insights.sensors.filter { !$0.isThermostat }.map { "\($0.name) occupancy" }
            Text("Time-aligned rows, bottom to top: \(rows.joined(separator: ", ")). Faded gray indicates unknown.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], alignment: .leading) {
                legendItem("Heating", color: .orange)
                legendItem("Cooling", color: .blue)
                legendItem("Idle", color: .gray)
                legendItem("Sleep", color: .purple)
                legendItem("Home", color: .green)
                legendItem("Away", color: .yellow)
                legendItem("Occupied", color: .mint)
                legendItem("Unoccupied", color: .gray.opacity(0.6))
                legendItem("Unknown", color: .gray.opacity(0.3))
            }
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 8)
            Text(title)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var accessibilitySummary: String {
        let temperatures = segments.map { segment in
            let values = segment.points.map(\.value)
            guard let minimum = values.min(), let maximum = values.max() else { return segment.name }
            return "\(segment.name): \(minimum.formatted(.number.precision(.fractionLength(1)))) to "
                + "\(maximum.formatted(.number.precision(.fractionLength(1)))) \(insights.unit)"
        }
        let activity = contextBands.map { band in
            let start = PlacementDayCalendar.timeLabel(band.start, in: timeZone ?? .gmt)
            let end = PlacementDayCalendar.timeLabel(band.end, in: timeZone ?? .gmt)
            return "\(band.trackName) \(band.value) from \(start) to \(end)"
        }
        return (temperatures + activity).joined(separator: ". ")
    }

    private func color(for segment: PlacementDayChartSegment) -> Color {
        if segment.isSetpoint { return Theme.Colors.warning }
        if segment.isAverage { return Theme.Colors.accent }
        return colorMap[segment.name] ?? MetricSeriesPalette.outside
    }

    private func lineStyle(for segment: PlacementDayChartSegment) -> StrokeStyle {
        if segment.isSetpoint { return StrokeStyle(lineWidth: 2, dash: [5, 3]) }
        if segment.isAverage { return StrokeStyle(lineWidth: 2, dash: [2, 2]) }
        return StrokeStyle(lineWidth: 2)
    }

    private func contextColor(for band: PlacementDayChartBand) -> Color {
        if band.value == "Unknown" { return .gray }
        switch band.kind {
        case .hvac: return hvacColor(for: band.value)
        case .comfort: return comfortColor(for: band.value)
        case .occupancy: return band.value == "Occupied" ? .mint : .gray.opacity(0.6)
        }
    }

    private func hvacColor(for value: String) -> Color {
        switch value.lowercased() {
        case "heating": return .orange
        case "cooling": return .blue
        default: return .gray
        }
    }

    private func comfortColor(for value: String) -> Color {
        switch value.lowercased() {
        case "sleep": return .purple
        case "home": return .green
        case "away": return .yellow
        default: return .gray
        }
    }
}
