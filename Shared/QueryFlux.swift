//
//  QueryFlux.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "QueryFlux")

// MARK: - Helper Functions

/// Check if a login error message indicates an authentication failure (vs transient/server issue)
func isAuthFailureMessage(_ message: String) -> Bool {
    let lower = message.lowercased()
    return lower.contains("password") || lower.contains("incorrect") || lower.contains("unauthorized")
}

private struct CsrfResponse: Decodable {
    let csrfToken: String
}

func fetchCsrfToken() async -> String? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/auth/csrf-token"

    guard let url = components.url else { return nil }

    var request = URLRequest(url: url)
    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    do {
        let session = URLSession(configuration: .default)
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(CsrfResponse.self, from: data)
        return response.csrfToken
    } catch {
        logger.error("Failed to fetch CSRF token: \(error.localizedDescription)")
        return nil
    }
}

class BasicAuthDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let user: String
    let password: String

    init(user: String, password: String) {
        self.user = user
        self.password = password
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic {
            if challenge.previousFailureCount == 0 {
                let credential = URLCredential(user: user, password: password, persistence: .forSession)
                return (.useCredential, credential)
            }
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.performDefaultHandling, nil)
    }
}

// MARK: - Retry Helper
private struct RetryConfig {
    let maxRetries: Int = 3
    let initialDelayMs: UInt32 = 500

    func delayMs(for attempt: Int) -> UInt32 {
        UInt32(Double(initialDelayMs) * pow(2.0, Double(attempt)))
    }
}

private func isTransientNetworkError(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return false }
    let transientCodes = [
        NSURLErrorTimedOut,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorResourceUnavailable
    ]
    return transientCodes.contains(nsError.code)
}

private func buildFluxAPIRequest(password: String) -> URLRequest? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/"
    guard let url = components.url else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "get"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        let base64 = Data("demo:\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
    }
    return request
}

func queryFlux(password: String) {
    queryFluxWithRetry(password: password, attempt: 0)
}

private func queryFluxWithRetry(password: String, attempt: Int) {
    guard let request = buildFluxAPIRequest(password: password) else { return }

    let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
    let task = session.dataTask(with: request) { data, response, error in
        let httpResponse = response as? HTTPURLResponse

        if httpResponse?.statusCode == 401 {
            handleUnauthorized(password: password)
            return
        }

        if let error = error {
            if isTransientNetworkError(error) && attempt < RetryConfig().maxRetries {
                let delayMs = RetryConfig().delayMs(for: attempt)
                logger.warning("queryFlux: transient error on attempt \(attempt + 1), retrying in \(delayMs)ms")
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs))) {
                    queryFluxWithRetry(password: password, attempt: attempt + 1)
                }
                return
            }
        }

        handleQueryFluxResponse(data: data, error: error, password: password)
    }
    task.resume()
}

private func handleUnauthorized(password: String) {
    if AuthManager.shared.getAccessToken() != nil {
        logger.debug("handleUnauthorized: 401 with OIDC token, requesting refresh")
        Task { @MainActor in
            let oldToken = AuthManager.shared.getAccessToken()?.suffix(8) ?? "nil"
            let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
            if refreshed {
                let newToken = AuthManager.shared.getAccessToken()?.suffix(8) ?? "nil"
                logger.debug("handleUnauthorized: refresh succeeded (…\(oldToken) → …\(newToken)), retrying")
                retryQueryFlux(password: password)
            } else {
                logger.error("handleUnauthorized: refresh FAILED — signing out")
                AuthManager.shared.signOut()
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["keysFailed": true]
                )
            }
        }
    } else {
        logger.error("handleUnauthorized: demo auth failed — signing out and posting loginError")
        DispatchQueue.main.async {
            AuthManager.shared.signOut()
            NotificationCenter.default.post(
                name: Notification.Name.loginsUpdated,
                object: nil,
                userInfo: ["loginError": "Incorrect Password"]
            )
        }
    }
}

/// Single retry after token refresh — signs out on second 401 without further retry.
private func retryQueryFlux(password: String) {
    guard let request = buildFluxAPIRequest(password: password) else { return }

    let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
    let task = session.dataTask(with: request) { data, response, error in
        let httpResponse = response as? HTTPURLResponse
        if httpResponse?.statusCode == 401 {
            logger.error("retryQueryFlux: still 401 after refresh — signing out")
            DispatchQueue.main.async {
                AuthManager.shared.signOut()
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["keysFailed": true]
                )
            }
            return
        }
        handleQueryFluxResponse(data: data, error: error, password: password)
    }
    task.resume()
}

