//
//  CarIntents.swift
//  FluxHaus
//
//  App Intents for controlling the FluxHaus car. Siri AI tool conformances are in
//  SiriTools.swift.
//

import AppIntents

extension CarAnalyticsRange: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Car history period"

    static let caseDisplayRepresentations: [CarAnalyticsRange: DisplayRepresentation] = [
        .week: "Last 7 days",
        .month: "Last 30 days",
        .quarter: "Last 90 days",
        .year: "Last year",
        .all: "All retained history"
    ]
}

extension CarAnalyticsTopic: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Car insight"

    static let caseDisplayRepresentations: [CarAnalyticsTopic: DisplayRepresentation] = [
        .overview: "Overview",
        .charging: "Charging",
        .efficiency: "Efficiency",
        .weather: "Weather impact",
        .comparison: "Previous-period comparison"
    ]
}

enum CarLockAction: String, AppEnum {
    case lock
    case unlock

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Car lock action"

    static let caseDisplayRepresentations: [CarLockAction: DisplayRepresentation] = [
        .lock: "Lock",
        .unlock: "Unlock"
    ]
}

struct SetCarLockIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Car Lock"
    static let description = IntentDescription("Lock or unlock the FluxHaus car.")
    // Unlocking is possible here, so require Face ID / passcode on this device.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(
        title: "Action",
        description: "Whether to lock or unlock the car's doors.",
        requestValueDialog: "Do you want to lock or unlock the car?"
    )
    var action: CarLockAction

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) the car")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch action {
        case .lock:
            try await FluxIntentActions.lockCar()
            return .result(dialog: "Locking the car.")
        case .unlock:
            try await FluxIntentActions.unlockCar()
            return .result(dialog: "Unlocking the car.")
        }
    }
}

struct AnalyzeCarUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Car Insights"
    static let description = IntentDescription(
        "Analyze charging, distance, efficiency, and weather impact for the FluxHaus car."
    )

    @Parameter(
        title: "Period",
        description: "How far back to analyze driving and charging history. Defaults to the last 30 days.",
        default: .month
    )
    var range: CarAnalyticsRange

    @Parameter(
        title: "Insight",
        description: "Which insight to report: overview, charging, efficiency, weather impact, or period comparison.",
        default: .overview
    )
    var topic: CarAnalyticsTopic

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$topic) for \(\.$range)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireIntentAuthentication()
        let analytics = try await CarAnalyticsClient().fetch(range: range, topic: topic)
        await donateIntent(self)
        return .result(dialog: "\(analytics.dialog(for: topic, range: range))")
    }
}

struct LockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Car"
    static let description = IntentDescription("Lock the FluxHaus car's doors.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.lockCar()
        return .result(dialog: "Locking the car.")
    }
}

struct UnlockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Unlock Car"
    static let description = IntentDescription("Unlock the FluxHaus car's doors.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.unlockCar()
        return .result(dialog: "Unlocking the car.")
    }
}

struct StartCarClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Car Climate"
    static let description = IntentDescription(
        "Start climate control in the FluxHaus car to warm it up or cool it down before driving."
    )

    @Parameter(
        title: "Defrost",
        description: "Turn on the window defroster. Useful when it's near or below freezing.",
        default: false
    )
    var defrost: Bool

    @Parameter(
        title: "Heated Features",
        description: "Turn on the heated steering wheel.",
        default: false
    )
    var heatedFeatures: Bool

    @Parameter(
        title: "Temperature",
        description: "Target cabin temperature in whole degrees Celsius (16-28). Omit to keep the car's last setting."
    )
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
