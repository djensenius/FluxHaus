//
//  ClimateView.swift
//  FluxHaus
//
//  The Climate section: thermostat control, every room's reading, the air
//  purifier, and indoor history in one place.
//

import SwiftUI

struct ClimateView: View {
    var apiResponse: Api
    /// Owned above navigation and shared per signed-in session, so reopening Climate
    /// keeps feeding the same command queue.
    var thermostat: Thermostat
    var airPurifier: AirPurifier
    var metrics: MetricsService
    @State private var showHistory = false
    @State private var showPlacement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let state = thermostat.state, state.hasData {
                    ThermostatControlCard(thermostat: thermostat)
                    if !state.sensors.isEmpty {
                        sectionHeader("Rooms", detail: roomsDetail(state))
                        IndoorRoomsGrid(state: state)
                    }
                } else {
                    ContentUnavailableView(
                        "No Climate Data",
                        systemImage: "thermometer.medium.slash",
                        description: Text("FluxHaus hasn't received any thermostat readings yet.")
                    )
                }
                sectionHeader("Air")
                AirPurifierView(purifier: airPurifier)
                    .fluxDeviceAnnotation(.airPurifier)
                historyButton
                placementButton
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Climate")
        .refreshable {
            queryFlux(password: WhereWeAre.getPassword() ?? "")
        }
        .onChange(of: apiResponse.response?.indoorClimate?.timestamp) {
            thermostat.apiResponse = apiResponse
        }
        .onDisappear {
            Task { await thermostat.commitSetpoint() }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                IndoorClimateMetricsView(metrics: metrics)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showHistory = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPlacement) {
            NavigationStack {
                SensorPlacementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPlacement = false }
                        }
                    }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func roomsDetail(_ state: IndoorClimateState) -> String? {
        guard let range = state.temperatureRange else { return nil }
        let low = IndoorClimateFormat.temperature(range.lowerBound, unit: state.unit, precise: false)
        let high = IndoorClimateFormat.temperature(range.upperBound, unit: state.unit, precise: false)
        return "\(low) – \(high)"
    }

    private var historyButton: some View {
        Button {
            showHistory = true
        } label: {
            HStack {
                Label("Indoor history", systemImage: "chart.xyaxis.line")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding()
            #if !os(visionOS)
            .background(Theme.Colors.secondaryBackground)
            #endif
            .cornerRadius(Theme.cornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var placementButton: some View {
        Button {
            showPlacement = true
        } label: {
            HStack {
                Label("Sensor placement", systemImage: "thermometer.medium")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding()
            #if !os(visionOS)
            .background(Theme.Colors.secondaryBackground)
            #endif
            .cornerRadius(Theme.cornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
