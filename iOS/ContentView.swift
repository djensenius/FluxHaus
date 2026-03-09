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

    var body: some View {
        TabView {
            homeTab
                .tabItem { Label("Home", systemImage: "house.fill") }
            weatherTab
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
            if authManager.isOIDC {
                ChatView(chat: chat)
                    .tabItem {
                        Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill")
                    }
            }
            carTab
                .tabItem { Label("Car", systemImage: "car.fill") }
            appliancesTab
                .tabItem { Label("Appliances", systemImage: "washer.fill") }
        }
        .tabViewStyle(.sidebarAdaptable)
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
            Link(
                "Weather provided by  Weather",
                destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
            )
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
