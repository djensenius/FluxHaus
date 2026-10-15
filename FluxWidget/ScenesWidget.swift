//
//  ScenesWidget.swift
//  FluxWidget
//
//  Scenes widget: one-tap HomeKit scenes from the Home Screen or StandBy.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Entity & intents

struct WidgetSceneEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static let defaultQuery = WidgetSceneQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(scene: HomeScene) {
        self.init(id: scene.entityId, name: scene.name)
    }
}

struct WidgetSceneQuery: EntityQuery {
    func entities(for identifiers: [WidgetSceneEntity.ID]) async throws -> [WidgetSceneEntity] {
        let scenes = await SceneStore.load()
        return identifiers.compactMap { id in scenes.first { $0.entityId == id }.map(WidgetSceneEntity.init(scene:)) }
    }

    func suggestedEntities() async throws -> [WidgetSceneEntity] {
        await SceneStore.load().map(WidgetSceneEntity.init(scene:))
    }
}

struct ScenesConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Scenes"
    static let description = IntentDescription("Choose the scenes to show. Leave empty to show your first scenes.")

    @Parameter(title: "Scenes", size: [.systemSmall: 2, .systemMedium: 4, .systemLarge: 8])
    var scenes: [WidgetSceneEntity]?

    init() {}
}

struct RunSceneWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Scene"
    static let description = IntentDescription("Activate a FluxHaus scene.")
    static let isDiscoverable = false

    @Parameter(title: "Scene ID")
    var sceneId: String

    init() {}

    init(sceneId: String) {
        self.sceneId = sceneId
    }

    func perform() async throws -> some IntentResult {
        try await requireIntentAuthentication()
        try await activateScene(entityId: sceneId)
        SceneStore.markActivated(sceneId)
        return .result()
    }
}

// MARK: - Data

enum SceneStore {
    private static let cacheKey = "FluxWidget.scenes"
    private static let activatedKey = "FluxWidget.sceneActivated"

    struct Activation: Codable {
        let id: String
        let date: Date
    }

    static func load() async -> [HomeScene] {
        guard WidgetCache.hasCredentials else {
            WidgetCache.clear(key: cacheKey)
            return []
        }
        do {
            let scenes = try await fetchScenes()
            WidgetCache.save(scenes, key: cacheKey)
            return scenes
        } catch {
            return WidgetCache.load([HomeScene].self, key: cacheKey) ?? []
        }
    }

    static func markActivated(_ id: String) {
        WidgetCache.save(Activation(id: id, date: Date()), key: activatedKey)
    }

    /// Scene tapped in the last couple of minutes, to confirm the tap visually.
    static func recentlyActivated(now: Date = Date()) -> String? {
        guard let value = WidgetCache.load(Activation.self, key: activatedKey),
              now.timeIntervalSince(value.date) < 120 else { return nil }
        return value.id
    }
}

/// Best-effort SF Symbol for a scene based on its name.
func sceneSymbol(for name: String) -> String {
    let lower = name.lowercased()
    let table: [([String], String)] = [
        (["movie", "tv", "cinema", "film"], "tv.fill"),
        (["morning", "wake", "sunrise"], "sun.horizon.fill"),
        (["night", "sleep", "bed"], "moon.stars.fill"),
        (["away", "leave", "goodbye", "out"], "figure.walk"),
        (["arrive", "home", "welcome"], "house.fill"),
        (["dinner", "eat", "cook", "kitchen"], "fork.knife"),
        (["read", "book"], "book.fill"),
        (["relax", "chill", "evening"], "sofa.fill"),
        (["work", "focus", "office"], "desktopcomputer"),
        (["off", "all off"], "power"),
        (["bright", "on", "day"], "lightbulb.max.fill")
    ]
    for (keywords, symbol) in table where keywords.contains(where: { lower.contains($0) }) {
        return symbol
    }
    return "sparkles"
}

// MARK: - Timeline

struct SceneItem: Hashable {
    let id: String
    let name: String
    var isActive: Bool
    /// Highlighted only because it was just tapped (cleared after a couple of minutes).
    var justTapped = false
}

struct ScenesEntry: TimelineEntry {
    let date: Date
    let scenes: [SceneItem]
    let signedIn: Bool
}

