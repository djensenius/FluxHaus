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
    var apiResponse: Api
    @State private var whereWeAre = WhereWeAre()
    @StateObject private var locationManager = LocationManager()
    @State private var chat = Chat()
    @State private var radarService = RadarService()

    var body: some View {
        TabView {
            homeTab
                .tabItem { Label("Home", systemImage: "house.fill") }
            weatherTab
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
            if AuthManager.hasOIDCToken() {
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
    }

    private var homeTab: some View {
        ScrollView {
            VStack {
                DateTimeView()
                WeatherView(lman: locationManager)
                HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
                HStack {
                    Text("Appliances")
                        .font(.title)
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

    private var appliancesTab: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("Appliances")
                        .font(.title)
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
        apiResponse: MockData.createApi()
    )
}
#endif
