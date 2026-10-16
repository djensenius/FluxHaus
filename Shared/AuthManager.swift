// swiftlint:disable file_length
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
#if canImport(AppKit)
import AppKit
#endif

extension Notification.Name {
    static let authDidSignOut = Notification.Name("authDidSignOut")
}

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "AuthManager")

/// Keychain query helper shared by AuthManager and WhereWeAre.
///
/// On macOS, items go in the data protection keychain (like iOS/visionOS) so the sandboxed
/// widget extension can read them through the shared access group. Earlier macOS builds
/// stored them in the legacy file-based keychain, so the app migrates them. Every keychain
/// operation in a process is routed to the same keychain: the legacy one until a migration
/// has fully succeeded, then the data protection one.
enum Keychain {
    static func query(_ base: [String: Any]) -> CFDictionary {
        #if os(macOS)
        guard useDataProtection() else { return base as CFDictionary }
        var query = base
        query[kSecUseDataProtectionKeychain as String] = true
        return query as CFDictionary
        #else
        return base as CFDictionary
        #endif
    }

    #if os(macOS)
    /// Items the app keeps in the keychain (legacy identity, without the data protection flag).
    private static var knownItems: [[String: Any]] {
        let oidcAccounts = ["oidc_access_token", "oidc_refresh_token", "oidc_token_expiry", "widget_session_id"]
        return oidcAccounts.map {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "io.fluxhaus.oidc",
                kSecAttrAccount as String: $0
            ]
        } + [[
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: "api.fluxhaus.io",
            kSecAttrAccount as String: "demo"
        ]]
    }

    private enum Route {
        case undecided
        case dataProtection
        case legacy(lastAttempt: Date)
    }

    private static let routeLock = NSLock()
    nonisolated(unsafe) private static var route: Route = .undecided

    /// Decides (and if needed migrates) which keychain this process uses. A failed
    /// migration keeps using the legacy keychain and is retried at most once a minute.
    private static func useDataProtection() -> Bool {
        routeLock.lock()
        defer { routeLock.unlock() }
        switch route {
        case .dataProtection:
            return true
        case .legacy(let lastAttempt) where Date().timeIntervalSince(lastAttempt) < 60:
            return false
        default:
            break
        }
        guard dataProtectionAvailable() else {
            // No provisioned keychain-access-groups entitlement (e.g. unsigned local build).
            route = .legacy(lastAttempt: .distantFuture)
            return false
        }
        // Only the app migrates; the sandboxed widget extension can't read the app's
        // legacy items and always uses the data protection keychain.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            route = .dataProtection
            return true
        }
        if migrateLegacyItems() {
            route = .dataProtection
            return true
        }
        route = .legacy(lastAttempt: Date())
        return false
    }

    private static func dataProtectionAvailable() -> Bool {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: "keychain_probe",
            kSecUseDataProtectionKeychain as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(probe as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            logger.warning("Data protection keychain unavailable; using legacy keychain")
            return false
        }
        return true
    }

    /// Copies every legacy item into the data protection keychain, and only once all of
    /// them are copied deletes the legacy ones. Legacy values win over existing copies
    /// (they are what this process has been using). Returns false on any read/write error,
    /// leaving the legacy session intact.
    private static func migrateLegacyItems() -> Bool {
        var copied: [[String: Any]] = []
        for identity in knownItems {
            var lookup = identity
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            lookup[kSecReturnData as String] = true
            var item: CFTypeRef?
            let readStatus = SecItemCopyMatching(lookup as CFDictionary, &item)
            if readStatus == errSecItemNotFound { continue }
            guard readStatus == errSecSuccess, let data = item as? Data else {
                logger.error("Keychain migration read failed: OSStatus \(readStatus)")
                return false
            }

            var target = identity
            target[kSecUseDataProtectionKeychain as String] = true
            var attributes = target
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            attributes[kSecValueData as String] = data
            var writeStatus = SecItemAdd(attributes as CFDictionary, nil)
            if writeStatus == errSecDuplicateItem {
                let update = [kSecValueData as String: data]
                writeStatus = SecItemUpdate(target as CFDictionary, update as CFDictionary)
            }
            guard writeStatus == errSecSuccess else {
                logger.error("Keychain migration write failed: OSStatus \(writeStatus)")
                return false
            }
            copied.append(identity)
        }
        for identity in copied {
            SecItemDelete(identity as CFDictionary)
        }
        if !copied.isEmpty {
            logger.info("Migrated \(copied.count) keychain item(s) to the data protection keychain")
        }
        return true
    }
    #endif
}

