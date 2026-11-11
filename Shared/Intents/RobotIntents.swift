//
//  RobotIntents.swift
//  FluxHaus
//
//  App Intents for controlling the Cleanbot robot. Siri AI tool conformances are in
//  SiriTools.swift.
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

    static var allCases: [RobotChoice] { [.cleanBot] }

    var kind: RobotKind { .cleanBot }
}

extension StartRobotIntent {
    init(robot: RobotChoice) {
        self.init()
        self.robot = robot
    }
}

extension StopRobotIntent {
    init(robot: RobotChoice) {
        self.init()
        self.robot = robot
    }
}

struct StartRobotIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Robot"
    static let description = IntentDescription("Start a whole-home cleaning run with the FluxHaus cleaning robot.")

    @Parameter(title: "Robot", description: "The cleaning robot to control. FluxHaus has one robot, Cleanbot.")
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
    static let description = IntentDescription("Stop the FluxHaus cleaning robot and send it back to its dock.")

    @Parameter(title: "Robot", description: "The cleaning robot to control. FluxHaus has one robot, Cleanbot.")
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

struct CleanRoomsIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Rooms"
    static let description = IntentDescription("Tell Cleanbot to clean one or more rooms in a single run.")

    @Parameter(
        title: "Rooms",
        description: "Rooms to clean in one run: Hallway, Kitchen, Bathroom, Living Room, Master Bedroom, or Office."
    )
    var rooms: [CleanbotRoom]

    static var parameterSummary: some ParameterSummary {
        Summary("Clean \(\.$rooms)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let selectedRooms = FluxIntentActions.uniqueRooms(rooms)
        guard !selectedRooms.isEmpty else {
            throw $rooms.needsValueError("Which rooms should Cleanbot clean?")
        }
        try await FluxIntentActions.cleanRooms(selectedRooms)
        let roomList = ListFormatter.localizedString(byJoining: selectedRooms.map(\.displayName))
        return .result(dialog: "Cleanbot is cleaning \(roomList).")
    }
}
