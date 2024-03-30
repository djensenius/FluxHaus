//
//  ContentView.swift
//  VisionOS
//
//  Created by David Jensenius on 2024-03-03.
//

import SwiftUI
import RealityKit
import RealityKitContent
import OAuth2

struct ContentView: View {
    var fluxHausConsts: FluxHausConsts
    var hconn: HomeConnect
    var miele: Miele
    var robots: Robots
    var battery: Battery
    var car: Car

    var body: some View {
        VStack {
            VStack {
                DateTimeView()
                WeatherView()
                HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
                HStack {
                    Text("Appliances")
                        .padding(.leading)
                    Spacer()
                }
                Appliances(
                    fluxHausConsts: fluxHausConsts,
                    hconn: hconn,
                    miele: miele,
                    robots: robots,
                    battery: battery,
                    car: car
                )
            }
        }
        .padding()
        Link(
            "Weather provided by  Weather",
            destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
        )
        .font(.footnote)
        .padding(.bottom)
    }
}

/*
#Preview(windowStyle: .automatic) {
    ContentView()
}
*/