// Provides a presentation anchor for ASWebAuthenticationSession.
// Uses KVC to access UIApplication.shared, avoiding the compile-time
// "unavailable in app extensions" error (the widget never calls this).
private class AuthSessionAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApp.keyWindow ?? NSWindow()
        #elseif os(iOS) || os(visionOS)
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
                    if let firstWindow = windows.first {
                        return firstWindow as! ASPresentationAnchor // swiftlint:disable:this force_cast
                    }
                }
            }
        }
        // Should never reach here when called from a foreground app.
        if #unavailable(iOS 26, visionOS 26) {
            return ASPresentationAnchor(frame: .zero)
        }
        fatalError("No window scene available for ASWebAuthenticationSession")
        #else
        return ASPresentationAnchor(frame: .zero)
        #endif
    }
}

enum AuthError: Error, LocalizedError {
    case noCode
    case tokenExchangeFailed(String)
    case cancelled
    case unknown
    case refreshTokenInvalid(String)
    case transientRefreshFailure(Error)

    var errorDescription: String? {
        switch self {
        case .noCode: return "No authorization code received"
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .cancelled: return "Sign in was cancelled"
        case .unknown: return "An unknown error occurred"
        case .refreshTokenInvalid(let msg): return "Session expired: \(msg)"
        case .transientRefreshFailure(let err): return "Temporary refresh failure: \(err.localizedDescription)"
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

/// Coalesces concurrent token refreshes within the same authentication session.
private actor RefreshCoordinator {
    private var refreshingGenerations: Set<UInt64> = []
    private var continuations: [UInt64: [CheckedContinuation<Bool, Never>]] = [:]

    func acquireOrWait(for generation: UInt64) async -> Bool? {
        if refreshingGenerations.contains(generation) {
            return await withCheckedContinuation { continuation in
                continuations[generation, default: []].append(continuation)
            }
        }
        refreshingGenerations.insert(generation)
        return nil
    }

    func complete(for generation: UInt64, success: Bool) {
        let waiters = continuations.removeValue(forKey: generation) ?? []
        refreshingGenerations.remove(generation)
        for waiter in waiters { waiter.resume(returning: success) }
    }
}

// swiftlint:disable:next type_body_length
@Observable class AuthManager: @unchecked Sendable {
    static let shared = AuthManager()

    private enum RefreshTokenState {
        case available(String)
        case sessionChanged
        case signInInProgress
        case missing
    }

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

    var authState: AuthState = .unknown

    /// True while an OIDC sign-in is completing (exchange → first API call).
    /// Used to suppress duplicate queryFlux triggered by scenePhase changes.
    var isCompletingOIDCLogin = false

    // Keep strong references to prevent deallocation during auth
    private var currentAuthSession: ASWebAuthenticationSession?
    private var anchorProvider: AuthSessionAnchorProvider?

    // Serializes concurrent refresh attempts via actor isolation
    private let refreshCoordinator = RefreshCoordinator()
    private let sessionGenerationLock = NSLock()
    private var sessionGeneration: UInt64 = 0
    private var oidcSignInGeneration: UInt64?

    var isSignedIn: Bool {
        if case .signedIn = authState { return true }
        return false
    }

    var isOIDC: Bool {
        if case .signedIn(method: .oidc) = authState { return true }
        return false
    }

    var isSignedOut: Bool {
        if case .signedOut = authState { return true }
        return false
    }

    private init() {
        let hasAccessToken = getAccessToken() != nil
        let hasRefreshToken = getKeychainItem(account: "oidc_refresh_token") != nil
        if hasAccessToken {
            if let expiryString = getKeychainItem(account: "oidc_token_expiry"),
               let expiryInterval = TimeInterval(expiryString),
               Date() >= Date(timeIntervalSince1970: expiryInterval) {
                if hasRefreshToken {
                    authState = .unknown
                    logger.info("Init: OIDC token expired, will validate with refresh token")
                } else {
                    clearOIDCTokens()
                    if WhereWeAre.getPassword() != nil {
                        authState = .signedIn(method: .demo)
                        logger.info("Init: expired OIDC token without refresh; falling back to demo")
                    } else {
                        authState = .signedOut
                        logger.info("Init: expired OIDC token without refresh, state=signedOut")
                    }
                }
            } else {
                authState = .signedIn(method: .oidc)
                logger.info(
                    "Init: signedIn(oidc) — accessToken=YES, refreshToken=\(hasRefreshToken ? "YES" : "MISSING!")"
                )
            }
        } else if WhereWeAre.getPassword() != nil {
            authState = .signedIn(method: .demo)
            logger.info("Init: signedIn(demo)")
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
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(Keychain.query(query), &item) == noErr,
              let data = item as? Data,
              !data.isEmpty else {
            return false
        }

        let refreshQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: "oidc_refresh_token",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: false
        ]
        let hasRefreshToken = SecItemCopyMatching(Keychain.query(refreshQuery), nil) == noErr

        let expiryQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: "oidc_token_expiry",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var expiryItem: CFTypeRef?
        guard SecItemCopyMatching(Keychain.query(expiryQuery), &expiryItem) == noErr,
              let expiryData = expiryItem as? Data,
              let expiryString = String(data: expiryData, encoding: .utf8),
              let expiryInterval = TimeInterval(expiryString) else {
            return true
        }

        let isExpired = Date() >= Date(timeIntervalSince1970: expiryInterval)
        return !isExpired || hasRefreshToken
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
        logger.warning("authorizationHeader: no credentials available")
        return nil
    }

    // MARK: - OIDC Sign In
    @MainActor func signInWithOIDC() async throws {
        let generation = beginOIDCSignIn()
        isCompletingOIDCLogin = true
        defer {
            finishOIDCSignIn(for: generation)
            if !isSignedIn {
                isCompletingOIDCLogin = false
            }
        }
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
        guard storeSignedInTokens(tokens, for: generation) else {
            throw AuthError.cancelled
        }
        authState = .signedIn(method: .oidc)
        if tokens.refreshToken == nil {
            logger.error("OIDC sign in: NO refresh token! Expires in \(tokens.expiresIn ?? -1)s with no renewal.")
        }
    }

    // MARK: - Demo Sign In
    @MainActor func signInDemo(password: String) {
        guard !password.isEmpty else {
            signOut()
            return
        }
        invalidateOIDCSession()
        var whereWeAre = WhereWeAre()
        whereWeAre.setPassword(password: password)
        authState = .signedIn(method: .demo)
    }

    // MARK: - Sign Out
    @MainActor func signOut() {
        logger.warning("signOut() called — clearing all tokens and credentials")
        isCompletingOIDCLogin = false
        invalidateOIDCSession()
        var whereWeAre = WhereWeAre()
        whereWeAre.deleteKeyChainPasword()
        authState = .signedOut
        NotificationCenter.default.post(name: .authDidSignOut, object: nil)
    }

    // MARK: - Widget Session

    private static let widgetSessionService = "io.fluxhaus.oidc"
    private static let widgetSessionAccount = "widget_session_id"

    /// Identifies the current signed-in session for caches kept outside the app process
    /// (widgets, controls). It is deleted synchronously whenever credentials are cleared
    /// (sign-out, account switch), so data cached under a previous session is never shown.
    /// Returns nil when signed out. Concurrent callers always agree on the same ID.
    func widgetSessionID() -> String? {
        guard authorizationHeader() != nil else { return nil }
        if let id = Self.readWidgetSession() { return id }
        let candidate = UUID().uuidString
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.widgetSessionService,
            kSecAttrAccount as String: Self.widgetSessionAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(candidate.utf8)
        ]
        // Add without replacing: if another process/thread created one first, use theirs.
        let status = SecItemAdd(Keychain.query(attributes), nil)
        if status == errSecSuccess { return candidate }
        return Self.readWidgetSession()
    }

    /// Invalidates widget caches tied to the current session. Static and singleton-free so
    /// it is safe to call while `AuthManager.shared` is still initializing.
    static func rotateWidgetSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: widgetSessionService,
            kSecAttrAccount as String: widgetSessionAccount
        ]
        SecItemDelete(Keychain.query(query))
    }

