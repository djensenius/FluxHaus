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
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name.loginsUpdated)) { object in
                        if ((object.userInfo?["keysComplete"]) != nil) == true {
                            if (object.object != nil) {
                                let configResponse = object.object! as! LoginResponse
                                let config = FluxHausConfig(
                                    mieleClientId: configResponse.mieleClientId,
                                    mieleSecretId: configResponse.mieleSecretId,
                                    mieleAppliances: configResponse.mieleAppliances,
                                    boschClientId: configResponse.boschClientId,
                                    boschSecretId: configResponse.boschSecretId,
                                    boschAppliance: configResponse.boschAppliance,
                                    favouriteHomeKit: configResponse.favouriteHomeKit
                                )
                                fluxHausConsts.setConfig(config: config)
                                loadMiele()
                            }
                        }
                        
                        if ((object.userInfo?["mieleComplete"]) != nil) == true {
                            loadHomeConnect()
                        }
                        
                        if ((object.userInfo?["homeConnectComplete"]) != nil) == true {
                            whereWeAre.finishedLoading()
                        }
                        
                        if (object.userInfo?["updateKeychain"]) != nil {
                            whereWeAre.setPassword(password: object.userInfo!["updateKeychain"] as! String)
                        }
                        
                        if ((object.userInfo?["keysFailed"]) != nil) == true {
                            whereWeAre.deleteKeyChainPasword()
                        }
                    }
                    .onOpenURL { (url) in
                        if (url.absoluteString.contains("fluxhaus_miele")) {
                            oauth2Miele!.handleRedirectURL(url)
                        } else {
                            oauth2!.handleRedirectURL(url)
                        }
                    }
            } else {
                ContentView(fluxHausConsts: fluxHausConsts, hc: hc!, miele: miele!)
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
        hc = HomeConnect.init(boschAppliance: fluxHausConsts.boschAppliance)
    }
}

struct WhereWeAre {
    var hasKeyChainPassword = false
    var loading = true
    
    // Check if user exists in the keychain
    init() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: "admin",
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        
        var item: CFTypeRef?
        
        if SecItemCopyMatching(query as CFDictionary, &item) == noErr {
            // Extract result
            if let existingItem = item as? [String: Any],
               let passwordData = existingItem[kSecValueData as String] as? Data,
               let password = String(data: passwordData, encoding: .utf8)
            {
                queryFlux(password: password)
                hasKeychainPassword(has: true)
            }
        } else {
            hasKeychainPassword(has: false)
        }
    }
    
    mutating func setPassword(password: String) {
        // Set attributes
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccount as String: "admin",
            kSecValueData as String: password.data(using: String.Encoding.utf8)!,
        ]
        // Add user
        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status == noErr {
            print("User saved successfully in the keychain")
        }
        hasKeychainPassword(has: true)
    }
    
    mutating func hasKeychainPassword(has: Bool) {
        hasKeyChainPassword = has
    }
    
    mutating func finishedLoading() {
        loading = false
    }
    
    mutating func deleteKeyChainPasword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccount as String: "admin",
        ]
        // Find user and delete
        if SecItemDelete(query as CFDictionary) == noErr {
            print("User removed successfully from the keychain")
        } else {
            print("Something went wrong trying to remove the user from the keychain")
        }
        hasKeychainPassword(has: false)
    }
}
