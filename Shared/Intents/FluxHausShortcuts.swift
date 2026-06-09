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
            intent: LockCarIntent(),
            phrases: [
                "Lock my car with \(.applicationName)",
                "Lock the car in \(.applicationName)"
            ],
            shortTitle: "Lock Car",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockCarIntent(),
            phrases: [
                "Unlock my car with \(.applicationName)",
                "Unlock the car in \(.applicationName)"
            ],
            shortTitle: "Unlock Car",
            systemImageName: "lock.open.fill"
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
                "Start a robot with \(.applicationName)",
                "Start cleaning with \(.applicationName)"
            ],
            shortTitle: "Start Robot",
            systemImageName: "robotic.vacuum.cleaner"
        )
        AppShortcut(
            intent: StopRobotIntent(),
            phrases: [
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
                "Activate a scene with \(.applicationName)",
                "Run a \(.applicationName) scene"
            ],
            shortTitle: "Activate Scene",
            systemImageName: "theatermasks.fill"
        )
        AppShortcut(
            intent: CarStatusIntent(),
            phrases: [
                "What's my car status in \(.applicationName)",
                "Check my car with \(.applicationName)"
            ],
            shortTitle: "Car Status",
            systemImageName: "car.fill"
        )
    }
}
