//
//  SensorPlacementView.swift
//  FluxHaus
//

import SwiftUI

struct SensorPlacementView: View {
    @State private var service: SensorPlacementService
    @State private var refreshID = 0
    @State private var completedRefreshID = 0
    @State private var showSetup = false

    init(service: SensorPlacementService = SensorPlacementService()) {
        _service = State(initialValue: service)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if !service.isSessionValid {
                    ContentUnavailableView(
                        "Session changed",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Close this screen and reopen it for the current account.")
                    )
                } else if let insights = service.insights {
                    if service.isLoading {
                        ProgressView("Refreshing sensor placement…")
                    }
                    if let error = service.error {
                        errorMessage(error)
                    }
                    content(insights)
                } else if let error = service.error {
                    errorMessage(error)
                } else {
                    ProgressView("Loading sensor placement…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Sensor placement")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshID += 1
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(service.isLoading || !service.isSessionValid)
            }
        }
        .sheet(isPresented: $showSetup) {
            if let insights = service.insights {
                ThermostatSetupView(sensors: insights.sensors, config: service.config) { config in
                    if service.updateConfig(config) { refreshID += 1 }
                }
            }
        }
        .task(id: "\(refreshID)-\(service.isSessionValid)") {
            guard service.isSessionValid else { return }
            // Only reload on request: this task also restarts when returning from a sensor's detail view.
            if service.insights == nil || refreshID != completedRefreshID {
                completedRefreshID = refreshID
                await service.refresh()
            }
        }
    }

    private func errorMessage(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle")
            Button("Retry") { refreshID += 1 }
                .disabled(service.isLoading)
        }
        .foregroundColor(Theme.Colors.textPrimary)
    }

    private func content(_ insights: PlacementInsights) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text("These preliminary suggestions are based on historical patterns, not proof of their causes.")
                .foregroundColor(Theme.Colors.textSecondary)
            if let notice = service.notice {
                Label(notice, systemImage: "info.circle")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            thermostatSetup(insights)
            coverage(insights)
            recommendations(insights)
            sensors(insights)
        }
    }

    private func thermostatSetup(_ insights: PlacementInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Thermostat setup")
            if let config = service.config {
                ForEach(PlacementConfig.Setting.allCases) { setting in
                    let names = insights.sensors.filter { config.sensors(in: setting).contains($0.id) }
                        .map(\.displayName)
                    Text("\(setting.title): \(names.isEmpty ? "No sensors" : names.joined(separator: ", "))")
                }
                Text("Follow Me: \(config.followMe ? "On" : "Off")")
            } else {
                Text("Not set up. Tips can't tell which sensors your Home, Sleep and Away settings average.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Button(service.config == nil ? "Set Up Thermostat…" : "Edit Thermostat Setup…") { showSetup = true }
                .disabled(insights.roomSensorIDs.isEmpty)
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func coverage(_ insights: PlacementInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Data coverage")
            Text("Analysis window: \(insights.windowDays) days")
            let coverage = insights.coverage
            Text("From: \(dateText(coverage.start))")
            Text("To: \(dateText(coverage.end))")
            if let inferred = coverage.inferredMorningEvents, let observed = coverage.observedMorningEvents {
                Text("Observed morning events: \(observed)")
                Text("Inferred morning events: \(inferred)")
                Text("Inferred events are estimates, not verified routines.")
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                Text("Morning events: \(coverage.morningEvents) (provenance unavailable)")
            }
            if coverage.returnHistoryAvailable == false {
                Text("Return-from-away history is unavailable; returns cannot be detected.")
            } else if let detected = coverage.detectedReturnEvents {
                Text("Detected return-from-away events: \(detected)")
            } else {
                Text("Possible return-from-away events: \(coverage.returnEvents) (detection availability unknown)")
            }
            if coverage.hvacHistoryAvailable {
                if let earliest = coverage.hvacEarliestStateAt {
                    Text("Earliest thermostat state returned: \(dateText(earliest))")
                    Text("This may be a snapshot; it does not establish how much HVAC history is available.")
                } else {
                    Text("Some HVAC history is available, but its coverage is unknown.")
                }
            } else {
                Label(
                    "HVAC history unavailable; suggestions may be limited.",
                    systemImage: "exclamationmark.triangle"
                )
            }
            disclosures(coverage)
            if let count = coverage.unknownUnitWindows, count > 0 {
                Text(
                    "15-minute sensor windows omitted for unknown or conflicting temperature units: \(count)"
                )
            }
            Text("Generated: \(dateText(insights.generatedAt))")
        }
        .font(Theme.Fonts.bodyMedium)
    }

    @ViewBuilder
    private func disclosures(_ coverage: PlacementInsights.Coverage) -> some View {
        if let wake = coverage.wakeEvents { Text("Wake-up transitions (Sleep → Home): \(wake)") }
        if coverage.comfortScheduleAvailable == false {
            Text("Comfort-setting history is unavailable; waking tips are limited.")
        }
        if coverage.occupancyAvailable == false {
            Text("Occupancy history is unavailable, so Follow Me can't be taken into account.")
        }
        if coverage.participationConfigured == false {
            Text("Comfort-setting participation is unknown, so tips say \"if included\".")
        }
        if let from = coverage.coolingFrom, let until = coverage.coolingTo {
            let lastSeason = Self.isEarlier(until, than: coverage.start)
            Text("Cooling\(lastSeason ? " (last season)" : ""): \(dateText(from)) – \(dateText(until))"
                 + (coverage.coolingEvents.map { ", \($0) cooling periods" } ?? ""))
        } else if coverage.coolingEvents == 0 {
            Text("No cooling activity in the past year; there are no cooling tips.")
        }
    }

    private func recommendations(_ insights: PlacementInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Recommendations")
            let groups = Self.groups(insights.rankedRecommendations)
            if groups.isEmpty {
                Text("No recommendations for this window. There may not be enough history to make suggestions.")
            } else {
                ForEach(groups, id: \.mode) { group in
                    if groups.count > 1 || group.mode != nil {
                        Label(Self.modeTitle(group.mode), systemImage: Self.modeIcon(group.mode))
                            .font(Theme.Fonts.bodyLarge.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.items) { PlacementRecommendationCard(recommendation: $0, insights: insights) }
                }
            }
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func sensors(_ insights: PlacementInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Sensors")
            if insights.sensors.isEmpty {
                Text("No sensor history is available for this window.")
            } else {
                ForEach(insights.sensors) { sensor in
                    NavigationLink {
                        SensorPlacementDetailView(service: service, sensorID: sensor.id)
                    } label: {
                        sensorCard(sensor, unit: insights.unit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func sensorCard(_ sensor: PlacementInsights.Sensor, unit: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sensor.displayName).fontWeight(.semibold)
                if let verdict = sensor.outlierVerdict {
                    PlacementVerdictBadge(verdict: verdict)
                }
                Text("Samples: \(countText(sensor.sampleCount))")
                Text("Average offset: \(Self.offset(sensor.averageOffset, unit: unit))")
                Text("Morning offset: \(Self.offset(sensor.morningOffset, unit: unit))")
                Text("Return-from-away offset: \(Self.offset(sensor.returnOffset, unit: unit))")
                if sensor.wakeOffset != nil {
                    Text("Waking offset: \(Self.offset(sensor.wakeOffset, unit: unit))")
                }
                if sensor.coolingOffset != nil {
                    Text("Cooling offset: \(Self.offset(sensor.coolingOffset, unit: unit))")
                }
                if let participation = Self.participationText(sensor.participation) {
                    Text(participation)
                }
                Text("Overshoot after confirmed heating stops: \(Self.offset(sensor.overshoot, unit: unit))")
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(Theme.cornerRadius)
        .contentShape(Rectangle())
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.headerLarge())
            .foregroundColor(Theme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func dateText(_ value: String?) -> String {
        guard let value else { return "Unavailable" }
        guard let date = MetricPoint.parse(value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func countText(_ count: Int?) -> String {
        count.map(String.init) ?? "Unavailable"
    }

    static func offset(_ value: Double?, unit: String?) -> String {
        guard let value, let unit, !unit.isEmpty else { return "Unavailable" }
        // These are differences, not absolute temperatures: do not apply a temperature scale's zero point.
        let number = value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        return "\(number) \(unit)"
    }

    static func priority(_ value: String) -> String {
        switch value {
        case "high": return "High"
        case "medium": return "Medium"
        case "low": return "Low"
        default: return "Unknown"
        }
    }

    static func actionLabel(_ action: String?, setting: PlacementInsights.ComfortSetting? = nil) -> String? {
        let name = settingName(setting)
        switch action {
        case "move": return "Consider moving"
        case "remove_from_setting": return "Consider removing from \(name)"
        case "add_to_setting": return "Consider adding to \(name)"
        case "exclude_from_comfort": return "Consider excluding from comfort"
        case "include_in_comfort": return "Consider including in comfort"
        case "none": return "No sensor change needed"
        default: return nil  // Unknown future actions: the title and detail still explain the tip.
        }
    }

    private static func settingName(_ setting: PlacementInsights.ComfortSetting?) -> String {
        switch setting {
        case .home: return "the Home comfort setting"
        case .sleep: return "the Sleep comfort setting"
        case .away: return "the Away comfort setting"
        case .unknown, nil: return "a comfort setting"
        }
    }

    static func settingLabel(_ setting: PlacementInsights.ComfortSetting?) -> String? {
        switch setting {
        case .home: return "Home setting"
        case .sleep: return "Sleep setting"
        case .away: return "Away setting"
        case .unknown, nil: return nil
        }
    }

    static func periodLabel(_ period: PlacementInsights.Period?) -> String? {
        switch period {
        case .wake: return "When waking"
        case .sleep: return "Overnight"
        case .home: return "While home"
        case .returning: return "Returning home"
        case .unknown, nil: return nil
        }
    }

    static func modeTitle(_ mode: PlacementInsights.Mode?) -> String {
        switch mode {
        case .heating: return "Heating"
        case .cooling: return "Cooling"
        case .unknown, nil: return "General"
        }
    }

    static func modeIcon(_ mode: PlacementInsights.Mode?) -> String {
        switch mode {
        case .heating: return "flame"
        case .cooling: return "snowflake"
        case .unknown, nil: return "lightbulb"
        }
    }

    /// Groups ranked recommendations Heating, Cooling, then everything else, keeping rank order within each.
    static func groups(
        _ ranked: [PlacementInsights.Recommendation]
    ) -> [(mode: PlacementInsights.Mode?, items: [PlacementInsights.Recommendation])] {
        let heating = ranked.filter { $0.mode == .heating }
        let cooling = ranked.filter { $0.mode == .cooling }
        let general = ranked.filter { $0.mode != .heating && $0.mode != .cooling }
        let groups: [(mode: PlacementInsights.Mode?, items: [PlacementInsights.Recommendation])] = [
            (.heating, heating), (.cooling, cooling), (nil, general)
        ]
        return groups.filter { !$0.items.isEmpty }
    }

    static func name(_ sensorID: String, in insights: PlacementInsights) -> String {
        insights.sensors.first(where: { $0.id == sensorID })?.displayName ?? sensorID
    }

    private static func participationText(_ participation: PlacementInsights.Participation?) -> String? {
        guard let participation else { return nil }
        let included = PlacementConfig.Setting.allCases.filter { participation.value(for: $0) == true }.map(\.title)
        let excluded = PlacementConfig.Setting.allCases.filter { participation.value(for: $0) == false }.map(\.title)
        guard !included.isEmpty || !excluded.isEmpty else { return nil }
        return [included.isEmpty ? nil : "Included in: " + included.joined(separator: ", "),
                excluded.isEmpty ? nil : "Not in: " + excluded.joined(separator: ", ")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private static func isEarlier(_ value: String, than other: String) -> Bool {
        guard let date = PlacementInsights.isoDate(value), let otherDate = PlacementInsights.isoDate(other) else {
            return false
        }
        return date < otherDate
    }
}

#if DEBUG
#Preview {
    let data = Data("""
    {
      "generatedAt": "2026-03-20T12:00:00Z", "windowDays": 14, "unit": "°C",
      "coverage": {"start": "2026-03-06T12:00:00Z", "end": "2026-03-20T12:00:00Z",
        "hvacHistoryAvailable": true, "hvacEarliestStateAt": "2026-03-10T12:00:00Z",
        "returnHistoryAvailable": false, "morningEvents": 5, "inferredMorningEvents": 2, "returnEvents": 0,
        "unknownUnitWindows": 3},
      "sensors": [{"id": "bedroom", "name": "Bedroom", "isThermostat": false,
        "averageOffset": -0.5, "morningOffset": -1.2, "returnOffset": null,
        "overshoot": null, "sampleCount": 60, "classification": "cold"}],
      "recommendations": [{"id": "move", "severity": "high", "sensorId": "bedroom", "mode": "heating",
        "period": "wake", "comfortSetting": "home", "action": "remove_from_setting", "affectedSensorIds": ["bedroom"],
        "title": "Check the sensor location", "likelyCauses": ["near a window"],
        "detail": "Consider moving it away from a draft."}]
    }
    """.utf8)
    let insights = try? JSONDecoder().decode(PlacementInsights.self, from: data)
    return NavigationStack {
        SensorPlacementView(service: SensorPlacementService(insights: insights, sessionCheck: { true }))
    }
}
#endif
