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
    @ObservedObject private var authManager = AuthManager.shared
    @State private var chat = Chat()
    @State private var showChat = false

    var body: some View {
        VStack {
            DateTimeView()
            WeatherView(lman: locationManager)
            if authManager.isOIDC {
                HStack {
                    Spacer()
                    Button(action: { showChat = true }, label: {
                        Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.accent)
                    })
                }
                .padding(.top, 4)
                .padding(.trailing)
            }
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
            HStack {
                Link(
                    "Weather provided by  Weather",
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
        .background(Theme.Colors.background)
        .fullScreenCover(isPresented: $showChat) {
            ChatView(chat: chat)
        }
        .overlay {
            if authManager.isOIDC {
                Button("") { showChat = true }
                    .keyboardShortcut("c", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
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
