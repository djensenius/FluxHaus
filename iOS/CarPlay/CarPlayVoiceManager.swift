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
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var conversationId: String?
    private var silenceTimer: Task<Void, Never>?
    private var silenceStart: Date?
    private var meteringTimer: Timer?
    private var isActive = false

    /// Callback to update the assistant tab UI with current state
    var onStateChange: ((VoiceState) -> Void)?

    enum VoiceState {
        case idle
        case listening
        case thinking
        case speaking
    }

    /// Seconds of silence before auto-stopping
    private let silenceThreshold: TimeInterval = 1.5
    /// dB level below which we consider silence
    private let silenceLevel: Float = -40
    /// Minimum recording duration before silence detection activates
    private let minRecordingDuration: TimeInterval = 1.0
    private var recordingStartTime: Date?

    // MARK: - Public API

    func toggleRecording() {
        if isActive {
            // Stop everything
            cancelSession()
        } else {
            startRecording()
        }
    }

    func cleanup() {
        cancelSession()
        conversationId = nil
    }

    private func cancelSession() {
        stopSilenceDetection()
        silenceTimer?.cancel()
        silenceTimer = nil
        stopPlayback()
        audioRecorder?.stop()
        audioRecorder = nil
        cleanupRecording()
        deactivateAudioSession()
        isActive = false
        onStateChange?(.idle)
    }

    // MARK: - Recording

    private func startRecording() {
        do {
            try configureRecordingSession()
        } catch {
            logger.error("CarPlay: audio session setup failed: \(error.localizedDescription)")
            onStateChange?(.idle)
            return
        }

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
            audioRecorder?.isMeteringEnabled = true
            guard audioRecorder?.record() == true else {
                logger.error("CarPlay: AVAudioRecorder.record() returned false")
                onStateChange?(.idle)
                deactivateAudioSession()
                return
            }
            isActive = true
            onStateChange?(.listening)
            silenceStart = nil
            recordingStartTime = Date()
            logger.info("CarPlay: recording started")

            startSilenceDetection()

            // Hard cap: auto-stop after 30 seconds
            silenceTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                if self?.audioRecorder?.isRecording == true {
                    self?.stopSilenceDetection()
                    self?.stopRecordingAndSend()
                }
            }
        } catch {
            logger.error("CarPlay: failed to start recording: \(error.localizedDescription)")
            isActive = false
            onStateChange?(.idle)
            deactivateAudioSession()
        }
    }

    private func stopRecording() {
        stopSilenceDetection()
        silenceTimer?.cancel()
        silenceTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        cleanupRecording()
    }

    private func stopRecordingAndSend() {
        stopSilenceDetection()
        silenceTimer?.cancel()
        silenceTimer = nil
        audioRecorder?.stop()

        guard let url = recordingURL,
              let audioData = try? Data(contentsOf: url) else {
            logger.error("CarPlay: failed to read recording")
            cancelSession()
            return
        }

        onStateChange?(.thinking)

        Task { [weak self] in
            await self?.sendVoice(audioData: audioData)
        }

        cleanupRecording()
    }

    // MARK: - Voice API

    private func sendVoice(audioData: Data) async {
        logger.info("CarPlay: sending \(audioData.count) bytes to voice API")
        do {
            var responseText = "Done."
            var responseAudio: Data?

            for try await event in streamVoice(
                audioData: audioData,
                conversationId: conversationId
            ) {
                switch event.type {
                case "done":
                    if let text = event.text {
                        responseText = text
                        logger.info("CarPlay: got response text: \(text.prefix(80))")
                    }
                    if let b64 = event.audio, let data = Data(base64Encoded: b64) {
                        responseAudio = data
                        logger.info("CarPlay: got response audio: \(data.count) bytes")
                    }
                case "error":
                    logger.error("CarPlay voice error: \(event.text ?? "unknown")")
                    cancelSession()
                    return
                default:
                    break
                }
            }

            if let audio = responseAudio {
                playResponse(data: audio)
            } else {
                logger.info("CarPlay response (no audio): \(responseText)")
                cancelSession()
            }
        } catch {
            logger.error("CarPlay voice stream failed: \(error.localizedDescription)")
            cancelSession()
        }
    }

    // MARK: - Audio playback

    private func playResponse(data: Data) {
        configurePlaybackSession()
        onStateChange?(.speaking)
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            logger.error("CarPlay: failed to play response: \(error.localizedDescription)")
            cancelSession()
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
            self.isActive = false
            self.deactivateAudioSession()
            self.onStateChange?(.idle)
        }
    }

    // MARK: - Silence detection

    private func startSilenceDetection() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAudioLevel()
            }
        }
    }

    private func stopSilenceDetection() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        silenceStart = nil
    }

    private func checkAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        // Don't check for silence until minimum recording duration has passed
        if let start = recordingStartTime,
           Date().timeIntervalSince(start) < minRecordingDuration {
            return
        }

        recorder.updateMeters()
        let avgPower = recorder.averagePower(forChannel: 0)

        if avgPower < silenceLevel {
            if silenceStart == nil {
                silenceStart = Date()
            } else if let start = silenceStart,
                      Date().timeIntervalSince(start) >= silenceThreshold {
                logger.info("CarPlay: silence detected, sending recording")
                stopRecordingAndSend()
            }
        } else {
            silenceStart = nil
        }
    }

    // MARK: - Audio session management

    private func configureRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.duckOthers, .allowBluetoothA2DP]
        )
        try session.setActive(true)
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