    private static func readWidgetSession() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: widgetSessionService,
            kSecAttrAccount as String: widgetSessionAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(Keychain.query(query), &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Token Management
    func getAccessToken() -> String? {
        return getKeychainItem(account: "oidc_access_token")
    }

    /// Returns true if the access token is expired or will expire within the given margin.
    func isTokenExpiringSoon(margin: TimeInterval = 60) -> Bool {
        guard getAccessToken() != nil else { return false }
        guard let expiryString = getKeychainItem(account: "oidc_token_expiry"),
              let expiryInterval = TimeInterval(expiryString) else {
            // No stored expiry — assume it could be stale
            return true
        }
        let expiryDate = Date(timeIntervalSince1970: expiryInterval)
        return Date().addingTimeInterval(margin) >= expiryDate
    }

    /// Proactively refreshes the token if it's expiring soon. Returns true if token is valid afterward.
    func ensureValidToken() async -> Bool {
        await restoreStateIfNeeded()
        guard getAccessToken() != nil else { return false }
        if isTokenExpiringSoon() {
            logger.debug("ensureValidToken: token expiring soon, refreshing proactively")
            return await refreshTokenIfNeeded()
        }
        return true
    }

    /// Validates an expired stored OIDC session at launch.
    @MainActor func validateSessionOnLaunch() async {
        guard case .unknown = authState else { return }
        guard getKeychainItem(account: "oidc_refresh_token") != nil else {
            logger.info("validateSessionOnLaunch: no refresh token — signing out")
            signOut()
            return
        }

        let refreshed = await refreshTokenIfNeeded()
        if case .unknown = authState {
            authState = .signedIn(method: .oidc)
            logger.info("validateSessionOnLaunch: \(refreshed ? "refreshed token" : "keeping cached session")")
        }
    }

    @MainActor func markOIDCSessionValid() {
        guard getAccessToken() != nil else {
            return
        }
        if !isOIDC {
            authState = .signedIn(method: .oidc)
        }
    }

    @MainActor private func markRefreshedOIDCSessionValid(for generation: UInt64) -> Bool {
        guard isSessionGenerationCurrent(generation), getAccessToken() != nil else {
            return false
        }
        markOIDCSessionValid()
        return true
    }

    /// For app extensions (widgets, controls): align the in-memory auth state with the
    /// credentials in the shared keychain, which the app may have changed since the
    /// extension launched (sign-in, sign-out, or switching between OIDC and demo).
    @MainActor func reconcileWithStoredCredentials() {
        let hasOIDC = getAccessToken() != nil || getKeychainItem(account: "oidc_refresh_token") != nil
        if hasOIDC {
            switch authState {
            case .signedIn(method: .oidc), .unknown:
                break
            default:
                authState = .signedIn(method: .oidc)
            }
        } else if WhereWeAre.getPassword() != nil {
            if case .signedIn(method: .demo) = authState { return }
            authState = .signedIn(method: .demo)
        } else if !isSignedOut {
            authState = .signedOut
        }
    }

    /// Re-checks keychain and restores authState if it was lost (e.g. after process termination).
    @MainActor func restoreStateIfNeeded() {
        guard case .signedOut = authState else { return }
        if getAccessToken() != nil {
            authState = .signedIn(method: .oidc)
        } else if WhereWeAre.getPassword() != nil {
            authState = .signedIn(method: .demo)
        }
    }

    func refreshTokenIfNeeded() async -> Bool {
        let generation = sessionGenerationSnapshot()
        // The keychain is shared with app extensions, which keep their own in-memory
        // generation. Also capture the shared session so a refresh that started before
        // another process signed out / switched accounts can't write back or sign out.
        let sharedSession = widgetSessionID()

        // If another refresh is in-flight, wait for its result (actor-serialized)
        if let coalescedResult = await refreshCoordinator.acquireOrWait(for: generation) {
            guard isSessionGenerationCurrent(generation) else {
                return false
            }
            logger.debug("refreshTokenIfNeeded: coalesced with in-flight refresh, result=\(coalescedResult)")
            return coalescedResult
        }

        let refreshToken: String
        switch refreshTokenState(for: generation) {
        case .available(let token):
            refreshToken = token
        case .sessionChanged:
            await refreshCoordinator.complete(for: generation, success: false)
            return false
        case .signInInProgress:
            logger.debug("refreshTokenIfNeeded: OIDC sign-in is replacing the current session")
            await refreshCoordinator.complete(for: generation, success: false)
            return false
        case .missing:
            logger.warning("refreshTokenIfNeeded: no refresh token in keychain — cannot refresh")
            await refreshCoordinator.complete(for: generation, success: false)
            if getAccessToken() == nil, WhereWeAre.getPassword() != nil {
                // Another process (the app) switched to demo sign-in and cleared the OIDC
                // tokens. Follow it rather than signing out, which would delete that password.
                await reconcileWithStoredCredentials()
            } else {
                await signOutIfSessionGenerationMatches(generation, sharedSession: sharedSession)
            }
            return false
        }

        logger.debug("refreshTokenIfNeeded: starting token refresh...")

        do {
            let tokens = try await refreshAccessToken(refreshToken)
            guard storeRefreshedTokens(tokens, for: generation, sharedSession: sharedSession),
                  await markRefreshedOIDCSessionValid(for: generation) else {
                logger.info("Discarding token refresh because the authentication session changed")
                await refreshCoordinator.complete(for: generation, success: false)
                return false
            }
            logger.info("Token refreshed (expiresIn=\(tokens.expiresIn ?? -1))")
            await refreshCoordinator.complete(for: generation, success: true)
            return true
        } catch AuthError.refreshTokenInvalid(let reason) {
            logger.error("Refresh token rejected by server — signing out: \(reason)")
            await refreshCoordinator.complete(for: generation, success: false)
            await signOutIfSessionGenerationMatches(generation, sharedSession: sharedSession)
            return false
        } catch {
            logger.warning("refreshTokenIfNeeded: transient failure, keeping session — \(error.localizedDescription)")
            await refreshCoordinator.complete(for: generation, success: false)
            return false
        }
    }

    private func sessionGenerationSnapshot() -> UInt64 {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        return sessionGeneration
    }

    private func isSessionGenerationCurrent(_ generation: UInt64) -> Bool {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        return sessionGeneration == generation
    }

    private func refreshTokenState(for generation: UInt64) -> RefreshTokenState {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        guard sessionGeneration == generation else {
            return .sessionChanged
        }
        guard oidcSignInGeneration != generation else {
            return .signInInProgress
        }
        guard let refreshToken = getKeychainItem(account: "oidc_refresh_token") else {
            return .missing
        }
        return .available(refreshToken)
    }

    /// Stores tokens from a refresh only if neither this process (generation) nor another
    /// process sharing the keychain (shared session, rotated whenever credentials are
    /// cleared) has changed the session since the refresh started. The keychain has no
    /// cross-process transaction, so a change landing between this check and the write is
    /// still possible but limited to that instant rather than the whole network round trip.
    private func storeRefreshedTokens(_ tokens: OIDCTokens, for generation: UInt64, sharedSession: String?) -> Bool {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        guard sessionGeneration == generation, Self.readWidgetSession() == sharedSession else {
            return false
        }
        storeTokens(tokens)
        return true
    }

    private func beginOIDCSignIn() -> UInt64 {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        sessionGeneration &+= 1
        oidcSignInGeneration = sessionGeneration
        return sessionGeneration
    }

    private func storeSignedInTokens(_ tokens: OIDCTokens, for generation: UInt64) -> Bool {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        guard sessionGeneration == generation, oidcSignInGeneration == generation else {
            return false
        }
        clearOIDCTokens()
        storeTokens(tokens)
        return true
    }

    private func finishOIDCSignIn(for generation: UInt64) {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        if oidcSignInGeneration == generation {
            oidcSignInGeneration = nil
        }
    }

    private func invalidateOIDCSession() {
        sessionGenerationLock.lock()
        defer { sessionGenerationLock.unlock() }
        sessionGeneration &+= 1
        oidcSignInGeneration = nil
        clearOIDCTokens()
    }

    @MainActor private func signOutIfSessionGenerationMatches(_ generation: UInt64, sharedSession: String?) {
        guard isSessionGenerationCurrent(generation), Self.readWidgetSession() == sharedSession else {
            return
        }
        signOut()
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> OIDCTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", Self.redirectURI),
            ("client_id", Self.clientID),
            ("code_verifier", codeVerifier),
            ("scope", Self.scopes)
        ]
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        logger.info("exchangeCode: POST \(Self.tokenURL)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            logger.error("exchangeCode: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) — \(body.prefix(500))")
            throw AuthError.tokenExchangeFailed(body)
        }

