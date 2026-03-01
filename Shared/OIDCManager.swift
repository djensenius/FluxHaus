//
//  OIDCManager.swift
//  FluxHaus
//
//  Created by Copilot on 2026-03-01.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

// MARK: - OIDC Configuration
private enum OIDCConfig {
    static let issuerURL = "https://auth.fluxhaus.io/application/o/fluxhaus"
    static let clientID = "fluxhaus-ios"
    static let redirectURI = "fluxhaus://auth/callback"
    static let scope = "openid profile email"
    static let keychainService = "io.fluxhaus.oidc"
    static let accessTokenAccount = "access_token"
    static let refreshTokenAccount = "refresh_token"
}

// MARK: - PKCE Helpers
private func generateCodeVerifier() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func codeChallenge(for verifier: String) -> String {
    let data = Data(verifier.utf8)
    let hash = SHA256.hash(data: data)
    return Data(hash)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func randomState() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// MARK: - Token Response
private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - OIDCManager
class OIDCManager: NSObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = OIDCManager()

    private override init() {}

    // MARK: - Public API

    /// Start OIDC authorization code flow with PKCE.
    /// Stores tokens in Keychain on success.
    func login() async throws {
        let verifier = generateCodeVerifier()
        let challenge = codeChallenge(for: verifier)
        let state = randomState()

        guard var components = URLComponents(string: "\(OIDCConfig.issuerURL)/authorize/") else {
            throw OIDCError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OIDCConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: OIDCConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: OIDCConfig.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw OIDCError.invalidURL
        }

        let callbackURL = try await performWebAuth(url: authURL)
        let code = try extractCode(from: callbackURL, expectedState: state)
        let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier)
        try storeTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
    }

    /// Attempt to refresh the access token using the stored refresh token.
    /// Updates stored access token on success.
    @discardableResult
    func refreshTokens() async throws -> String {
        guard let refreshToken = getKeychainItem(account: OIDCConfig.refreshTokenAccount) else {
            throw OIDCError.noRefreshToken
        }

        guard let tokenURL = URL(string: "\(OIDCConfig.issuerURL)/token/") else {
            throw OIDCError.invalidURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "client_id=\(OIDCConfig.clientID)",
            "refresh_token=\(refreshToken)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OIDCError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        try storeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken
        )
        return tokenResponse.accessToken
    }

    /// Returns the stored access token, or nil if not available.
    func getAccessToken() -> String? {
        return getKeychainItem(account: OIDCConfig.accessTokenAccount)
    }

    /// Returns true if an OIDC access token is stored.
    var hasToken: Bool {
        return getAccessToken() != nil
    }

    /// Delete stored OIDC tokens from Keychain.
    func deleteTokens() {
        deleteKeychainItem(account: OIDCConfig.accessTokenAccount)
        deleteKeychainItem(account: OIDCConfig.refreshTokenAccount)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return windowScene?.windows.first ?? UIWindow()
    }

    // MARK: - Private Helpers

    private func performWebAuth(url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "fluxhaus"
            ) { callbackURL, error in
                if let error = error {
                    let asError = error as? ASWebAuthenticationSessionError
                    if asError?.code == .canceledLogin {
                        continuation.resume(throwing: OIDCError.userCancelled)
                    } else {
                        continuation.resume(throwing: OIDCError.networkError(error))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OIDCError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func extractCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw OIDCError.invalidCallback
        }
        let params = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        if let error = params["error"] {
            throw OIDCError.authorizationError(error)
        }
        guard let returnedState = params["state"], returnedState == expectedState else {
            throw OIDCError.stateMismatch
        }
        guard let code = params["code"] else {
            throw OIDCError.invalidCallback
        }
        return code
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> TokenResponse {
        guard let tokenURL = URL(string: "\(OIDCConfig.issuerURL)/token/") else {
            throw OIDCError.invalidURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let encodedRedirect = OIDCConfig.redirectURI
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? OIDCConfig.redirectURI
        let body = [
            "grant_type=authorization_code",
            "client_id=\(OIDCConfig.clientID)",
            "code=\(code)",
            "redirect_uri=\(encodedRedirect)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OIDCError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func storeTokens(accessToken: String, refreshToken: String?) throws {
        try saveKeychainItem(account: OIDCConfig.accessTokenAccount, value: accessToken)
        if let refreshToken {
            try saveKeychainItem(account: OIDCConfig.refreshTokenAccount, value: refreshToken)
        }
    }

    private func saveKeychainItem(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw OIDCError.keychainError
        }
        deleteKeychainItem(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OIDCConfig.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OIDCError.keychainError
        }
    }

    private func getKeychainItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OIDCConfig.keychainService,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OIDCConfig.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - OIDCError
enum OIDCError: Error, LocalizedError {
    case invalidURL
    case userCancelled
    case invalidCallback
    case stateMismatch
    case authorizationError(String)
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case networkError(Error)
    case keychainError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid authorization URL"
        case .userCancelled: return "Sign in was cancelled"
        case .invalidCallback: return "Invalid authorization callback"
        case .stateMismatch: return "OAuth state mismatch"
        case .authorizationError(let msg): return "Authorization error: \(msg)"
        case .tokenExchangeFailed: return "Failed to exchange code for tokens"
        case .tokenRefreshFailed: return "Failed to refresh access token"
        case .noRefreshToken: return "No refresh token available"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .keychainError: return "Keychain operation failed"
        }
    }
}
