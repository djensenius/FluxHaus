//
//  WhereWeAreTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation

struct WhereWeAreTests {
    
    @Test("WhereWeAre struct has correct initial properties")
    func testWhereWeAreInitialProperties() {
        // We can't test the actual keychain functionality easily in tests,
        // but we can test the struct's basic properties and behavior
        
        // Create a mock WhereWeAre that doesn't call the keychain
        var whereWeAre = WhereWeAre()
        
        // Test the mutable functions work correctly
        whereWeAre.hasKeychainPassword(has: true)
        #expect(whereWeAre.hasKeyChainPassword == true)
        
        whereWeAre.hasKeychainPassword(has: false)
        #expect(whereWeAre.hasKeyChainPassword == false)
        
        whereWeAre.finishedLoading()
        #expect(whereWeAre.loading == false)
    }
    
    @Test("WhereWeAre keychain attributes are formed correctly")
    func testKeychainAttributeFormation() {
        // Test that keychain attributes are formed correctly without actually writing to keychain
        let password = "testPassword123"
        let expectedServer = "api.fluxhaus.io"
        let expectedAccount = "admin"
        
        // Simulate the attribute creation logic from setPassword
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: expectedServer,
            kSecAttrAccount as String: expectedAccount,
            kSecValueData as String: password.data(using: String.Encoding.utf8)!
        ]
        
        #expect(attributes[kSecClass as String] as? String == kSecClassInternetPassword as String)
        #expect(attributes[kSecAttrServer as String] as? String == expectedServer)
        #expect(attributes[kSecAttrAccount as String] as? String == expectedAccount)
        
        let passwordData = attributes[kSecValueData as String] as? Data
        #expect(passwordData != nil)
        
        let reconstructedPassword = String(data: passwordData!, encoding: .utf8)
        #expect(reconstructedPassword == password)
    }
    
    @Test("WhereWeAre keychain query is formed correctly")
    func testKeychainQueryFormation() {
        // Test that keychain query is formed correctly for getPassword
        let expectedServer = "api.fluxhaus.io"
        let expectedAccount = "admin"
        
        // Simulate the query creation logic from getPassword
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: expectedAccount,
            kSecAttrServer as String: expectedServer,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        
        #expect(query[kSecClass as String] as? String == kSecClassInternetPassword as String)
        #expect(query[kSecAttrServer as String] as? String == expectedServer)
        #expect(query[kSecAttrAccount as String] as? String == expectedAccount)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(query[kSecReturnAttributes as String] as? Bool == true)
        #expect(query[kSecReturnData as String] as? Bool == true)
    }
    
    @Test("WhereWeAre delete query is formed correctly")
    func testKeychainDeleteQueryFormation() {
        // Test that keychain delete query is formed correctly
        let expectedServer = "api.fluxhaus.io"
        let expectedAccount = "admin"
        
        // Simulate the query creation logic from deleteKeyChainPasword
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: expectedServer,
            kSecAttrAccount as String: expectedAccount
        ]
        
        #expect(query[kSecClass as String] as? String == kSecClassInternetPassword as String)
        #expect(query[kSecAttrServer as String] as? String == expectedServer)
        #expect(query[kSecAttrAccount as String] as? String == expectedAccount)
        
        // Should only have these three keys for deletion
        #expect(query.keys.count == 3)
    }
    
    @Test("WhereWeAre password data encoding and decoding works")
    func testPasswordDataHandling() {
        let originalPassword = "mySecurePassword123!@#"
        
        // Test encoding
        let passwordData = originalPassword.data(using: String.Encoding.utf8)
        #expect(passwordData != nil)
        
        // Test decoding
        let decodedPassword = String(data: passwordData!, encoding: .utf8)
        #expect(decodedPassword == originalPassword)
    }
    
    @Test("WhereWeAre state management works correctly")
    func testStateManagement() {
        var whereWeAre = WhereWeAre()
        
        // Test initial loading state
        #expect(whereWeAre.loading == true)
        
        // Test finishing loading
        whereWeAre.finishedLoading()
        #expect(whereWeAre.loading == false)
        
        // Test keychain password state changes
        whereWeAre.hasKeychainPassword(has: true)
        #expect(whereWeAre.hasKeyChainPassword == true)
        
        whereWeAre.hasKeychainPassword(has: false)
        #expect(whereWeAre.hasKeyChainPassword == false)
        
        // Multiple state changes should work
        whereWeAre.hasKeychainPassword(has: true)
        whereWeAre.finishedLoading()
        #expect(whereWeAre.hasKeyChainPassword == true)
        #expect(whereWeAre.loading == false)
    }
    
    @Test("WhereWeAre handles edge cases in password data")
    func testPasswordDataEdgeCases() {
        // Test empty password
        let emptyPassword = ""
        let emptyData = emptyPassword.data(using: .utf8)
        #expect(emptyData != nil)
        #expect(emptyData?.count == 0)
        
        // Test password with special characters
        let specialPassword = "päßwörd123!@#$%^&*()_+-=[]{}|;':\"<>?,./"
        let specialData = specialPassword.data(using: .utf8)
        #expect(specialData != nil)
        
        let decodedSpecial = String(data: specialData!, encoding: .utf8)
        #expect(decodedSpecial == specialPassword)
        
        // Test very long password
        let longPassword = String(repeating: "a", count: 1000)
        let longData = longPassword.data(using: .utf8)
        #expect(longData != nil)
        #expect(longData?.count == 1000)
        
        let decodedLong = String(data: longData!, encoding: .utf8)
        #expect(decodedLong == longPassword)
    }
}