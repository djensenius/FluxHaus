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
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp: Date
}

@MainActor
@Observable class Chat {
    var messages: [ChatMessage] = []
    var isLoading = false
    var isRecording = false

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?

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
            messages.append(ChatMessage(role: .error, content: "Failed to read recording", timestamp: Date()))
            return
        }

        messages.append(ChatMessage(role: .user, content: "🎤 Voice message", timestamp: Date()))
        isLoading = true

        do {
            let response = try await sendVoice(audioData: audioData)

            // Update user message with transcript if available
            if !response.transcript.isEmpty {
                if let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) {
                    messages[lastUserIndex] = ChatMessage(
                        role: .user,
                        content: "🎤 \(response.transcript)",
                        timestamp: messages[lastUserIndex].timestamp
                    )
                }
            }

            messages.append(ChatMessage(
                role: .assistant,
                content: response.responseText,
                timestamp: Date()
            ))

            playAudioResponse(data: response.audioData)
        } catch {
            logger.error("Voice error: \(error.localizedDescription)")
            messages.append(ChatMessage(
                role: .error,
                content: error.localizedDescription,
                timestamp: Date()
            ))
        }

        isLoading = false
        cleanupRecording()
    }

    private func playAudioResponse(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
        }
    }

    private func cleanupRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}
