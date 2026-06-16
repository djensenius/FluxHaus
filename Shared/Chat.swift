//
//  Chat.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-01.
//

// swiftlint:disable file_length
import Foundation
import AVFoundation
import SwiftUI
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Chat")

/// Inline markdown rendering for simple text (e.g. user messages, progress labels).
func markdownAttributed(_ string: String) -> AttributedString {
    var cleaned = string
    cleaned = cleaned.replacingOccurrences(of: "\n", with: "  \n")
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    return (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(string)
}

enum ChatRole: String {
    case user
    case assistant
    case error
}

struct ChatImage: Identifiable {
    let id = UUID()
    let mediaType: String
    let base64: String

    var uiImageData: Data? {
        Data(base64Encoded: base64)
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    var audioData: Data?
    var images: [ChatImage]
    var isVoice: Bool
    var isProgress: Bool
    var serverMessageId: String?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        audioData: Data? = nil,
        images: [ChatImage] = [],
        isVoice: Bool = false,
        isProgress: Bool = false,
        serverMessageId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.audioData = audioData
        self.images = images
        self.isVoice = isVoice
        self.isProgress = isProgress
        self.serverMessageId = serverMessageId
    }

    /// Returns a copy with the same `id`, updated `content`/`isVoice`, and all other fields preserved.
    ///
    /// Keeping the same `id` avoids transcript row churn while streamed text updates.
    func updating(content: String, isVoice: Bool) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            audioData: audioData,
            images: images,
            isVoice: isVoice,
            isProgress: isProgress,
            serverMessageId: serverMessageId
        )
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
    var isLoading = false
    var isRecording = false
    var audioLevel: Float = 0
    var conversationId: String?
    var playingMessageId: UUID?
    var sessionError: String?
    var conversations: [Conversation] = []
    private(set) var cachedConversationIds: [String] = []
    private var cachedMessages: [String: [ChatMessage]] = [:]
    private let maxCachedConversations = 5
    private var streamingConversationId: String?
    private var activeStreamId: UUID?
    private var activeStreamTask: Task<Void, Never>?

    var messages: [ChatMessage] {
        get { conversationId.flatMap { cachedMessages[$0] } ?? [] }
        set {
            guard let id = conversationId else { return }
            cachedMessages[id] = newValue
        }
    }

    func messages(for convId: String) -> [ChatMessage] {
        cachedMessages[convId] ?? []
    }

    func isConversationBusy(_ convId: String) -> Bool {
        streamingConversationId == convId || loadingConversationIds.contains(convId)
    }

    private func touchConversation(_ id: String) {
        cachedConversationIds.removeAll { $0 == id }
        cachedConversationIds.insert(id, at: 0)
        pruneCachedConversations()
    }

    private func pruneCachedConversations() {
        while cachedConversationIds.count > maxCachedConversations {
            let protectedIds = loadingConversationIds.union([streamingConversationId].compactMap(\.self))
            let evictionIndex = cachedConversationIds.lastIndex { !protectedIds.contains($0) }
            guard let evictionIndex else { break }
            let evicted = cachedConversationIds.remove(at: evictionIndex)
            cachedMessages.removeValue(forKey: evicted)
        }
    }

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var levelTimer: Timer?
    private var isSyncing = false
    private var loadingConversationIds: Set<String> = []

    func send(_ text: String, images: [ChatImage] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard await ensureConversation() else {
            cleanupRecording()
            return
        }
        guard let targetConversationId = conversationId else {
            cleanupRecording()
            return
        }
        guard let streamId = beginStream(conversationId: targetConversationId) else { return }
        appendMessage(
            ChatMessage(role: .user, content: trimmed, images: images),
            to: targetConversationId
        )

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runTextStream(
                streamCommand(trimmed, conversationId: targetConversationId, images: images),
                conversationId: targetConversationId,
                streamId: streamId
            )
        }
        activeStreamTask = task
        await task.value
    }

    private func runTextStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        conversationId targetConversationId: String,
        streamId: UUID
    ) async {
        defer { finishStream(streamId: streamId, conversationId: targetConversationId) }
        do {
            let result = try await processStream(stream, conversationId: targetConversationId, streamId: streamId)
            guard isActiveStream(streamId) else { return }
            // Batch: remove progress + add assistant in one mutation
            var updated = messages(for: targetConversationId).filter { !$0.isProgress }
            updated.append(ChatMessage(role: .assistant, content: result.text))
            setMessages(updated, for: targetConversationId)
            updateMessageCount(by: 2, conversationId: targetConversationId)
            await updateTitleIfNeeded(conversationId: targetConversationId)
        } catch is CancellationError {
            removeProgressMessages(conversationId: targetConversationId)
        } catch {
            guard isActiveStream(streamId) else { return }
            var updated = messages(for: targetConversationId).filter { !$0.isProgress }
            logger.error("Chat error: \(error.localizedDescription)")
            updated.append(ChatMessage(role: .error, content: error.localizedDescription))
            setMessages(updated, for: targetConversationId)
        }
    }

    private struct StreamResult {
        var text: String = "Done."
        var transcript: String?
        var audioData: Data?
    }

    private func processStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        conversationId: String,
        streamId: UUID
    ) async throws -> StreamResult {
        var result = StreamResult()
        var hadToolCalls = false
        var receivedDone = false
        for try await event in stream {
            try Task.checkCancellation()
            guard isActiveStream(streamId) else { throw CancellationError() }
            try handleStreamEvent(
                event,
                result: &result,
                hadToolCalls: &hadToolCalls,
                receivedDone: &receivedDone,
                conversationId: conversationId
            )
        }
        if !receivedDone && hadToolCalls {
            result.text = "The request timed out while processing. Please try again."
        }
        return result
    }

    private func handleStreamEvent(
        _ event: StreamEvent,
        result: inout StreamResult,
        hadToolCalls: inout Bool,
        receivedDone: inout Bool,
        conversationId: String
    ) throws {
        switch event.type {
        case "transcript":
            result.transcript = event.text
            updateUserTranscript(event.text, conversationId: conversationId)
        case "progress":
            appendProgress(event.text, conversationId: conversationId)
        case "tool_call":
            hadToolCalls = true
            appendToolCall(event.tool, conversationId: conversationId)
        case "done":
            receivedDone = true
            if let text = event.text { result.text = text }
            if let b64 = event.audio, let data = Data(base64Encoded: b64) {
                result.audioData = data
            }
        case "error":
            throw ChatServiceError.serverError(event.text ?? "Unknown error")
        default:
            break
        }
    }

    private func appendProgress(_ text: String?, conversationId: String) {
        guard let text, !text.isEmpty else { return }
        appendMessage(ChatMessage(role: .assistant, content: text, isProgress: true), to: conversationId)
    }

    private func appendToolCall(_ tool: String?, conversationId: String) {
        guard let tool else { return }
        appendMessage(ChatMessage(
            role: .assistant, content: "🔧 \(formatToolName(tool))", isProgress: true
        ), to: conversationId)
    }

    private func updateUserTranscript(_ text: String?, conversationId: String) {
        guard let text, !text.isEmpty,
              let idx = messages(for: conversationId).lastIndex(where: { $0.role == .user }) else { return }
        mutateMessages(for: conversationId) { conversationMessages in
            let existing = conversationMessages[idx]
            conversationMessages[idx] = existing.updating(content: text, isVoice: true)
        }
    }

    private func formatToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

}