        let tokens = try JSONDecoder().decode(OIDCTokens.self, from: data)
        logger.info("exchangeCode: OK, expiresIn=\(tokens.expiresIn ?? -1), refresh=\(tokens.refreshToken != nil)")
        return tokens
    }
    private func refreshAccessToken(_ refreshToken: String) async throws -> OIDCTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", Self.clientID),
            ("scope", Self.scopes)
        ]
        request.httpBody = Self.formEncode(params).data(using: .utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.transientRefreshFailure(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.transientRefreshFailure(URLError(.badServerResponse))
        }
        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(OIDCTokens.self, from: data)
        }

        let body = String(data: data, encoding: .utf8) ?? "unknown"
        if (400...499).contains(httpResponse.statusCode) {
            throw AuthError.refreshTokenInvalid(body)
        }
        throw AuthError.transientRefreshFailure(URLError(.badServerResponse))
    }

    private func storeTokens(_ tokens: OIDCTokens) {
        setKeychainItem(account: "oidc_access_token", value: tokens.accessToken)
        if let refreshToken = tokens.refreshToken {
            setKeychainItem(account: "oidc_refresh_token", value: refreshToken)
        }
        if let expiresIn = tokens.expiresIn {
            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            setKeychainItem(
                account: "oidc_token_expiry",
                value: String(expiryDate.timeIntervalSince1970)
            )
        } else {
            deleteKeychainItem(account: "oidc_token_expiry")
            logger.warning("storeTokens: no expiresIn — cannot track expiry")
        }
    }

    // MARK: - Keychain Helpers
    private func setKeychainItem(account: String, value: String) {
        deleteKeychainItem(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        let status = SecItemAdd(Keychain.query(attributes), nil)
        if status != noErr {
            logger.error("Keychain write FAILED for \(account): OSStatus \(status)")
        }
    }

    private func getKeychainItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(Keychain.query(query), &item)
        if status == noErr, let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        if status != errSecItemNotFound {
            logger.error("Keychain read FAILED for \(account): OSStatus \(status)")
        }
        return nil
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.fluxhaus.oidc",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(Keychain.query(query))
    }

    private func clearOIDCTokens() {
        // Rotate the widget session so caches written under the old session are discarded.
        Self.rotateWidgetSession()
        deleteKeychainItem(account: "oidc_access_token")
        deleteKeychainItem(account: "oidc_refresh_token")
        deleteKeychainItem(account: "oidc_token_expiry")
    }

    // MARK: - PKCE Helpers
    private static func formEncode(_ params: [(String, String)]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return params.map { key, value in
            let encKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encVal = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encKey)=\(encVal)"
        }.joined(separator: "&")
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Self.base64URLEncode(Data(buffer))
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        Self.base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private func generateRandomString() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Self.base64URLEncode(Data(buffer))
    }
}
