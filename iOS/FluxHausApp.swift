//
//  FluxHausApp.swift
//  Shared
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI
import UIKit

var hconn: HomeConnect?
var miele: Miele?
var robots: Robots?
var battery: Battery?
var car: Car?

@main
struct FluxHausApp: App {
    @State private var whereWeAre = WhereWeAre()
    @State var fluxHausConsts = FluxHausConsts()
    @State private var battery = Battery()

    var body: some Scene {
        WindowGroup {
            if whereWeAre.loading == true {
                LoadingView(needLoginView: !whereWeAre.hasKeyChainPassword)
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.loginsUpdated)) { object in
                        if ((object.userInfo?["keysComplete"]) != nil) == true {
                            if object.object != nil {
                                let configResponse = object.object! as? LoginResponse
                                let config = FluxHausConfig(
                                    mieleClientId: configResponse?.mieleClientId ?? "",
                                    mieleSecretId: configResponse?.mieleSecretId ?? "",
                                    mieleAppliances: configResponse?.mieleAppliances ?? [],
                                    boschClientId: configResponse?.boschClientId ?? "",
                                    boschSecretId: configResponse?.boschSecretId ?? "",
                                    boschAppliance: configResponse?.boschAppliance ?? "",
                                    favouriteHomeKit: configResponse?.favouriteHomeKit ?? []
                                )
                                fluxHausConsts.setConfig(config: config)
                                loadMiele()
                                loadRobots()
                                loadBattery()
                                loadCar()
                                loadHomeConnect()
                            }
                        }

                        if ((object.userInfo?["homeConnectComplete"]) != nil) == true {
                            whereWeAre.finishedLoading()
                        }

                        if (object.userInfo?["updateKeychain"]) != nil {
                            whereWeAre.setPassword(password: object.userInfo!["updateKeychain"] as? String ?? "")
                        }

                        if ((object.userInfo?["keysFailed"]) != nil) == true {
                            whereWeAre.deleteKeyChainPasword()
                        }
                    }
            } else {
                ContentView(
                    fluxHausConsts: fluxHausConsts,
                    hconn: hconn!,
                    miele: miele!,
                    robots: robots!,
                    battery: battery,
                    car: car!
                )
            }
        }
    }
    func loadMiele() {
        miele = Miele.init()
        fluxHausConsts.mieleAppliances.forEach { (appliance) in
            if miele != nil {
                miele?.fetchAppliance(appliance: appliance)
            }
        }
    }

    func loadHomeConnect() {
        hconn = HomeConnect.init(boschAppliance: fluxHausConsts.boschAppliance)
    }

    func loadRobots() {
        robots = Robots()
    }

    func loadBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func loadCar() {
        car = Car()
    }
}
