//
//  WhereWeAre.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "WhereWeAre")

public struct WhereWeAre {
    public var hasKeyChainPassword = false
    public var loading = true

    // Check if user exists in the keychain (OIDC token or demo password)
    public init() {
        if AuthManager.hasOIDCToken() {
            hasKeychainPassword(has: true)
        } else {
            let password = WhereWeAre.getPassword()
            if password != nil {
                hasKeychainPassword(has: true)
            } else {
                hasKeychainPassword(has: false)
            }
        }
    }

    public mutating func setPassword(password: String) {
        guard !password.isEmpty else {
            deleteKeyChainPasword()
            return
        }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccount as String: "demo",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: password.data(using: String.Encoding.utf8)!
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: "api.fluxhaus.io",
                kSecAttrAccount as String: "demo"
            ]
            let update: [String: Any] = [
                kSecValueData as String: password.data(using: String.Encoding.utf8)!
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if updateStatus != noErr {
                logger.error("Keychain update FAILED for demo password: OSStatus \(updateStatus)")
            }
        } else if status != noErr {
            logger.error("Keychain write FAILED for demo password: OSStatus \(status)")
        }
        hasKeychainPassword(has: true)
    }

    public static func getPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: "demo",
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == noErr,
           let existingItem = item as? [String: Any],
           let passwordData = existingItem[kSecValueData as String] as? Data,
           let password = String(data: passwordData, encoding: .utf8) {
            guard !password.isEmpty else {
                deleteDemoPassword()
                return nil
            }
            return password
        }
        if status != errSecItemNotFound {
            logger.error("Keychain read FAILED for demo password: OSStatus \(status)")
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
        Self.deleteDemoPassword()
        hasKeychainPassword(has: false)
    }

    private static func deleteDemoPassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccount as String: "demo"
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != noErr && status != errSecItemNotFound {
            logger.error("Keychain delete FAILED for demo password: OSStatus \(status)")
        }
    }
}
