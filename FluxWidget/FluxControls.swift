//
//  FluxControls.swift
//  FluxWidget
//
//  Control Center / Lock Screen / Action button controls.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import AppIntents
import SwiftUI
import WidgetKit

enum FluxControlKind {
    static let cleanbot = "io.fluxhaus.control.cleanbot"
    static let carClimate = "io.fluxhaus.control.carClimate"
    static let carLock = "io.fluxhaus.control.carLock"
    static let scene = "io.fluxhaus.control.scene"
}

// MARK: - Cleanbot

struct CleanbotRunIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Run Cleanbot"
    static let isDiscoverable = false

    @Parameter(title: "Running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let value = value
        let session = try await WidgetCache.runCommand {
            if value {
                try await FluxIntentActions.startRobot(.cleanBot)
            } else {
                try await FluxIntentActions.stopRobot(.cleanBot)
            }
        }
        if let session {
            PendingValue.set(value, key: CleanbotValueProvider.pendingKey, session: session)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "FluxWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "FluxWidgetSmall")
        return .result()
    }
}

struct CleanbotValueProvider: ControlValueProvider {
    static let pendingKey = "FluxWidget.cleanbotPending"

    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        // The robot's reported state lags the command; show the requested state briefly.
        if let pending = PendingValue<Bool>.current(key: Self.pendingKey) { return pending }
        return await FluxWidgetNetwork.fetchSnapshot()?.devices.first { $0.name == "Cleanbot" }?.running ?? false
    }
}

struct CleanbotControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: FluxControlKind.cleanbot, provider: CleanbotValueProvider()) { running in
            ControlWidgetToggle("Cleanbot", isOn: running, action: CleanbotRunIntent()) { isOn in
                Label(isOn ? "Cleaning" : "Docked", systemImage: "robotic.vacuum.fill")
            }
            .tint(.green)
        }
        .displayName("Cleanbot")
        .description("Start or stop the Cleanbot.")
    }
}

// MARK: - Car

struct CarClimateToggleIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Car Climate"
    static let isDiscoverable = false

    @Parameter(title: "On")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let value = value
        let session = try await WidgetCache.runCommand {
            if value {
                try await FluxIntentActions.startCarClimate(defrost: false, heatedFeatures: false, temperature: nil)
            } else {
                try await FluxIntentActions.stopCarClimate()
            }
        }
        CarOverride.set(climateOn: value, session: session)
        return .result()
    }
}

struct CarClimateValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        if let pending = CarOverride.current()?.climateOn { return pending }
        return await FluxWidgetNetwork.fetchSnapshot()?.car?.climateOn ?? false
    }
}

struct CarClimateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: FluxControlKind.carClimate,
            provider: CarClimateValueProvider()
        ) { isOn in
            ControlWidgetToggle("Car Climate", isOn: isOn, action: CarClimateToggleIntent()) { isOn in
                Label(isOn ? "On" : "Off", systemImage: isOn ? "fan.fill" : "fan")
            }
            .tint(.blue)
        }
        .displayName("Car Climate")
        .description("Start or stop the car's climate control.")
    }
}

struct CarLockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: FluxControlKind.carLock) {
            ControlWidgetButton(action: CarWidgetLockIntent()) {
                Label("Lock Car", systemImage: "lock.fill")
            }
        }
        .displayName("Lock Car")
        .description("Lock the car.")
    }
}

// MARK: - Scene

struct SceneControlConfig: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Scene"
    static let isDiscoverable = false

    @Parameter(title: "Scene")
    var scene: WidgetSceneEntity?

    init() {}
}

struct SceneControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: FluxControlKind.scene, intent: SceneControlConfig.self) { config in
            // Controls aren't tied to a session; the intent checks the scene (ID and name)
            // exists for the signed-in account before running it.
            ControlWidgetButton(action: RunSceneWidgetIntent(
                sceneId: config.scene?.id ?? "",
                sceneName: config.scene?.name ?? "",
                originSession: nil
            )) {
                Label(
                    config.scene?.name ?? "Choose Scene",
                    systemImage: sceneSymbol(for: config.scene?.name ?? "")
                )
            }
        }
        .displayName("Scene")
        .description("Run a HomeKit scene.")
        .promptsForUserConfiguration()
    }
}
#endif
