//
//  ChatTranscriptRendererTests.swift
//  FluxHaus Tests
//
//  Created by Copilot on 2026-05-22.
//

import Foundation
import Testing
@testable import FluxHaus

struct ChatTranscriptRendererTests {

    @Test("Transcript snapshot serializes message state")
    func transcriptSnapshotSerializesMessageState() throws {
        let message = ChatMessage(
            role: .assistant,
            content: "**Done**",
            audioData: Data([1, 2, 3]),
            isVoice: true,
            isProgress: false
        )
        let snapshot = ChatTranscriptSnapshot(
            conversationId: "conversation",
            messages: [message],
            isLoading: true,
            playingMessageId: message.id
        )

        let json = try jsonObject(from: snapshot)
        let messages = try #require(json["messages"] as? [[String: Any]])
        let serialized = try #require(messages.first)

        #expect(json["conversationId"] as? String == "conversation")
        #expect(json["isLoading"] as? Bool == true)
        #expect(serialized["id"] as? String == message.id.uuidString)
        #expect(serialized["role"] as? String == "assistant")
        #expect(serialized["content"] as? String == "**Done**")
        #expect(serialized["hasAudio"] as? Bool == true)
        #expect(serialized["isVoice"] as? Bool == true)
        #expect(serialized["isPlaying"] as? Bool == true)
    }

    @Test("Transcript image allows only safe data URLs")
    func transcriptImageAllowsOnlySafeDataURLs() throws {
        let message = ChatMessage(
            role: .user,
            content: "images",
            images: [
                ChatImage(mediaType: "image/png", base64: "aGVsbG8="),
                ChatImage(mediaType: "image/svg+xml", base64: "aGVsbG8="),
                ChatImage(mediaType: "image/jpeg", base64: "not base64")
            ]
        )
        let snapshot = ChatTranscriptSnapshot(
            conversationId: "conversation",
            messages: [message],
            isLoading: false,
            playingMessageId: nil
        )

        let json = try jsonObject(from: snapshot)
        let messages = try #require(json["messages"] as? [[String: Any]])
        let serialized = try #require(messages.first)
        let images = try #require(serialized["images"] as? [[String: Any]])
        let image = try #require(images.first)

        #expect(images.count == 1)
        #expect(image["mediaType"] as? String == "image/png")
        #expect(image["dataURL"] as? String == "data:image/png;base64,aGVsbG8=")
    }

    private func jsonObject(from snapshot: ChatTranscriptSnapshot) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
