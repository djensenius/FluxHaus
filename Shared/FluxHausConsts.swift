//
//  FluxHausConsts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation
import OAuth2

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

        oauth2 = OAuth2CodeGrant(settings: [
            "client_id": self.boschClientId,
            "client_secret": self.boschSecretId,
            "authorize_uri": "https://api.home-connect.com/security/oauth/authorize",
            "token_uri": "https://api.home-connect.com/security/oauth/token",
            "redirect_uris": ["fluxhaus://oauth/callback"],
            "scope": "IdentifyAppliance Monitor",
            "keychain": true
        ] as OAuth2JSON)

        oauth2Miele = OAuth2CodeGrant(settings: [
            "client_id": self.mieleClientId,
            "client_secret": self.mieleSecretId,
            "authorize_uri": "https://api.mcs3.miele.com/thirdparty/login",
            "token_uri": "https://api.mcs3.miele.com/thirdparty/token",
            "redirect_uris": ["fluxhaus://oauth/callback/fluxhaus_miele"],
            "parameters": ["vg": "en-CA"],
            "secret_in_body": true,
            "keychain": true
        ] as OAuth2JSON)

        loader = OAuth2DataLoader(oauth2: oauth2!)
        loaderMiele = OAuth2DataLoader(oauth2: oauth2Miele!)
    }
}
