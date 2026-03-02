//
//  Chat.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-01.
//

import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Chat")

enum ChatRole: String {
    case user
    case assistant
    case error
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    var audioData: Data?
    var isVoice: Bool
    var serverMessageId: String?

    init(
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        audioData: Data? = nil,
        isVoice: Bool = false,
        serverMessageId: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.audioData = audioData
        self.isVoice = isVoice
        self.serverMessageId = serverMessageId
    }
}

struct Conversation: Identifiable, Codable {
    let id: String
    var title: String?
    let createdAt: String
    var updatedAt: String
    var messageCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messageCount = "message_count"
    }
}

@MainActor
@Observable class Chat: NSObject, AVAudioPlayerDelegate {
    var messages: [ChatMessage] = []
    var isLoading = false
    var isRecording = false
    var conversationId: String?
    var playingMessageId: UUID?
    var conversations: [Conversation] = []

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmed))
        isLoading = true

        do {
            let response = try await sendCommand(trimmed, conversationId: conversationId)
            messages.append(ChatMessage(role: .assistant, content: response))
        } catch {
            logger.error("Chat error: \(error.localizedDescription)")
            messages.append(ChatMessage(
                role: .error,
                content: error.localizedDescription
            ))
        }

        isLoading = false
    }

    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to set up audio session: \(error.localizedDescription)")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("voice_recording.m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecordingAndSend() async {
        audioRecorder?.stop()
        isRecording = false

        guard let url = recordingURL,
              let audioData = try? Data(contentsOf: url) else {
            messages.append(ChatMessage(role: .error, content: "Failed to read recording"))
            return
        }

        messages.append(ChatMessage(
            role: .user,
            content: "🎤 Voice message",
            audioData: audioData,
            isVoice: true
        ))
        isLoading = true

        do {
            let response = try await sendVoice(audioData: audioData, conversationId: conversationId)

            // Update user message with transcript
            if !response.transcript.isEmpty {
                if let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) {
                    messages[lastUserIndex] = ChatMessage(
                        role: .user,
                        content: response.transcript,
                        timestamp: messages[lastUserIndex].timestamp,
                        audioData: messages[lastUserIndex].audioData,
                        isVoice: true
                    )
                }
            }

            messages.append(ChatMessage(
                role: .assistant,
                content: response.responseText,
                audioData: response.audioData,
                isVoice: true
            ))

            playAudioResponse(data: response.audioData)
        } catch {
            logger.error("Voice error: \(error.localizedDescription)")
            messages.append(ChatMessage(
                role: .error,
                content: error.localizedDescription
            ))
        }

        isLoading = false
        cleanupRecording()
    }

    private func playAudioResponse(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
        }
    }

    func playAudio(for message: ChatMessage) {
        guard let data = message.audioData else { return }
        stopPlayback()
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            playingMessageId = message.id
            audioPlayer?.play()
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
            playingMessageId = nil
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        playingMessageId = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.playingMessageId = nil
        }
    }

    // MARK: - Session management

    func loadConversations() async {
        do {
            conversations = try await fetchConversations()
        } catch {
            logger.error("Failed to load conversations: \(error.localizedDescription)")
        }
    }

    func createNewConversation() async {
        do {
            let conv = try await createConversation()
            conversationId = conv.id
            messages = []
            conversations.insert(conv, at: 0)
        } catch {
            logger.error("Failed to create conversation: \(error.localizedDescription)")
        }
    }

    func loadConversation(_ conv: Conversation) async {
        conversationId = conv.id
        messages = []
        isLoading = true
        do {
            let detail = try await fetchConversation(id: conv.id)
            messages = detail.messages.map { msg in
                ChatMessage(
                    role: ChatRole(rawValue: msg.role) ?? .assistant,
                    content: msg.content,
                    timestamp: ISO8601DateFormatter().date(from: msg.createdAt) ?? Date(),
                    isVoice: msg.isVoice
                )
            }
        } catch {
            logger.error("Failed to load conversation: \(error.localizedDescription)")
            messages.append(ChatMessage(role: .error, content: "Failed to load history"))
        }
        isLoading = false
    }

    func deleteConversation(_ conv: Conversation) async {
        do {
            try await deleteConversationRequest(id: conv.id)
            conversations.removeAll { $0.id == conv.id }
            if conversationId == conv.id {
                conversationId = nil
                messages = []
            }
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

    private func cleanupRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}
