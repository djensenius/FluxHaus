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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insights.wake == nil ? "Daily room temperatures" : "Wake-window temperatures")
                .font(Theme.Fonts.headerLarge())
                .accessibilityAddTraits(.isHeader)
            if segments.isEmpty || range == nil || timeZone == nil {
                Text("No room temperature samples are available in this period.")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
                    .frame(height: 220)
                    .accessibilityLabel("Room temperatures and thermostat setpoint")
                    .accessibilityValue(accessibilitySummary)
                    .accessibilityElement(children: .ignore)
                legend
            }
        }
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.cornerRadius)
    }

    private var chart: some View {
        Chart {
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

    private var yDomain: ClosedRange<Double> {
        let values = segments.flatMap { $0.points.map(\.value) }
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        if minimum == maximum {
            let padding = max(abs(minimum) * 0.05, 0.5)
            return (minimum - padding)...(maximum + padding)
        }
        let padding = (maximum - minimum) * 0.1
        return (minimum - padding)...(maximum + padding)
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

    private var accessibilitySummary: String {
        segments.map { segment in
            let values = segment.points.map(\.value)
            guard let minimum = values.min(), let maximum = values.max() else { return segment.name }
            return "\(segment.name): \(minimum.formatted(.number.precision(.fractionLength(1)))) to "
                + "\(maximum.formatted(.number.precision(.fractionLength(1)))) \(insights.unit)"
        }.joined(separator: ". ")
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
}
