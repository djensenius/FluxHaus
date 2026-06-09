//
//  AskFluxHausIntent.swift
//  FluxHaus
//
//  Free-text AI intent that routes a prompt to the FluxHaus assistant and speaks the answer.
//

import AppIntents

struct AskFluxHausIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask FluxHaus"
    static let description = IntentDescription("Ask the FluxHaus assistant about your home.")

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask FluxHaus?")
    var prompt: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask FluxHaus \(\.$prompt)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AuthManager.shared.isSignedIn else {
            throw IntentError.notSignedIn
        }

        var answer = ""
        var lastError: String?
        for try await event in streamCommand(prompt) {
            if event.type == "error" {
                lastError = event.text
                continue
            }
            if let text = event.text {
                answer += text
            }
        }

        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let message = lastError ?? "I didn't get a response. Please try again."
            return .result(dialog: "\(message)")
        }
        return .result(dialog: "\(trimmed)")
    }
}
