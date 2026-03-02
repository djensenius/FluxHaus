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
    @State private var carButtonsDisabled = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                weatherCard
                scenesCard
                ForEach(sortedDeviceCards, id: \.id) { card in
                    card.view
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Dashboard")
        .task {
            await locationManager.startMonitoring()
            await locationManager.fetchTheWeather()
            await sceneManager.loadScenes(
                favouriteNames: fluxHausConsts.favouriteScenes
            )
        }
    }

    private struct DeviceCard: Identifiable {
        let id: String
        let isActive: Bool
        let view: AnyView
    }

    private var sortedDeviceCards: [DeviceCard] {
        var cards: [DeviceCard] = []
        let broomActive = robots.broomBot.running == true || robots.broomBot.paused == true
        cards.append(DeviceCard(
            id: "broomBot", isActive: broomActive,
            view: AnyView(robotCard(title: "BroomBot", robot: robots.broomBot, robotName: "broomBot", icon: "fan"))
        ))
        let mopActive = robots.mopBot.running == true || robots.mopBot.paused == true
        let mopView = robotCard(
            title: "MopBot", robot: robots.mopBot, robotName: "mopBot", icon: "humidifier.and.droplets"
        )
        cards.append(DeviceCard(id: "mopBot", isActive: mopActive, view: AnyView(mopView)))
        for (idx, item) in allAppliances.enumerated() {
            cards.append(DeviceCard(
                id: "appliance-\(idx)", isActive: item.appliance.inUse,
                view: AnyView(applianceCard(appliance: item.appliance, source: item.source))
            ))
        }
        cards.append(DeviceCard(id: "car", isActive: false, view: AnyView(carCard)))
        return cards.sorted { $0.isActive && !$1.isActive }
    }

    // MARK: - Weather
    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let weather = locationManager.weather {
                HStack(spacing: 16) {
                    Image(systemName: weatherIcon)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 42))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(temperatureString)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(weather.currentWeather.condition.description)
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if let high = highTemp, let low = lowTemp {
                        VStack(alignment: .trailing, spacing: 4) {
                            Label("H: \(high)", systemImage: "arrow.up")
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Label("L: \(low)", systemImage: "arrow.down")
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading weather…")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
    }

    // MARK: - Car
    private var carCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Car").font(Theme.Fonts.headerLarge()).foregroundColor(Theme.Colors.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                Text("EV Data Updated \(getCarTime(strDate: car.vehicle.evStatusTimestamp))")
                    .font(Theme.Fonts.caption).foregroundColor(Theme.Colors.textSecondary)
                Text("Battery: \(car.vehicle.batteryLevel)%, \(car.vehicle.distance) km")
                    .font(Theme.Fonts.bodyMedium).foregroundColor(Theme.Colors.textPrimary)
                HStack(spacing: 16) {
                    if car.vehicle.pluggedIn {
                        Label("Plugged in", systemImage: "powerplug.fill").foregroundColor(Theme.Colors.success)
                    } else {
                        Label("Unplugged", systemImage: "powerplug").foregroundColor(Theme.Colors.textSecondary)
                    }
                    if car.vehicle.batteryCharge {
                        Label("Charging", systemImage: "bolt.fill").foregroundColor(Theme.Colors.success)
                    }
                    if car.vehicle.locked {
                        Label("Locked", systemImage: "lock.fill").foregroundColor(Theme.Colors.textSecondary)
                    } else {
                        Label("Unlocked", systemImage: "lock.open.fill").foregroundColor(Theme.Colors.warning)
                    }
                }.font(Theme.Fonts.bodyMedium)
            }
            Divider()
            HStack(spacing: 8) {
                if car.vehicle.hvac {
                    Button(action: { performCarAction("stop") }, label: {
                        Label("Climate Off", systemImage: "snowflake.slash")
                    }).tint(.red)
                } else {
                    Button(action: { performCarAction("start") }, label: {
                        Label("Start Climate", systemImage: "snowflake")
                    }).tint(Theme.Colors.accent)
                }
                if car.vehicle.locked {
                    Button(action: { performCarAction("unlock") }, label: {
                        Label("Unlock", systemImage: "lock.open.fill")
                    })
                } else {
                    Button(action: { performCarAction("lock") }, label: {
                        Label("Lock", systemImage: "lock.fill")
                    })
                }
                Button(action: { performCarAction("rsync") }, label: {
                    Label("Resync", systemImage: "arrow.triangle.2.circlepath")
                })
                Spacer()
                Button(action: { onNavigate(.car) }, label: {
                    Text("Details →").font(Theme.Fonts.bodyMedium)
                }).buttonStyle(.plain).foregroundColor(Theme.Colors.accent)
            }.buttonStyle(.bordered).disabled(carButtonsDisabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
    }

    // MARK: - Robots
    private func robotCard(title: String, robot: Robot, robotName: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundColor(robotIconColor(robot))
                Text(title).font(Theme.Fonts.headerLarge()).foregroundColor(Theme.Colors.textPrimary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    robotStatusLabel(robot)
                    if let battery = robot.batteryLevel {
                        Label("\(battery)%", systemImage: batteryIcon(battery))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }.font(Theme.Fonts.bodyMedium)
                if robot.binFull == true {
                    Label("Bin Full", systemImage: "trash.fill")
                        .font(Theme.Fonts.bodyMedium).foregroundColor(Theme.Colors.error)
                }
                if robot.running == true, let started = robot.timeStarted {
                    Text("Started \(getCarTime(strDate: started))")
                        .font(Theme.Fonts.caption).foregroundColor(Theme.Colors.textSecondary)
                }
                Text("Updated \(getCarTime(strDate: robot.timestamp))")
                    .font(Theme.Fonts.caption).foregroundColor(Theme.Colors.textSecondary)
            }
            Divider()
            HStack(spacing: 8) {
                Button(action: { robots.performAction(action: "start", robot: robotName) }, label: {
                    Label("Start", systemImage: "play.fill")
                }).tint(Theme.Colors.accent).disabled(robot.running == true)
                Button(action: { robots.performAction(action: "stop", robot: robotName) }, label: {
                    Label("Stop", systemImage: "stop.fill")
                }).disabled(robot.running != true)
                Button(action: { robots.performAction(action: "dock", robot: robotName) }, label: {
                    Label("Dock", systemImage: "house.fill")
                })
                if robots.broomBot.running != true && robots.mopBot.running != true {
                    Button(action: { robots.performAction(action: "deepClean", robot: robotName) }, label: {
                        Label("Deep Clean", systemImage: "sparkles")
                    })
                }
            }.buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
    }

}

