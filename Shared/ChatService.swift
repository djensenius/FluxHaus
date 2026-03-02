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
    let conversationId: String?
}

struct CommandResponse: Decodable {
    let response: String
}

struct VoiceRequest: Encodable {
    let audio: String?
    let text: String?
    let filename: String?
    let conversationId: String?
}

struct CommandError: Decodable {
    let error: String
}

struct VoiceResponse {
    let audioData: Data
    let transcript: String
    let responseText: String
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

private func buildAuthRequest(url: URL, method: String = "POST") throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")

    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        throw ChatServiceError.unauthorized
    }
    return request
}

private func handleUnauthorizedRetry(
    url: URL,
    body: Data,
    session: URLSession
) async throws -> (Data, URLResponse) {
    guard AuthManager.shared.getAccessToken() != nil else {
        throw ChatServiceError.unauthorized
    }
    let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
    guard refreshed else {
        throw ChatServiceError.unauthorized
    }
    var retryRequest = try buildAuthRequest(url: url)
    retryRequest.httpBody = body
    return try await session.data(for: retryRequest)
}

func sendCommand(_ command: String, conversationId: String? = nil) async throws -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/command"
    let url = components.url!

    var request = try buildAuthRequest(url: url)
    let body = CommandRequest(command: command, conversationId: conversationId)
    let bodyData = try JSONEncoder().encode(body)
    request.httpBody = bodyData

    let session = URLSession(configuration: .default)
    var (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
        (data, response) = try await handleUnauthorizedRetry(url: url, body: bodyData, session: session)
    }

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        if let errorResponse = try? JSONDecoder().decode(CommandError.self, from: data) {
            throw ChatServiceError.serverError(errorResponse.error)
        }
        throw ChatServiceError.serverError("Server error (\(httpResponse.statusCode))")
    }

    let result = try JSONDecoder().decode(CommandResponse.self, from: data)
    return result.response
}

func sendVoice(audioData: Data, conversationId: String? = nil) async throws -> VoiceResponse {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/voice"
    let url = components.url!

    var request = try buildAuthRequest(url: url)
    let voiceReq = VoiceRequest(
        audio: audioData.base64EncodedString(),
        text: nil,
        filename: "audio.m4a",
        conversationId: conversationId
    )
    let bodyData = try JSONEncoder().encode(voiceReq)
    request.httpBody = bodyData

    let session = URLSession(configuration: .default)
    var (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
        (data, response) = try await handleUnauthorizedRetry(url: url, body: bodyData, session: session)
    }

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        if let errorResponse = try? JSONDecoder().decode(CommandError.self, from: data) {
            throw ChatServiceError.serverError(errorResponse.error)
        }
        throw ChatServiceError.serverError("Server error (\(httpResponse.statusCode))")
    }

    let httpResponse = response as? HTTPURLResponse
    let transcript = httpResponse?.value(forHTTPHeaderField: "X-Transcript")
        .flatMap { $0.removingPercentEncoding } ?? ""
    let responseText = httpResponse?.value(forHTTPHeaderField: "X-Response")
        .flatMap { $0.removingPercentEncoding } ?? ""

    return VoiceResponse(audioData: data, transcript: transcript, responseText: responseText)
}

// MARK: - Conversation CRUD

struct ConversationsResponse: Decodable {
    let conversations: [Conversation]
}

struct ConversationDetailMessage: Decodable {
    let id: String
    let role: String
    let content: String
    let isVoice: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case isVoice = "is_voice"
        case createdAt = "created_at"
    }
}

struct ConversationDetail: Decodable {
    let id: String
    let title: String?
    let messages: [ConversationDetailMessage]

    enum CodingKeys: String, CodingKey {
        case id, title, messages
    }
}

func fetchConversations() async throws -> [Conversation] {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/conversations"
    let url = components.url!

    var request = try buildAuthRequest(url: url, method: "GET")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let session = URLSession(configuration: .default)
    var (data, response) = try await session.data(for: request)

    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
        (data, response) = try await handleUnauthorizedRetry(
            url: url, body: Data(), session: session
        )
    }

    let result = try JSONDecoder().decode(ConversationsResponse.self, from: data)
    return result.conversations
}

func createConversation() async throws -> Conversation {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/conversations"
    let url = components.url!

    var request = try buildAuthRequest(url: url)
    request.httpBody = try JSONEncoder().encode(["title": "New conversation"])

    let session = URLSession(configuration: .default)
    var (data, response) = try await session.data(for: request)

    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
        (data, response) = try await handleUnauthorizedRetry(
            url: url, body: request.httpBody ?? Data(), session: session
        )
    }

    return try JSONDecoder().decode(Conversation.self, from: data)
}

func fetchConversation(id: String) async throws -> ConversationDetail {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/conversations/\(id)"
    let url = components.url!

    let request = try buildAuthRequest(url: url, method: "GET")

    let session = URLSession(configuration: .default)
    var (data, response) = try await session.data(for: request)

    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
        (data, response) = try await handleUnauthorizedRetry(
            url: url, body: Data(), session: session
        )
    }

    return try JSONDecoder().decode(ConversationDetail.self, from: data)
}

func deleteConversationRequest(id: String) async throws {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/conversations/\(id)"
    let url = components.url!

    let request = try buildAuthRequest(url: url, method: "DELETE")

    let session = URLSession(configuration: .default)
    let (_, response) = try await session.data(for: request)

    if let http = response as? HTTPURLResponse,
       http.statusCode != 204 && http.statusCode != 200 {
        throw ChatServiceError.serverError("Delete failed (\(http.statusCode))")
    }
}
