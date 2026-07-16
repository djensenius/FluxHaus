//
//  DeviceEntity.swift
//  FluxHaus
//
//  Phase 2 of the iOS 27 Siri AI work: expose FluxHaus's controllable devices as
//  App Entities and contribute them to the Spotlight semantic index. This gives
//  Siri / Apple Intelligence "personal context" about the user's home ("my car",
//  "the dishwasher") with attribution back to FluxHaus, and powers a single
//  device-parameterised status intent.
//
//  Smart-home content has no matching Apple assistant schema in iOS 27, so we use
//  the custom AppEntity + IndexedEntity pattern (as SceneAppEntity already does)
//  rather than @AssistantEntity(schema:).
//

import AppIntents
import CoreSpotlight
import os

/// The fixed set of FluxHaus devices that can be queried by name.
enum DeviceKind: String, CaseIterable, Sendable {
    case car
    case broomBot
    case mopBot
    case dishwasher
    case scooter

    var displayName: String {
        switch self {
        case .car: return "Car"
        case .broomBot: return "BroomBot"
        case .mopBot: return "MopBot"
        case .dishwasher: return "Dishwasher"
        case .scooter: return "Scooter"
        }
    }

    var symbolName: String {
        switch self {
        case .car: return "car.fill"
        case .broomBot: return "robotic.vacuum.cleaner"
        case .mopBot: return "robotic.vacuum.cleaner.fill"
        case .dishwasher: return "dishwasher.fill"
        case .scooter: return "scooter"
        }
    }

    /// Produces the spoken status for this device from a fetched response.
    func status(from response: LoginResponse) -> String {
        switch self {
        case .car: return FluxStatusText.car(response)
        case .broomBot: return FluxStatusText.robot(response.broombot)
        case .mopBot: return FluxStatusText.robot(response.mopbot)
        case .dishwasher: return FluxStatusText.dishwasher(response)
        case .scooter: return FluxStatusText.scooter(response)
        }
    }
}

struct DeviceAppEntity: IndexedEntity {
    let id: String

    var kind: DeviceKind

    @Property(title: "Name")
    var name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Device"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: DisplayRepresentation.Image(systemName: kind.symbolName)
        )
    }

    static let defaultQuery = DeviceEntityQuery()

    init(kind: DeviceKind) {
        self.id = kind.rawValue
        self.kind = kind
        self.name = kind.displayName
    }

    init?(id: String) {
        guard let kind = DeviceKind(rawValue: id) else { return nil }
        self.id = kind.rawValue
        self.kind = kind
        self.name = kind.displayName
    }
}

/// Adds every FluxHaus device to the Spotlight index so it's searchable and so
/// Siri / Apple Intelligence can resolve it as a parameter.
func indexDevices() async {
    let entities = DeviceKind.allCases.map(DeviceAppEntity.init(kind:))
    do {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    } catch {
        let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "DeviceIndex")
        logger.error("Failed to index devices: \(error.localizedDescription)")
    }
}

struct DeviceEntityQuery: EntityStringQuery {
    func entities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
        identifiers.compactMap(DeviceAppEntity.init(id:))
    }

    /// Lets Siri / Apple Intelligence resolve a device the user names out loud
    /// (e.g. "what's the status of the dishwasher").
    func entities(matching string: String) async throws -> [DeviceAppEntity] {
        let needle = string.lowercased()
        return DeviceKind.allCases
            .filter { $0.displayName.lowercased().contains(needle) }
            .map(DeviceAppEntity.init(kind:))
    }

    func suggestedEntities() async throws -> [DeviceAppEntity] {
        DeviceKind.allCases.map(DeviceAppEntity.init(kind:))
    }
}

struct DeviceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Device Status"
    static let description = IntentDescription("Get the status of a FluxHaus device.")

    @Parameter(title: "Device")
    var device: DeviceAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the status of \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        return .result(dialog: "\(device.kind.status(from: response))")
    }
}
