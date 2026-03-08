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
    var isProgress: Bool
    var serverMessageId: String?

    init(
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        audioData: Data? = nil,
        isVoice: Bool = false,
        isProgress: Bool = false,
        serverMessageId: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.audioData = audioData
        self.isVoice = isVoice
        self.isProgress = isProgress
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
    var audioLevel: Float = 0
    var conversationId: String?
    var playingMessageId: UUID?
    var sessionError: String?
    var conversations: [Conversation] = []

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var levelTimer: Timer?

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await ensureConversation()
        messages.append(ChatMessage(role: .user, content: trimmed))
        isLoading = true

        do {
            let result = try await processStream(
                streamCommand(trimmed, conversationId: conversationId)
            )
            messages.removeAll { $0.isProgress }
            messages.append(ChatMessage(role: .assistant, content: result.text))
            updateMessageCount(by: 2)
            await updateTitleIfNeeded()
        } catch {
            messages.removeAll { $0.isProgress }
            logger.error("Chat error: \(error.localizedDescription)")
            messages.append(ChatMessage(role: .error, content: error.localizedDescription))
        }

        isLoading = false
    }

    private struct StreamResult {
        var text: String = "Done."
        var transcript: String?
        var audioData: Data?
    }

    private func processStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>
    ) async throws -> StreamResult {
        var result = StreamResult()
        for try await event in stream {
            switch event.type {
            case "transcript":
                result.transcript = event.text
                updateUserTranscript(event.text)
            case "progress":
                appendProgress(event.text)
            case "tool_call":
                appendToolCall(event.tool)
            case "done":
                if let text = event.text { result.text = text }
                if let b64 = event.audio, let data = Data(base64Encoded: b64) {
                    result.audioData = data
                }
            case "error":
                throw ChatServiceError.serverError(event.text ?? "Unknown error")
            default: break
            }
        }
        return result
    }

    private func appendProgress(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        messages.append(ChatMessage(role: .assistant, content: text, isProgress: true))
    }

    private func appendToolCall(_ tool: String?) {
        guard let tool else { return }
        messages.append(ChatMessage(
            role: .assistant, content: "🔧 \(formatToolName(tool))", isProgress: true
        ))
    }

    private func updateUserTranscript(_ text: String?) {
        guard let text, !text.isEmpty,
              let idx = messages.lastIndex(where: { $0.role == .user }) else { return }
        messages[idx] = ChatMessage(
            role: .user, content: text,
            timestamp: messages[idx].timestamp,
            audioData: messages[idx].audioData, isVoice: true
        )
    }

    private func formatToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    func startRecording() {
        #if canImport(UIKit)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to set up audio session: \(error.localizedDescription)")
            return
        }
        #endif

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
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            startLevelTimer()
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecordingAndSend() async {
        audioRecorder?.stop()
        isRecording = false
        stopLevelTimer()

        guard let url = recordingURL,
              let audioData = try? Data(contentsOf: url) else {
            messages.append(ChatMessage(role: .error, content: "Failed to read recording"))
            return
        }

        await ensureConversation()
        messages.append(ChatMessage(
            role: .user, content: "🎤 Voice message",
            audioData: audioData, isVoice: true
        ))
        isLoading = true

        do {
            let result = try await processStream(
                streamVoice(audioData: audioData, conversationId: conversationId)
            )
            messages.removeAll { $0.isProgress }
            messages.append(ChatMessage(
                role: .assistant, content: result.text,
                audioData: result.audioData, isVoice: true
            ))
            updateMessageCount(by: 2)
            await updateTitleIfNeeded()
            if let audio = result.audioData {
                playAudioResponse(data: audio)
            }
        } catch {
            messages.removeAll { $0.isProgress }
            logger.error("Voice error: \(error.localizedDescription)")
            messages.append(ChatMessage(role: .error, content: error.localizedDescription))
        }

        isLoading = false
        cleanupRecording()
    }

    private func playAudioResponse(data: Data) {
        configurePlaybackSession()
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
        configurePlaybackSession()
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

    private func configurePlaybackSession() {
        #if canImport(UIKit)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to configure playback session: \(error.localizedDescription)")
        }
        #endif
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
            if sessionError == "Chat history unavailable" {
                sessionError = nil
            }
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
            sessionError = nil
        } catch {
            logger.error("Failed to create conversation: \(error.localizedDescription)")
            sessionError = "Chat history unavailable"
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
                await ensureConversation()
            }
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

    // MARK: - Conversation helpers

    private func ensureConversation() async {
        guard conversationId == nil else { return }
        do {
            let conv = try await createConversation()
            conversationId = conv.id
            conversations.insert(conv, at: 0)
            sessionError = nil
        } catch {
            logger.error("Failed to ensure conversation: \(error.localizedDescription)")
        }
    }

    private func updateTitleIfNeeded() async {
        guard let convId = conversationId else { return }
        let userMessages = messages.filter { $0.role == .user }
        let count = userMessages.count
        guard count == 1 || count % 3 == 0 else { return }
        guard let latestMessage = userMessages.last?.content else { return }
        let title = String(latestMessage.prefix(50))
        do {
            try await updateConversationTitle(id: convId, title: title)
            if let index = conversations.firstIndex(where: { $0.id == convId }) {
                conversations[index].title = title
            }
        } catch {
            logger.error("Failed to update title: \(error.localizedDescription)")
        }
    }

    private func updateMessageCount(by count: Int) {
        guard let convId = conversationId,
              let index = conversations.firstIndex(where: { $0.id == convId }) else { return }
        conversations[index].messageCount += count
    }

    private func cleanupRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }

    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0, min(1, (power + 50) / 50))
                self.audioLevel = normalized
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }
}