extension Chat {
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

        guard await ensureConversation() else {
            cleanupRecording()
            return
        }
        guard let targetConversationId = conversationId else {
            cleanupRecording()
            return
        }
        guard let streamId = beginStream(conversationId: targetConversationId) else {
            cleanupRecording()
            return
        }
        appendMessage(ChatMessage(
            role: .user, content: "🎤 Voice message",
            audioData: audioData, isVoice: true
        ), to: targetConversationId)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runVoiceStream(
                streamVoice(audioData: audioData, conversationId: targetConversationId),
                conversationId: targetConversationId,
                streamId: streamId
            )
        }
        activeStreamTask = task
        await task.value
        cleanupRecording()
    }

    private func runVoiceStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        conversationId targetConversationId: String,
        streamId: UUID
    ) async {
        defer { finishStream(streamId: streamId, conversationId: targetConversationId) }
        do {
            let result = try await processStream(stream, conversationId: targetConversationId, streamId: streamId)
            guard isActiveStream(streamId) else { return }
            var updated = messages(for: targetConversationId).filter { !$0.isProgress }
            updated.append(ChatMessage(
                role: .assistant, content: result.text,
                audioData: result.audioData, isVoice: true
            ))
            setMessages(updated, for: targetConversationId)
            updateMessageCount(by: 2, conversationId: targetConversationId)
            await updateTitleIfNeeded(conversationId: targetConversationId)
            if let audio = result.audioData {
                playAudioResponse(data: audio)
            }
        } catch is CancellationError {
            removeProgressMessages(conversationId: targetConversationId)
        } catch {
            guard isActiveStream(streamId) else { return }
            var updated = messages(for: targetConversationId).filter { !$0.isProgress }
            logger.error("Voice error: \(error.localizedDescription)")
            updated.append(ChatMessage(role: .error, content: error.localizedDescription))
            setMessages(updated, for: targetConversationId)
        }
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

}

extension Chat {
    // MARK: - Session management

