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
    var hc: HomeConnect
    var miele: Miele
    var robots: Robots
    var battery: Battery
    
    var body: some View {
        VStack {
            VStack {
                DateTimeView()
                WeatherView()
                HStack {
                    Text("Appliances")
                        .padding(.leading)
                    Spacer()
                }
                Appliances(fluxHausConsts: fluxHausConsts, hc: hc, miele: miele, robots: robots, battery: battery)
            }
        }
        .padding()
    }
}

/*
#Preview(windowStyle: .automatic) {
    ContentView()
}
*/
