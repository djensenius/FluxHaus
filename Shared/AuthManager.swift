//
//  AuthManager.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-01.
//

import Foundation
import AuthenticationServices
import CryptoKit
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "AuthManager")

#if os(iOS) || os(visionOS)
import UIKit
#endif

enum AuthError: Error, LocalizedError {
    case noCode
    case tokenExchangeFailed(String)
    case cancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .noCode: return "No authorization code received"
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .cancelled: return "Sign in was cancelled"
        case .unknown: return "An unknown error occurred"
        }
    }
}

struct OIDCTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

class AuthManager: NSObject, ObservableObject, @unchecked Sendable {
    nonisolated(unsafe) static let shared = AuthManager()

    // OIDC configuration — set OIDCClientID and OIDCIssuerBase in Info.plist
    private static let issuerBase: String = {
        Bundle.main.object(forInfoDictionaryKey: "OIDCIssuerBase") as? String
            ?? "https://auth.fluxhaus.io/application/o/fluxhaus-server"
    }()
    static var authorizeURL: String {
        guard let base = URL(string: issuerBase) else { return issuerBase }
        return base.deletingLastPathComponent().appendingPathComponent("authorize").absoluteString + "/"
    }
    static var tokenURL: String {
        guard let base = URL(string: issuerBase) else { return issuerBase }
        return base.deletingLastPathComponent().appendingPathComponent("token").absoluteString + "/"
    }
    static var endSessionURL: String { "\(issuerBase)/end-session/" }
    static let clientID: String = {
        Bundle.main.object(forInfoDictionaryKey: "OIDCClientID") as? String
            ?? "ios-fluxhaus"
    }()
    static let redirectScheme = "fluxhaus"
    static let redirectURI = "fluxhaus://auth/callback"
    static let scopes = "openid email profile offline_access"

    enum AuthState {
        case unknown
        case signedIn(method: AuthMethod)
        case signedOut
    }

    enum AuthMethod {
        case oidc
        case demo
    }

    @MainActor @Published var authState: AuthState = .unknown

    // Keep strong reference to prevent deallocation during auth
    private var currentAuthSession: ASWebAuthenticationSession?
    #if os(iOS) || os(visionOS)
    private var authPresentationAnchor: UIWindow?
    #endif

    @MainActor var isSignedIn: Bool {
        if case .signedIn = authState { return true }
        return false
    }

    private override init() {
        super.init()
        if getAccessToken() != nil {
            _authState = Published(initialValue: .signedIn(method: .oidc))
        } else if WhereWeAre.getPassword() != nil {
            _authState = Published(initialValue: .signedIn(method: .demo))
        } else {
            _authState = Published(initialValue: .signedOut)
        }
    }

    /// Check if an OIDC access token exists (safe to call from any isolation context)
    static func hasOIDCToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: "oidc_access_token",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: false
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == noErr
    }

    // MARK: - Authorization Header

    /// Returns the Authorization header value for API requests
    func authorizationHeader() -> String? {
        if let token = getAccessToken() {
            return "Bearer \(token)"
        }
        if let password = WhereWeAre.getPassword() {
            return "Basic \(Data("demo:\(password)".utf8).base64EncodedString())"
        }
        return nil
    }

    // MARK: - OIDC Sign In

    @MainActor func signInWithOIDC() async throws {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = generateRandomString()
        let nonce = generateRandomString()

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else { throw AuthError.unknown }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.redirectScheme
            ) { [weak self] url, error in
                self?.currentAuthSession = nil
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthError.unknown)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            #if os(iOS) || os(visionOS)
            self.authPresentationAnchor = UIWindow()
            session.presentationContextProvider = self
            #endif
            self.currentAuthSession = session
            session.start()
        }

        // Extract code from callback
        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard let code = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }

        // Verify state matches
        let returnedState = callbackComponents?.queryItems?.first(where: { $0.name == "state" })?.value
        if returnedState != state {
            logger.error("OIDC state mismatch")
            throw AuthError.unknown
        }

        // Exchange code for tokens
        let tokens = try await exchangeCode(code, codeVerifier: codeVerifier)
        storeTokens(tokens)
        authState = .signedIn(method: .oidc)
        logger.info("OIDC sign in successful")
    }

    // MARK: - Demo Sign In

    @MainActor func signInDemo(password: String) {
        var whereWeAre = WhereWeAre()
        whereWeAre.setPassword(password: password)
        authState = .signedIn(method: .demo)
    }

    // MARK: - Sign Out

    @MainActor func signOut() {
        deleteKeychainItem(account: "oidc_access_token")
        deleteKeychainItem(account: "oidc_refresh_token")
        var whereWeAre = WhereWeAre()
        whereWeAre.deleteKeyChainPasword()
        authState = .signedOut
    }

    // MARK: - Token Management

    func getAccessToken() -> String? {
        return getKeychainItem(account: "oidc_access_token")
    }

    func refreshTokenIfNeeded() async -> Bool {
        guard let refreshToken = getKeychainItem(account: "oidc_refresh_token") else {
            return false
        }

        do {
            let tokens = try await refreshAccessToken(refreshToken)
            storeTokens(tokens)
            return true
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> OIDCTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(Self.redirectURI)",
            "client_id=\(Self.clientID)",
            "code_verifier=\(codeVerifier)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed(body)
        }

        return try JSONDecoder().decode(OIDCTokens.self, from: data)
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> OIDCTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(Self.clientID)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed(body)
        }

        return try JSONDecoder().decode(OIDCTokens.self, from: data)
    }

    private func storeTokens(_ tokens: OIDCTokens) {
        setKeychainItem(account: "oidc_access_token", value: tokens.accessToken)
        if let refreshToken = tokens.refreshToken {
            setKeychainItem(account: "oidc_refresh_token", value: refreshToken)
        }
    }

    // MARK: - Keychain Helpers

    private func setKeychainItem(account: String, value: String) {
        deleteKeychainItem(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: account,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func getKeychainItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == noErr,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return nil
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateRandomString() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#if os(iOS) || os(visionOS)
extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        authPresentationAnchor ?? ASPresentationAnchor()
    }
}
#endif
