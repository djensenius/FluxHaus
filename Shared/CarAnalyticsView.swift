//
//  CarAnalyticsView.swift
//  FluxHaus
//

import SwiftUI

struct CarAnalyticsView: View {
    @State private var selectedRange: CarAnalyticsRange = .month
    @State private var response: CarAnalyticsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                Picker("Period", selection: $selectedRange) {
                    ForEach(CarAnalyticsRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if isLoading && response == nil {
                    ProgressView("Loading car insights...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Car Insights Unavailable",
                        systemImage: "chart.xyaxis.line",
                        description: Text(errorMessage)
                    )
                } else if let response {
                    analyticsContent(response)
                }
            }
            .padding()
        }
        .navigationTitle("Car Insights")
        .background(Theme.Colors.background)
        .task(id: selectedRange) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private func analyticsContent(_ analytics: CarAnalyticsResponse) -> some View {
        Text(analytics.summary)
            .font(Theme.Fonts.bodyLarge)
            .foregroundColor(Theme.Colors.textPrimary)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: Theme.Spacing.medium) {
            analyticsCard(
                title: "Charging",
                value: "\(analytics.charging.sessionCount)",
                detail: chargingDetail(analytics.charging),
                symbol: "bolt.car.fill"
            )
            analyticsCard(
                title: "Distance",
                value: "\(formatted(analytics.usage.distanceKm)) km",
                detail: comparisonDetail(analytics.comparison?.distanceChangePercent),
                symbol: "road.lanes"
            )
            analyticsCard(
                title: analytics.usage.efficiency.label,
                value: efficiencyValue(analytics.usage.efficiency),
                detail: efficiencyDetail(analytics),
                symbol: "gauge.with.dots.needle.50percent"
            )
            analyticsCard(
                title: "Weather impact",
                value: weatherValue(analytics.weather),
                detail: weatherDetail(analytics.weather),
                symbol: "cloud.sun.fill"
            )
        }

        if let comparison = comparisonSummary(analytics.comparison) {
            Label("Compared with the previous period", systemImage: "arrow.left.arrow.right")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(comparison)
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }

        if !analytics.dataQuality.warnings.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Label("Data quality", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.warning)
                ForEach(analytics.dataQuality.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .padding()
            .cardBackground()
        }

        Text(
            "Server analysis using \(analytics.period.aggregationWindow) aggregation in "
                + "\(analytics.period.timezone). Coverage: "
                + "\(formatted(analytics.dataQuality.coveragePercent))%."
        )
        .font(Theme.Fonts.caption)
        .foregroundColor(Theme.Colors.textSecondary)
    }

    private func analyticsCard(
        title: String,
        value: String,
        detail: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label(title, systemImage: symbol)
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            Text(detail)
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .cardBackground()
    }

    private func chargingDetail(_ charging: CarChargingAnalytics) -> String {
        guard let interval = charging.averageIntervalDays else {
            return charging.sessionCount == 0 ? "No sessions detected" : "One session detected"
        }
        return "About every \(formatted(interval)) days"
    }

    private func efficiencyValue(_ efficiency: CarEfficiencyResult) -> String {
        guard let value = efficiency.value, let unit = efficiency.unit else { return "Unavailable" }
        return "\(formatted(value)) \(unit)"
    }

    private func efficiencyDetail(_ analytics: CarAnalyticsResponse) -> String {
        if analytics.usage.efficiency.method == .proxy {
            return "Battery-based estimate, not measured kWh"
        }
        guard analytics.usage.efficiency.method == .measured else {
            return "More distance and energy data needed"
        }
        return "\(formatted(analytics.dataQuality.energyCoveragePercent))% energy coverage"
    }

    private func weatherValue(_ weather: CarWeatherAnalytics) -> String {
        guard let impact = weather.estimatedImpactPercent else { return "Not enough data" }
        return "\(formatted(abs(impact)))% \(impact >= 0 ? "worse" : "better")"
    }

    private func weatherDetail(_ weather: CarWeatherAnalytics) -> String {
        if weather.estimatedImpactPercent != nil {
            return "Below freezing vs. mild weather"
        }
        guard let average = weather.averageTemperatureC else {
            return "Outdoor temperature unavailable"
        }
        return "Average temperature \(formatted(average))°C"
    }

    private func comparisonDetail(_ change: Double?) -> String {
        guard let change else { return "Previous-period comparison unavailable" }
        return "\(formatted(abs(change)))% \(change >= 0 ? "more" : "less") than before"
    }

    private func comparisonSummary(_ comparison: CarAnalyticsComparison?) -> String? {
        guard let comparison else { return nil }
        let changes = [
            comparison.distanceChangePercent.map { changeSummary("Distance", value: $0) },
            comparison.chargingFrequencyChangePercent.map { changeSummary("Charging", value: $0) },
            comparison.efficiencyChangePercent.map { changeSummary("Energy use", value: $0) }
        ].compactMap { $0 }
        return changes.isEmpty ? nil : changes.joined(separator: " · ")
    }

    private func changeSummary(_ label: String, value: Double) -> String {
        "\(label): \(formatted(abs(value)))% \(value >= 0 ? "more" : "less")"
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            response = try await CarAnalyticsClient().fetch(range: selectedRange)
        } catch is CancellationError {
            return
        } catch {
            carAnalyticsLogger.error("Car analytics request failed: \(error.localizedDescription)")
            response = nil
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    @ViewBuilder
    func cardBackground() -> some View {
        #if os(visionOS)
        glassBackgroundEffect(in: .rect(cornerRadius: Theme.cornerRadius))
        #else
        background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        #endif
    }
}
