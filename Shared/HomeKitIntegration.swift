//
//  HomeKitIntegration.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-20.
//

import Foundation
import HomeKit

struct HomeKitFavourite {
    let name: String
    let isActive: Bool
    let hkSet: HMActionSet
}

class HomeKitIntegration: NSObject, ObservableObject, HMHomeDelegate {
    @Published var homeManager = HMHomeManager()
    @Published var favourites: [HomeKitFavourite] = []
    @Published var primaryHome: HMHome?

    func startHome() {
        DispatchQueue.main.async {
            for home in self.homeManager.homes where home.isPrimary {
                self.primaryHome = home
                self.refreshHome()
            }
        }
    }

    func refreshHome() {
        var hkaction: [HomeKitFavourite] = []
        if self.primaryHome != nil {
            for set: HMActionSet in primaryHome!.actionSets {
                var setOn = true
                for action in set.actions {
                    let acc = action as? HMCharacteristicWriteAction<NSCopying>
                    acc?.characteristic.readValue(completionHandler: { (err) in
                        print("Got \(String(describing: err))")
                        return
                    })
                    let value1 = acc?.characteristic.value as? Bool
                    let value2 = acc?.targetValue as? Bool
                    if value1 != value2 {
                        setOn = false
                    }
                }
                hkaction.append(HomeKitFavourite(name: set.name, isActive: setOn, hkSet: set))
            }
        }
        self.favourites = hkaction
    }

    func getActiveScenes() {

    }
}
