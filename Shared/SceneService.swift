//
//  SceneService.swift
//  FluxHaus
//
//  Created by Copilot on 2026-03-02.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "SceneService")

struct HomeScene: Codable, Identifiable {
    let entityId: String
    let name: String

    var id: String { entityId }
}

struct SceneActivateRequest: Encodable {
    let entityId: String
}

enum SceneServiceError: Error, LocalizedError {
    case unauthorized
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication required"
        case .serverError(let msg):
            return msg
        case .networkError(let msg):
            return msg
        }
    }
}

func fetchScenes() async throws -> [HomeScene] {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/scenes"
    let url = components.url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        throw SceneServiceError.unauthorized
    }

    let session = URLSession(configuration: .default)
    let (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
        let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
        guard refreshed else { throw SceneServiceError.unauthorized }
        var retry = URLRequest(url: url)
        retry.httpMethod = "GET"
        retry.addValue("application/json", forHTTPHeaderField: "Accept")
        if let header = AuthManager.shared.authorizationHeader() {
            retry.setValue(header, forHTTPHeaderField: "Authorization")
        }
        let (retryData, _) = try await session.data(for: retry)
        return try JSONDecoder().decode([HomeScene].self, from: retryData)
    }

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        logger.error("Failed to fetch scenes: HTTP \(httpResponse.statusCode)")
        throw SceneServiceError.serverError("Failed to load scenes")
    }

    return try JSONDecoder().decode([HomeScene].self, from: data)
}

func activateScene(entityId: String) async throws {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/scenes/activate"
    let url = components.url!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        throw SceneServiceError.unauthorized
    }
    let body = SceneActivateRequest(entityId: entityId)
    request.httpBody = try JSONEncoder().encode(body)

    let session = URLSession(configuration: .default)
    let (_, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
        let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
        guard refreshed else { throw SceneServiceError.unauthorized }
        var retry = URLRequest(url: url)
        retry.httpMethod = "POST"
        retry.addValue("application/json", forHTTPHeaderField: "Content-Type")
        retry.addValue("application/json", forHTTPHeaderField: "Accept")
        if let header = AuthManager.shared.authorizationHeader() {
            retry.setValue(header, forHTTPHeaderField: "Authorization")
        }
        retry.httpBody = try JSONEncoder().encode(body)
        let (_, retryResp) = try await session.data(for: retry)
        if let retryHttp = retryResp as? HTTPURLResponse, retryHttp.statusCode != 200 {
            throw SceneServiceError.serverError("Failed to activate scene")
        }
        return
    }

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        logger.error("Failed to activate scene: HTTP \(httpResponse.statusCode)")
        throw SceneServiceError.serverError("Failed to activate scene")
    }
}
