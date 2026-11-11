//
//  DeviceSnippet.swift
//  FluxHaus
//
//  The card Siri shows for a FluxHaus device (iOS/visionOS 27.3 Siri AI). The system
//  pre-renders snippets into a static archive, so the card reads only data that's
//  already on the entity. Buttons run App Intents, after which Siri re-renders it.
//

import AppIntents
import SwiftUI

struct DeviceSnippetCard: View {
    let device: DeviceAppEntity

    nonisolated init(device: DeviceAppEntity) {
        self.device = device
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: device.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text(device.name)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Text(device.status ?? "Ask FluxHaus for the latest status.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding()
    }

    @ViewBuilder
    private var actions: some View {
        switch device.kind {
        case .car:
            HStack {
                Button(intent: LockCarIntent()) {
                    Label("Lock", systemImage: "lock.fill")
                }
                Button(intent: StartCarClimateIntent()) {
                    Label("Climate", systemImage: "fan.fill")
                }
            }
            .buttonStyle(.bordered)
        case .cleanBot:
            HStack {
                Button(intent: StartRobotIntent(robot: .cleanBot)) {
                    Label("Start", systemImage: "play.fill")
                }
                Button(intent: StopRobotIntent(robot: .cleanBot)) {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            .buttonStyle(.bordered)
        case .dishwasher, .washer, .dryer, .scooter, .airPurifier:
            EmptyView()
        }
    }
}

#if canImport(AppIntents, _version: 301.1.17)
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension DeviceAppEntity: SnippetRepresentableEntity {
    static var snippet: some EntitySnippetContent<DeviceAppEntity> {
        CardSnippet(supportedFamilies: [.standard]) { device, _ in
            DeviceSnippetCard(device: device)
        }
    }
}
#endif
