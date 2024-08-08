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
                hconn: hconn,
                miele: miele,
                apiResponse: apiResponse,
                robots: robots,
                battery: battery,
                car: car
            )
            Spacer()
            HStack {
                Link(
                    "Weather provided by  Weather",
                    destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
                )
                .font(.footnote)
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
                })
                .font(.footnote)
                .padding([.bottom, .trailing])
            }
        }
    }
}

/*
#Preview {
    ContentView()
}
*/