struct ScenesProvider: AppIntentTimelineProvider {
    private static let preview = [
        SceneItem(id: "1", name: "Good Morning", isActive: false),
        SceneItem(id: "2", name: "Movie Night", isActive: true),
        SceneItem(id: "3", name: "Dinner", isActive: false),
        SceneItem(id: "4", name: "Good Night", isActive: false)
    ]

    func placeholder(in context: Context) -> ScenesEntry {
        ScenesEntry(date: Date(), scenes: Self.preview, signedIn: true)
    }

    func snapshot(for configuration: ScenesConfigIntent, in context: Context) async -> ScenesEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: ScenesConfigIntent, in context: Context) async -> Timeline<ScenesEntry> {
        let entry = await entry(for: configuration, family: context.family)
        var entries = [entry]
        if SceneStore.recentlyActivated() != nil {
            // Drop the tap confirmation after it expires.
            let cleared = entry.scenes.map { scene -> SceneItem in
                guard scene.justTapped else { return scene }
                var scene = scene
                scene.isActive = false
                scene.justTapped = false
                return scene
            }
            entries.append(ScenesEntry(
                date: entry.date.addingTimeInterval(120),
                scenes: cleared,
                signedIn: entry.signedIn
            ))
        }
        return Timeline(entries: entries, policy: .after(entry.date.addingTimeInterval(60 * 60)))
    }

    private func entry(for configuration: ScenesConfigIntent, family: WidgetFamily) async -> ScenesEntry {
        let all = await SceneStore.load()
        let limit = family == .systemSmall ? 2 : family == .systemMedium ? 4 : 8
        let chosen: [HomeScene]
        if let selected = configuration.scenes, !selected.isEmpty {
            chosen = selected.compactMap { entity in all.first { $0.entityId == entity.id } }
        } else {
            chosen = Array(all.prefix(limit))
        }
        let tapped = SceneStore.recentlyActivated()
        let items = chosen.prefix(limit).map { scene in
            let serverActive = scene.isActive == true
            let justTapped = !serverActive && scene.entityId == tapped
            return SceneItem(
                id: scene.entityId,
                name: scene.name,
                isActive: serverActive || justTapped,
                justTapped: justTapped
            )
        }
        return ScenesEntry(date: Date(), scenes: Array(items), signedIn: WidgetCache.hasCredentials)
    }
}

// MARK: - Views

private let sceneTint = Color(red: 0.98, green: 0.75, blue: 0.30)

struct SceneButton: View {
    let scene: SceneItem
    var compact = false

    var body: some View {
        PaletteReader { palette in
            Button(intent: RunSceneWidgetIntent(sceneId: scene.id)) {
                HStack(spacing: 8) {
                    Image(systemName: sceneSymbol(for: scene.name))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(scene.isActive ? palette.tint(sceneTint) : palette.primary)
                        .widgetAccentable()
                        .frame(width: 22)
                    Text(scene.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(scene.isActive ? palette.fill(sceneTint) : palette.secondary.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Run \(scene.name)")
        }
    }
}

struct ScenesWidgetEntryView: View {
    let entry: ScenesEntry
    @Environment(\.widgetFamily) private var family

    private var columns: [GridItem] {
        family == .systemSmall
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        Group {
            if entry.scenes.isEmpty {
                EmptyStateView(message: entry.signedIn ? "No scenes yet" : "Open FluxHaus to sign in")
            } else {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.id) { scene in
                                SceneButton(scene: scene)
                            }
                            if row.count < columns.count {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
        .widgetURL(URL(string: "fluxhaus://scenes"))
    }

    private var rows: [[SceneItem]] {
        stride(from: 0, to: entry.scenes.count, by: columns.count).map {
            Array(entry.scenes[$0..<min($0 + columns.count, entry.scenes.count)])
        }
    }
}

struct FluxScenesWidget: Widget {
    let kind = "FluxScenesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ScenesConfigIntent.self, provider: ScenesProvider()) { entry in
            ScenesWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Scenes")
        .description("Run your favourite HomeKit scenes with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    FluxScenesWidget()
} timeline: {
    ScenesEntry(
        date: .now,
        scenes: [
            SceneItem(id: "1", name: "Good Morning", isActive: false),
            SceneItem(id: "2", name: "Movie Night", isActive: true),
            SceneItem(id: "3", name: "Dinner", isActive: false),
            SceneItem(id: "4", name: "Good Night", isActive: false)
        ],
        signedIn: true
    )
}
