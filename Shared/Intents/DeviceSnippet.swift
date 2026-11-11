//
//  DeviceSnippet.swift
//  FluxHaus
//
//  The card Siri shows for a FluxHaus device (iOS/visionOS 27.3 Siri AI). The system
//  pre-renders snippets into a static archive, so the card reads only data that's
//  already on the entity. Buttons run App Intents, after which Siri re-renders it.
//  Buttons only appear on cards from Device Status and act for that card's account.
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
        if let session = device.originSession {
            switch device.kind {
            case .car:
                HStack {
                    button("Lock", systemImage: "lock.fill", action: .lockCar, session: session)
                    button("Climate", systemImage: "fan.fill", action: .startCarClimate, session: session)
                }
                .buttonStyle(.bordered)
            case .cleanBot:
                HStack {
                    button("Start", systemImage: "play.fill", action: .startCleanbot, session: session)
                    button("Stop", systemImage: "stop.fill", action: .stopCleanbot, session: session)
                }
                .buttonStyle(.bordered)
            case .dishwasher, .washer, .dryer, .scooter, .airPurifier:
                EmptyView()
            }
        }
    }

    private func button(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: DeviceSnippetAction,
        session: String
    ) -> some View {
        Button(intent: DeviceSnippetActionIntent(action: action, originSession: session)) {
            Label(title, systemImage: systemImage)
        }
    }
}

enum DeviceSnippetAction: String, AppEnum {
    case lockCar
    case startCarClimate
    case startCleanbot
    case stopCleanbot

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Card Action"
    static let caseDisplayRepresentations: [DeviceSnippetAction: DisplayRepresentation] = [
        .lockCar: "Lock Car",
        .startCarClimate: "Start Car Climate",
        .startCleanbot: "Start Cleanbot",
        .stopCleanbot: "Stop Cleanbot"
    ]
}

/// Runs a device card button for the account the card was created under. Like the
/// widgets' `WidgetCache.runCommand(expecting:)`, it refuses to send if another account
/// is signed in, so a stale card can't control a different account's devices.
struct DeviceSnippetActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Device Card Action"
    static let description = IntentDescription("Runs a button on a FluxHaus device card.")
    static let isDiscoverable = false

    @Parameter(title: "Action")
    var action: DeviceSnippetAction

    @Parameter(title: "Session")
    var originSession: String

    init() {}

    init(action: DeviceSnippetAction, originSession: String) {
        self.action = action
        self.originSession = originSession
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let origin = originSession
        guard !origin.isEmpty else { throw IntentError.notSignedIn }
        let isStillValid: @Sendable () -> Bool = { AuthManager.shared.widgetSessionID() == origin }
        switch action {
        case .lockCar:
            try await FluxIntentActions.lockCar(isStillValid: isStillValid)
        case .startCarClimate:
            try await FluxIntentActions.startCarClimate(
                defrost: false, heatedFeatures: false, temperature: nil, isStillValid: isStillValid
            )
        case .startCleanbot:
            try await FluxIntentActions.startRobot(.cleanBot, isStillValid: isStillValid)
        case .stopCleanbot:
            try await FluxIntentActions.stopRobot(.cleanBot, isStillValid: isStillValid)
        }
        return .result()
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
