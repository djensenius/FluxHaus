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
    var airPurifier: AirPurifier
    var metrics: MetricsService
    @State private var whereWeAre = WhereWeAre()
    @State private var locationManager = LocationManager()
    @State private var authManager = AuthManager.shared
    @State private var chat = Chat()
    @State private var radarService = RadarService()
    @State private var selectedTab = "home"
    @State private var tabCustomization = TabViewCustomization()

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
        .background { tabKeyboardShortcuts }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("navigateToSection"))
        ) { notification in
            if let section = notification.userInfo?["section"] as? String {
                selectedTab = primaryTabValues.contains(section) ? section : "more"
            }
        }
    }

    private var primaryTabValues: Set<String> {
        authManager.isOIDC ? ["home", "weather", "assistant", "car", "more"] : ["home", "weather", "car", "more"]
    }

    private var moreTab: some View {
        NavigationStack {
            List {
                Section("Devices") {
                    NavigationLink(destination: scooterTab) {
                        Label {
                            Text("Scooter")
                        } icon: {
                            Image.flippedScooter
                        }
                    }
                    NavigationLink(destination: robotsTab) {
                        Label("Robots", systemImage: "robotic.vacuum.fill")
                    }
                    NavigationLink(destination: appliancesTab) {
                        Label("Appliances", systemImage: "washer.fill")
                    }
                }

                Section("Home") {
                    NavigationLink(destination: scenesTab) {
                        Label("Scenes", systemImage: "lightbulb.fill")
                    }
                    NavigationLink(destination: metricsTab) {
                        Label("Metrics", systemImage: "chart.xyaxis.line")
                    }
                    NavigationLink(destination: settingsTab) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background.ignoresSafeArea())
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var homeTab: some View {
        GeometryReader { proxy in
            if AdaptiveLayout.usesWideDashboard(width: proxy.size.width) {
                wideHomeLayout(width: proxy.size.width)
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
            appliancesGrid
            Spacer()
            footer
        }
    }

    private func wideHomeLayout(width: CGFloat) -> some View {
        let sidebarWidth = min(max(width * 0.34, 320), 440)
        return HStack(alignment: .top, spacing: Theme.Spacing.large) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                    DateTimeView()
                    WeatherView(lman: locationManager)
                    HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
                    footer
                }
                .padding()
            }
            .frame(width: sidebarWidth)
            .background(Theme.Colors.secondaryBackground.opacity(0.55))

            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                appliancesHeader
                appliancesGrid
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

    private var appliancesGrid: some View {
        Appliances(
            fluxHausConsts: fluxHausConsts,
            hconn: hconn,
            miele: miele,
            apiResponse: apiResponse,
            robots: robots,
            battery: battery,
            car: car,
            locationManager: locationManager,
            airPurifier: airPurifier
        )
    }

    private var weatherTab: some View {
        WeatherDetailView(
            locationManager: locationManager,
            radarService: radarService,
            metrics: metrics
        )
    }

    private var carTab: some View {
        CarDetailView(car: car, locationManager: locationManager)
    }

    private var scooterTab: some View {
        ScooterDetailView(scooter: scooter)
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
        NavigationStack {
            SettingsView()
        }
    }

    private var tabKeyboardShortcuts: some View {
        Group {
            Button("") { selectedTab = "home" }.keyboardShortcut("1")
            Button("") { selectedTab = "weather" }.keyboardShortcut("2")
            if authManager.isOIDC {
                Button("") { selectedTab = "assistant" }.keyboardShortcut("3")
                Button("") { selectedTab = "car" }.keyboardShortcut("4")
                Button("") { selectedTab = "more" }.keyboardShortcut("5")
            } else {
                Button("") { selectedTab = "car" }.keyboardShortcut("3")
                Button("") { selectedTab = "more" }.keyboardShortcut("4")
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

#if DEBUG
#Preview {
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
        apiResponse: MockData.createApi(),
        airPurifier: MockData.createAirPurifier(),
        metrics: MetricsService()
    )
}
#endif
