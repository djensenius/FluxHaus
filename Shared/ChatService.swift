//
//  ChatService.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-01.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "ChatService")

struct CommandRequest: Encodable {
    let command: String
}

struct CommandResponse: Decodable {
    let response: String
}

struct CommandError: Decodable {
    let error: String
}

enum ChatServiceError: Error, LocalizedError {
    case serverError(String)
    case networkError(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .networkError(let message):
            return message
        case .unauthorized:
            return "Session expired. Please sign in again."
        }
    }
}

func sendCommand(_ command: String) async throws -> String {
    let scheme = "https"
    let host = "api.fluxhaus.io"
    let path = "/command"

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path

    let url = components.url!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")

    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        throw ChatServiceError.unauthorized
    }

    let body = CommandRequest(command: command)
    request.httpBody = try JSONEncoder().encode(body)

    let session = URLSession(configuration: .default)
    let (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 401 {
            // Try refreshing token and retry once
            if AuthManager.shared.getAccessToken() != nil {
                let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
                if refreshed {
                    var retryRequest = URLRequest(url: url)
                    retryRequest.httpMethod = "POST"
                    retryRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    retryRequest.addValue("application/json", forHTTPHeaderField: "Accept")
                    if let newAuth = AuthManager.shared.authorizationHeader() {
                        retryRequest.setValue(newAuth, forHTTPHeaderField: "Authorization")
                    }
                    retryRequest.httpBody = try JSONEncoder().encode(body)
                    let (retryData, retryResponse) = try await session.data(for: retryRequest)
                    if let retryHttp = retryResponse as? HTTPURLResponse, retryHttp.statusCode == 200 {
                        let result = try JSONDecoder().decode(CommandResponse.self, from: retryData)
                        return result.response
                    }
                }
            }
            throw ChatServiceError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(CommandError.self, from: data) {
                throw ChatServiceError.serverError(errorResponse.error)
            }
            throw ChatServiceError.serverError("Server error (\(httpResponse.statusCode))")
        }
    }

    let result = try JSONDecoder().decode(CommandResponse.self, from: data)
    return result.response
}