private func handleQueryFluxResponse(data: Data?, error: Error?, password: String) {
    if let data = data {
        do {
            let response = try JSONDecoder().decode(LoginResponse.self, from: data)
            DispatchQueue.main.async {
                AuthManager.shared.isCompletingOIDCLogin = false
                guard AuthManager.shared.isSignedIn else {
                    logger.debug("Ignoring late queryFlux success after sign-out")
                    return
                }
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: response,
                    userInfo: ["keysComplete": true]
                )
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["updateKeychain": password]
                )
                NotificationCenter.default.post(
                    name: Notification.Name.dataUpdated,
                    object: nil,
                    userInfo: ["data": response]
                )
            }
        } catch {
            logger.error("JSON decode failed: \(error)")
            if let jsonStr = String(data: data, encoding: .utf8) {
                logger.error("Response body: \(jsonStr.prefix(500))")
            }
            DispatchQueue.main.async {
                AuthManager.shared.isCompletingOIDCLogin = false
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["loginError": "Failed to load data"]
                )
            }
        }
    } else if let error = error {
        // Only post error for non-transient failures
        if !isTransientNetworkError(error) {
            logger.error("handleQueryFluxResponse: non-transient error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                AuthManager.shared.isCompletingOIDCLogin = false
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["loginError": error.localizedDescription]
                )
            }
        } else {
            // Transient network error but retries exhausted
            let msg = "transient error exhausted after retries"
            logger.error("handleQueryFluxResponse: \(msg): \(error.localizedDescription)")
            DispatchQueue.main.async {
                AuthManager.shared.isCompletingOIDCLogin = false
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["loginError": "Network error"]
                )
            }
        }
    } else {
        DispatchQueue.main.async {
            AuthManager.shared.isCompletingOIDCLogin = false
        }
    }
}

func getFlux(password: String) async throws -> LoginResponse? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/"

    let url = components.url!
    var request = URLRequest(url: url)
    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        let credentialData = Data("demo:\(password)".utf8)
        let base64Credential = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credential)", forHTTPHeaderField: "Authorization")
    }

    let session = URLSession(configuration: .default)
    let (data, response) = try await session.data(for: request)

    // If 401 and we have an OIDC token, try refreshing and retry once
    if let httpResponse = response as? HTTPURLResponse,
       httpResponse.statusCode == 401,
       AuthManager.shared.getAccessToken() != nil {
        let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
        if refreshed {
            var retryRequest = URLRequest(url: url)
            if let newAuth = AuthManager.shared.authorizationHeader() {
                retryRequest.setValue(newAuth, forHTTPHeaderField: "Authorization")
            }
            let (retryData, _) = try await session.data(for: retryRequest)
            return try JSONDecoder().decode(LoginResponse.self, from: retryData)
        }
    }

    let value = try JSONDecoder().decode(LoginResponse.self, from: data)
    return value
}

struct FluxData {
    var mopBot: Robot?
    var broomBot: Robot?
    var car: CarDetails?
    var dishwasher: DishWasher?
    var dryer: WasherDryer?
    let washer: WasherDryer?
}

func convertLoginResponseToAppData(response: LoginResponse) -> FluxData {
    let mopBot = Robot(
        name: "MopBot",
        timestamp: response.mopbot.timestamp,
        batteryLevel: response.mopbot.batteryLevel,
        binFull: response.mopbot.binFull,
        running: response.mopbot.running,
        charging: response.mopbot.charging,
        docking: response.mopbot.docking,
        paused: response.mopbot.paused,
        timeStarted: response.mopbot.timeStarted
    )

    let broomBot = Robot(
        name: "BroomBot",
        timestamp: response.broombot.timestamp,
        batteryLevel: response.broombot.batteryLevel,
        binFull: response.broombot.binFull,
        running: response.broombot.running,
        charging: response.broombot.charging,
        docking: response.broombot.docking,
        paused: response.broombot.paused,
        timeStarted: response.broombot.timeStarted
    )

    var car: CarDetails?
    if let fluxCar = response.car, let evStatus = response.carEvStatus {
        car = CarDetails(
            timestamp: fluxCar.timestamp,
            evStatusTimestamp: evStatus.timestamp,
            batteryLevel: evStatus.batteryStatus,
            distance: evStatus.drvDistance[0].rangeByFuel.evModeRange.value,
            hvac: fluxCar.airCtrlOn,
            pluggedIn: evStatus.batteryPlugin == 0 ? false : true,
            batteryCharge: evStatus.batteryCharge,
            locked: fluxCar.doorLock,
            doorsOpen: Doors(
                frontRight: fluxCar.doorOpen.frontRight,
                frontLeft: fluxCar.doorOpen.frontLeft,
                backRight: fluxCar.doorOpen.backRight,
                backLeft: fluxCar.doorOpen.backLeft
            ),
            trunkOpen: fluxCar.trunkOpen,
            defrost: fluxCar.defrost,
            hoodOpen: fluxCar.hoodOpen,
            odometer: response.carOdometer ?? 0,
            engine: fluxCar.engine
        )
    }

    let dishwasher = response.dishwasher

    let dryer = response.dryer

    let washer = response.washer

    return FluxData(
        mopBot: mopBot,
        broomBot: broomBot,
        car: car,
        dishwasher: dishwasher,
        dryer: dryer,
        washer: washer
    )
}
