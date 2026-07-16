//
//  OfflineAssistant.swift
//  FluxHaus
//
//  On-device fallback for the Ask FluxHaus intent. When the FluxHaus server is
//  unreachable, answer with Apple's on-device Foundation Model so Siri still
//  responds with something useful instead of a hard error.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OfflineAssistant {
    /// Whether the on-device model is ready to answer right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    /// Answers a prompt using the on-device model.
    ///
    /// Returns `nil` when the model is unavailable (device not eligible, Apple
    /// Intelligence disabled, model not ready) or generation fails, so callers
    /// can fall back to their own error handling.
    static func answer(to prompt: String) async -> String? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private static let instructions = """
    You are FluxHaus, a smart-home assistant. The connection to the FluxHaus \
    server is currently unavailable, so you cannot read live device state or \
    control any devices right now. Answer the user's question helpfully from \
    general knowledge. If they ask about the current status of a device or want \
    to control something, briefly let them know you're offline and can't reach \
    their home at the moment.
    """
}
