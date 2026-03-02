//
//  Chat.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-01.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Chat")

enum ChatRole: String {
    case user
    case assistant
    case error
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp: Date
}

@MainActor
@Observable class Chat {
    var messages: [ChatMessage] = []
    var isLoading = false

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmed, timestamp: Date()))
        isLoading = true

        do {
            let response = try await sendCommand(trimmed)
            messages.append(ChatMessage(role: .assistant, content: response, timestamp: Date()))
        } catch {
            logger.error("Chat error: \(error.localizedDescription)")
            messages.append(ChatMessage(
                role: .error,
                content: error.localizedDescription,
                timestamp: Date()
            ))
        }

        isLoading = false
    }
}
