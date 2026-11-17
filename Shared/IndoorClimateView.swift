//
//  IndoorClimateView.swift
//  FluxHaus
//
//  Indoor temperature UI: the "Inside" card (thermostat + a tile per room),
//  the Home tab summary with a per-room breakdown, and the indoor history charts.
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

private extension ThermostatSummary.Activity {
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
        return ThermostatSummary(thermostat: thermostat) { value in format(value, precise: false) }
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

// MARK: - Home summary

/// Indoor summary for the Home tab: a headline row styled like `WeatherView`'s
/// right-aligned rows, followed by a compact per-room breakdown named after
/// each sensor's Home Assistant area.
struct IndoorSummaryView: View {
    var apiResponse: Api
    /// Caps the room chips on space-constrained layouts; the rest are reachable
    /// through `onTap`.
    var maxRooms: Int?
    var onTap: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        if let state = apiResponse.response?.indoorClimate, state.hasData,
           let temp = state.primaryTemperature {
            Button(action: onTap) {
                VStack(alignment: .trailing, spacing: 8) {
                    headline(state: state, temperature: temp)
                    if state.sensors.count > 1 {
                        let (shown, hidden) = Self.visibleRooms(state.rooms, limit: maxRooms)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            ForEach(shown) { sensor in
                                IndoorRoomChip(
                                    sensor: sensor,
                                    name: state.displayName(for: sensor),
                                    warmth: state.warmth(of: sensor),
                                    unit: state.unit
                                )
                            }
                            if hidden > 0 {
                                MoreRoomsChip(count: hidden)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows indoor climate details")
        }
    }

    /// The rooms to show and how many are hidden. When over the limit, one slot
    /// goes to the "more" chip so the grid keeps the same height.
    nonisolated static func visibleRooms(
        _ rooms: [IndoorTemperatureSensor], limit: Int?
    ) -> (shown: [IndoorTemperatureSensor], hidden: Int) {
        guard let limit, limit > 0, rooms.count > limit else { return (rooms, 0) }
        let shown = Array(rooms.prefix(limit - 1))
        return (shown, rooms.count - shown.count)
    }

    private func headline(state: IndoorClimateState, temperature: Double) -> some View {
        HStack {
            Spacer()
            Image(systemName: "house.fill")
                .foregroundColor(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text("Inside \(state.format(temperature))")
                .foregroundColor(Theme.Colors.textPrimary)
            if let summary = state.thermostatSummary, summary.activity != .off {
                Image(systemName: summary.systemImage)
                    .foregroundColor(summary.activity.color)
                    .accessibilityHidden(true)
                Text(summary.text)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            if let humidity = state.thermostat?.currentHumidity {
                Image(systemName: "humidity")
                    .foregroundColor(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text(IndoorClimateFormat.humidity(humidity))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .accessibilityLabel("\(IndoorClimateFormat.humidity(humidity)) humidity")
            }
        }
        .font(Theme.Fonts.bodyMedium)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.trailing)
    }
}

/// One room in the Home tab breakdown: area name, reading, and occupancy.
private struct MoreRoomsChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis.circle")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text("\(count) more")
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("\(count) more rooms")
    }
}

struct IndoorRoomChip: View {
    let sensor: IndoorTemperatureSensor
    let name: String
    let warmth: IndoorWarmth
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(Theme.Fonts.caption)
                .foregroundColor(iconColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(name)
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(reading)
                .font(Theme.Fonts.bodyMedium).fontWeight(.semibold)
                .foregroundColor(sensor.isAvailable ? warmth.color : Theme.Colors.textSecondary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityValue)
    }

    private var reading: String {
        guard sensor.isAvailable, let temp = sensor.temperature else { return "—" }
        return IndoorClimateFormat.temperature(temp, unit: sensor.unit ?? unit, precise: false)
    }

    private var icon: String {
        if !sensor.isAvailable { return "wifi.slash" }
        if sensor.isThermostat == true { return "thermometer.medium" }
        if sensor.occupied == true { return "person.fill" }
        return "sensor"
    }

    private var iconColor: Color {
        if !sensor.isAvailable { return Theme.Colors.warning }
        if sensor.occupied == true { return Theme.Colors.accent }
        return Theme.Colors.textSecondary
    }

    private var accessibilityValue: String {
        guard sensor.isAvailable, let temp = sensor.temperature else { return "Offline" }
        var parts = [IndoorClimateFormat.temperature(temp, unit: sensor.unit ?? unit)]
        if sensor.isThermostat == true { parts.append("Thermostat") }
        if sensor.occupied == true { parts.append("Occupied") }
        if let warmth = warmth.accessibilityDescription { parts.append(warmth) }
        return parts.joined(separator: ", ")
    }
}

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
