//
//  SceneServiceTests.swift
//  FluxHaus Tests
//
//  Created by Copilot on 2026-03-02.
//

import Testing
import Foundation
@testable import FluxHaus

struct SceneServiceTests {

    @Test("HomeScene model can be created")
    func testHomeSceneModel() {
        let scene = HomeScene(entityId: "scene.good_morning", name: "Good Morning", isActive: true)
        #expect(scene.entityId == "scene.good_morning")
        #expect(scene.name == "Good Morning")
        #expect(scene.isActive == true)
        #expect(scene.id == "scene.good_morning")
    }

    @Test("HomeScene conforms to Identifiable using entityId")
    func testHomeSceneIdentifiable() {
        let scene1 = HomeScene(entityId: "scene.a", name: "A", isActive: nil)
        let scene2 = HomeScene(entityId: "scene.b", name: "B", isActive: nil)
        #expect(scene1.id != scene2.id)
    }

    @Test("HomeScene encodes to JSON correctly")
    func testHomeSceneEncoding() throws {
        let scene = HomeScene(entityId: "scene.bedtime", name: "Bedtime", isActive: false)
        let data = try JSONEncoder().encode(scene)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["entityId"] as? String == "scene.bedtime")
        #expect(json?["name"] as? String == "Bedtime")
        #expect(json?["isActive"] as? Bool == false)
    }

    @Test("HomeScene decodes from JSON correctly")
    func testHomeSceneDecoding() throws {
        let json = Data("""
        {"entityId": "scene.relax", "name": "Relax", "isActive": true}
        """.utf8)
        let scene = try JSONDecoder().decode(HomeScene.self, from: json)
        #expect(scene.entityId == "scene.relax")
        #expect(scene.name == "Relax")
        #expect(scene.isActive == true)
    }

    @Test("HomeScene decodes without isActive field")
    func testHomeSceneDecodingWithoutActive() throws {
        let json = Data("""
        {"entityId": "scene.relax", "name": "Relax"}
        """.utf8)
        let scene = try JSONDecoder().decode(HomeScene.self, from: json)
        #expect(scene.isActive == nil)
    }

    @Test("HomeScene array decodes from JSON correctly")
    func testHomeSceneArrayDecoding() throws {
        let json = Data("""
        [
            {"entityId": "scene.morning", "name": "Morning"},
            {"entityId": "scene.night", "name": "Night"}
        ]
        """.utf8)
        let scenes = try JSONDecoder().decode([HomeScene].self, from: json)
        #expect(scenes.count == 2)
        #expect(scenes[0].name == "Morning")
        #expect(scenes[1].entityId == "scene.night")
    }

    @Test("SceneActivateRequest encodes entityId")
    func testSceneActivateRequestEncoding() throws {
        let request = SceneActivateRequest(entityId: "scene.bedtime")
        let data = try JSONEncoder().encode(request)
        let json = try JSONDecoder().decode([String: String].self, from: data)
        #expect(json["entityId"] == "scene.bedtime")
    }

    @Test("SceneServiceError has descriptive messages")
    func testSceneServiceErrorDescriptions() {
        let unauthorized = SceneServiceError.unauthorized
        #expect(unauthorized.localizedDescription == "Authentication required")

        let server = SceneServiceError.serverError("Bad gateway")
        #expect(server.localizedDescription == "Bad gateway")

        let network = SceneServiceError.networkError("Timeout")
        #expect(network.localizedDescription == "Timeout")
    }
}
