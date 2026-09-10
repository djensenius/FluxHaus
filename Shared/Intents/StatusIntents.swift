//
//  StatusIntents.swift
//  FluxHaus
//
//  App Intents that report the current status of FluxHaus devices.
//

import AppIntents

func fetchStatus() async throws -> LoginResponse {
    guard AuthManager.shared.isSignedIn else {
        throw IntentError.notSignedIn
    }
    guard await AuthManager.shared.ensureValidToken(),
          AuthManager.shared.authorizationHeader() != nil else {
        throw IntentError.notSignedIn
    }
    guard let response = try await getFlux(password: "") else {
        throw IntentError.requestFailed(-1)
    }
    return response
}

struct CarStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Car Status"
    static let description = IntentDescription("Get the FluxHaus car's battery, range, and lock status.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        return .result(dialog: "\(FluxStatusText.car(response))")
    }
}

struct RobotStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Robot Status"
    static let description = IntentDescription("Get the status of the FluxHaus cleaning robots.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        return .result(dialog: "\(FluxStatusText.robots(response))")
    }
}

struct ApplianceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Dishwasher Status"
    static let description = IntentDescription("Get the status of the FluxHaus dishwasher.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        return .result(dialog: "\(FluxStatusText.dishwasher(response))")
    }
}

struct ScooterStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Scooter Status"
    static let description = IntentDescription("Get the FluxHaus scooter's battery and range.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        return .result(dialog: "\(FluxStatusText.scooter(response))")
    }
}
