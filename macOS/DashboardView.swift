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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                if !fluxHausConsts.favouriteHomeKit.isEmpty {
                    scenesSection
                }
                devicesGrid
                footerSection
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateString)
                    .font(.title2.weight(.semibold))
                Text(timeString)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Spacer()
            weatherSummary
        }
    }

    private var weatherSummary: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let weather = locationManager.weather {
                HStack(spacing: 4) {
                    Image(systemName: weatherIcon)
                        .symbolRenderingMode(.multicolor)
                    Text(temperatureString)
                        .font(.body)
                }
                if let condition = weather.currentWeather.condition
                    .description as String? {
                    Text(condition)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task {
            await locationManager.startMonitoring()
            await locationManager.fetchTheWeather()
        }
    }

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scenes")
                .font(.headline)
            SceneView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
        }
    }

    private var devicesGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Devices")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                carCard
                robotCard(name: "BroomBot", robot: robots.broomBot)
                robotCard(name: "MopBot", robot: robots.mopBot)
                ForEach(activeAppliances.indices, id: \.self) { idx in
                    applianceCard(activeAppliances[idx])
                }
            }
        }
    }

    private var carCard: some View {
        Button(action: { onNavigate(.car) }, label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(carIconColor)
                    Spacer()
                    Text("\(car.vehicle.batteryLevel)%")
                        .font(.title3.weight(.semibold))
                }
                Text("Car")
                    .font(.subheadline.weight(.medium))
                Text(carStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        })
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
    }

    private func robotCard(name: String, robot: Robot) -> some View {
        Button(action: { onNavigate(.robots) }, label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "fan.fill")
                        .foregroundColor(robotIconColor(robot))
                    Spacer()
                    if let batteryLvl = robot.batteryLevel {
                        Text("\(batteryLvl)%")
                            .font(.title3.weight(.semibold))
                    }
                }
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(robotStatusText(robot))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        })
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
    }

    private func applianceCard(_ appliance: Appliance) -> some View {
        Button(action: { onNavigate(.appliances) }, label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "washer.fill")
                        .foregroundColor(
                            appliance.inUse
                                ? Theme.Colors.accent : .secondary
                        )
                    Spacer()
                    if appliance.inUse && appliance.timeRemaining > 0 {
                        Text("\(appliance.timeRemaining)m")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(Theme.Colors.accent)
                    }
                }
                Text(appliance.name)
                    .font(.subheadline.weight(.medium))
                Text(appliance.inUse ? appliance.programName : "Off")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        })
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
    }

    private var footerSection: some View {
        HStack {
            Link(
                "Weather provided by  Weather",
                destination: URL(
                    string: "https://weatherkit.apple.com/legal-attribution.html"
                )!
            )
            .font(.caption)
            .foregroundColor(.secondary)
            Spacer()
            Button(action: {
                AuthManager.shared.signOut()
                NotificationCenter.default.post(
                    name: Notification.Name.logout,
                    object: nil,
                    userInfo: ["logout": true]
                )
            }, label: {
                Text("Logout")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.accent)
            })
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var activeAppliances: [Appliance] {
        let all = hconn.appliances + miele.appliances
        let active = all.filter { $0.inUse }
        return active.isEmpty ? all : active
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
        if car.vehicle.locked { parts.append("Locked") } else { parts.append("Unlocked") }
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
