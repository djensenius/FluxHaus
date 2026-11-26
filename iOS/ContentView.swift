//
//  ContentView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import SwiftUI

struct ContentView: View {
    var fluxHausConsts: FluxHausConsts
    var hconn: HomeConnect
    var miele: Miele
    var robots: Robots
    var battery: Battery
    var car: Car
    var scooter: Scooter
    var apiResponse: Api
    var thermostat: Thermostat
    var airPurifier: AirPurifier
    var metrics: MetricsService
    @State private var whereWeAre = WhereWeAre()
    @State private var locationManager = LocationManager()
    @State private var authManager = AuthManager.shared
    @State private var chat = Chat()
    @State private var radarService = RadarService()
    @State private var selectedTab = "home"
    @State private var morePath: [String] = []
    @State private var tabCustomization = TabViewCustomization()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Climate is its own tab in wide iPad windows; on iPhone (even a large one in landscape,
    /// which is also regular width) and in narrow iPad windows it heads the More list.
    private var showsClimateTab: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: "home") {
                homeTab
            }
            .customizationID("home")
            Tab("Weather", systemImage: "cloud.sun.fill", value: "weather") {
                weatherTab
            }
            .customizationID("weather")
            if showsClimateTab {
                Tab("Climate", systemImage: "thermometer.medium", value: "climate") {
                    NavigationStack { climateView }
                }
                .customizationID("climate")
            }
            if authManager.isOIDC {
                Tab("Assistant", systemImage: "bubble.left.and.bubble.right.fill", value: "assistant") {
                    ChatView(chat: chat)
                }
                .customizationID("assistant")
            }
            Tab("Car", systemImage: "car.fill", value: "car") {
                carTab
            }
            .customizationID("car")
            Tab("More", systemImage: "ellipsis.circle", value: "more") {
                moreTab
            }
            .customizationID("more")
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabCustomization)
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("navigateToSection"))
        ) { notification in
            if let section = notification.userInfo?["section"] as? String {
                handleNavigationRequest(section)
            }
        }
        .onChange(of: showsClimateTab) { _, hasTab in
            if hasTab, selectedTab == "more", morePath == ["climate"] {
                selectedTab = "climate"
                morePath = []
            } else if !hasTab, selectedTab == "climate" {
                selectedTab = "more"
                morePath = ["climate"]
            }
        }
    }

    private var primaryTabValues: Set<String> {
        var tabs: Set<String> = ["home", "weather", "car", "more"]
        if authManager.isOIDC { tabs.insert("assistant") }
        if showsClimateTab { tabs.insert("climate") }
        return tabs
    }

    private var moreDestinationValues: Set<String> {
        ["climate", "scooter", "cleanbot", "robots", "appliances", "scenes", "metrics", "settings"]
    }

    private func handleNavigationRequest(_ requestedSection: String) {
        let section = requestedSection.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !section.isEmpty else { return }

        if primaryTabValues.contains(section) {
            selectedTab = section
            if section != "more" {
                morePath = []
            }
        } else if moreDestinationValues.contains(section) {
            selectedTab = "more"
            morePath = [section == "robots" ? "cleanbot" : section]
        }
    }

    private var moreTab: some View {
        NavigationStack(path: $morePath) {
            List {
                if !showsClimateTab {
                    Section {
                        NavigationLink(value: "climate") {
                            Label("Climate", systemImage: "thermometer.medium")
                        }
                    }
                    .listRowBackground(Theme.Colors.secondaryBackground)
                }

                Section("Devices") {
                    NavigationLink(value: "scooter") {
                        Label {
                            Text("Scooter")
                        } icon: {
                            Image.flippedScooter
                        }
                    }
                    NavigationLink(value: "cleanbot") {
                        Label("Cleanbot", systemImage: "robotic.vacuum.fill")
                    }
                    NavigationLink(value: "appliances") {
                        Label("Appliances", systemImage: "washer.fill")
                    }
                }
                .listRowBackground(Theme.Colors.secondaryBackground)

                Section("Home") {
                    NavigationLink(value: "scenes") {
                        Label("Scenes", systemImage: "lightbulb.fill")
                    }
                    NavigationLink(value: "metrics") {
                        Label("Metrics", systemImage: "chart.xyaxis.line")
                    }
                    NavigationLink(value: "settings") {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .listRowBackground(Theme.Colors.secondaryBackground)
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: String.self) { destination in
                moreDestination(for: destination)
            }
            .navigationTitle("More")
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background.ignoresSafeArea())
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func moreDestination(for destination: String) -> some View {
        switch destination {
        case "climate":
            climateView
        case "scooter":
            scooterTab
        case "cleanbot", "robots":
            RobotDetailView(robot: robots.cleanBot, robots: robots, embedsInNavigationStack: false)
                .navigationTitle("Cleanbot")
        case "appliances":
            appliancesTab
        case "scenes":
            scenesTab
        case "metrics":
            metricsTab
        case "settings":
            settingsTab
        default:
            ContentUnavailableView("Unknown Destination", systemImage: "questionmark.circle")
        }
    }

    private var homeTab: some View {
        GeometryReader { proxy in
            if AdaptiveLayout.usesWideDashboard(width: proxy.size.width) {
                wideHomeLayout
            } else {
                compactHomeLayout
            }
        }
        .background(Theme.Colors.background)
    }

    private var compactHomeLayout: some View {
        VStack {
            DateTimeView()
            WeatherView(lman: locationManager)
            HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
            appliancesHeader
            appliancesGrid()
            Spacer()
            footer
        }
    }

    /// One full-width scrolling dashboard: date and weather side by side, then the
    /// device cards across as many columns as fit, then HomeKit favourites.
    private var wideHomeLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                HStack(alignment: .top, spacing: Theme.Spacing.large) {
                    DateTimeView(leading: true)
                    WeatherView(lman: locationManager)
                }
                appliancesHeader
                appliancesGrid(scrolls: false)
                HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
                footer
            }
            .padding(.vertical)
            .frame(maxWidth: AdaptiveLayout.dashboardMaxContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var climateView: some View {
        ClimateView(apiResponse: apiResponse, thermostat: thermostat, airPurifier: airPurifier, metrics: metrics)
    }

    private var appliancesHeader: some View {
        HStack {
            Text("Appliances")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.leading)
            Spacer()
        }
    }

    private func appliancesGrid(scrolls: Bool = true) -> some View {
        Appliances(
            fluxHausConsts: fluxHausConsts,
            hconn: hconn,
            miele: miele,
            apiResponse: apiResponse,
            robots: robots,
            battery: battery,
            car: car,
            locationManager: locationManager,
            airPurifier: airPurifier,
            onOpenClimate: { handleNavigationRequest("climate") },
            scrolls: scrolls
        )
    }

    private var weatherTab: some View {
        WeatherDetailView(
            locationManager: locationManager,
            radarService: radarService,
            metrics: metrics,
            apiResponse: apiResponse
        )
    }

    private var carTab: some View {
        CarDetailView(car: car, locationManager: locationManager)
    }

    private var scooterTab: some View {
        ScooterDetailView(scooter: scooter, embedsInNavigationStack: false)
    }

    private var scenesTab: some View {
        SceneView(favouriteScenes: fluxHausConsts.favouriteScenes)
    }

    private var robotsTab: some View {
        RobotsListView(robots: robots)
    }

    private var metricsTab: some View {
        ScrollView {
            MetricsView(metrics: metrics)
        }
        .background(Theme.Colors.background)
    }

    private var appliancesTab: some View {
        AppliancesDetailView(
            hconn: hconn,
            miele: miele,
            apiResponse: apiResponse,
            robots: robots,
            airPurifier: airPurifier
        )
    }

    private var footer: some View {
        HStack {
            Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                Text("Weather data provided by \(Image(systemName: "apple.logo")) Weather")
            }
            .font(Theme.Fonts.caption)
            .foregroundColor(Theme.Colors.textSecondary)
            .padding([.bottom, .leading])

            Spacer()
        }
    }

    private var settingsTab: some View {
        SettingsView()
    }

}

#if DEBUG
#Preview {
    let api = MockData.createApi()
    ContentView(
        fluxHausConsts: {
            let config = FluxHausConsts()
            config.setConfig(config: FluxHausConfig(favouriteHomeKit: ["Light 1", "Light 2"], favouriteScenes: []))
            return config
        }(),
        hconn: MockData.createHomeConnect(),
        miele: MockData.createMiele(),
        robots: MockData.createRobots(),
        battery: MockData.createBattery(),
        car: MockData.createCar(),
        scooter: Scooter(),
        apiResponse: api,
        thermostat: Thermostat(apiResponse: api),
        airPurifier: MockData.createAirPurifier(),
        metrics: MetricsService()
    )
}
#endif
