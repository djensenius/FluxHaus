//
//  FluxHausConsts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation

struct FluxHausConfig {
    let mieleClientId: String
    let mieleSecretId: String
    let mieleAppliances: [String]
    let boschClientId: String
    let boschSecretId: String
    let boschAppliance: String
    let favouriteHomeKit: [String]
}

class FluxHausConsts: ObservableObject {
    @Published var mieleClientId = ""
    @Published var mieleSecretId = ""
    @Published var mieleAppliances: [String] = []
    @Published var boschClientId = ""
    @Published var boschSecretId = ""
    @Published var boschAppliance = ""
    @Published var favouriteHomeKit: [String] = []

    func setConfig(config: FluxHausConfig) {
        self.mieleClientId = config.mieleClientId
        self.mieleSecretId = config.mieleSecretId
        self.mieleAppliances = config.mieleAppliances
        self.boschClientId = config.boschClientId
        self.boschSecretId = config.boschSecretId
        self.boschAppliance = config.boschAppliance
        self.favouriteHomeKit = config.favouriteHomeKit
    }
}
