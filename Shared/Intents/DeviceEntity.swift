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
    case washer
    case dryer
    case scooter
    case airPurifier

    var displayName: String {
        switch self {
        case .car: return "Car"
        case .broomBot: return "BroomBot"
        case .mopBot: return "MopBot"
        case .dishwasher: return "Dishwasher"
        case .washer: return "Washer"
        case .dryer: return "Dryer"
        case .scooter: return "Scooter"
        case .airPurifier: return "Air Purifier"
        }
    }

    var symbolName: String {
        switch self {
        case .car: return "car.fill"
        case .broomBot: return "robotic.vacuum.cleaner"
        case .mopBot: return "robotic.vacuum.cleaner.fill"
        case .dishwasher: return "dishwasher.fill"
        case .washer: return "washer.fill"
        case .dryer: return "dryer.fill"
        case .scooter: return "scooter"
        case .airPurifier: return "air.purifier.fill"
        }
    }

    var searchTerms: [String] {
        switch self {
        case .car: return ["car", "vehicle", "electric car", "ev"]
        case .broomBot: return ["broombot", "broom bot", "robot vacuum", "vacuum"]
        case .mopBot: return ["mopbot", "mop bot", "robot mop", "mop"]
        case .dishwasher: return ["dishwasher", "dish washer"]
        case .washer: return ["washer", "washing machine", "laundry washer"]
        case .dryer: return ["dryer", "tumble dryer", "laundry dryer"]
        case .scooter: return ["scooter"]
        case .airPurifier: return ["air purifier", "purifier", "air filter"]
        }
    }

    init?(applianceName: String) {
        let name = applianceName.lowercased()
        if name.contains("dish") {
            self = .dishwasher
        } else if name.contains("dryer") {
            self = .dryer
        } else if name.contains("wash") {
            self = .washer
        } else {
            return nil
        }
    }

    /// Produces the spoken status for this device from a fetched response.
    func status(from response: LoginResponse) -> String {
        switch self {
        case .car: return FluxStatusText.car(response)
        case .broomBot: return FluxStatusText.robot(response.broombot)
        case .mopBot: return FluxStatusText.robot(response.mopbot)
        case .dishwasher: return FluxStatusText.dishwasher(response)
        case .washer: return FluxStatusText.washer(response)
        case .dryer: return FluxStatusText.dryer(response)
        case .scooter: return FluxStatusText.scooter(response)
        case .airPurifier: return FluxStatusText.airPurifier(response)
        }
    }
}

struct DeviceAppEntity: IndexedEntity {
    let id: String

    let kind: DeviceKind

    @Property(title: "Name", indexingKey: \.displayName)
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

enum FluxSpotlightIndexes {
    static let devicesName = "FluxHausDevices"
    static let scenesName = "FluxHausScenes"

    static var devices: CSSearchableIndex {
        CSSearchableIndex(name: devicesName)
    }

    static var scenes: CSSearchableIndex {
        CSSearchableIndex(name: scenesName)
    }
}

/// Adds every FluxHaus device to the Spotlight index so it's searchable and so
/// Siri / Apple Intelligence can resolve it as a parameter.
func indexDevices() async {
    let entities = DeviceKind.allCases.map(DeviceAppEntity.init(kind:))
    do {
        try await FluxSpotlightIndexes.devices.indexAppEntities(entities)
    } catch {
        let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "DeviceIndex")
        logger.error("Failed to index devices: \(error.localizedDescription)")
    }
    FluxHausShortcuts.updateAppShortcutParameters()
}

struct DeviceEntityQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
        identifiers.compactMap(DeviceAppEntity.init(id:))
    }

    /// Lets Siri / Apple Intelligence resolve a device the user names out loud
    /// (e.g. "what's the status of the dishwasher").
    func entities(matching string: String) async throws -> [DeviceAppEntity] {
        let words = string.lowercased().split { !$0.isLetter && !$0.isNumber }
        let meaningfulWords = words.drop(while: { word in
            word == "a" || word == "an" || word == "my" || word == "the"
        })
        let needle = meaningfulWords.joined(separator: " ")
        guard !needle.isEmpty else {
            return []
        }

        let exactMatches = DeviceKind.allCases.filter { $0.searchTerms.contains(needle) }
        if !exactMatches.isEmpty {
            return exactMatches.map(DeviceAppEntity.init(kind:))
        }

        return DeviceKind.allCases.filter { kind in
            kind.searchTerms.contains { term in
                term.hasPrefix(needle) || needle.hasPrefix("\(term) ")
            }
        }
        .map(DeviceAppEntity.init(kind:))
    }

    func suggestedEntities() async throws -> [DeviceAppEntity] {
        DeviceKind.allCases.map(DeviceAppEntity.init(kind:))
    }

    func reindexEntities(
        for identifiers: [DeviceAppEntity.ID],
        indexDescription _: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await FluxSpotlightIndexes.devices.indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        try await FluxSpotlightIndexes.devices.indexAppEntities(
            DeviceKind.allCases.map(DeviceAppEntity.init(kind:))
        )
    }
}

struct DeviceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Device Status"
    static let description = IntentDescription("Get the status of a FluxHaus device.")

    @Parameter(title: "Device", requestValueDialog: "Which FluxHaus device?")
    var device: DeviceAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the status of \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await fetchStatus()
        return .result(dialog: "\(device.kind.status(from: response))")
    }
}
