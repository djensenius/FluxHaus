//
//  FluxIntentActions.swift
//  FluxHaus
//
//  Shared async network helpers used by App Intents so that Siri / Apple Intelligence
//  can report real success or failure. Unlike the fire-and-forget `performAction` methods
//  on the @Observable device classes, these await the server response and throw on error.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "FluxIntentActions")

enum IntentError: LocalizedError {
    case notSignedIn
    case requestFailed(Int)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to FluxHaus first."
        case .requestFailed(let code):
            return "The request failed (HTTP \(code))."
        case .invalidURL:
            return "Could not build the request."
        }
    }
}

enum FluxIntentActions {
    static let scheme = "https"
    static let host = "api.fluxhaus.io"

    /// Performs an authenticated POST to the given API path and throws on a non-2xx response.
    static func post(path: String, body: [String: Any]? = nil) async throws {
        guard AuthManager.shared.isSignedIn else {
            throw IntentError.notSignedIn
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        guard let url = components.url else {
            throw IntentError.invalidURL
        }

        _ = await AuthManager.shared.ensureValidToken()
        let csrfToken = await fetchCsrfToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let authHeader = AuthManager.shared.authorizationHeader() {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        } else {
            throw IntentError.notSignedIn
        }
        if let csrfToken = csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let session = URLSession(configuration: .default)
        let (_, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(statusCode) else {
            logger.error("Intent action \(path) failed with HTTP \(statusCode)")
            throw IntentError.requestFailed(statusCode)
        }
        logger.info("Intent action \(path) completed with HTTP \(statusCode)")
    }

    // MARK: - Robots

    static func startRobot(_ robot: RobotKind) async throws {
        try await post(path: robot == .mopBot ? "/turnOnMopbot" : "/turnOnBroombot")
    }

    static func stopRobot(_ robot: RobotKind) async throws {
        try await post(path: robot == .mopBot ? "/turnOffMopbot" : "/turnOffBroombot")
    }

    static func deepClean() async throws {
        try await post(path: "/turnOnDeepClean")
    }

    // MARK: - Car

    static func lockCar() async throws { try await post(path: "/lockCar") }
    static func unlockCar() async throws { try await post(path: "/unlockCar") }
    static func resyncCar() async throws { try await post(path: "/resyncCar") }
    static func stopCarClimate() async throws { try await post(path: "/stopCar") }

    static func startCarClimate(
        defrost: Bool,
        heatedFeatures: Bool,
        temperature: Int?
    ) async throws {
        var body: [String: Any] = [
            "heatedFeatures": heatedFeatures,
            "seatFL": 0,
            "seatFR": 0,
            "seatRL": 0,
            "seatRR": 0,
            "defrost": defrost
        ]
        if let temperature = temperature {
            body["temp"] = temperature
        }
        try await post(path: "/startCar", body: body)
    }
}

/// The two robots FluxHaus controls. Shared by the action layer and the robot App Intents.
enum RobotKind: String {
    case broomBot
    case mopBot

    var displayName: String {
        switch self {
        case .broomBot: return "BroomBot"
        case .mopBot: return "MopBot"
        }
    }
}
