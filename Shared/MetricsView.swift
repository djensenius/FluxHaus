//
//  MetricsView.swift
//  FluxHaus
//
//  Grafana-style metrics dashboard — one chart per stat with a line per
//  series (room, vehicle, host, …).
//

import SwiftUI
import Charts

struct MetricsView: View {
    @Bindable var metrics: MetricsService

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            header
            rangePicker
            content
        }
        .padding(.vertical)
        .task {
            if metrics.catalog.isEmpty {
                await metrics.refresh()
            }
            // Keep the dashboard live: refresh series periodically until the
            // view goes away (the task is cancelled automatically on disappear).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await metrics.loadAllSeries()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Metrics")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Button {
                Task { await metrics.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(Theme.Colors.accent)
                    .symbolEffect(
                        .rotate,
                        options: .repeat(.continuous),
                        isActive: metrics.isLoading || metrics.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .disabled(metrics.isLoading || metrics.isRefreshing)
        }
        .padding(.horizontal)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $metrics.selectedRange) {
            ForEach(MetricRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: metrics.selectedRange) {
            Task { await metrics.loadAllSeries() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if metrics.catalog.isEmpty && !metrics.isLoading {
            emptyState
        } else {
            ForEach(metrics.groupedCatalog, id: \.group) { section in
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    Text(section.group)
                        .font(Theme.Fonts.bodySmall)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal)
                    ForEach(section.metrics) { metric in
                        MetricChartCard(metric: metric, response: metrics.series[metric.id])
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(metrics.lastError ?? "No metrics available")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

struct MetricChartCard: View {
    let metric: MetricCatalogItem
    let response: MetricSeriesResponse?

    @State private var selectedDate: Date?

    private var series: [MetricSeries] {
        (response?.series ?? []).filter { !$0.points.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text(metric.title)
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(metric.unit)
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            if series.isEmpty {
                Text("No data")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                readout
                chart
            }
        }
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.cornerRadius)
        .padding(.horizontal)
    }

    /// Y-axis domain derived from the data with a little padding so flat-ish
    /// series don't get stretched across the full height.
    private var yDomain: ClosedRange<Double>? {
        let values = series.flatMap { $0.points.map(\.value) }
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        if minValue == maxValue {
            let pad = abs(minValue) * 0.05
            let delta = pad == 0 ? 1 : pad
            return (minValue - delta)...(maxValue + delta)
        }
        let pad = (maxValue - minValue) * 0.1
        return (minValue - pad)...(maxValue + pad)
    }

    private var sortedDates: [Date] {
        Array(Set(series.flatMap { $0.points.compactMap(\.date) })).sorted()
    }

    private var latestDate: Date? { sortedDates.last }

    private var snappedDate: Date? {
        guard let selectedDate else { return nil }
        return sortedDates.min(by: {
            abs($0.timeIntervalSince(selectedDate)) < abs($1.timeIntervalSince(selectedDate))
        })
    }

    private func value(for line: MetricSeries, at date: Date) -> Double? {
        line.points.min(by: {
            abs(($0.date ?? .distantPast).timeIntervalSince(date))
                < abs(($1.date ?? .distantPast).timeIntervalSince(date))
        })?.value
    }

    /// Always-visible readout row. Shows values at the hovered/touched time,
    /// or the most recent reading when nothing is selected. Kept outside the
    /// chart so it's never clipped, even with many series.
    private var readout: some View {
        let date = snappedDate ?? latestDate
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let date {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .foregroundColor(Theme.Colors.textSecondary)
                    ForEach(series) { line in
                        if let value = value(for: line, at: date) {
                            HStack(spacing: 4) {
                                if series.count > 1 {
                                    Text(line.name)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Text("\(value, specifier: "%.1f")\(metric.unit)")
                                    .foregroundColor(Theme.Colors.textPrimary)
                            }
                        }
                    }
                }
            }
            .font(Theme.Fonts.caption)
        }
        .frame(height: 18)
    }

    private var chart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points, id: \.time) { point in
                    if let date = point.date {
                        LineMark(
                            x: .value("Time", date),
                            y: .value(metric.unit, point.value)
                        )
                        .foregroundStyle(by: .value("Series", line.name))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            if let snappedDate {
                RuleMark(x: .value("Time", snappedDate))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                ForEach(series) { line in
                    if let value = value(for: line, at: snappedDate) {
                        PointMark(
                            x: .value("Time", snappedDate),
                            y: .value(metric.unit, value)
                        )
                        .foregroundStyle(by: .value("Series", line.name))
                        .symbolSize(60)
                    }
                }
            }
        }
        .chartLegend(series.count > 1 ? .visible : .hidden)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYScale(domain: yDomain ?? 0...1)
        .chartXSelection(value: $selectedDate)
        .frame(height: 180)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        MetricChartCard(
            metric: MetricCatalogItem(id: "temperature", title: "Temperature", unit: "°C", group: "Environment"),
            response: MetricSeriesResponse(
                metric: "temperature",
                title: "Temperature",
                unit: "°C",
                range: "24h",
                series: [
                    MetricSeries(name: "Bedroom", points: [
                        MetricPoint(time: "2024-01-01T00:00:00Z", value: 21),
                        MetricPoint(time: "2024-01-01T01:00:00Z", value: 21.6)
                    ]),
                    MetricSeries(name: "Kitchen", points: [
                        MetricPoint(time: "2024-01-01T00:00:00Z", value: 22.8),
                        MetricPoint(time: "2024-01-01T01:00:00Z", value: 23.1)
                    ])
                ]
            )
        )
    }
}
#endif
