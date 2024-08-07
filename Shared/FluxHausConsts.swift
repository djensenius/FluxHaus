//
//  FluxHausConsts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation

struct FluxHausConfig {
    let favouriteHomeKit: [String]
}

class FluxHausConsts: ObservableObject {
    @Published var favouriteHomeKit: [String] = []

    func setConfig(config: FluxHausConfig) {
        self.favouriteHomeKit = config.favouriteHomeKit
    }
}
