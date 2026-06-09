//
//  CarIntents.swift
//  FluxHaus
//
//  App Intents for controlling the FluxHaus car.
//

import AppIntents

struct LockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Car"
    static let description = IntentDescription("Lock the FluxHaus car.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.lockCar()
        return .result(dialog: "Locking the car.")
    }
}

struct UnlockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Unlock Car"
    static let description = IntentDescription("Unlock the FluxHaus car.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.unlockCar()
        return .result(dialog: "Unlocking the car.")
    }
}

struct StartCarClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Car Climate"
    static let description = IntentDescription("Start climate control in the FluxHaus car.")

    @Parameter(title: "Defrost", default: false)
    var defrost: Bool

    @Parameter(title: "Heated Features", default: false)
    var heatedFeatures: Bool

    @Parameter(title: "Temperature")
    var temperature: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Start car climate") {
            \.$temperature
            \.$defrost
            \.$heatedFeatures
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.startCarClimate(
            defrost: defrost,
            heatedFeatures: heatedFeatures,
            temperature: temperature
        )
        return .result(dialog: "Starting the car's climate control.")
    }
}

struct StopCarClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Car Climate"
    static let description = IntentDescription("Stop climate control in the FluxHaus car.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.stopCarClimate()
        return .result(dialog: "Stopping the car's climate control.")
    }
}

struct ResyncCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Resync Car"
    static let description = IntentDescription("Refresh the FluxHaus car's status from the vehicle.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.resyncCar()
        return .result(dialog: "Resyncing the car.")
    }
}
