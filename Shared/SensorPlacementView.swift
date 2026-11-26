//
//  SensorPlacementView.swift
//  FluxHaus
//

import SwiftUI

struct SensorPlacementView: View {
    @State private var service: SensorPlacementService
    @State private var refreshID = 0

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
        .task(id: "\(refreshID)-\(service.isSessionValid)") {
            guard service.isSessionValid else { return }
            if service.insights == nil || refreshID > 0 {
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
            coverage(insights)
            recommendations(insights)
            sensors(insights)
        }
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
            if let count = coverage.unknownUnitReadings, count > 0 {
                Text("Readings omitted because their temperature unit was unknown: \(count)")
            }
            Text("Generated: \(dateText(insights.generatedAt))")
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func recommendations(_ insights: PlacementInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Recommendations")
            if insights.rankedRecommendations.isEmpty {
                Text("No recommendations for this window. There may not be enough history to make suggestions.")
            } else {
                ForEach(insights.rankedRecommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.title).fontWeight(.semibold)
                        Text("Priority: \(priority(recommendation.severity))")
                            .foregroundColor(Theme.Colors.textSecondary)
                        if let sensorID = recommendation.sensorId {
                            let name = insights.sensors.first(where: { $0.id == sensorID })?.name ?? sensorID
                            Text("Sensor: \(name)")
                        }
                        if let action = actionLabel(recommendation.action) {
                            Text("Suggested action: \(action)")
                        }
                        Text(recommendation.detail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    #if !os(visionOS)
                    .background(Theme.Colors.secondaryBackground)
                    #endif
                    .cornerRadius(Theme.cornerRadius)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sensor.name + (sensor.isThermostat == true ? " · Thermostat" : ""))
                            .fontWeight(.semibold)
                        Text(sensor.classificationLabel)
                        Text("Samples: \(countText(sensor.sampleCount))")
                        Text("Average offset: \(offset(sensor.averageOffset, unit: insights.unit))")
                        Text("Morning offset: \(offset(sensor.morningOffset, unit: insights.unit))")
                        Text("Return-from-away offset: \(offset(sensor.returnOffset, unit: insights.unit))")
                        Text(
                            "Overshoot after confirmed heating stops: \(offset(sensor.overshoot, unit: insights.unit))"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    #if !os(visionOS)
                    .background(Theme.Colors.secondaryBackground)
                    #endif
                    .cornerRadius(Theme.cornerRadius)
                }
            }
        }
        .font(Theme.Fonts.bodyMedium)
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

    private func offset(_ value: Double?, unit: String?) -> String {
        guard let value, let unit, !unit.isEmpty else { return "Unavailable" }
        // These are differences, not absolute temperatures: do not apply a temperature scale's zero point.
        let number = value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        return "\(number) \(unit)"
    }

    private func priority(_ value: String) -> String {
        switch value {
        case "high": return "High"
        case "medium": return "Medium"
        case "low": return "Low"
        default: return "Unknown"
        }
    }

    private func actionLabel(_ action: String?) -> String? {
        switch action {
        case "move": return "Consider moving"
        case "exclude_from_comfort": return "Consider excluding from comfort"
        case "include_in_comfort": return "Consider including in comfort"
        case "none": return "No change suggested"
        case nil: return nil
        default: return "Unrecognized"
        }
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
        "unknownUnitReadings": 3},
      "sensors": [{"id": "bedroom", "name": "Bedroom", "isThermostat": false,
        "averageOffset": -0.5, "morningOffset": -1.2, "returnOffset": null,
        "overshoot": null, "sampleCount": 60, "classification": "cold"}],
      "recommendations": [{"id": "move", "severity": "high", "sensorId": "bedroom",
        "action": "move", "title": "Check the sensor location",
        "detail": "Consider moving it away from a draft."}]
    }
    """.utf8)
    let insights = try? JSONDecoder().decode(PlacementInsights.self, from: data)
    return NavigationStack {
        SensorPlacementView(service: SensorPlacementService(insights: insights, sessionCheck: { true }))
    }
}
#endif
