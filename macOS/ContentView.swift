//
//  ContentView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case scenes = "Scenes"
    case appliances = "Appliances"
    case car = "Car"
    case robots = "Robots"
    case assistant = "Assistant"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
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
    @State private var chat = Chat()
    @State private var selectedItem: SidebarItem = .dashboard

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    queryFlux(password: WhereWeAre.getPassword() ?? "")
                }, label: {
                    Image(systemName: "arrow.clockwise")
                })
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedItem) {
            ForEach(SidebarItem.allCases) { item in
                if item == .assistant && !AuthManager.hasOIDCToken() {
                    EmptyView()
                } else {
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
        }
        .navigationTitle("FluxHaus")
        .overlay {
            hiddenShortcuts
        }
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
                onNavigate: { selectedItem = $0 }
            )
        case .scenes:
            SceneView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
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

    private var hiddenShortcuts: some View {
        Group {
            Button("") { selectedItem = .dashboard }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { selectedItem = .scenes }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { selectedItem = .appliances }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { selectedItem = .car }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { selectedItem = .robots }
                .keyboardShortcut("5", modifiers: .command)
            Button("") {
                if AuthManager.hasOIDCToken() {
                    selectedItem = .assistant
                }
            }
            .keyboardShortcut("6", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

struct AppliancesMacView: View {
    var hconn: HomeConnect
    var miele: Miele

    var body: some View {
        List {
            if !hconn.appliances.isEmpty {
                Section("HomeConnect") {
                    ForEach(
                        Array(hconn.appliances.enumerated()),
                        id: \.offset
                    ) { _, appliance in
                        applianceRow(appliance)
                    }
                }
            }
            if !miele.appliances.isEmpty {
                Section("Miele") {
                    ForEach(
                        Array(miele.appliances.enumerated()),
                        id: \.offset
                    ) { _, appliance in
                        applianceRow(appliance)
                    }
                }
            }
            if hconn.appliances.isEmpty && miele.appliances.isEmpty {
                ContentUnavailableView(
                    "No Appliances",
                    systemImage: "washer.fill",
                    description: Text("All appliances are off")
                )
            }
        }
    }

    private func applianceRow(_ appliance: Appliance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "washer.fill")
                .font(.title3)
                .foregroundColor(
                    appliance.inUse ? Theme.Colors.accent : .secondary
                )
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(appliance.name)
                    .font(.body)
                if !appliance.programName.isEmpty {
                    Text(appliance.programName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if appliance.inUse {
                if appliance.timeRemaining > 0 {
                    Text("\(appliance.timeRemaining)m remaining")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.accent)
                } else {
                    Text("Running")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.accent)
                }
            } else {
                Text("Off")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct RobotsMacView: View {
    var robots: Robots

    var body: some View {
        List {
            Section("BroomBot") {
                robotRows(robot: robots.broomBot, robots: robots, name: "broomBot")
            }
            Section("MopBot") {
                robotRows(robot: robots.mopBot, robots: robots, name: "mopBot")
            }
        }
    }

    private func robotRows(robot: Robot, robots: Robots, name: String) -> some View {
        Group {
            HStack {
                Label("Status", systemImage: "circle.fill")
                    .foregroundColor(statusColor(robot))
                Spacer()
                Text(statusText(robot))
                    .foregroundColor(.secondary)
            }
            if let battery = robot.batteryLevel {
                HStack {
                    Label("Battery", systemImage: "battery.50percent")
                    Spacer()
                    Text("\(battery)%")
                        .foregroundColor(.secondary)
                }
            }
            if robot.binFull == true {
                HStack {
                    Label("Bin", systemImage: "trash.fill")
                        .foregroundColor(Theme.Colors.error)
                    Spacer()
                    Text("Full")
                        .foregroundColor(Theme.Colors.error)
                }
            }
            HStack(spacing: 12) {
                Button("Start") {
                    robots.performAction(action: "start", robot: name)
                }
                .disabled(robot.running == true)
                Button("Stop") {
                    robots.performAction(action: "stop", robot: name)
                }
                .disabled(robot.running != true)
                Button("Dock") {
                    robots.performAction(action: "dock", robot: name)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func statusColor(_ robot: Robot) -> Color {
        if robot.running == true { return Theme.Colors.accent }
        if robot.charging == true { return Theme.Colors.success }
        if robot.binFull == true { return Theme.Colors.error }
        return .secondary
    }

    private func statusText(_ robot: Robot) -> String {
        if robot.running == true { return "Running" }
        if robot.charging == true { return "Charging" }
        if robot.docking == true { return "Docking" }
        if robot.paused == true { return "Paused" }
        return "Idle"
    }
}

#if DEBUG
#Preview {
    ContentView(
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
        apiResponse: MockData.createApi()
    )
}
#endif
