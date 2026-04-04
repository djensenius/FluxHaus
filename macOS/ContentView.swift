//
//  ContentView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case weather = "Weather"
    case scenes = "Scenes"
    case appliances = "Appliances"
    case car = "Car"
    case robots = "Robots"
    case assistant = "Assistant"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .weather: return "cloud.sun.fill"
        case .scenes: return "lightbulb.fill"
        case .appliances: return "washer.fill"
        case .car: return "car.fill"
        case .robots: return "fan.fill"
        case .assistant: return "bubble.left.and.bubble.right.fill"
        }
    }
}

struct ContentView: View {
    var fluxHausConsts: FluxHausConsts
    var hconn: HomeConnect
    var miele: Miele
    var robots: Robots
    var battery: Battery
    var car: Car
    var apiResponse: Api
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authManager = AuthManager.shared
    @State private var chat = Chat()
    @State private var radarService = RadarService()
    @State private var selectedItem: SidebarItem = .dashboard

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 600)
        .background { keyboardShortcuts }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("navigateToSection"))
        ) { notification in
            if let rawValue = notification.userInfo?["section"] as? String,
               let section = SidebarItem(rawValue: rawValue) {
                selectedItem = section
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    queryFlux(password: WhereWeAre.getPassword() ?? "")
                }, label: {
                    Image(systemName: "arrow.clockwise")
                })
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedItem) {
            ForEach(SidebarItem.allCases) { item in
                if item == .assistant && !authManager.isOIDC {
                    EmptyView()
                } else {
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
        }
        .navigationTitle("FluxHaus")
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { selectedItem = .dashboard }.keyboardShortcut("1")
            Button("") { selectedItem = .weather }.keyboardShortcut("2")
            Button("") { selectedItem = .scenes }.keyboardShortcut("3")
            Button("") { selectedItem = .appliances }.keyboardShortcut("4")
            Button("") { selectedItem = .car }.keyboardShortcut("5")
            Button("") { selectedItem = .robots }.keyboardShortcut("6")
            Button("") { selectedItem = .assistant }.keyboardShortcut("7")
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .dashboard:
            DashboardView(
                fluxHausConsts: fluxHausConsts,
                hconn: hconn,
                miele: miele,
                robots: robots,
                battery: battery,
                car: car,
                apiResponse: apiResponse,
                locationManager: locationManager,
                radarService: radarService,
                onNavigate: { selectedItem = $0 }
            )
        case .weather:
            WeatherDetailView(
                locationManager: locationManager,
                radarService: radarService
            )
            .navigationTitle("Weather")
        case .scenes:
            SceneView(favouriteScenes: fluxHausConsts.favouriteScenes)
                .navigationTitle("Scenes")
        case .appliances:
            AppliancesMacView(hconn: hconn, miele: miele)
                .navigationTitle("Appliances")
        case .car:
            CarDetailView(car: car, locationManager: locationManager)
                .navigationTitle("Car")
        case .robots:
            RobotsMacView(robots: robots)
                .navigationTitle("Robots")
        case .assistant:
            ChatView(chat: chat)
                .navigationTitle("Assistant")
        }
    }

}

struct AppliancesMacView: View {
    var hconn: HomeConnect
    var miele: Miele

