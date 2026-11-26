//
//  IndoorClimateView.swift
//  FluxHaus
//
//  Indoor temperature UI: the "Inside" card (thermostat + a tile per room),
//  the Indoor device card shown on Home, and the indoor history charts.
//

import SwiftUI

private extension IndoorWarmth {
    var color: Color {
        switch self {
        case .warmer: return Theme.Colors.accent
        case .cooler: return Theme.Colors.info
        case .typical: return Theme.Colors.textPrimary
        }
    }

    var accessibilityDescription: String? {
        switch self {
        case .warmer: return "Warmer than average"
        case .cooler: return "Cooler than average"
        case .typical: return nil
        }
    }
}

extension ThermostatSummary.Activity {
    var color: Color {
        switch self {
        case .heating: return Theme.Colors.accent
        case .cooling: return Theme.Colors.info
        case .fan: return Theme.Colors.secondary
        case .idle, .off: return Theme.Colors.textSecondary
        case .unavailable: return Theme.Colors.warning
        }
    }
}

private extension IndoorClimateState {
    func format(_ value: Double, precise: Bool = true) -> String {
        IndoorClimateFormat.temperature(value, unit: unit, precise: precise)
    }

    var thermostatSummary: ThermostatSummary? {
        guard let thermostat else { return nil }
        return ThermostatSummary(thermostat: thermostat) { value in
            IndoorClimateFormat.temperature(value, unit: thermostatUnit, precise: false)
        }
    }
}

// MARK: - Inside card

