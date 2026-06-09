//
//  RobotIntents.swift
//  FluxHaus
//
//  App Intents for controlling the BroomBot and MopBot robots.
//

import AppIntents

enum RobotChoice: String, AppEnum {
    case broomBot
    case mopBot

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Robot"

    static let caseDisplayRepresentations: [RobotChoice: DisplayRepresentation] = [
        .broomBot: "BroomBot",
        .mopBot: "MopBot"
    ]

    var kind: RobotKind {
        switch self {
        case .broomBot: return .broomBot
        case .mopBot: return .mopBot
        }
    }
}

struct StartRobotIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Robot"
    static let description = IntentDescription("Start a FluxHaus cleaning robot.")

    @Parameter(title: "Robot")
    var robot: RobotChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$robot)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.startRobot(robot.kind)
        return .result(dialog: "Starting \(robot.kind.displayName).")
    }
}

struct StopRobotIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Robot"
    static let description = IntentDescription("Stop a FluxHaus cleaning robot.")

    @Parameter(title: "Robot")
    var robot: RobotChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Stop \(\.$robot)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.stopRobot(robot.kind)
        return .result(dialog: "Stopping \(robot.kind.displayName).")
    }
}

struct DeepCleanIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Deep Clean"
    static let description = IntentDescription("Start a deep clean with the FluxHaus robots.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.deepClean()
        return .result(dialog: "Starting a deep clean.")
    }
}
