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
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                scenesSection
                devicesGrid
                footerSection
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            DateTimeView()
            Spacer()
            WeatherView(lman: locationManager)
        }
    }

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenes")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            SceneView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
        }
    }

    private var devicesGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            LazyVGrid(columns: columns, spacing: 16) {
                carCard
                robotCard(name: "BroomBot", robot: robots.broomBot)
                robotCard(name: "MopBot", robot: robots.mopBot)
                ForEach(hconn.appliances.indices, id: \.self) { idx in
                    applianceCard(hconn.appliances[idx])
                }
                ForEach(miele.appliances.indices, id: \.self) { idx in
                    applianceCard(miele.appliances[idx])
                }
            }
        }
    }

    private var carCard: some View {
        Button(action: { onNavigate(.car) }, label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "car.fill")
                        .font(.title2)
                        .foregroundColor(carIconColor)
                    Spacer()
                    Text("\(car.vehicle.batteryLevel)%")
                        .font(Theme.Fonts.headerXL())
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                Text("Car")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(carStatusText)
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        })
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
    }

    private func robotCard(name: String, robot: Robot) -> some View {
        Button(action: { onNavigate(.robots) }, label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "fan.fill")
                        .font(.title2)
                        .foregroundColor(robotIconColor(robot))
                    Spacer()
                    if let battery = robot.batteryLevel {
                        Text("\(battery)%")
                            .font(Theme.Fonts.headerXL())
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
                Text(name)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(robotStatusText(robot))
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        })
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
    }

    private func applianceCard(_ appliance: Appliance) -> some View {
        Button(action: { onNavigate(.appliances) }, label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "washer.fill")
                        .font(.title2)
                        .foregroundColor(
                            appliance.inUse
                                ? Theme.Colors.accent : Theme.Colors.textSecondary
                        )
                    Spacer()
                    if appliance.inUse && appliance.timeRemaining > 0 {
                        Text("\(appliance.timeRemaining)m")
                            .font(Theme.Fonts.headerXL())
                            .foregroundColor(Theme.Colors.accent)
                    }
                }
                Text(appliance.name)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(appliance.inUse ? appliance.programName : "Off")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .padding()
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
            .font(Theme.Fonts.caption)
            .foregroundColor(Theme.Colors.textSecondary)
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
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.accent)
            })
            .buttonStyle(.plain)
        }
    }

    private var carIconColor: Color {
        if car.vehicle.pluggedIn || car.vehicle.batteryCharge {
            return Theme.Colors.success
        } else if car.vehicle.hvac || car.vehicle.engine {
            return Theme.Colors.accent
        }
        return Theme.Colors.textSecondary
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
        return Theme.Colors.textSecondary
    }

    private func robotStatusText(_ robot: Robot) -> String {
        if robot.running == true { return "Running" }
        if robot.charging == true { return "Charging" }
        if robot.docking == true { return "Docking" }
        if robot.paused == true { return "Paused" }
        return "Idle"
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
