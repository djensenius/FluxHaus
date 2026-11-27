//
//  SensorPlacementDetailView.swift
//  FluxHaus
//
//  Per-sensor drill-down for the Sensor placement screen.
//

import Charts
import SwiftUI

struct SensorPlacementDetailView: View {
    let service: SensorPlacementService
    let sensorID: String
    @State private var showSetup = false
    @State private var reloadID = 0

    var body: some View {
        let insights = service.insights
        let sensor = insights?.sensors.first(where: { $0.id == sensorID })
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let error = service.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Button("Retry") { reloadID += 1 }
                            .disabled(service.isLoading)
                    }
                }
                if let insights, let sensor {
                    if service.isLoading {
                        ProgressView("Refreshing sensor placement…")
                    }
                    if let notice = service.notice {
                        Label(notice, systemImage: "info.circle")
                    }
                    summary(sensor)
                    offsets(sensor, unit: insights.unit)
                    patterns(sensor, unit: insights.unit)
                    participation(sensor)
                    related(sensor, insights: insights)
                } else {
                    ContentUnavailableView(
                        "Sensor unavailable",
                        systemImage: "sensor",
                        description: Text("This sensor isn't in the latest analysis.")
                    )
                }
            }
            .font(Theme.Fonts.bodyMedium)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle(sensor?.displayName ?? "Sensor")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showSetup) {
            if let insights {
                ThermostatSetupView(sensors: insights.sensors, config: service.config) { config in
                    if service.updateConfig(config) { reloadID += 1 }
                }
            }
        }
        .task(id: reloadID) {
            // Also finish a setup change whose load was cancelled (e.g. by navigating here).
            if reloadID > 0 || service.hasPendingConfig { await service.refresh() }
        }
    }

    private func summary(_ sensor: PlacementInsights.Sensor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let verdict = sensor.outlierVerdict {
                PlacementVerdictBadge(verdict: verdict)
            } else if sensor.isThermostat {
                Text("Ecobee reports the comfort average of its participating sensors here, so it isn't "
                     + "judged as a room.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let text = sensor.verdictSummary {
                Text(text)
            }
            Text("Samples: \(sensor.sampleCount)").foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func offsets(_ sensor: PlacementInsights.Sensor, unit: String) -> some View {
        let rows = Self.offsetRows(sensor)
        return VStack(alignment: .leading, spacing: 8) {
            heading("Compared with the house")
            if rows.isEmpty {
                Text("No offsets are available for this sensor.")
            } else {
                Chart(rows, id: \.label) { row in
                    BarMark(x: .value("Offset", row.value), y: .value("Period", row.label))
                        .foregroundStyle(row.value < 0 ? Theme.Colors.info : Theme.Colors.accent)
                    RuleMark(x: .value("House average", 0))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(height: CGFloat(rows.count) * 32 + 24)
                .accessibilityHidden(true)
                ForEach(rows, id: \.label) { row in
                    LabeledContent(row.label, value: SensorPlacementView.offset(row.value, unit: unit))
                }
                Text("Positive means warmer than the house's comfort average; negative means cooler.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func patterns(_ sensor: PlacementInsights.Sensor, unit: String) -> some View {
        let lines = Self.patternLines(sensor, unit: unit)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("Patterns")
                ForEach(lines, id: \.self) { Text($0) }
            }
        }
    }

    private func participation(_ sensor: PlacementInsights.Sensor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Comfort settings")
            let config = service.config
            if sensor.isThermostat {
                Text("The thermostat reading is the average of the participating sensors, so it isn't one of them.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(PlacementConfig.Setting.allCases) { setting in
                    let included = config.map { $0.sensors(in: setting).contains(sensorID) }
                        ?? sensor.participation?.value(for: setting)
                LabeledContent(setting.title, value: included.map { $0 ? "Included" : "Not included" } ?? "Unknown")
                }
            }
            if let config {
                LabeledContent("Follow Me", value: config.followMe ? "On" : "Off")
            } else if service.canSaveConfig {
                Text("Set up your thermostat so tips know which settings use this sensor.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if !service.canSaveConfig {
                Text(SensorPlacementService.setupUnavailableNotice)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Button(config == nil ? "Set Up Thermostat…" : "Edit Thermostat Setup…") { showSetup = true }
                .disabled(service.insights?.roomSensorIDs.isEmpty ?? true || !service.canSaveConfig)
        }
    }

    private func related(_ sensor: PlacementInsights.Sensor, insights: PlacementInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Recommendations")
            let related = sensor.relatedRecommendations(in: insights)
            if related.isEmpty {
                Text("No recommendations about this sensor.")
            } else {
                ForEach(related) { PlacementRecommendationCard(recommendation: $0, insights: insights) }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.headerLarge())
            .accessibilityAddTraits(.isHeader)
    }

    /// Offsets by period; falls back to the older per-sensor offsets when `periodOffsets` is absent.
    static func offsetRows(_ sensor: PlacementInsights.Sensor) -> [(label: String, value: Double)] {
        let rows: [(String, Double?)]
        if let periods = sensor.periodOffsets {
            rows = [("Overnight", periods.sleep), ("Waking", periods.wake), ("Home", periods.home),
                    ("While heating", periods.heatingRuns), ("While cooling", periods.cooling)]
        } else {
            rows = [("Overall", sensor.averageOffset), ("Morning", sensor.morningOffset),
                    ("Waking", sensor.wakeOffset), ("Returning home", sensor.returnOffset),
                    ("While cooling", sensor.coolingOffset)]
        }
        return rows.compactMap { label, value in value.map { (label: label, value: $0) } }
    }

    static func patternLines(_ sensor: PlacementInsights.Sensor, unit: String) -> [String] {
        var lines: [String] = []
        if let value = sensor.wakeOvershoot {
            lines.append("Peak vs. Home set point after waking: \(SensorPlacementView.offset(value, unit: unit))")
        }
        if let value = sensor.coolingUndershoot {
            lines.append("Below the cooling set point while cooling: \(SensorPlacementView.offset(value, unit: unit))")
        }
        if let consistency = sensor.consistency {
            if let days = consistency.days, days > 0 {
                lines.append("Heating: cooler on \(consistency.coldDays ?? 0) of \(days) days, "
                             + "warmer on \(consistency.warmDays ?? 0) of \(days) days")
            }
            if let days = consistency.coolingDays, days > 0 {
                lines.append("Cooling: cooler on \(consistency.coolingColdDays ?? 0) of \(days) days, "
                             + "warmer on \(consistency.coolingWarmDays ?? 0) of \(days) days")
            }
        }
        let percent = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        if let wake = sensor.occupiedShare?.wake {
            lines.append("Occupied when waking: \(wake.formatted(percent))")
        }
        if let home = sensor.occupiedShare?.home {
            lines.append("Occupied while home: \(home.formatted(percent))")
        }
        return lines
    }
}

extension PlacementInsights.Sensor {
    /// The thermostat's reading appears to be Ecobee's averaged comfort temperature, not a room.
    var displayName: String { isThermostat ? "Thermostat (Ecobee average)" : name }

    /// The server's verdict (or one derived from the older `classification`); nil for the thermostat,
    /// which is the comfort average rather than a room that can be an outlier.
    var outlierVerdict: PlacementInsights.Verdict? {
        if isThermostat { return nil }
        if let verdict { return verdict }
        switch classification {
        case "cold": return .coldOutlier
        case "warm": return .warmOutlier
        case "representative": return .representative
        case "insufficient": return .insufficient
        default: return .unknown
        }
    }
}

struct PlacementVerdictBadge: View {
    let verdict: PlacementInsights.Verdict

    var body: some View {
        Label(Self.title(verdict), systemImage: icon)
            .font(Theme.Fonts.bodySmall.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }

    static func title(_ verdict: PlacementInsights.Verdict) -> String {
        switch verdict {
        case .coldOutlier: return "Reads cold"
        case .warmOutlier: return "Reads warm"
        case .representative: return "Representative"
        case .insufficient: return "Not enough data"
        case .unknown: return "Unclassified"
        }
    }

    private var icon: String {
        switch verdict {
        case .coldOutlier: return "thermometer.snowflake"
        case .warmOutlier: return "thermometer.sun"
        case .representative: return "checkmark.circle"
        case .insufficient, .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch verdict {
        case .coldOutlier: return Theme.Colors.info
        case .warmOutlier: return Theme.Colors.accent
        case .representative: return Theme.Colors.success
        case .insufficient, .unknown: return Theme.Colors.textSecondary
        }
    }
}

struct PlacementRecommendationCard: View {
    let recommendation: PlacementInsights.Recommendation
    let insights: PlacementInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let badge = Self.modeBadge(recommendation.mode) {
                let color = recommendation.mode == .cooling ? Theme.Colors.info : Theme.Colors.accent
                Label(badge.title, systemImage: badge.icon)
                    .font(Theme.Fonts.bodySmall.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.15), in: Capsule())
            }
            Text(recommendation.title).fontWeight(.semibold)
            let badges = [SensorPlacementView.periodLabel(recommendation.period),
                          SensorPlacementView.settingLabel(recommendation.comfortSetting)].compactMap { $0 }
            Text(([SensorPlacementView.priority(recommendation.severity) + " priority"] + badges)
                .joined(separator: " · "))
                .foregroundStyle(Theme.Colors.textSecondary)
            if let sensorID = recommendation.sensorId {
                Text("Sensor: \(SensorPlacementView.name(sensorID, in: insights))")
            }
            if !recommendation.affectedSensorIds.isEmpty {
                let rooms = recommendation.affectedSensorIds.map { SensorPlacementView.name($0, in: insights) }
                Text("Affected rooms: \(rooms.joined(separator: ", "))")
            }
            let setting = recommendation.comfortSetting
            if let action = SensorPlacementView.actionLabel(recommendation.action, setting: setting) {
                Text("Suggested action: \(action)")
            }
            Text(recommendation.detail)
            if !recommendation.likelyCauses.isEmpty {
                Text("Likely causes").fontWeight(.semibold).padding(.top, 4)
                ForEach(recommendation.likelyCauses, id: \.self) { Text("• \($0)") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(Theme.cornerRadius)
    }

    /// Heating/Cooling badge; nil for general (or unrecognized) recommendations, which still render.
    static func modeBadge(_ mode: PlacementInsights.Mode?) -> (title: String, icon: String)? {
        switch mode {
        case .heating, .cooling: return (SensorPlacementView.modeTitle(mode), SensorPlacementView.modeIcon(mode))
        case .unknown, nil: return nil
        }
    }
}
