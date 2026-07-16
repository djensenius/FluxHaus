//
//  AppIntentsTests.swift
//  Tests iOS
//
//  Phase 1 of the iOS 27 Siri AI work: validate that every FluxHaus App Intent
//  is well-formed and behaves deterministically when the user is signed out.
//
//  These tests exercise the real `perform()` pathway. Because every network-backed
//  intent checks `AuthManager.shared.isSignedIn` before doing any I/O, a fresh
//  (signed-out) test process lets us assert the guard fires with `IntentError.notSignedIn`
//  without hitting api.fluxhaus.io — keeping the suite hermetic and CI-safe.
//

import Testing
import AppIntents
@testable import FluxHaus

struct AppIntentsTests {

    // MARK: - Metadata

    @Test("At least one App Shortcut is registered")
    func shortcutsAreRegistered() {
        #expect(!FluxHausShortcuts.appShortcuts.isEmpty)
    }

    @Test("Shortcut count stays within the system limit of 10")
    func shortcutCountWithinLimit() {
        #expect(FluxHausShortcuts.appShortcuts.count <= 10)
    }

    @Test("Robot enum exposes a display name for every case")
    func robotChoiceDisplayNames() {
        #expect(RobotChoice.broomBot.kind.displayName == "BroomBot")
        #expect(RobotChoice.mopBot.kind.displayName == "MopBot")
    }

    // MARK: - Signed-out behaviour

    @MainActor
    @Test("Robot control intents require sign-in")
    func robotIntentsRequireSignIn() async throws {
        let start = StartRobotIntent()
        start.robot = .broomBot
        await #expect(throws: IntentError.self) { _ = try await start.perform() }

        let stop = StopRobotIntent()
        stop.robot = .mopBot
        await #expect(throws: IntentError.self) { _ = try await stop.perform() }

        await #expect(throws: IntentError.self) { _ = try await DeepCleanIntent().perform() }
    }

    @MainActor
    @Test("Car control intents require sign-in")
    func carIntentsRequireSignIn() async throws {
        await #expect(throws: IntentError.self) { _ = try await LockCarIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await UnlockCarIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await StartCarClimateIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await StopCarClimateIntent().perform() }
    }

    @Test("Status intents require sign-in")
    func statusIntentsRequireSignIn() async throws {
        await #expect(throws: IntentError.self) { _ = try await CarStatusIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await RobotStatusIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await ApplianceStatusIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await ScooterStatusIntent().perform() }
    }

    @Test("Ask FluxHaus intent requires sign-in")
    func askIntentRequiresSignIn() async throws {
        let intent = AskFluxHausIntent()
        intent.prompt = "Is the dishwasher running?"
        await #expect(throws: IntentError.self) { _ = try await intent.perform() }
    }

    @Test("Activate Scene intent requires sign-in")
    func activateSceneRequiresSignIn() async throws {
        let intent = ActivateSceneIntent()
        intent.scene = SceneAppEntity(id: "scene.test", name: "Good Morning")
        await #expect(throws: IntentError.self) { _ = try await intent.perform() }
    }

    // MARK: - Device entity (Phase 2)

    @Test("Device query resolves every device by identifier")
    func deviceQueryResolvesById() async throws {
        let query = DeviceEntityQuery()
        for kind in DeviceKind.allCases {
            let results = try await query.entities(for: [kind.rawValue])
            #expect(results.count == 1)
            #expect(results.first?.kind == kind)
        }
    }

    @Test("Device query matches by spoken name")
    func deviceQueryMatchesByName() async throws {
        let query = DeviceEntityQuery()
        let matches = try await query.entities(matching: "dish")
        #expect(matches.map(\.kind) == [.dishwasher])
    }

    @Test("Suggested devices cover the full fixed set")
    func deviceQuerySuggestsAll() async throws {
        let suggested = try await DeviceEntityQuery().suggestedEntities()
        #expect(Set(suggested.map(\.kind)) == Set(DeviceKind.allCases))
    }

    @Test("Unknown device identifier resolves to nothing")
    func deviceQueryIgnoresUnknownId() async throws {
        let results = try await DeviceEntityQuery().entities(for: ["not-a-device"])
        #expect(results.isEmpty)
    }

    @Test("Device status intent requires sign-in")
    func deviceStatusRequiresSignIn() async throws {
        let intent = DeviceStatusIntent()
        intent.device = DeviceAppEntity(kind: .car)
        await #expect(throws: IntentError.self) { _ = try await intent.perform() }
    }
}
