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
    var loadError: String?
    var hasLoaded = false

    func loadScenes(favouriteNames: [String]) async {
        do {
            scenes = try await fetchScenes()
            loadError = nil
            if favouriteNames.isEmpty {
                favourites = scenes
            } else {
                favourites = scenes.filter { favouriteNames.contains($0.name) }
            }
            hasLoaded = true
        } catch {
            loadError = error.localizedDescription
            scenes = []
            favourites = []
            hasLoaded = true
        }
    }

    func activate(_ scene: HomeScene, favouriteNames: [String] = []) {
        activatingSceneId = scene.entityId
        Task {
            try? await activateScene(entityId: scene.entityId)
            try? await Task.sleep(for: .seconds(1))
            await loadScenes(favouriteNames: favouriteNames)
            activatingSceneId = nil
        }
    }
}

struct SceneView: View {
    var favouriteHomeKit: [String]
    @State private var sceneManager = SceneManager()

    var body: some View {
        #if os(macOS)
        macOSSceneView
        #else
        iOSSceneView
        #endif
    }

    #if os(macOS)
    private var macOSSceneView: some View {
        ScrollView {
            if let error = sceneManager.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(Theme.Colors.warning)
                    Text("Unable to load scenes")
                        .font(Theme.Fonts.headerLarge())
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(error)
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if !sceneManager.hasLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading scenes…")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if sceneManager.favourites.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "lightbulb.slash")
                        .font(.largeTitle)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("No matching scenes")
                        .font(Theme.Fonts.headerLarge())
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(sceneManager.favourites) { scene in
                        Button(action: {
                            sceneManager.activate(scene, favouriteNames: favouriteHomeKit)
                        }, label: {
                            HStack {
                                if sceneManager.activatingSceneId == scene.entityId {
                                    ProgressView().controlSize(.small)
                                }
                                Image(systemName: scene.isActive == true ? "lightbulb.fill" : "lightbulb")
                                    .foregroundColor(
                                        scene.isActive == true ? Theme.Colors.accent : Theme.Colors.textSecondary
                                    )
                                Text(scene.name).font(Theme.Fonts.bodyMedium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        })
                        .buttonStyle(.bordered)
                        .tint(scene.isActive == true ? Theme.Colors.accent : nil)
                        .disabled(sceneManager.activatingSceneId != nil)
                    }
                }
                .padding()
            }
        }
        .background(Theme.Colors.background)
        .task {
            await sceneManager.loadScenes(favouriteNames: favouriteHomeKit)
        }
    }
    #endif

    private var iOSSceneView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.flexible())], spacing: 8) {
                ForEach(sceneManager.favourites) { scene in
                    Button(action: {
                        sceneManager.activate(scene, favouriteNames: favouriteHomeKit)
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
                    #if !os(visionOS)
                    .glassEffect(.regular.interactive())
                    #endif
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
