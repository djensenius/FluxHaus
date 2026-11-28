//
//  SensorPlacementDayView.swift
//  FluxHaus
//

import SwiftUI

struct SensorPlacementDayView: View {
    let service: SensorPlacementService

    @State private var insights: PlacementDayInsights?
    @State private var selectedDate: String?
    @State private var pendingDate: String?
    @State private var isLoading = false
    @State private var isUnsupported = false
    @State private var error: String?
    @State private var showDatePicker = false
    @State private var draftDate = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if !service.isSessionValid {
                    ContentUnavailableView(
                        "Session changed",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Close this screen and reopen it for the current account.")
                    )
                } else if isUnsupported {
                    ContentUnavailableView(
                        "Day analysis unavailable",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text(
                            "This server doesn't support selected-day analysis. Update the server to use this feature."
                        )
                    )
                } else if let insights {
                    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                        if isLoading {
                            ProgressView("Loading selected day…")
                        }
                        if let error {
                            loadError(error)
                        }
                        dayContent(insights)
                    }
                } else if let error {
                    loadError(error)
                } else {
                    ProgressView(isLoading ? "Loading day analysis…" : "Preparing day analysis…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Look at a day")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    request(pendingDate)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading || !service.isSessionValid)
            }
        }
        .task {
            await load(date: nil)
        }
        .sheet(isPresented: $showDatePicker) {
            datePicker
        }
    }

    private func dayContent(_ day: PlacementDayInsights) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            dateSelector(day)
            Text("House time zone: \(day.timeZone)")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
            findings(day)
            wake(day)
            PlacementDayChartView(insights: day)
            Text("The thermostat/aggregate series is not a physical room sensor; "
                 + "coverage shows reported versus estimated averages.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            activityContext(day)
            coverage(day)
            sensorMetrics(day)
        }
    }

    private func dateSelector(_ day: PlacementDayInsights) -> some View {
        let zone = TimeZone(identifier: day.timeZone)
        let today = zone.flatMap { PlacementDayCalendar.today(in: $0) }
        let oldest = zone.flatMap { timeZone in
            today.flatMap { PlacementDayCalendar.shifted($0, by: -364, in: timeZone) }
        }
        return HStack {
            Button {
                shiftDate(by: -1, in: day.timeZone)
            } label: {
                Label("Previous day", systemImage: "chevron.left")
            }
            .disabled(isLoading || selectedDate.map { $0 <= (oldest ?? $0) } ?? true)
            Spacer()
            Button {
                beginDateSelection(day)
            } label: {
                Label(PlacementDayCalendar.dateLabel(day.date, in: zone ?? .gmt), systemImage: "calendar")
            }
            .disabled(isLoading || zone == nil)
            .accessibilityHint("Choose any house-local date within the last 365 days.")
            Spacer()
            Button {
                shiftDate(by: 1, in: day.timeZone)
            } label: {
                Label("Next day", systemImage: "chevron.right")
            }
            .disabled(isLoading || selectedDate.map { $0 >= (today ?? $0) } ?? true)
        }
        .buttonStyle(.bordered)
    }

    private func findings(_ day: PlacementDayInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Findings").font(Theme.Fonts.headerLarge()).accessibilityAddTraits(.isHeader)
            if day.findings.isEmpty {
                Text("No unusual-shift finding was returned. Unknown metrics below mean "
                     + "there wasn't enough evidence; they don't mean normal.")
            } else {
                ForEach(day.findings) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.title).fontWeight(.semibold)
                        Text(finding.detail)
                        if !finding.sensorIds.isEmpty {
                            let names = finding.sensorIds.map { sensorName($0, in: day) }.joined(separator: ", ")
                            Text("Sensors: " + names)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.cornerRadius)
                }
            }
        }
        .font(Theme.Fonts.bodyMedium)
    }

    @ViewBuilder
    private func wake(_ day: PlacementDayInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wake analysis").font(Theme.Fonts.headerLarge()).accessibilityAddTraits(.isHeader)
            if let wake = day.wake, let zone = TimeZone(identifier: day.timeZone) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recorded transition: \(PlacementDayCalendar.dateTimeLabel(wake.timestamp, in: zone))")
                    Text("Context: \(PlacementDayCalendar.dateTimeLabel(wake.context.from, in: zone)) – "
                         + PlacementDayCalendar.dateTimeLabel(wake.context.end, in: zone))
                    Text("Context evidence: \(wake.contextComplete ? "Complete" : "Incomplete")"
                         + (wake.contextRetryable ? " (more history may become available)" : ""))
                    Text("Setpoint before / after: \(temperature(wake.setpointBefore, unit: day.unit)) / "
                         + temperature(wake.setpointAfter, unit: day.unit))
                    Text("Known heating: \(minutes(wake.heatingMinutes)); "
                         + "known cooling: \(minutes(wake.coolingMinutes))")
                    Text("Unknown HVAC time: \(minutes(wake.unknownMinutes))")
                    ForEach(wake.rooms) { room in
                        let name = sensorName(room.sensorId, in: day)
                        Text("\(name): at transition \(temperature(room.atSwitch, unit: day.unit)); "
                             + "peak \(temperature(room.peak, unit: day.unit)) at "
                             + PlacementDayCalendar.dateTimeLabel(room.peakAt, in: zone)
                             + "; above setpoint \(temperature(room.overSetpoint, unit: day.unit))")
                    }
                }
            } else {
                Text("No recorded Sleep → Home transition was found for this day.")
            }
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func activityContext(_ day: PlacementDayInsights) -> some View {
        let knownModes = day.timeline.compactMap(\.hvacMode)
        let knownActions = day.timeline.compactMap(\.hvacAction)
        let knownSettings = day.timeline.compactMap(\.comfortSetting)
        let modes = Set(knownModes).sorted()
        let actions = Set(knownActions).sorted()
        let settings = Set(knownSettings).sorted()
        let occupancy = day.timeline.flatMap { $0.occupied.values }
        let knownOccupancy = occupancy.compactMap { $0 }
        let expectedOccupancy = day.coverage.occupancyExpectedReadings
        let unknownOccupancy = max(0, expectedOccupancy - day.coverage.occupancyKnownReadings)
        let expectedBuckets = day.coverage.expectedBuckets
        return VStack(alignment: .leading, spacing: 6) {
            Text("Activity context").font(Theme.Fonts.headerLarge()).accessibilityAddTraits(.isHeader)
            Text("Thermostat modes: \(modes.isEmpty ? "Unknown" : modes.joined(separator: ", ")); "
                 + "\(max(0, expectedBuckets - knownModes.count)) windows unknown")
            Text("HVAC actions: \(actions.isEmpty ? "Unknown" : actions.joined(separator: ", ")); "
                 + "\(max(0, expectedBuckets - knownActions.count)) windows unknown")
            Text("Comfort settings: \(settings.isEmpty ? "Unknown" : settings.joined(separator: ", ")); "
                 + "\(max(0, expectedBuckets - knownSettings.count)) windows unknown")
            Text("Windows with missing HVAC mode/action: \(day.coverage.missingHvacBuckets)")
            Text("Occupancy samples: \(knownOccupancy.filter { $0 }.count) occupied, "
                 + "\(knownOccupancy.filter { !$0 }.count) unoccupied, "
                 + "\(unknownOccupancy) unknown of \(expectedOccupancy)")
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func coverage(_ day: PlacementDayInsights) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Data coverage").font(Theme.Fonts.headerLarge()).accessibilityAddTraits(.isHeader)
            Text("Complete 15-minute windows: \(day.coverage.completeBuckets) of \(day.coverage.expectedBuckets)")
            Text("Missing room readings: \(day.coverage.missingRoomReadings)")
            Text("Windows without known HVAC mode/action: \(day.coverage.missingHvacBuckets)")
            Text("Windows without an average: \(day.coverage.missingAverageBuckets)")
            Text("Unknown-unit windows (\(day.coverage.unknownUnitWindowsScope)): "
                 + "\(day.coverage.unknownUnitWindows)")
            Text("Averages: \(day.coverage.reportedAverageBuckets) reported, "
                 + "\(day.coverage.approximatedAverageBuckets) approximated")
            Text("Occupancy readings known: \(day.coverage.occupancyKnownReadings) of "
                 + "\(day.coverage.occupancyExpectedReadings)")
            Text("Comparison baseline: prior \(day.coverage.baselineDays) house-calendar days")
            if day.coverage.incompleteSensorInventory {
                Label("Some indoor temperature sensors couldn't be classified; room comparisons are unknown.",
                      systemImage: "exclamationmark.triangle")
            }
            if !day.coverage.hvacHistoryAvailable {
                Label("Thermostat history is unavailable.", systemImage: "exclamationmark.triangle")
            }
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func sensorMetrics(_ day: PlacementDayInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sensor day vs. usual").font(Theme.Fonts.headerLarge()).accessibilityAddTraits(.isHeader)
            ForEach(day.sensors) { sensor in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sensor.name).fontWeight(.semibold)
                    if sensor.isThermostat {
                        Text("Thermostat-associated sensor; not compared as a room.")
                    } else {
                        Text("Selected-day offset: \(temperature(sensor.dayOffset, unit: day.unit))")
                        Text("Usual baseline offset: \(temperature(sensor.baselineOffset, unit: day.unit))")
                        Text("Day-to-baseline change: \(temperature(sensor.deviation, unit: day.unit))")
                        Text("Assessment: \(assessment(sensor.unusual))")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.cornerRadius)
                .accessibilityElement(children: .combine)
            }
        }
        .font(Theme.Fonts.bodyMedium)
    }

    @ViewBuilder
    private var datePicker: some View {
        if let day = insights,
           let zone = TimeZone(identifier: day.timeZone),
           let today = PlacementDayCalendar.today(in: zone),
           let oldest = PlacementDayCalendar.shifted(today, by: -364, in: zone),
           let lower = PlacementDayCalendar.date(oldest, in: zone),
           let upper = PlacementDayCalendar.date(today, in: zone) {
            NavigationStack {
                DatePicker("Analysis day", selection: $draftDate, in: lower...upper, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Choose a day")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showDatePicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Show day") {
                                let date = PlacementDayCalendar.string(from: draftDate, in: zone)
                                showDatePicker = false
                                if let date { request(date) }
                            }
                        }
                    }
            }
            .environment(\.calendar, PlacementDayCalendar.calendar(in: zone))
            .environment(\.timeZone, zone)
        } else {
            ContentUnavailableView(
                "House time zone unavailable",
                systemImage: "clock",
                description: Text("The server didn't return a usable house time zone.")
            )
        }
    }

    private func beginDateSelection(_ day: PlacementDayInsights) {
        guard let zone = TimeZone(identifier: day.timeZone),
              let date = PlacementDayCalendar.date(day.date, in: zone) else { return }
        draftDate = date
        showDatePicker = true
    }

    private func shiftDate(by days: Int, in timeZoneID: String) {
        guard let selectedDate, let zone = TimeZone(identifier: timeZoneID),
              let next = PlacementDayCalendar.shifted(selectedDate, by: days, in: zone) else { return }
        request(next)
    }

    private func request(_ date: String?) {
        pendingDate = date
        Task { await load(date: date) }
    }

    @MainActor
    private func load(date: String?) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        isUnsupported = false
        defer { isLoading = false }
        do {
            let result = try await service.fetchDayInsights(date: date)
            guard !Task.isCancelled, service.isSessionValid else { return }
            insights = result
            selectedDate = result.date
            pendingDate = result.date
            if let zone = TimeZone(identifier: result.timeZone),
               let date = PlacementDayCalendar.date(result.date, in: zone) {
                draftDate = date
            }
        } catch {
            guard !Task.isCancelled else { return }
            if PlacementDayAPI.isUnsupported(error) {
                isUnsupported = true
            } else {
                self.error = Self.errorMessage(error)
            }
        }
    }

    private func loadError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
            Button("Retry") { request(pendingDate) }
                .disabled(isLoading)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    private static func errorMessage(_ error: Error) -> String {
        if let error = error as? PlacementRequestError {
            switch error {
            case .http(let status): return "Could not load this day (HTTP \(status)). Check the saved setup and retry."
            case .unauthorized: return "Sign in again to load day analysis."
            case .sessionChanged: return "Your session or saved setup changed. Retry to load the latest data."
            case .invalidResponse: return "The server returned an invalid day-analysis response."
            }
        }
        return "Could not load day analysis. Check your connection and retry."
    }

    private func temperature(_ value: Double?, unit: String) -> String {
        guard let value else { return "Unknown — insufficient data" }
        return "\(value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))) \(unit)"
    }

    private func minutes(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) min"
    }

    private func assessment(_ unusual: Bool?) -> String {
        switch unusual {
        case true: return "Unusual compared with the recent pattern"
        case false: return "No unusual shift detected with sufficient evidence"
        case nil: return "Unknown — insufficient evidence"
        }
    }

    private func sensorName(_ sensorID: String, in day: PlacementDayInsights) -> String {
        day.sensors.first(where: { $0.id == sensorID })?.name ?? sensorID
    }
}