    private var allAppliances: [(source: String, appliance: Appliance)] {
        hconn.appliances.map { ("HomeConnect", $0) } +
        miele.appliances.map { ("Miele", $0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if allAppliances.isEmpty {
                    ContentUnavailableView(
                        "No Appliances",
                        systemImage: "washer.fill",
                        description: Text("All appliances are off")
                    )
                } else {
                    ForEach(
                        Array(allAppliances.enumerated()),
                        id: \.offset
                    ) { _, item in
                        applianceCard(
                            appliance: item.appliance,
                            source: item.source
                        )
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
    }

    private func applianceCard(
        appliance: Appliance,
        source: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: applianceIcon(appliance))
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(
                        appliance.inUse
                            ? Theme.Colors.accent
                            : Theme.Colors.textSecondary
                    )
                Text(appliance.name)
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(source)
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                if appliance.inUse {
                    if appliance.timeRunning > 0 {
                        Label(
                            "Running for \(formatDurationMinutes(appliance.timeRunning))",
                            systemImage: "timer"
                        )
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                    }
                    if appliance.timeRemaining > 0 {
                        Label(
                            "Done in \(formatDurationMinutes(appliance.timeRemaining)) · \(appliance.timeFinish)",
                            systemImage: "hourglass"
                        )
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                    }
                    if !appliance.programName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label(
                            formatApplianceProgramName(appliance.programName),
                            systemImage: "list.bullet"
                        )
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                    }
                    if !appliance.step.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label(
                            formatApplianceProgramName(appliance.step),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                    }
                } else {
                    Label("Off", systemImage: "power.circle")
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

    private func applianceIcon(_ appliance: Appliance) -> String {
        let lower = appliance.name.lowercased()
        if lower.contains("dish") { return "dishwasher.fill" }
        if lower.contains("wash") { return "washer.fill" }
        if lower.contains("dryer") || lower.contains("dry") {
            return "dryer.fill"
        }
        if lower.contains("oven") { return "oven.fill" }
        if lower.contains("fridge") || lower.contains("refrig") {
            return "refrigerator.fill"
        }
        return "powerplug.fill"
    }
}

struct RobotsMacView: View {
    var robots: Robots

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                robotCard(
                    title: "BroomBot",
                    robot: robots.broomBot,
                    robotName: "broomBot",
                    icon: "fan"
                )
                robotCard(
                    title: "MopBot",
                    robot: robots.mopBot,
                    robotName: "mopBot",
                    icon: "humidifier.and.droplets"
                )
            }
            .padding()
        }
        .background(Theme.Colors.background)
    }

    private func robotCard(
        title: String,
        robot: Robot,
        robotName: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(statusColor(robot))
                Text(title)
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            // Status rows
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    statusLabel(robot)
                    if let battery = robot.batteryLevel {
                        Label(
                            "\(battery)%",
                            systemImage: batteryIcon(battery)
                        )
                        .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
                .font(Theme.Fonts.bodyMedium)

                if robot.binFull == true {
                    Label("Bin Full", systemImage: "trash.fill")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.error)
                }

                if robot.running == true,
                   let started = robot.timeStarted {
                    Text(
                        "Started \(getCarTime(strDate: started))"
                    )
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                }

                Text(
                    "Updated \(getCarTime(strDate: robot.timestamp))"
                )
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            }

            Divider()

            // Controls
            HStack(spacing: 8) {
                Button(action: {
                    robots.performAction(
                        action: "start", robot: robotName
                    )
                }, label: {
                    Label("Start", systemImage: "play.fill")
                })
                .tint(Theme.Colors.accent)
                .disabled(robot.running == true)

                Button(action: {
                    robots.performAction(
                        action: "stop", robot: robotName
                    )
                }, label: {
                    Label("Stop", systemImage: "stop.fill")
                })
                .disabled(robot.running != true)

                Button(action: {
                    robots.performAction(
                        action: "dock", robot: robotName
                    )
                }, label: {
                    Label("Dock", systemImage: "house.fill")
                })

                if robots.broomBot.running != true
                    && robots.mopBot.running != true {
                    Button(action: {
                        robots.performAction(
                            action: "deepClean", robot: robotName
                        )
                    }, label: {
                        Label("Deep Clean", systemImage: "sparkles")
                    })
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func statusLabel(_ robot: Robot) -> some View {
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

    private func statusColor(_ robot: Robot) -> Color {
        if robot.running == true { return Theme.Colors.accent }
        if robot.charging == true { return Theme.Colors.success }
        if robot.binFull == true { return Theme.Colors.error }
        return Theme.Colors.textSecondary
    }

    private func batteryIcon(_ level: Int) -> String {
        if level > 75 { return "battery.100percent" }
        if level > 50 { return "battery.75percent" }
        if level > 25 { return "battery.50percent" }
        return "battery.25percent"
    }
}

#if DEBUG
#Preview {
    ContentView(
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
        apiResponse: MockData.createApi()
    )
}
#endif
