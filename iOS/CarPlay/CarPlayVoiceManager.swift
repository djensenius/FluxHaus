//
//  CarPlayVoiceManager.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-04-18.
//

import CarPlay
import AVFoundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "CarPlayVoice")

@MainActor
class CarPlayVoiceManager: NSObject, AVAudioPlayerDelegate {
    private weak var interfaceController: CPInterfaceController?
    private var voiceTemplate: CPVoiceControlTemplate?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var conversationId: String?

    // Voice control states
    private let listeningState: CPVoiceControlState
    private let thinkingState: CPVoiceControlState
    private let speakingState: CPVoiceControlState
    private let idleState: CPVoiceControlState

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        listeningState = CPVoiceControlState(
            identifier: "listening",
            titleVariants: ["Listening…"],
            image: UIImage(systemName: "mic.fill"),
            repeats: false
        )
        thinkingState = CPVoiceControlState(
            identifier: "thinking",
            titleVariants: ["Thinking…"],
            image: UIImage(systemName: "brain"),
            repeats: false
        )
        speakingState = CPVoiceControlState(
            identifier: "speaking",
            titleVariants: ["Speaking…"],
            image: UIImage(systemName: "speaker.wave.2.fill"),
            repeats: false
        )
        idleState = CPVoiceControlState(
            identifier: "idle",
            titleVariants: ["Tap to speak"],
            image: UIImage(systemName: "mic.circle"),
            repeats: false
        )

        super.init()
    }

    // MARK: - Session lifecycle

    func startVoiceSession() {
        let states = [idleState, listeningState, thinkingState, speakingState]
        voiceTemplate = CPVoiceControlTemplate(voiceControlStates: states)

        guard let voiceTemplate, let interfaceController else { return }
        interfaceController.pushTemplate(voiceTemplate, animated: true, completion: nil)
        voiceTemplate.activateVoiceControlState(withIdentifier: "idle")

        startRecording()
    }

    func cleanup() {
        stopPlayback()
        stopRecording()
        deactivateAudioSession()
        conversationId = nil
    }

    // MARK: - Recording

    private func startRecording() {
        configureRecordingSession()

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("carplay_voice.m4a")
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
            voiceTemplate?.activateVoiceControlState(withIdentifier: "listening")
            logger.info("CarPlay: recording started")

            // Auto-stop after 30 seconds to prevent indefinite recording
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                if self?.audioRecorder?.isRecording == true {
                    self?.stopRecordingAndSend()
                }
            }
        } catch {
            logger.error("CarPlay: failed to start recording: \(error.localizedDescription)")
            deactivateAudioSession()
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        cleanupRecording()
    }

    private func stopRecordingAndSend() {
        audioRecorder?.stop()

        guard let url = recordingURL,
              let audioData = try? Data(contentsOf: url) else {
            logger.error("CarPlay: failed to read recording")
            voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
            deactivateAudioSession()
            return
        }

        voiceTemplate?.activateVoiceControlState(withIdentifier: "thinking")

        Task { [weak self] in
            await self?.sendVoice(audioData: audioData)
        }

        cleanupRecording()
    }

    // MARK: - Voice API

    private func sendVoice(audioData: Data) async {
        do {
            var responseText = "Done."
            var responseAudio: Data?

            for try await event in streamVoice(
                audioData: audioData,
                conversationId: conversationId
            ) {
                switch event.type {
                case "done":
                    if let text = event.text { responseText = text }
                    if let b64 = event.audio, let data = Data(base64Encoded: b64) {
                        responseAudio = data
                    }
                case "error":
                    logger.error("CarPlay voice error: \(event.text ?? "unknown")")
                    voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
                    deactivateAudioSession()
                    return
                default:
                    break
                }
            }

            if let audio = responseAudio {
                playResponse(data: audio)
            } else {
                logger.info("CarPlay response (no audio): \(responseText)")
                voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
                deactivateAudioSession()
            }
        } catch {
            logger.error("CarPlay voice stream failed: \(error.localizedDescription)")
            voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
            deactivateAudioSession()
        }
    }

    // MARK: - Audio playback

    private func playResponse(data: Data) {
        configurePlaybackSession()
        voiceTemplate?.activateVoiceControlState(withIdentifier: "speaking")
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            logger.error("CarPlay: failed to play response: \(error.localizedDescription)")
            voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
            deactivateAudioSession()
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
            self.deactivateAudioSession()
            // Start listening again for multi-turn conversation
            self.startRecording()
        }
    }

    // MARK: - Audio session management

    private func configureRecordingSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.duckOthers, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            logger.error("CarPlay: failed to configure recording session: \(error.localizedDescription)")
        }
    }

    private func configurePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.duckOthers, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            logger.error("CarPlay: failed to configure playback session: \(error.localizedDescription)")
        }
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("CarPlay: failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func cleanupRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}
