//
//  RobotIntents.swift
//  FluxHaus
//
//  App Intents for controlling the Cleanbot robot.
//

import AppIntents

enum RobotChoice: String, AppEnum {
    case cleanBot
    case broomBot
    case mopBot

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Robot"

    static let caseDisplayRepresentations: [RobotChoice: DisplayRepresentation] = [
        .cleanBot: "Cleanbot",
        .broomBot: "Cleanbot",
        .mopBot: "Cleanbot"
    ]

    var kind: RobotKind { .cleanBot }
}

struct StartRobotIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Robot"
    static let description = IntentDescription("Start the FluxHaus cleaning robot.")

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
    static let description = IntentDescription("Stop the FluxHaus cleaning robot.")

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
    static let description = IntentDescription("Start a deep clean with Cleanbot.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.deepClean()
        return .result(dialog: "Starting a deep clean.")
    }
}

struct CleanRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Room"
    static let description = IntentDescription("Tell Cleanbot to clean a specific room.")

    @Parameter(title: "Room")
    var room: CleanbotRoom

    static var parameterSummary: some ParameterSummary {
        Summary("Clean \(\.$room)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.cleanRoom(room)
        return .result(dialog: "Cleanbot is cleaning \(room.displayName).")
    }
}
