//
//  WhereWeAre.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

public struct WhereWeAre {
    public var hasKeyChainPassword = false
    public var loading = true

    // Check if user exists in the keychain
    public init() {
        let password = WhereWeAre.getPassword()
        if password != nil {
            queryFlux(password: password!, user: nil)
            hasKeychainPassword(has: true)
        } else {
            hasKeychainPassword(has: false)
        }
    }

    public mutating func setPassword(password: String) {
        // Set attributes
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccount as String: "admin",
            kSecValueData as String: password.data(using: String.Encoding.utf8)!
        ]
        // Add user
        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status == noErr {
            print("User saved successfully in the keychain")
        }
        hasKeychainPassword(has: true)
    }

    public static func getPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: "admin",
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?

        if SecItemCopyMatching(query as CFDictionary, &item) == noErr {
            // Extract result
            if let existingItem = item as? [String: Any],
               let passwordData = existingItem[kSecValueData as String] as? Data,
               let password = String(data: passwordData, encoding: .utf8) {
                return password
            }
        }
        return nil
    }

    public mutating func hasKeychainPassword(has: Bool) {
        hasKeyChainPassword = has
    }

    public mutating func finishedLoading() {
        loading = false
    }

    public mutating func deleteKeyChainPasword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccount as String: "admin"
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
