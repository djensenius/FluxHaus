//
//  VisionOSApp.swift
//  VisionOS
//
//  Created by David Jensenius on 2024-03-03.
//

import Foundation
import SwiftUI
import OAuth2
import Security

var oauth2: OAuth2CodeGrant? = nil
var oauth2Miele: OAuth2CodeGrant? = nil
var loader: OAuth2DataLoader? = nil
var loaderMiele: OAuth2DataLoader? = nil

/*
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
*/

var hc: HomeConnect? = nil
var miele: Miele? = nil

@main
struct VisionOSApp: App {
    
    @State private var whereWeAre = WhereWeAre()
    @State var fluxHausConsts = FluxHausConsts()
    
    var body: some Scene {
        WindowGroup {
            if whereWeAre.loading == true {
                LoadingView(needLoginView: !whereWeAre.hasKeyChainPassword)
                    .task {
                        loadKeys()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.loginsUpdated)) { object in
                        // newTask = object as? String
                        if ((object.userInfo?["keysComplete"]) != nil) == true {
                            loadMiele()
                        }
                        
                        if ((object.userInfo?["mieleComplete"]) != nil) == true {
                            loadHomeConnect()
                        }
                        
                        if ((object.userInfo?["homeConnectComplete"]) != nil) == true {
                            whereWeAre.finishedLoading()
                        }
                        
                        if ((object.userInfo?["keysFailed"]) != nil) == true {
                            whereWeAre.deleteKeyChainPasword()
                        }
                    }
                    .onOpenURL { (url) in
                        print("Hi David \(url)")// Handle url here
                        if (url.absoluteString.contains("fluxhaus_miele")) {
                            print("Handle Miele")
                            oauth2Miele!.handleRedirectURL(url)
                        } else {
                            print("Handle HomeConnect")
                            oauth2!.handleRedirectURL(url)
                        }
                    }
            } else {
                ContentView(fluxHausConsts: fluxHausConsts, hc: hc!, miele: miele!)
            }
        }
    }
    
    func loadKeys() {
        // Check access, assign robot and assign consts
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
        hc = HomeConnect.init()
    }
}

struct WhereWeAre {
    var hasKeyChainPassword = false
    var loading = true
    
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: "admin",
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnAttributes as String: true,
        kSecReturnData as String: true,
    ]
    
    var item: CFTypeRef?
    
    // Check if user exists in the keychain
    init() {
        print("Initting")
        if SecItemCopyMatching(query as CFDictionary, &item) == noErr {
            // Extract result
            if let existingItem = item as? [String: Any],
               let passwordData = existingItem[kSecValueData as String] as? Data,
               let password = String(data: passwordData, encoding: .utf8)
            {
                print(password)
                hasKeychainPassword(has: true)
            }
        } else {
            print("Can't find it")
            hasKeychainPassword(has: false)
        }
    }
    
    mutating func hasKeychainPassword(has: Bool) {
        hasKeyChainPassword = has
    }
    
    mutating func finishedLoading() {
        loading = false
    }
    
    mutating func deleteKeyChainPasword() {
        print("Going to delete password")
        hasKeyChainPassword = false
    }
}
