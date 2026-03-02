//
//  FluxHausConsts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation

struct FluxHausConfig {
    let favouriteHomeKit: [String]
    let favouriteScenes: [String]
}

class FluxHausConsts: ObservableObject {
    @Published var favouriteHomeKit: [String] = []
    @Published var favouriteScenes: [String] = []

    func setConfig(config: FluxHausConfig) {
        self.favouriteHomeKit = config.favouriteHomeKit
        self.favouriteScenes = config.favouriteScenes
    }
}
