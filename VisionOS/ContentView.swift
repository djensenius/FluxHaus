//
//  ContentView.swift
//  VisionOS
//
//  Created by David Jensenius on 2024-03-03.
//

import SwiftUI
import RealityKit
import RealityKitContent

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
    @State private var selectedTab = "Home"

    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag("Home")
            weatherTab
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
                .tag("Weather")
            SceneView(favouriteScenes: fluxHausConsts.favouriteScenes)
                .tabItem { Label("Scenes", systemImage: "lightbulb.fill") }
                .tag("Scenes")
            appliancesTab
                .tabItem { Label("Appliances", systemImage: "washer.fill") }
                .tag("Appliances")
            carTab
                .tabItem { Label("Car", systemImage: "car.fill") }
                .tag("Car")
            scooterTab
                .tabItem {
                    Label {
                        Text("Scooter")
                    } icon: {
                        Image.flippedScooter
                    }
                }
                .tag("Scooter")
            RobotsListView(robots: robots)
                .tabItem { Label("Robots", systemImage: "fan.fill") }
                .tag("Robots")
            if authManager.isOIDC {
                ChatView(chat: chat)
                    .tabItem {
                        Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .tag("Assistant")
            }
        }
        .background { visionKeyboardShortcuts }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("navigateToTab"))
        ) { notification in
            if let tab = notification.userInfo?["tab"] as? String {
                selectedTab = tab
            }
        }
    }

    private var homeTab: some View {
        ScrollView {
            VStack {
                DateTimeView()
                WeatherView(lman: locationManager)
                HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
                HStack {
                    Text("Appliances")
                        .font(Theme.Fonts.headerXL())
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
            }
            .padding()
        }
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

    private var appliancesTab: some View {
        AppliancesDetailView(
            hconn: hconn,
            miele: miele,
            apiResponse: apiResponse,
            robots: robots
        )
    }

    private var visionKeyboardShortcuts: some View {
        Group {
            Button("") { selectedTab = "Home" }.keyboardShortcut("1")
            Button("") { selectedTab = "Weather" }.keyboardShortcut("2")
            Button("") { selectedTab = "Scenes" }.keyboardShortcut("3")
            Button("") { selectedTab = "Appliances" }.keyboardShortcut("4")
            Button("") { selectedTab = "Car" }.keyboardShortcut("5")
            Button("") { selectedTab = "Scooter" }.keyboardShortcut("6")
            Button("") { selectedTab = "Robots" }.keyboardShortcut("7")
            Button("") { selectedTab = "Assistant" }.keyboardShortcut("8")
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

#if DEBUG
#Preview(windowStyle: .automatic) {
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
