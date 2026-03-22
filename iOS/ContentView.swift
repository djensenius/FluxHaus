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
    var apiResponse: Api
    @State private var whereWeAre = WhereWeAre()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authManager = AuthManager.shared
    @State private var chat = Chat()
    @State private var radarService = RadarService()
    @State private var selectedTab = "home"
    @State private var showNotificationSettings = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag("home")
            weatherTab
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
                .tag("weather")
            if horizontalSizeClass == .regular {
                scenesTab
                    .tabItem { Label("Scenes", systemImage: "lightbulb.fill") }
                    .tag("scenes")
            }
            appliancesTab
                .tabItem { Label("Appliances", systemImage: "washer.fill") }
                .tag("appliances")
            carTab
                .tabItem { Label("Car", systemImage: "car.fill") }
                .tag("car")
            if horizontalSizeClass == .regular {
                robotsTab
                    .tabItem { Label("Robots", systemImage: "fan.fill") }
                    .tag("robots")
            }
            if authManager.isOIDC {
                ChatView(chat: chat)
                    .tabItem {
                        Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .tag("assistant")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNotificationSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsView()
        }
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
            .padding([.bottom, .trailing])
        }
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
        apiResponse: MockData.createApi()
    )
}
#endif
