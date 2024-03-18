//
//  ContentView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import SwiftUI

struct ContentView: View {
    var fluxHausConsts: FluxHausConsts
    var hc: HomeConnect
    var miele: Miele
    var robots: Robots
    var battery: Battery
    
    var body: some View {
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
                hc: hc,
                miele: miele,
                robots: robots,
                battery: battery
            )
            Spacer()
            Link(
                "Weather provided by  Weather",
                destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
            )
            .font(.footnote)
            .padding(.bottom)
        }
    }
}

/*
#Preview {
    ContentView()
}
*/