    func syncConversationsPeriodically() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { break }
            await loadConversations()
        }
    }

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

    func startNewConversation() {
        stopPlayback()
        cancelActiveStream()
        conversationId = nil
        refreshLoadingState()
        sessionError = nil
    }

    func loadConversation(_ conv: Conversation) async {
        touchConversation(conv.id)
        conversationId = conv.id
        if cachedMessages[conv.id] != nil {
            refreshLoadingState()
            return
        }
        guard !loadingConversationIds.contains(conv.id) else {
            refreshLoadingState()
            return
        }
        loadingConversationIds.insert(conv.id)
        refreshLoadingState()
        do {
            let detail = try await fetchConversation(id: conv.id)
            cachedMessages[conv.id] = detail.messages.map { msg in
                ChatMessage(
                    role: ChatRole(rawValue: msg.role) ?? .assistant,
                    content: msg.content,
                    timestamp: ISO8601DateFormatter().date(from: msg.createdAt) ?? Date(),
                    isVoice: msg.isVoice
                )
            }
        } catch {
            logger.error("Failed to load conversation: \(error.localizedDescription)")
            cachedMessages[conv.id] = [
                ChatMessage(role: .error, content: "Failed to load history")
            ]
        }
        loadingConversationIds.remove(conv.id)
        pruneCachedConversations()
        refreshLoadingState()
    }

    func deleteConversation(_ conv: Conversation) async {
        if streamingConversationId == conv.id {
            cancelActiveStream()
        }
        do {
            try await deleteConversationRequest(id: conv.id)
            conversations.removeAll { $0.id == conv.id }
            cachedMessages.removeValue(forKey: conv.id)
            cachedConversationIds.removeAll { $0 == conv.id }
            loadingConversationIds.remove(conv.id)
            if conversationId == conv.id {
                // Select next available conversation instead of creating a new one
                if let next = conversations.first {
                    await loadConversation(next)
                } else {
                    conversationId = nil
                }
            }
            refreshLoadingState()
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

}

extension Chat {
    // MARK: - Conversation helpers

    @discardableResult
    private func ensureConversation() async -> Bool {
        guard conversationId == nil else { return true }
        do {
            let conv = try await createConversation()
            conversationId = conv.id
            touchConversation(conv.id)
            conversations.insert(conv, at: 0)
            sessionError = nil
            return true
        } catch {
            logger.error("Failed to ensure conversation: \(error.localizedDescription)")
            sessionError = error.localizedDescription
            return false
        }
    }

    func renameConversation(_ conv: Conversation, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await updateConversationTitle(id: conv.id, title: trimmed)
            if let index = conversations.firstIndex(where: { $0.id == conv.id }) {
                conversations[index].title = trimmed
            }
        } catch {
            logger.error("Failed to rename: \(error.localizedDescription)")
        }
    }

    private func updateTitleIfNeeded(conversationId convId: String) async {
        guard let idx = conversations.firstIndex(where: { $0.id == convId }),
              conversations[idx].title == nil || conversations[idx].title == "New conversation" else { return }

        // Ask the server to generate a title using AI
        do {
            let title = try await generateConversationTitle(id: convId)
            conversations[idx].title = title
        } catch {
            // Fallback: use first user message truncated
            guard let firstMessage = messages(for: convId).first(where: { $0.role == .user })?.content else {
                return
            }
            let title = String(firstMessage.prefix(50))
            do {
                try await updateConversationTitle(id: convId, title: title)
                conversations[idx].title = title
            } catch {
                logger.error("Failed to update title: \(error.localizedDescription)")
            }
        }
    }

    private func updateMessageCount(by count: Int, conversationId convId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == convId }) else { return }
        conversations[index].messageCount += count
        if index != 0 {
            let conv = conversations.remove(at: index)
            conversations.insert(conv, at: 0)
        }
    }

    private func appendMessage(_ message: ChatMessage, to conversationId: String) {
        cachedMessages[conversationId, default: []].append(message)
    }

    private func setMessages(_ messages: [ChatMessage], for conversationId: String) {
        cachedMessages[conversationId] = messages
    }

    private func beginStream(conversationId: String) -> UUID? {
        guard activeStreamTask == nil else { return nil }
        let streamId = UUID()
        activeStreamId = streamId
        streamingConversationId = conversationId
        refreshLoadingState()
        return streamId
    }

    private func finishStream(streamId: UUID, conversationId: String) {
        guard activeStreamId == streamId else { return }
        activeStreamId = nil
        activeStreamTask = nil
        if streamingConversationId == conversationId {
            streamingConversationId = nil
        }
        pruneCachedConversations()
        refreshLoadingState()
    }

    private func cancelActiveStream() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeStreamId = nil
        streamingConversationId = nil
        refreshLoadingState()
    }

    private func isActiveStream(_ streamId: UUID) -> Bool {
        activeStreamId == streamId && !Task.isCancelled
    }

    private func removeProgressMessages(conversationId: String) {
        setMessages(messages(for: conversationId).filter { !$0.isProgress }, for: conversationId)
    }

    /// Mutates one conversation's cached message array and writes it back once.
    ///
    /// This keeps dictionary reads/writes localized to one pass when updating
    /// an element in-place instead of repeatedly fetching/storing the array.
    /// Use `setMessages(_:for:)` when replacing the entire conversation payload.
    private func mutateMessages(
        for conversationId: String,
        _ mutate: (inout [ChatMessage]) -> Void
    ) {
        var conversationMessages = cachedMessages[conversationId, default: []]
        mutate(&conversationMessages)
        cachedMessages[conversationId] = conversationMessages
    }

    private func refreshLoadingState() {
        isLoading = streamingConversationId != nil
            || conversationId.map { loadingConversationIds.contains($0) } == true
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
