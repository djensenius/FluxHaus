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

    var body: some View {
        VStack {
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
        }
        .padding()
        HStack {
            Link(
                "Weather provided by  Weather",
                destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
            )
            .font(.caption)
            .padding([.bottom, .leading])

            Spacer()

            Button(action: {
                whereWeAre.deleteKeyChainPasword()
                NotificationCenter.default.post(
                    name: Notification.Name.logout,
                    object: nil,
                    userInfo: ["logout": true]
                )
            }, label: {
                Text("Logout")
                    .font(.caption)
            })
            .padding([.bottom, .trailing])
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView(
        fluxHausConsts: {
            let config = FluxHausConsts()
            config.setConfig(config: FluxHausConfig(favouriteHomeKit: ["Light 1", "Light 2"]))
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
