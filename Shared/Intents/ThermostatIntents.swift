//
//  ThermostatIntents.swift
//  FluxHaus
//
//  Shortcuts actions for the home thermostat. These intentionally have no
//  App Shortcut phrases; FluxHausShortcuts stays within Siri's phrase budget.
//

import AppIntents

enum ThermostatModeOption: String, AppEnum {
    case heat
    case cool
    case auto = "heat_cool"
    case off

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Thermostat mode"

    static let caseDisplayRepresentations: [ThermostatModeOption: DisplayRepresentation] = [
        .heat: "Heat",
        .cool: "Cool",
        .auto: "Auto",
        .off: "Off"
    ]
}

struct SetThermostatIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Thermostat"
    static let description = IntentDescription("""
        Change the home thermostat's mode and/or temperature, in the thermostat's unit. \
        In Auto mode, set the heat and cool temperatures in FluxHaus instead.
        """)

    @Parameter(title: "Temperature", controlStyle: .field, inclusiveRange: (5, 95))
    var temperature: Double?

    @Parameter(title: "Mode")
    var mode: ThermostatModeOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Set the thermostat") {
            \.$temperature
            \.$mode
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try Self.validate(mode: mode, temperature: temperature)
        // Both requests go to the account signed in when this started, or neither is sent.
        let isStillValid = Thermostat.currentSessionCheck()
        var state: IndoorClimateState?
        if let mode {
            state = try await FluxIntentActions.controlThermostat(.setMode(mode.rawValue), isStillValid: isStillValid)
        }
        if let temperature, mode != .off {
            state = try await FluxIntentActions.controlThermostat(
                .setTemperature(temperature), isStillValid: isStillValid
            ) ?? state
        }
        await donateIntent(self)
        return .result(dialog: "\(Self.dialog(mode: mode, temperature: temperature, state: state))")
    }

    /// Rejects requests the server would refuse, before anything is changed.
    static func validate(mode: ThermostatModeOption?, temperature: Double?) throws {
        guard temperature != nil || mode != nil else {
            throw IntentError.rejected("Choose a temperature or a mode.")
        }
        if mode == .auto, temperature != nil {
            throw IntentError.rejected(
                "Auto uses separate heat and cool temperatures. Set them in FluxHaus, or choose Auto on its own."
            )
        }
    }

    static func dialog(mode: ThermostatModeOption?, temperature: Double?, state: IndoorClimateState?) -> String {
        let unit = state?.thermostatUnit ?? ""
        let target = temperature.map { IndoorClimateFormat.temperature($0, unit: unit, precise: false) }
        switch (mode, target) {
        case (.off?, _):
            return "Turning the thermostat off."
        case let (mode?, target?):
            return "Setting the thermostat to \(ThermostatLabels.mode(mode.rawValue)) at \(target)."
        case let (mode?, nil):
            return "Setting the thermostat to \(ThermostatLabels.mode(mode.rawValue))."
        case let (nil, target?):
            return "Setting the thermostat to \(target)."
        case (nil, nil):
            return "No thermostat changes."
        }
    }
}

struct ResumeThermostatScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Thermostat Schedule"
    static let description = IntentDescription(
        "Cancel any temperature hold on the home thermostat and return to its schedule."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await FluxIntentActions.controlThermostat(
            .resumeSchedule, isStillValid: Thermostat.currentSessionCheck()
        )
        await donateIntent(self)
        return .result(dialog: "Resuming the thermostat schedule.")
    }
}