struct IndoorClimateCard: View {
    let state: IndoorClimateState
    var actionTitle: LocalizedStringKey = "Indoor history"
    var actionIcon = "chart.xyaxis.line"
    /// Adds a footer button (e.g. history or the Climate section) when set.
    var onAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !state.sensors.isEmpty {
                IndoorRoomsGrid(state: state)
            }
            if let onAction {
                Divider()
                Button(action: onAction) {
                    HStack {
                        Label(actionTitle, systemImage: actionIcon)
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Theme.Fonts.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
        #if os(visionOS)
        .glassBackgroundEffect()
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "house.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Inside")
                    .font(Theme.Fonts.bodySmall).fontWeight(.semibold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                Text(state.primaryTemperature.map { state.format($0) } ?? "—")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let summary = state.thermostatSummary {
                    Label(summary.text, systemImage: summary.systemImage)
                        .foregroundColor(summary.activity.color)
                }
                if let humidity = state.thermostat?.currentHumidity {
                    Label("\(IndoorClimateFormat.humidity(humidity)) humidity", systemImage: "humidity")
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                if let range = state.temperatureRange {
                    Label(
                        "\(state.format(range.lowerBound))–\(state.format(range.upperBound))",
                        systemImage: "arrow.left.and.right"
                    )
                    .foregroundColor(Theme.Colors.textSecondary)
                    .accessibilityLabel(
                        "Rooms range from \(state.format(range.lowerBound)) to \(state.format(range.upperBound))"
                    )
                }
                if let preset = presetName {
                    Label(preset, systemImage: "slider.horizontal.3")
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .font(Theme.Fonts.bodyMedium)
            .multilineTextAlignment(.trailing)
            .minimumScaleFactor(0.8)
        }
    }

    private var presetName: String? {
        guard let preset = state.thermostat?.presetMode, !preset.isEmpty, preset.lowercased() != "none" else {
            return nil
        }
        return preset.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// A tile per room, named after its Home Assistant area, thermostat first.
struct IndoorRoomsGrid: View {
    let state: IndoorClimateState

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(state.rooms) { sensor in
                IndoorRoomTile(
                    sensor: sensor,
                    name: state.displayName(for: sensor),
                    warmth: state.warmth(of: sensor),
                    unit: state.unit
                )
            }
        }
    }
}

struct IndoorRoomTile: View {
    let sensor: IndoorTemperatureSensor
    let name: String
    let warmth: IndoorWarmth
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(name)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                if sensor.isThermostat == true {
                    Image(systemName: "thermometer.medium")
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .accessibilityLabel("Thermostat")
                }
            }
            if sensor.isAvailable, let temp = sensor.temperature {
                Text(IndoorClimateFormat.temperature(temp, unit: sensor.unit ?? unit))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(warmth.color)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            status
                .font(Theme.Fonts.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityValue(warmth.accessibilityDescription ?? "")
    }

    @ViewBuilder
    private var status: some View {
        if !sensor.isAvailable {
            Label("Offline", systemImage: "wifi.slash")
                .foregroundColor(Theme.Colors.warning)
        } else if sensor.occupied == true {
            Label("Occupied", systemImage: "person.fill")
                .foregroundColor(Theme.Colors.accent)
        } else if sensor.occupied == false {
            Label("Unoccupied", systemImage: "person")
                .foregroundColor(Theme.Colors.textSecondary)
        } else {
            Label(sensor.isThermostat == true ? "Thermostat" : "Sensor", systemImage: "sensor")
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Indoor device card

/// What the Indoor device card on Home shows: the headline temperature, what
/// the thermostat is doing, and the warmest and coolest rooms.
struct IndoorCardSummary: Equatable {
    static let placeholder = "—"
    static let noReadings = "No readings yet"

    /// Headline reading, or `placeholder` before any reading arrives.
    let value: String
    /// Thermostat status, e.g. "Heating to 21.5°C" or "Heat · set to 21°C".
    let status: String?
    /// "Warmest Kitchen 22.6°C · Coolest Main Bedroom 19.8°C", with two or more distinct readings.
    let extremes: String?
    let activity: ThermostatSummary.Activity?
    /// SF Symbol for `status`.
    let statusImage: String?

    var hasReadings: Bool { value != Self.placeholder }

    /// Sorted with the running devices while the thermostat is heating or cooling.
    var isActive: Bool { activity == .heating || activity == .cooling }

    /// One line per fact for the card's secondary text.
    var detail: String {
        let lines = [status, extremes].compactMap { $0 }
        if lines.isEmpty { return hasReadings ? "" : Self.noReadings }
        return lines.joined(separator: "\n")
    }

    var tint: Color {
        guard hasReadings, let activity, activity != .idle else { return Theme.Colors.textSecondary }
        return activity.color
    }

    /// The freshest indoor state for Home: the session thermostat's view (its last accepted
    /// change until a newer poll) when there is one, else the polled snapshot. A control
    /// reply may carry no room sensors, so the polled rooms fill in until the next poll.
    /// An ended session's controller has dropped its replies and shows the poll.
    @MainActor
    static func currentState(thermostat: Thermostat?, polled: IndoorClimateState?) -> IndoorClimateState? {
        guard let current = thermostat?.state else { return polled }
        guard current.sensors.isEmpty, let polled, !polled.sensors.isEmpty else { return current }
        return IndoorClimateState(
            timestamp: current.timestamp,
            unit: current.reportedUnit ?? polled.reportedUnit,
            thermostat: current.thermostat ?? polled.thermostat,
            sensors: polled.sensors,
            confirmed: current.confirmed
        )
    }

    init(state: IndoorClimateState?) {
        guard let state, state.hasData else {
            value = Self.placeholder
            status = nil
            extremes = nil
            activity = nil
            statusImage = nil
            return
        }
        value = state.primaryTemperature.map { state.format($0) } ?? Self.placeholder
        let summary = state.thermostatSummary
        status = summary?.text
        activity = summary?.activity
        statusImage = summary?.systemImage
        extremes = Self.extremes(in: state)
    }

    private static func extremes(in state: IndoorClimateState) -> String? {
        let readings = state.rooms.compactMap { sensor -> (name: String, temp: Double)? in
            guard sensor.isAvailable, let temp = state.temperature(of: sensor) else { return nil }
            return (state.displayName(for: sensor), temp)
        }
        guard let warmest = readings.max(by: { $0.temp < $1.temp }),
              let coolest = readings.min(by: { $0.temp < $1.temp }),
              warmest.temp > coolest.temp else { return nil }
        return "Warmest \(warmest.name) \(state.format(warmest.temp))"
            + " · Coolest \(coolest.name) \(state.format(coolest.temp))"
    }
}

#if os(macOS)
/// The Indoor device card on the Mac dashboard, styled like its other device cards.
struct IndoorDashboardCard: View {
    let summary: IndoorCardSummary
    var onOpen: () -> Void

    var body: some View {
        // The whole card opens Climate, like the iPhone and iPad Indoor card.
        Button(action: onOpen) {
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(12)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Climate")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "thermometer.medium")
                    .foregroundColor(summary.tint)
                Text("Indoor")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(summary.value)
                    .font(Theme.Fonts.headerXL())
                    .foregroundColor(summary.hasReadings ? Theme.Colors.secondary : Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 8) {
                if let status = summary.status, let image = summary.statusImage {
                    Label(status, systemImage: image)
                        .foregroundColor(summary.isActive ? summary.tint : Theme.Colors.textPrimary)
                }
                if let extremes = summary.extremes {
                    Label(extremes, systemImage: "arrow.up.arrow.down")
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                if !summary.hasReadings && summary.status == nil {
                    Text(IndoorCardSummary.noReadings)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .font(Theme.Fonts.bodyMedium)
            Divider()
            Text("Climate →")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.accent)
                .accessibilityHidden(true)
        }
    }
}
#endif

// MARK: - Indoor history

struct IndoorClimateMetricsView: View {
    @Bindable var metrics: MetricsService

    /// The server adds the outdoor reading to these metrics as "Outside"; it
    /// belongs on the outdoor charts, not here.
    private static let outdoorSeries: Set<String> = ["Outside"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                MetricRangePicker(metrics: metrics, scope: \.indoorCatalog)
                content
            }
            .padding(.vertical)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Indoor History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await metrics.refresh(scope: \.indoorCatalog) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .symbolEffect(
                            .rotate,
                            options: .repeat(.continuous),
                            isActive: metrics.isLoading || metrics.isRefreshing
                        )
                }
                .disabled(metrics.isLoading || metrics.isRefreshing)
            }
        }
        .task {
            if metrics.catalog.isEmpty || metrics.indoorCatalog.isEmpty {
                // A catalog cached before the server added indoor metrics won't
                // include them; re-fetch so they appear without a manual refresh.
                await metrics.refresh(scope: \.indoorCatalog)
            } else if !metrics.hasSeries(for: metrics.indoorCatalog) {
                await metrics.loadSeries(metrics.indoorCatalog)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if metrics.indoorCatalog.isEmpty {
            VStack(spacing: Theme.Spacing.small) {
                Image(systemName: metrics.isLoading ? "arrow.clockwise" : "house")
                    .font(.largeTitle)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(metrics.isLoading ? "Loading…" : (metrics.lastError ?? "No indoor metrics available"))
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            ForEach(metrics.indoorCatalog) { metric in
                MetricChartCard(
                    metric: metric,
                    response: metrics.series[metric.id]?.excludingSeries(named: Self.outdoorSeries)
                )
            }
        }
    }
}
