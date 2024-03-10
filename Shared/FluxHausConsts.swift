//
//  FluxHausConsts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation
import OAuth2

class FluxHausConsts: ObservableObject {
    @Published var fluxhausUrl = "http://fluxhaus.io:8080"
    @Published var mieleClientId = ProcessInfo.processInfo.environment["mieleClientId"]!
    @Published var mieleSecretId = ProcessInfo.processInfo.environment["mieleSecretId"]!
    @Published var mieleAppliances = try! JSONSerialization.jsonObject(with: Data(ProcessInfo.processInfo.environment["mieleAppliances"]!.utf8)) as! [String]
    @Published var boschClientId = ProcessInfo.processInfo.environment["boschClientId"]!
    @Published var boschSecretId = ProcessInfo.processInfo.environment["boschSecretId"]!
    static let boschAppliance = ProcessInfo.processInfo.environment["boschAppliance"]!
    static let favouriteHomeKit = try! JSONSerialization.jsonObject(with: Data(ProcessInfo.processInfo.environment["favouriteHomeKit"]!.utf8)) as! [String]
    
    func setConfig() {
        self.mieleClientId = "BEEP BOOP"
        
        oauth2 = OAuth2CodeGrant(settings: [
            "client_id": self.boschClientId,
            "client_secret": self.boschSecretId,
            "authorize_uri": "https://api.home-connect.com/security/oauth/authorize",
            "token_uri": "https://api.home-connect.com/security/oauth/token",
            "redirect_uris": ["fluxhaus://oauth/callback"],
            "scope": "IdentifyAppliance Monitor",
            "keychain": true,
        ] as OAuth2JSON)

        oauth2Miele = OAuth2CodeGrant(settings: [
            "client_id": self.mieleClientId,
            "client_secret": self.mieleSecretId,
            "authorize_uri": "https://api.mcs3.miele.com/thirdparty/login",
            "token_uri": "https://api.mcs3.miele.com/thirdparty/token",
            "redirect_uris": ["fluxhaus://oauth/callback/fluxhaus_miele"],
            "parameters": ["vg": "en-CA"],
            "secret_in_body": true,
            "keychain": true,
        ] as OAuth2JSON)


        loader = OAuth2DataLoader(oauth2: oauth2!)
        loaderMiele = OAuth2DataLoader(oauth2: oauth2Miele!)
    }
}

