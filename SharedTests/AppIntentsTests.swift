//
//  AppIntentsTests.swift
//  FluxHaus Tests
//
//  Unit tests for the pure logic in the FluxHaus App Intents layer.
//

import Testing
import Foundation
@testable import FluxHaus

struct AppIntentsTests {

    @Test("RobotChoice maps to the matching RobotKind")
    func robotChoiceMapsToKind() {
        #expect(RobotChoice.broomBot.kind == .broomBot)
        #expect(RobotChoice.mopBot.kind == .mopBot)
    }

    @Test("RobotKind exposes the expected display names")
    func robotKindDisplayNames() {
        #expect(RobotKind.broomBot.displayName == "BroomBot")
        #expect(RobotKind.mopBot.displayName == "MopBot")
    }

    @Test("SceneAppEntity is built from a HomeScene")
    func sceneEntityFromHomeScene() {
        let scene = HomeScene(entityId: "scene.movie_night", name: "Movie Night", isActive: false)
        let entity = SceneAppEntity(scene: scene)
        #expect(entity.id == "scene.movie_night")
        #expect(entity.name == "Movie Night")
    }

    @Test("IntentError provides user-facing descriptions")
    func intentErrorDescriptions() {
        #expect(IntentError.notSignedIn.errorDescription == "Please sign in to FluxHaus first.")
        #expect(IntentError.requestFailed(503).errorDescription == "The request failed (HTTP 503).")
        #expect(IntentError.invalidURL.errorDescription == "Could not build the request.")
    }
}
