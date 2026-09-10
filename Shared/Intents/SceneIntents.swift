//
//  SceneIntents.swift
//  FluxHaus
//
//  App Intent + entity for activating a HomeKit scene.
//

import AppIntents
import CoreSpotlight
import os

struct SceneAppEntity: IndexedEntity {
    let id: String

    @Property(title: "Name", indexingKey: \.displayName)
    var name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = SceneEntityQuery()

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(scene: HomeScene) {
        self.id = scene.entityId
        self.name = scene.name
    }
}

/// Adds the app's HomeKit scenes to the Spotlight index so they're searchable and so
/// Apple Intelligence / Siri can use them to fill in the Activate Scene intent.
func indexScenes(_ scenes: [HomeScene]) async {
    let entities = scenes.map(SceneAppEntity.init(scene:))
    do {
        try await FluxSpotlightIndexes.scenes.indexAppEntities(entities)
    } catch {
        let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "SceneIndex")
        logger.error("Failed to index scenes: \(error.localizedDescription)")
    }
}

struct SceneEntityQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [SceneAppEntity.ID]) async throws -> [SceneAppEntity] {
        let ids = Set(identifiers)
        let scenes = try await fetchScenes()
        return scenes
            .filter { ids.contains($0.entityId) }
            .map(SceneAppEntity.init(scene:))
    }

    /// Lets Siri / Apple Intelligence resolve a scene the user names out loud
    /// (e.g. "activate the Good Morning scene").
    func entities(matching string: String) async throws -> [SceneAppEntity] {
        let needle = string.lowercased()
        let scenes = try await fetchScenes()
        return scenes
            .filter { $0.name.lowercased().contains(needle) }
            .map(SceneAppEntity.init(scene:))
    }

    func suggestedEntities() async throws -> [SceneAppEntity] {
        let scenes = try await fetchScenes()
        return scenes.map(SceneAppEntity.init(scene:))
    }

    func reindexEntities(
        for identifiers: [SceneAppEntity.ID],
        indexDescription _: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await FluxSpotlightIndexes.scenes.indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        let scenes = try await fetchScenes()
        try await FluxSpotlightIndexes.scenes.indexAppEntities(scenes.map(SceneAppEntity.init(scene:)))
    }
}

struct ActivateSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Activate Scene"
    static let description = IntentDescription("Activate a FluxHaus HomeKit scene.")

    @Parameter(title: "Scene")
    var scene: SceneAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Activate \(\.$scene)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AuthManager.shared.isSignedIn else {
            throw IntentError.notSignedIn
        }
        try await activateScene(entityId: scene.id)
        return .result(dialog: "Activating \(scene.name).")
    }
}
