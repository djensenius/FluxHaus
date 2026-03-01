//
//  BearerQueryFlux.swift
//  FluxHaus
//
//  Created by Copilot on 2026-03-01.
//

import Foundation
import os

private let bearerLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "BearerQueryFlux")

// MARK: - OIDC Bearer Auth

/// Query the FluxHaus API using an OIDC Bearer token.
/// On 401, attempts a token refresh and retries once.
/// Does NOT fall back to demo user — OIDC users are admin only.
func queryFluxWithBearer(accessToken: String) {
    makeBearerRequest(bearerToken: accessToken, isRetry: false)
}

private func makeBearerRequest(bearerToken: String, isRetry: Bool) {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/"
    guard let url = components.url else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

    let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
    let task = session.dataTask(with: request) { data, response, error in
        let httpResponse = response as? HTTPURLResponse
        if httpResponse?.statusCode == 401 {
            if !isRetry {
                Task {
                    do {
                        let newToken = try await OIDCManager.shared.refreshTokens()
                        makeBearerRequest(bearerToken: newToken, isRetry: true)
                    } catch {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: Notification.Name.loginsUpdated,
                                object: nil,
                                userInfo: ["loginError": "Session expired. Please sign in again."]
                            )
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: nil,
                        userInfo: ["loginError": "Session expired. Please sign in again."]
                    )
                }
            }
            return
        }
        if let data = data {
            do {
                let response = try JSONDecoder().decode(LoginResponse.self, from: data)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: response,
                        userInfo: ["keysComplete": true]
                    )
                    NotificationCenter.default.post(
                        name: Notification.Name.dataUpdated,
                        object: nil,
                        userInfo: ["data": response]
                    )
                }
            } catch {
                bearerLogger.error("JSON decode failed (Bearer): \(error)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: nil,
                        userInfo: ["loginError": "Failed to parse server response"]
                    )
                }
            }
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["loginError": error?.localizedDescription ?? "Network error"]
                )
            }
        }
    }
    task.resume()
}
