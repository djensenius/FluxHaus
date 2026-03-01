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

// Provides a presentation anchor for ASWebAuthenticationSession.
// Uses KVC to access UIApplication.shared, avoiding the compile-time
// "unavailable in app extensions" error (the widget never calls this).
private class AuthSessionAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS) || os(visionOS)
        if let app = (NSClassFromString("UIApplication") as? NSObject.Type)?
            .value(forKeyPath: "sharedApplication") as? NSObject,
           let scenes = app.value(forKey: "connectedScenes") as? Set<NSObject> {
            for scene in scenes {
                if String(describing: type(of: scene)).contains("UIWindowScene"),
                   let windows = scene.value(forKey: "windows") as? [NSObject] {
                    for window in windows {
                        if let isKey = window.value(forKey: "isKeyWindow") as? Bool, isKey {
                            return window as! ASPresentationAnchor // swiftlint:disable:this force_cast
                        }
                    }
                    // No key window found, but we have a scene — return first window
                    if let firstWindow = windows.first {
                        return firstWindow as! ASPresentationAnchor // swiftlint:disable:this force_cast
                    }
                }
            }
        }
        #endif
        // Should never reach here when called from a foreground app.
        if #unavailable(iOS 26, visionOS 26) {
            return ASPresentationAnchor(frame: .zero)
        }
        // iOS 26+ requires UIWindow(windowScene:) — but if we're here,
        // no scene was found, so the auth session will fail regardless.
        fatalError("No window scene available for ASWebAuthenticationSession")
    }
}

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

/// Thread-safe coordination for token refresh to prevent concurrent refreshes.
/// When the 5-second polling timer causes multiple 401s simultaneously,
/// only one refresh executes — others wait for its result.
private actor RefreshCoordinator {
    private var isRefreshing = false
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    /// Returns nil if the caller should perform the refresh.
    /// Returns a Bool (via suspension) if another refresh is in-flight.
    func acquireOrWait() async -> Bool? {
        if isRefreshing {
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        isRefreshing = true
        return nil
    }

    /// Signals all waiters with the result and resets the lock.
    func complete(success: Bool) {
        let waiters = continuations
        continuations.removeAll()
        isRefreshing = false
        for waiter in waiters { waiter.resume(returning: success) }
    }
}

class AuthManager: ObservableObject, @unchecked Sendable {
    static let shared = AuthManager()

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

    @Published var authState: AuthState = .unknown

    // Keep strong references to prevent deallocation during auth
    private var currentAuthSession: ASWebAuthenticationSession?
    private var anchorProvider: AuthSessionAnchorProvider?

    // Serializes concurrent refresh attempts via actor isolation
    private let refreshCoordinator = RefreshCoordinator()

    var isSignedIn: Bool {
        if case .signedIn = authState { return true }
        return false
    }

    private init() {
        if getAccessToken() != nil {
            authState = .signedIn(method: .oidc)
            logger.info("Init: found OIDC token, state=signedIn(oidc)")
        } else if WhereWeAre.getPassword() != nil {
            authState = .signedIn(method: .demo)
            logger.info("Init: found demo password, state=signedIn(demo)")
        } else {
            authState = .signedOut
            logger.info("Init: no credentials found, state=signedOut")
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
            logger.debug("authorizationHeader: using Bearer token (\(token.prefix(8))...)")
            return "Bearer \(token)"
        }
        if let password = WhereWeAre.getPassword() {
            logger.debug("authorizationHeader: using Basic auth (demo)")
            return "Basic \(Data("demo:\(password)".utf8).base64EncodedString())"
        }
        logger.warning("authorizationHeader: no credentials available")
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
            ) { @Sendable url, error in
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
            let provider = AuthSessionAnchorProvider()
            session.presentationContextProvider = provider
            self.anchorProvider = provider
            self.currentAuthSession = session
            session.start()
        }
        // Clean up references after continuation resumes
        self.currentAuthSession = nil
        self.anchorProvider = nil

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
        logger.warning("signOut() called — clearing all tokens and credentials")
        deleteKeychainItem(account: "oidc_access_token")
        deleteKeychainItem(account: "oidc_refresh_token")
        var whereWeAre = WhereWeAre()
        whereWeAre.deleteKeyChainPasword()
        authState = .signedOut
        logger.warning("signOut() complete — state=signedOut")
    }

    // MARK: - Token Management

    func getAccessToken() -> String? {
        return getKeychainItem(account: "oidc_access_token")
    }

    func refreshTokenIfNeeded() async -> Bool {
        // If another refresh is in-flight, wait for its result (actor-serialized)
        if let coalescedResult = await refreshCoordinator.acquireOrWait() {
            logger.info("refreshTokenIfNeeded: coalesced with in-flight refresh, result=\(coalescedResult)")
            return coalescedResult
        }

        guard let refreshToken = getKeychainItem(account: "oidc_refresh_token") else {
            logger.warning("refreshTokenIfNeeded: no refresh token in keychain — cannot refresh")
            await refreshCoordinator.complete(success: false)
            return false
        }

        logger.info("refreshTokenIfNeeded: starting token refresh...")

        do {
            let tokens = try await refreshAccessToken(refreshToken)
            storeTokens(tokens)
            logger.info("""
                refreshTokenIfNeeded: SUCCESS \
                (expiresIn=\(tokens.expiresIn ?? -1), \
                hasNewRefreshToken=\(tokens.refreshToken != nil))
                """)
            await refreshCoordinator.complete(success: true)
            return true
        } catch {
            logger.error("refreshTokenIfNeeded: FAILED — \(error.localizedDescription)")
            await refreshCoordinator.complete(success: false)
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
            "client_id=\(Self.clientID)",
            "scope=\(Self.scopes)"
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
            logger.info("storeTokens: stored access + refresh tokens")
        } else {
            logger.warning("storeTokens: stored access token only (no refresh token returned!)")
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
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != noErr {
            logger.error("Keychain write FAILED for \(account): OSStatus \(status)")
        }
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
