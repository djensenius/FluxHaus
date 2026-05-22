//
//  ChatTranscriptRenderer.swift
//  FluxHaus
//
//  Created by Copilot on 2026-05-22.
//

import Foundation

enum ChatTranscriptRenderer {
    private static let defaultsKey = "ChatTranscriptWebRendererEnabled"

    static var usesWebTranscript: Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var isAvailable: Bool {
        Bundle.main.url(forResource: "ChatTranscriptRenderer", withExtension: "html") != nil
    }
}

struct ChatTranscriptSnapshot: Encodable {
    let conversationId: String
    let messages: [ChatTranscriptMessage]
    let isLoading: Bool

    init(conversationId: String, messages: [ChatMessage], isLoading: Bool, playingMessageId: UUID?) {
        self.conversationId = conversationId
        self.messages = messages.map {
            ChatTranscriptMessage(message: $0, isPlaying: $0.id == playingMessageId)
        }
        self.isLoading = isLoading
    }
}

struct ChatTranscriptMessage: Encodable {
    let id: String
    let role: String
    let content: String
    let isProgress: Bool
    let isVoice: Bool
    let hasAudio: Bool
    let isPlaying: Bool
    let images: [ChatTranscriptImage]

    init(message: ChatMessage, isPlaying: Bool) {
        id = message.id.uuidString
        role = message.role.rawValue
        content = message.content
        isProgress = message.isProgress
        isVoice = message.isVoice
        hasAudio = message.audioData != nil
        self.isPlaying = isPlaying
        images = message.images.compactMap(ChatTranscriptImage.init(image:))
    }
}

struct ChatTranscriptImage: Encodable {
    let mediaType: String
    let dataURL: String
    private static let allowedTypes: Set<String> = [
        "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"
    ]

    init?(image: ChatImage) {
        guard Self.allowedTypes.contains(image.mediaType.lowercased()),
              Data(base64Encoded: image.base64) != nil else { return nil }
        mediaType = image.mediaType.lowercased()
        dataURL = "data:\(mediaType);base64,\(image.base64)"
    }
}
