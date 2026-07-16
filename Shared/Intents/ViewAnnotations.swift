//
//  ViewAnnotations.swift
//  FluxHaus
//
//  Phase 3 of the iOS 27 Siri AI work: on-screen awareness via the View Annotations
//  API. Mapping a SwiftUI view to an App Entity's identifier lets Siri / Apple
//  Intelligence resolve conversational references to what's on screen ("start this",
//  "what's the status of that") to the corresponding FluxHaus entity.
//

import SwiftUI
import AppIntents

extension View {
    /// Annotates the view as representing a FluxHaus device so Siri can resolve
    /// on-screen references (e.g. "lock this") to the matching device entity.
    func fluxDeviceAnnotation(_ kind: DeviceKind) -> some View {
        appEntityIdentifier(EntityIdentifier(for: DeviceAppEntity(kind: kind)))
    }

    /// Annotates the view as representing a FluxHaus HomeKit scene so Siri can
    /// resolve on-screen references (e.g. "activate this scene").
    func fluxSceneAnnotation(_ scene: SceneAppEntity) -> some View {
        appEntityIdentifier(EntityIdentifier(for: scene))
    }
}
