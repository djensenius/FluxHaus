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
            Appliances(fluxHausConsts: fluxHausConsts, hc: hc, miele: miele, robots: robots)
            Spacer()
        }
    }
}

/*
#Preview {
    ContentView()
}
*/
