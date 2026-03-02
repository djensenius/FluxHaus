//
//  SceneView.swift
//  FluxHaus
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

@MainActor
@Observable class SceneManager {
    var scenes: [HomeScene] = []
    var favourites: [HomeScene] = []
    var activatingSceneId: String?

    func loadScenes(favouriteNames: [String]) async {
        do {
            scenes = try await fetchScenes()
            favourites = scenes.filter { scene in
                favouriteNames.contains(scene.name)
            }
        } catch {
            scenes = []
            favourites = []
        }
    }

    func activate(_ scene: HomeScene) {
        activatingSceneId = scene.entityId
        Task {
            try? await activateScene(entityId: scene.entityId)
            try? await Task.sleep(for: .seconds(1))
            activatingSceneId = nil
        }
    }
}

struct SceneView: View {
    var favouriteHomeKit: [String]
    @State private var sceneManager = SceneManager()
    private let gridItemLayout = [GridItem(.flexible())]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: gridItemLayout, spacing: 8) {
                ForEach(sceneManager.favourites) { scene in
                    Button(action: {
                        sceneManager.activate(scene)
                    }, label: {
                        HStack {
                            if sceneManager.activatingSceneId == scene.entityId {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text(scene.name)
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .frame(width: 100)
                        }
                        .frame(width: 120, height: 50, alignment: .center)
                    })
                    .glassEffect(.regular.interactive())
                    .disabled(sceneManager.activatingSceneId != nil)
                    .padding(.leading)
                }
            }
        }
        .task {
            await sceneManager.loadScenes(favouriteNames: favouriteHomeKit)
            startRefreshTimer()
        }
    }

    private func startRefreshTimer() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                await sceneManager.loadScenes(favouriteNames: favouriteHomeKit)
            }
        }
    }
}

#if DEBUG
#Preview {
    SceneView(favouriteHomeKit: ["Good Morning", "Bedtime"])
}
#endif