// MARK: - DashboardView Helpers

extension DashboardView {
    var allAppliances: [(source: String, appliance: Appliance)] {
        hconn.appliances.map { ("HomeConnect", $0) } +
        miele.appliances.map { ("Miele", $0) }
    }

    func applianceCard(appliance: Appliance, source: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: applianceIcon(appliance))
                    .foregroundColor(appliance.inUse ? Theme.Colors.accent : Theme.Colors.textSecondary)
                Text(appliance.name)
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(source).font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                if appliance.inUse {
                    if appliance.timeRunning > 0 {
                        Label("Running for \(appliance.timeRunning) min", systemImage: "timer")
                            .font(Theme.Fonts.bodyMedium).foregroundColor(Theme.Colors.textPrimary)
                    }
                    if appliance.timeRemaining > 0 {
                        Label(
                            "Done in \(appliance.timeRemaining) min · \(appliance.timeFinish)",
                            systemImage: "hourglass"
                        ).font(Theme.Fonts.bodyMedium).foregroundColor(Theme.Colors.textPrimary)
                    }
                    if !appliance.programName.isEmpty {
                        Text("Program: \(appliance.programName)")
                            .font(Theme.Fonts.bodyMedium).foregroundColor(Theme.Colors.textSecondary)
                    }
                    if !appliance.step.isEmpty {
                        Text("Step: \(appliance.step)")
                            .font(Theme.Fonts.bodyMedium).foregroundColor(Theme.Colors.textSecondary)
                    }
                } else {
                    Label("Off", systemImage: "power.circle")
                        .font(Theme.Fonts.bodyMedium).foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
    }

