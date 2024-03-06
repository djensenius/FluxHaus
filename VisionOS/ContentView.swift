//
//  ContentView.swift
//  VisionOS
//
//  Created by David Jensenius on 2024-03-03.
//

import SwiftUI
import RealityKit
import RealityKitContent
import OAuth2

let oauth2 = OAuth2CodeGrant(settings: [
    "client_id": FluxHausConsts.boschClientId,
    "client_secret": FluxHausConsts.boschSecretId,
    "authorize_uri": "https://api.home-connect.com/security/oauth/authorize",
    "token_uri": "https://api.home-connect.com/security/oauth/token",
    "redirect_uris": ["fluxhaus://oauth/callback"],
    "scope": "IdentifyAppliance Monitor",
    "keychain": true,
] as OAuth2JSON)

let oauth2Miele = OAuth2CodeGrant(settings: [
    "client_id": FluxHausConsts.mieleClientId,
    "client_secret": FluxHausConsts.mieleSecretId,
    "authorize_uri": "https://api.mcs3.miele.com/thirdparty/login",
    "token_uri": "https://api.mcs3.miele.com/thirdparty/token",
    "redirect_uris": ["fluxhaus://oauth/callback/fluxhaus_miele"],
    "parameters": ["vg": "en-CA"],
    "secret_in_body": true,
    "keychain": true,
] as OAuth2JSON)


let loader = OAuth2DataLoader(oauth2: oauth2)
let loaderMiele = OAuth2DataLoader(oauth2: oauth2Miele)

let hc = HomeConnect.init()
let miele = Miele.init()


struct ContentView: View {
    var body: some View {
        VStack {
            VStack {
                DateTimeView()
                Weather()
                HStack {
                    Text("Appliances")
                        .padding(.leading)
                    Spacer()
                }
                Appliances().onOpenURL { (url) in
                    print("Hi David \(url)")// Handle url here
                    if (url.absoluteString.contains("fluxhaus_miele")) {
                        print("Handle Miele")
                        oauth2Miele.handleRedirectURL(url)
                    } else {
                        print("Handle HomeConnect")
                        oauth2.handleRedirectURL(url)
                    }
                }
            }
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
