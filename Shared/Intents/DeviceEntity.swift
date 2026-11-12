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
import CoreTransferable
import os

/// The fixed set of FluxHaus devices that can be queried by name.
enum DeviceKind: String, CaseIterable, Sendable {
    case car
    case cleanBot
    case dishwasher
    case washer
    case dryer
    case scooter
    case airPurifier

    var displayName: String {
        switch self {
        case .car: return "Car"
        case .cleanBot: return "Cleanbot"
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
        case .cleanBot: return "robotic.vacuum.cleaner.fill"
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
        case .cleanBot: return ["cleanbot", "mova", "v70", "robot vacuum", "robot mop", "vacuum", "mop"]
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
        case .cleanBot: return FluxStatusText.robot(response.cleanbot)
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

    @Property(title: "Search Aliases", indexingKey: \.textContent)
    var searchableAliases: String

    /// Live status text. Only set on entities returned by Device Status; it isn't
    /// indexed because it goes stale.
    @Property(title: "Status")
    var status: String?

    /// The account session the status was fetched under, so the card's buttons can't act
    /// for a different account (see `DeviceSnippetActionIntent`). Not exposed to Siri.
    let originSession: String?

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Device"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: DisplayRepresentation.Image(systemName: kind.symbolName)
        )
    }

    static let defaultQuery = DeviceEntityQuery()

    init(kind: DeviceKind) {
        self.init(id: kind.rawValue, kind: kind, status: nil, originSession: nil)
    }

    private init(id: String, kind: DeviceKind, status: String?, originSession: String?) {
        self.id = id
        self.kind = kind
        self.originSession = originSession
        self.name = kind.displayName
        self.searchableAliases = kind.searchTerms.joined(separator: "\n")
        self.status = status
    }

    init?(id: String) {
        let normalizedId: String
        let outputId: String
        switch id {
        case "broomBot", "mopBot":
            normalizedId = DeviceKind.cleanBot.rawValue
            outputId = id
        default:
            normalizedId = id
            outputId = id
        }
        guard let kind = DeviceKind(rawValue: normalizedId) else { return nil }
        self.init(id: outputId, kind: kind, status: nil, originSession: nil)
    }

    /// Returns a new entity because `@Property` storage is shared between copies.
    func withStatus(_ status: String, session: String?) -> DeviceAppEntity {
        DeviceAppEntity(id: id, kind: kind, status: Self.siriStatus(status), originSession: session)
    }

    static let maxStatusLength = 300
    private static let statusCharacters = CharacterSet.alphanumerics
        .union(.whitespaces)
        .union(CharacterSet(charactersIn: ".,:;'’%°()/-+&…"))

    /// Status text includes server data and goes into Siri's context, so keep it to one
    /// bounded line of letters, numbers, and plain sentence punctuation.
    static func siriStatus(_ text: String) -> String {
        let line = FluxStatusText.filtered(text, allowing: statusCharacters)
        guard line.count > maxStatusLength else { return line }
        return String(line.prefix(maxStatusLength - 1)) + "…"
    }

    /// Plain-text summary used when Siri shares or passes the device to another app.
    var transferText: String {
        guard let status else { return name }
        return "\(name): \(status)"
    }
}

extension DeviceAppEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (device: DeviceAppEntity) in device.transferText }
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

func removeLegacyDeviceIndexEntries() async throws {
    try await FluxSpotlightIndexes.devices.deleteSearchableItems(withIdentifiers: ["broomBot", "mopBot"])
}

/// Adds every FluxHaus device to the Spotlight index so it's searchable and so
/// Siri / Apple Intelligence can resolve it as a parameter.
func indexDevices() async {
    let entities = DeviceKind.allCases.map(DeviceAppEntity.init(kind:))
    do {
        try await removeLegacyDeviceIndexEntries()
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
        try await removeLegacyDeviceIndexEntries()
        try await FluxSpotlightIndexes.devices.indexAppEntities(
            DeviceKind.allCases.map(DeviceAppEntity.init(kind:))
        )
    }
}

struct DeviceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Device Status"
    static let description = IntentDescription(
        "Get a FluxHaus device's live status, like car charge and locks, Cleanbot progress, or appliance time left."
    )

    @Parameter(
        title: "Device",
        description: "The device to check: car, Cleanbot, dishwasher, washer, dryer, scooter, or air purifier.",
        requestValueDialog: "Which FluxHaus device?"
    )
    var device: DeviceAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the status of \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<DeviceAppEntity> & ProvidesDialog {
        try await requireIntentAuthentication()
        // Like the widgets, treat a missing session ID (e.g. keychain failure) as signed out.
        guard let session = AuthManager.shared.widgetSessionID() else { throw IntentError.notSignedIn }
        let response = try await fetchStatus()
        // Don't return the previous account's status if the account changed during the fetch.
        guard AuthManager.shared.widgetSessionID() == session else { throw IntentError.notSignedIn }
        let status = DeviceAppEntity.siriStatus(device.kind.status(from: response))
        return .result(value: device.withStatus(status, session: session), dialog: "\(status)")
    }
}