    var scenesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenes")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            if let error = sceneManager.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.warning)
            } else if !sceneManager.hasLoaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            } else if sceneManager.favourites.isEmpty {
                Text("No matching scenes")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(sceneManager.favourites) { scene in
                        Button(action: {
                            sceneManager.activate(scene, favouriteNames: fluxHausConsts.favouriteScenes)
                        }, label: {
                            HStack(spacing: 4) {
                                Image(systemName: scene.isActive == true ? "lightbulb.fill" : "lightbulb")
                                    .foregroundColor(
                                        scene.isActive == true ? Theme.Colors.accent : Theme.Colors.textSecondary
                                    )
                                Text(scene.name)
                                    .font(Theme.Fonts.bodyMedium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        })
                        .buttonStyle(.bordered)
                        .tint(scene.isActive == true ? Theme.Colors.accent : nil)
                        .disabled(sceneManager.activatingSceneId != nil)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
    }
    func performCarAction(_ action: String) {
        carButtonsDisabled = true
        car.performAction(action: action)
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task { @MainActor in
                if action != "resync" { car.performAction(action: "resync") }
                car.apiResponse = apiResponse
                car.fetchCarDetails()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 90.0, repeats: false) { _ in
            Task { @MainActor in
                car.performAction(action: "resync")
                car.apiResponse = apiResponse
                car.fetchCarDetails()
                carButtonsDisabled = false
            }
        }
    }

    @ViewBuilder
    func robotStatusLabel(_ robot: Robot) -> some View {
        if robot.running == true {
            Label("Running", systemImage: "play.circle.fill")
                .foregroundColor(Theme.Colors.accent)
        } else if robot.charging == true {
            Label("Charging", systemImage: "bolt.fill")
                .foregroundColor(Theme.Colors.success)
        } else if robot.docking == true {
            Label("Docking", systemImage: "house.fill")
                .foregroundColor(Theme.Colors.textSecondary)
        } else if robot.paused == true {
            Label("Paused", systemImage: "pause.circle.fill")
                .foregroundColor(Theme.Colors.warning)
        } else {
            Label("Idle", systemImage: "zzz")
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    func robotIconColor(_ robot: Robot) -> Color {
        if robot.running == true { return Theme.Colors.accent }
        if robot.charging == true { return Theme.Colors.success }
        if robot.binFull == true { return Theme.Colors.error }
        return Theme.Colors.textSecondary
    }

    func batteryIcon(_ level: Int) -> String {
        if level > 75 { return "battery.100percent" }
        if level > 50 { return "battery.75percent" }
        if level > 25 { return "battery.50percent" }
        return "battery.25percent"
    }

    func applianceIcon(_ appliance: Appliance) -> String {
        let lower = appliance.name.lowercased()
        if lower.contains("dish") { return "dishwasher.fill" }
        if lower.contains("wash") { return "washer.fill" }
        if lower.contains("dryer") || lower.contains("dry") { return "dryer.fill" }
        if lower.contains("oven") { return "oven.fill" }
        if lower.contains("fridge") || lower.contains("refrig") { return "refrigerator.fill" }
        return "powerplug.fill"
    }

    var temperatureString: String {
        guard let weather = locationManager.weather else { return "" }
        let measurement = Measurement(
            value: weather.currentWeather.temperature.value,
            unit: UnitTemperature.celsius
        )
        let fmt = MeasurementFormatter()
        fmt.numberFormatter.maximumFractionDigits = 0
        return fmt.string(from: measurement)
    }

    var highTemp: String? {
        guard let weather = locationManager.weather,
              let today = weather.dailyForecast.first else { return nil }
        let fmt = MeasurementFormatter()
        fmt.numberFormatter.maximumFractionDigits = 0
        return fmt.string(from: Measurement(
            value: today.highTemperature.value, unit: UnitTemperature.celsius
        ))
    }

    var lowTemp: String? {
        guard let weather = locationManager.weather,
              let today = weather.dailyForecast.first else { return nil }
        let fmt = MeasurementFormatter()
        fmt.numberFormatter.maximumFractionDigits = 0
        return fmt.string(from: Measurement(
            value: today.lowTemperature.value, unit: UnitTemperature.celsius
        ))
    }

    var weatherIcon: String {
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
                config: FluxHausConfig(favouriteHomeKit: ["Light 1"], favouriteScenes: [])
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
