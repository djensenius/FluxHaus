//
//  ChatTranscriptRendererTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2026-05-22.
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

struct PastedTextAttachmentTests {

    @Test("Long text qualifies as a pasted attachment")
    func longTextQualifies() {
        let long = String(repeating: "a", count: 600)
        #expect(PastedTextAttachment.qualifies(long))
        #expect(!PastedTextAttachment.qualifies("short"))
    }

    @Test("Many lines qualify as a pasted attachment")
    func manyLinesQualify() {
        let manyLines = Array(repeating: "x", count: 15).joined(separator: "\n")
        #expect(PastedTextAttachment.qualifies(manyLines))
        let fewLines = Array(repeating: "x", count: 3).joined(separator: "\n")
        #expect(!PastedTextAttachment.qualifies(fewLines))
    }

    @Test("Detects a large insertion and strips it from the remaining text")
    func detectsLargeInsertion() throws {
        let pasted = String(repeating: "z", count: 700)
        let result = try #require(
            PastedTextAttachment.detectLargeInsertion(old: "Hi !", new: "Hi \(pasted)!")
        )
        #expect(result.inserted == pasted)
        #expect(result.remaining == "Hi !")
    }

    @Test("Ignores small insertions")
    func ignoresSmallInsertion() {
        #expect(PastedTextAttachment.detectLargeInsertion(old: "Hi", new: "Hi there") == nil)
    }

    @Test("Line and character counts are accurate")
    func countsAreAccurate() {
        let attachment = PastedTextAttachment(text: "one\ntwo\nthree")
        #expect(attachment.lineCount == 3)
        #expect(attachment.charCount == 13)
    }
}

@MainActor
struct ChatComposeCommandTests {

    @Test("Composes typed text with fenced pasted attachments")
    func composesFencedAttachments() {
        let pasted = PastedTextAttachment(text: "let x = 1")
        let composed = Chat.composeCommand(text: "Review this", pastedTexts: [pasted])
        #expect(composed == "Review this\n\n```\nlet x = 1\n```")
    }

    @Test("Uses a longer fence when content contains backtick runs")
    func usesLongerFenceForBackticks() {
        let pasted = PastedTextAttachment(text: "```\ncode\n```")
        let composed = Chat.composeCommand(text: "", pastedTexts: [pasted])
        #expect(composed == "````\n```\ncode\n```\n````")
    }

    @Test("Returns trimmed text when there are no pasted attachments")
    func returnsPlainTextWithoutAttachments() {
        #expect(Chat.composeCommand(text: "  hello  ", pastedTexts: []) == "hello")
    }
}
