//
//  DashboardView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

struct DashboardView: View {
    var fluxHausConsts: FluxHausConsts
    var hconn: HomeConnect
    var miele: Miele
    var robots: Robots
    var battery: Battery
    var car: Car
    var apiResponse: Api
    @ObservedObject var locationManager: LocationManager
    var onNavigate: (SidebarItem) -> Void
    @State private var sceneManager = SceneManager()

    var body: some View {
        List {
            overviewSection
            if !sceneManager.favourites.isEmpty {
                scenesListSection
            }
            devicesSection
            appliancesSection
        }
        .listStyle(.sidebar)
        .navigationTitle("Dashboard")
        .task {
            await locationManager.startMonitoring()
            await locationManager.fetchTheWeather()
            await sceneManager.loadScenes(
                favouriteNames: fluxHausConsts.favouriteHomeKit
            )
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateString)
                        .font(.title3.weight(.semibold))
                    Text(timeString)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let weather = locationManager.weather {
                    HStack(spacing: 6) {
                        Image(systemName: weatherIcon)
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                        Text(temperatureString)
                            .font(.title3.weight(.medium))
                    }
                }
            }
        }
    }

    // MARK: - Scenes

    private var scenesListSection: some View {
        Section("Scenes") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                spacing: 8
            ) {
                ForEach(sceneManager.favourites) { scene in
                    Button(action: {
                        sceneManager.activate(scene)
                    }, label: {
                        Text(scene.name)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    })
                    .buttonStyle(.bordered)
                    .disabled(sceneManager.activatingSceneId != nil)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        Section("Devices") {
            Button(action: { onNavigate(.car) }, label: {
                HStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .font(.title3)
                        .foregroundColor(carIconColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Car")
                            .font(.body)
                        Text(carStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(car.vehicle.batteryLevel)%")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)

            Button(action: { onNavigate(.robots) }, label: {
                deviceRow(
                    icon: "fan.fill",
                    iconColor: robotIconColor(robots.broomBot),
                    name: "BroomBot",
                    status: robotStatusText(robots.broomBot),
                    detail: robots.broomBot.batteryLevel.map { "\($0)%" }
                )
            })
            .buttonStyle(.plain)

            Button(action: { onNavigate(.robots) }, label: {
                deviceRow(
                    icon: "fan.fill",
                    iconColor: robotIconColor(robots.mopBot),
                    name: "MopBot",
                    status: robotStatusText(robots.mopBot),
                    detail: robots.mopBot.batteryLevel.map { "\($0)%" }
                )
            })
            .buttonStyle(.plain)
        }
    }

    private func deviceRow(
        icon: String,
        iconColor: Color,
        name: String,
        status: String,
        detail: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let detail {
                Text(detail)
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Appliances

    private var allAppliances: [Appliance] {
        hconn.appliances + miele.appliances
    }

    private var appliancesSection: some View {
        Section("Appliances") {
            if allAppliances.isEmpty {
                Text("No appliances connected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(
                    Array(allAppliances.enumerated()),
                    id: \.offset
                ) { _, appliance in
                    Button(action: { onNavigate(.appliances) }, label: {
                        HStack(spacing: 12) {
                            Image(systemName: applianceIcon(appliance))
                                .font(.title3)
                                .foregroundColor(
                                    appliance.inUse ? Theme.Colors.accent : .secondary
                                )
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appliance.name)
                                    .font(.body)
                                Text(
                                    appliance.inUse
                                        ? appliance.programName : "Off"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            if appliance.inUse && appliance.timeRemaining > 0 {
                                Text("\(appliance.timeRemaining)m")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(Theme.Colors.accent)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .contentShape(Rectangle())
                    })
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func applianceIcon(_ appliance: Appliance) -> String {
        let lower = appliance.name.lowercased()
        if lower.contains("washer") || lower.contains("wash") {
            return "washer.fill"
        }
        if lower.contains("dryer") { return "dryer.fill" }
        if lower.contains("dish") { return "dishwasher.fill" }
        if lower.contains("oven") { return "oven.fill" }
        if lower.contains("fridge") || lower.contains("refrig") {
            return "refrigerator.fill"
        }
        return "powerplug.fill"
    }

    private var carIconColor: Color {
        if car.vehicle.pluggedIn || car.vehicle.batteryCharge {
            return Theme.Colors.success
        } else if car.vehicle.hvac || car.vehicle.engine {
            return Theme.Colors.accent
        }
        return .secondary
    }

    private var carStatusText: String {
        var parts: [String] = []
        if car.vehicle.locked {
            parts.append("Locked")
        } else {
            parts.append("Unlocked")
        }
        if car.vehicle.pluggedIn { parts.append("Plugged in") }
        if car.vehicle.hvac { parts.append("Climate on") }
        return parts.joined(separator: " · ")
    }

    private func robotIconColor(_ robot: Robot) -> Color {
        if robot.running == true { return Theme.Colors.accent }
        if robot.charging == true { return Theme.Colors.success }
        if robot.binFull == true { return Theme.Colors.error }
        return .secondary
    }

    private func robotStatusText(_ robot: Robot) -> String {
        if robot.running == true { return "Running" }
        if robot.charging == true { return "Charging" }
        if robot.docking == true { return "Docking" }
        if robot.paused == true { return "Paused" }
        return "Idle"
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }

    private var temperatureString: String {
        guard let weather = locationManager.weather else { return "" }
        let temp = weather.currentWeather.temperature
        let measurement = Measurement(
            value: temp.value,
            unit: UnitTemperature.celsius
        )
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: measurement)
    }

    private var weatherIcon: String {
        guard let weather = locationManager.weather else { return "cloud" }
        switch weather.currentWeather.condition {
        case .clear, .mostlyClear: return "sun.max.fill"
        case .cloudy, .mostlyCloudy: return "cloud.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .rain, .heavyRain: return "cloud.rain.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .snow, .heavySnow, .flurries: return "cloud.snow.fill"
        case .sleet, .freezingRain: return "cloud.sleet.fill"
        case .thunderstorms: return "cloud.bolt.fill"
        case .foggy, .haze: return "cloud.fog.fill"
        case .windy, .breezy: return "wind"
        default: return "cloud"
        }
    }
}

#if DEBUG
#Preview {
    DashboardView(
        fluxHausConsts: {
            let config = FluxHausConsts()
            config.setConfig(
                config: FluxHausConfig(favouriteHomeKit: ["Light 1"])
            )
            return config
        }(),
        hconn: MockData.createHomeConnect(),
        miele: MockData.createMiele(),
        robots: MockData.createRobots(),
        battery: MockData.createBattery(),
        car: MockData.createCar(),
        apiResponse: MockData.createApi(),
        locationManager: LocationManager(),
        onNavigate: { _ in }
    )
}
#endif
