//
//  FluxHausShortcuts.swift
//  FluxHaus
//
//  Exposes FluxHaus App Intents to Siri, Spotlight, and the Shortcuts app with
//  spoken trigger phrases. Every phrase includes \(.applicationName) as required.
//

import AppIntents

struct FluxHausShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskFluxHausIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) about my home"
            ],
            shortTitle: "Ask FluxHaus",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SetCarLockIntent(),
            phrases: [
                "\(\.$action) my car with \(.applicationName)",
                "\(\.$action) the car in \(.applicationName)"
            ],
            shortTitle: "Car Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: StartCarClimateIntent(),
            phrases: [
                "Start my car's climate with \(.applicationName)",
                "Warm up my car with \(.applicationName)"
            ],
            shortTitle: "Start Car Climate",
            systemImageName: "thermometer.medium"
        )
        AppShortcut(
            intent: StopCarClimateIntent(),
            phrases: [
                "Stop my car's climate with \(.applicationName)",
                "Turn off my car's climate in \(.applicationName)"
            ],
            shortTitle: "Stop Car Climate",
            systemImageName: "thermometer.snowflake"
        )
        AppShortcut(
            intent: StartRobotIntent(),
            phrases: [
                "Start \(\.$robot) with \(.applicationName)",
                "Start a robot with \(.applicationName)",
                "Start cleaning with \(.applicationName)"
            ],
            shortTitle: "Start Robot",
            systemImageName: "robotic.vacuum.cleaner"
        )
        AppShortcut(
            intent: StopRobotIntent(),
            phrases: [
                "Stop \(\.$robot) with \(.applicationName)",
                "Stop a robot with \(.applicationName)",
                "Stop cleaning with \(.applicationName)"
            ],
            shortTitle: "Stop Robot",
            systemImageName: "robotic.vacuum.cleaner.fill"
        )
        AppShortcut(
            intent: DeepCleanIntent(),
            phrases: [
                "Start a deep clean with \(.applicationName)",
                "Deep clean with \(.applicationName)"
            ],
            shortTitle: "Deep Clean",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ActivateSceneIntent(),
            phrases: [
                "Activate \(\.$scene) with \(.applicationName)",
                "Activate a scene with \(.applicationName)",
                "Run a \(.applicationName) scene"
            ],
            shortTitle: "Activate Scene",
            systemImageName: "theatermasks.fill"
        )
        AppShortcut(
            intent: DeviceStatusIntent(),
            phrases: [
                "Get \(\.$device) status with \(.applicationName)",
                "Check \(\.$device) in \(.applicationName)",
                "How much time is left on \(\.$device) in \(.applicationName)",
                "When will \(\.$device) be done in \(.applicationName)"
            ],
            shortTitle: "Device Status",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
        AppShortcut(
            intent: AnalyzeCarUsageIntent(),
            phrases: [
                "Analyze my car with \(.applicationName)",
                "How has weather affected my car in \(.applicationName)"
            ],
            shortTitle: "Car Insights",
            systemImageName: "chart.xyaxis.line"
        )
    }
}
