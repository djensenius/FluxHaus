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
    @State private var whereWeAre = WhereWeAre()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authManager = AuthManager.shared
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
            Tab(value: "scooter") {
                scooterTab
            } label: {
                Label {
                    Text("Scooter")
                } icon: {
                    Image(systemName: "scooter")
                        .scaleEffect(x: -1)
                }
            }
            .customizationID("scooter")
            TabSection {
                Tab("Appliances", systemImage: "washer.fill", value: "appliances") {
                    appliancesTab
                }
                .customizationID("appliances")
                Tab("Scenes", systemImage: "lightbulb.fill", value: "scenes") {
                    scenesTab
                }
                .customizationID("scenes")
                Tab("Robots", systemImage: "fan.fill", value: "robots") {
                    robotsTab
                }
                .customizationID("robots")
                Tab("Settings", systemImage: "gearshape", value: "settings") {
                    settingsTab
                }
                .customizationID("settings")
            } header: {
                Label("More", systemImage: "ellipsis")
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
                selectedTab = section
            }
        }
    }

    private var homeTab: some View {
        VStack {
            DateTimeView()
            WeatherView(lman: locationManager)
            HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
            HStack {
                Text("Appliances")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.leading)
                Spacer()
            }
            Appliances(
                fluxHausConsts: fluxHausConsts,
                hconn: hconn,
                miele: miele,
                apiResponse: apiResponse,
                robots: robots,
                battery: battery,
                car: car,
                locationManager: locationManager
            )
            Spacer()
            footer
        }
        .background(Theme.Colors.background)
    }

    private var weatherTab: some View {
        WeatherDetailView(
            locationManager: locationManager,
            radarService: radarService
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

    private var appliancesTab: some View {
        AppliancesDetailView(
            hconn: hconn,
            miele: miele,
            apiResponse: apiResponse,
            robots: robots
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
            Button("") { selectedTab = "assistant" }.keyboardShortcut("3")
            Button("") { selectedTab = "car" }.keyboardShortcut("4")
            Button("") { selectedTab = "scooter" }.keyboardShortcut("5")
            Button("") { selectedTab = "appliances" }.keyboardShortcut("6")
            Button("") { selectedTab = "scenes" }.keyboardShortcut("7")
            Button("") { selectedTab = "robots" }.keyboardShortcut("8")
            Button("") { selectedTab = "settings" }.keyboardShortcut("9")
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
        apiResponse: MockData.createApi()
    )
}
#endif
