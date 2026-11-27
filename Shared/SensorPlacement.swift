//
//  SensorPlacement.swift
//  FluxHaus
//
//  On-demand, server-generated placement insights.
//

import Foundation

struct PlacementInsights: Decodable, Sendable {
    let generatedAt: String
    let windowDays: Int
    let unit: String
    let coverage: Coverage
    let sensors: [Sensor]
    let recommendations: [Recommendation]

    private enum CodingKeys: String, CodingKey {
        case generatedAt, windowDays, unit, coverage, sensors, recommendations
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try values.decode(String.self, forKey: .generatedAt)
        windowDays = try values.decode(Int.self, forKey: .windowDays)
        unit = try values.decode(String.self, forKey: .unit)
        coverage = try values.decode(Coverage.self, forKey: .coverage)
        sensors = try values.decode([Sensor].self, forKey: .sensors)
        recommendations = try values.decode([Recommendation].self, forKey: .recommendations)
        guard windowDays > 0, !unit.isEmpty,
              Self.isoDate(generatedAt) != nil, Self.isoDate(coverage.start) != nil, Self.isoDate(coverage.end) != nil,
              coverage.morningEvents >= 0, coverage.returnEvents >= 0,
              coverage.inferredMorningEvents.map({ (0...coverage.morningEvents).contains($0) }) ?? true,
              coverage.hvacEarliestStateAt.map({ Self.isoDate($0) != nil }) ?? true,
              coverage.unknownUnitWindows.map({ $0 >= 0 }) ?? true,
              coverage.wakeEvents.map({ $0 >= 0 }) ?? true, coverage.coolingEvents.map({ $0 >= 0 }) ?? true,
              coverage.coolingFrom.map({ Self.isoDate($0) != nil }) ?? true,
              coverage.coolingTo.map({ Self.isoDate($0) != nil }) ?? true,
              sensors.allSatisfy({ $0.sampleCount >= 0 && !$0.id.isEmpty && !$0.name.isEmpty }),
              sensors.allSatisfy({ $0.hasValidDrillDown }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .coverage, in: values, debugDescription: "Invalid placement insights"
            )
        }
    }

    static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    struct Coverage: Decodable, Sendable {
        let start: String
        let end: String
        let hvacHistoryAvailable: Bool
        let morningEvents: Int
        let returnEvents: Int
        let hvacEarliestStateAt: String?
        let returnHistoryAvailable: Bool?
        let inferredMorningEvents: Int?
        let unknownUnitWindows: Int?
        let participationConfigured: Bool?
        let followMe: Bool?
        let occupancyAvailable: Bool?
        let comfortScheduleAvailable: Bool?
        let wakeEvents: Int?
        let coolingFrom: String?
        let coolingTo: String?
        let coolingEvents: Int?

        var observedMorningEvents: Int? {
            inferredMorningEvents.map { morningEvents - $0 }
        }

        var detectedReturnEvents: Int? {
            returnHistoryAvailable == true ? returnEvents : nil
        }

    }

    struct Sensor: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let isThermostat: Bool
        let averageOffset: Double?
        let morningOffset: Double?
        let returnOffset: Double?
        let overshoot: Double?
        let sampleCount: Int
        // Keep unknown server classifications instead of failing the entire response.
        let classification: String
        let wakeOffset: Double?
        let coolingOffset: Double?
        let participation: Participation?
        let occupiedShare: OccupiedShare?
        // Per-sensor drill-down (all optional; older servers omit them).
        let verdict: Verdict?
        let verdictSummary: String?
        let periodOffsets: PeriodOffsets?
        let wakeOvershoot: Double?
        let coolingUndershoot: Double?
        let consistency: Consistency?
        let recommendationIds: [String]?

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: PlacementSensorKeys.self)
            id = try values.decode(String.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            isThermostat = try values.decode(Bool.self, forKey: .isThermostat)
            averageOffset = try values.decode(Double?.self, forKey: .averageOffset)
            morningOffset = try values.decode(Double?.self, forKey: .morningOffset)
            returnOffset = try values.decode(Double?.self, forKey: .returnOffset)
            overshoot = try values.decode(Double?.self, forKey: .overshoot)
            sampleCount = try values.decode(Int.self, forKey: .sampleCount)
            classification = try values.decode(String.self, forKey: .classification)
            wakeOffset = try values.decodeIfPresent(Double.self, forKey: .wakeOffset)
            coolingOffset = try values.decodeIfPresent(Double.self, forKey: .coolingOffset)
            participation = try values.decodeIfPresent(Participation.self, forKey: .participation)
            // An earlier contract draft sent a scalar here; ignore any shape other than `{wake, home}`.
            occupiedShare = (try? values.decodeIfPresent(OccupiedShare.self, forKey: .occupiedShare)) ?? nil
            verdict = try values.decodeIfPresent(String.self, forKey: .verdict)
                .map { Verdict(rawValue: $0) ?? .unknown }
            verdictSummary = try values.decodeIfPresent(String.self, forKey: .verdictSummary)
            periodOffsets = try values.decodeIfPresent(PeriodOffsets.self, forKey: .periodOffsets)
            wakeOvershoot = try values.decodeIfPresent(Double.self, forKey: .wakeOvershoot)
            coolingUndershoot = try values.decodeIfPresent(Double.self, forKey: .coolingUndershoot)
            consistency = try values.decodeIfPresent(Consistency.self, forKey: .consistency)
            recommendationIds = try values.decodeIfPresent([String].self, forKey: .recommendationIds)
        }

        fileprivate var hasValidDrillDown: Bool {
            let shares = [occupiedShare?.wake, occupiedShare?.home].compactMap { $0 }
            return shares.allSatisfy { (0...1).contains($0) } && (consistency?.isValid ?? true)
        }

        /// Recommendations about this sensor: the server's ids when given, else those naming it.
        func relatedRecommendations(in insights: PlacementInsights) -> [Recommendation] {
            let ranked = insights.rankedRecommendations
            if let ids = recommendationIds { return ranked.filter { ids.contains($0.id) } }
            return ranked.filter { $0.sensorId == id || $0.affectedSensorIds.contains(id) }
        }

        var classificationLabel: String {
            switch classification {
            case "cold": return "Cooler"
            case "warm": return "Warmer"
            case "representative": return "Representative"
            case "insufficient": return "Insufficient data"
            default: return "Unknown"
            }
        }
    }

    enum Verdict: String, Sendable {
        case coldOutlier = "cold_outlier", warmOutlier = "warm_outlier", representative, insufficient, unknown
    }

    struct PeriodOffsets: Decodable, Equatable, Sendable {
        let sleep: Double?
        let wake: Double?
        let home: Double?
        let heatingRuns: Double?
        let cooling: Double?
    }

    struct OccupiedShare: Decodable, Equatable, Sendable {
        let wake: Double?
        let home: Double?
    }

    /// Days whose daily mean offset was ≤ −0.5 (cold) or ≥ +0.5 (warm), for heating and cooling.
    struct Consistency: Decodable, Equatable, Sendable {
        let days: Int?
        let coldDays: Int?
        let warmDays: Int?
        let coolingDays: Int?
        let coolingColdDays: Int?
        let coolingWarmDays: Int?

        var isValid: Bool {
            [days, coldDays, warmDays, coolingDays, coolingColdDays, coolingWarmDays]
                .allSatisfy { ($0 ?? 0) >= 0 }
        }
    }

    struct Participation: Decodable, Equatable, Sendable {
        let home: Bool?
        let sleep: Bool?
        let away: Bool?

        func value(for setting: PlacementConfig.Setting) -> Bool? {
            switch setting {
            case .home: return home
            case .sleep: return sleep
            case .away: return away
            }
        }
    }

    // Server enums map unrecognized future values to `.unknown` instead of failing the response.
    enum Mode: String, Sendable { case heating, cooling, unknown }

    enum Period: String, Sendable { case wake, sleep, home, returning = "return", unknown }

    enum ComfortSetting: String, Sendable { case home, sleep, away, unknown }

    struct Recommendation: Decodable, Identifiable, Sendable {
        let id: String
        let severity: String
        let sensorId: String?
        let action: String
        let title: String
        let detail: String
        let mode: Mode?
        let period: Period?
        let comfortSetting: ComfortSetting?
        let affectedSensorIds: [String]
        let likelyCauses: [String]

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: PlacementRecommendationKeys.self)
            id = try values.decode(String.self, forKey: .id)
            severity = try values.decode(String.self, forKey: .severity)
            sensorId = try values.decode(String?.self, forKey: .sensorId)
            action = try values.decode(String.self, forKey: .action)
            title = try values.decode(String.self, forKey: .title)
            detail = try values.decode(String.self, forKey: .detail)
            mode = try values.decodeIfPresent(String.self, forKey: .mode).map { Mode(rawValue: $0) ?? .unknown }
            period = try values.decodeIfPresent(String.self, forKey: .period).map { Period(rawValue: $0) ?? .unknown }
            comfortSetting = try values.decodeIfPresent(String.self, forKey: .comfortSetting)
                .map { ComfortSetting(rawValue: $0) ?? .unknown }
            affectedSensorIds = try values.decodeIfPresent([String].self, forKey: .affectedSensorIds) ?? []
            likelyCauses = try values.decodeIfPresent([String].self, forKey: .likelyCauses) ?? []
        }

        var severityRank: Int {
            switch severity {
            case "high": return 0
            case "medium": return 1
            case "low": return 2
            default: return 3
            }
        }
    }

    /// Physical room sensors that can participate in comfort settings (excludes the thermostat average).
    var roomSensorIDs: Set<String> { Set(sensors.filter { !$0.isThermostat }.map(\.id)) }
    var thermostatIDs: Set<String> { Set(sensors.filter(\.isThermostat).map(\.id)) }

    var rankedRecommendations: [Recommendation] {
        recommendations.enumerated().sorted {
            if $0.element.severityRank != $1.element.severityRank {
                return $0.element.severityRank < $1.element.severityRank
            }
            return $0.offset < $1.offset
        }.map(\.element)
    }
}

private enum PlacementSensorKeys: String, CodingKey {
    case id, name, isThermostat, averageOffset, morningOffset, returnOffset, overshoot, sampleCount, classification
    case wakeOffset, coolingOffset, participation, occupiedShare
    case verdict, verdictSummary, periodOffsets, wakeOvershoot, coolingUndershoot, consistency, recommendationIds
}

private enum PlacementRecommendationKeys: String, CodingKey {
    case id, severity, sensorId, action, title, detail, mode, period, comfortSetting, affectedSensorIds, likelyCauses
}

enum PlacementRequestError: Error {
    case invalidResponse
    case http(Int)
    case sessionChanged
    case unauthorized
}

@MainActor
@Observable final class SensorPlacementService {
    typealias SessionCheck = @MainActor () -> Bool
    typealias Fetch = @MainActor (PlacementConfig?, @escaping SessionCheck) async throws -> PlacementInsights

    static let prunedNotice = "Sensors that are no longer reported were removed from your thermostat setup."
    static let rejectedNotice = "Your thermostat setup couldn't be used, so these tips don't account for it. "
        + "Review it in Thermostat setup."
    static let sensorsUnavailableNotice = "Sensors aren't available right now, so these tips don't account for "
        + "your thermostat setup. Your setup is kept and will be used once sensors are back."
    static let setupUnavailableNotice = "Thermostat setup can't be saved because this sign-in doesn't identify "
        + "your account. Sign out and sign in again to set it up."

    private struct Outcome: Sendable {
        let insights: PlacementInsights
        let config: PlacementConfig?
        let notice: String?
    }

    private var storedInsights: PlacementInsights?
    private var storedConfig: PlacementConfig?
    private var loading = false
    private var storedError: String?
    private var storedNotice: String?
    /// Bumped on every setup change; `appliedRevision` catches up only when a load succeeds.
    private var configRevision = 0
    private var appliedRevision = 0
    @ObservationIgnored private var loadTask: Task<Outcome, Error>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let configStore: PlacementConfigStore?
    private let sessionCheck: SessionCheck
    private let fetch: Fetch

    var isSessionValid: Bool { sessionCheck() }
    var insights: PlacementInsights? { isSessionValid ? storedInsights : nil }
    var config: PlacementConfig? { isSessionValid ? storedConfig : nil }
    var isLoading: Bool { isSessionValid && loading }
    var error: String? { isSessionValid ? storedError : nil }
    /// A non-fatal message about the thermostat setup (e.g. unknown sensors were dropped).
    var notice: String? { isSessionValid ? storedNotice : nil }
    /// False when there's no stable account identity to save the setup under; setup is then unavailable.
    var canSaveConfig: Bool { configStore != nil }
    /// A setup change hasn't been loaded yet (e.g. its refresh was cancelled), so views should retry.
    var hasPendingConfig: Bool { isSessionValid && configRevision != appliedRevision }

    init(
        insights: PlacementInsights? = nil,
        sessionCheck: @escaping SessionCheck = SensorPlacementService.currentSessionCheck(),
        configStore: PlacementConfigStore? = PlacementConfigStore.current(),
        fetch: @escaping Fetch = { try await SensorPlacementService.fetchInsights(config: $0, sessionCheck: $1) }
    ) {
        self.storedInsights = insights
        self.sessionCheck = sessionCheck
        self.configStore = configStore
        self.storedConfig = configStore?.load()
        self.fetch = fetch
    }

    /// Saves a new thermostat setup (nil clears it). Returns true when it changed and insights should reload.
    @discardableResult
    func updateConfig(_ config: PlacementConfig?) -> Bool {
        let config = config?.excluding(storedInsights?.thermostatIDs ?? [])
        guard isSessionValid, let configStore, config != storedConfig else { return false }
        storedConfig = config
        storedNotice = nil
        configStore.save(config)
        configRevision &+= 1
        return true
    }

    /// Loads insights for the current setup. Returns true only on success (including an intentional
    /// unconfigured fallback); a cancelled or failed load leaves a pending setup change pending.
    @discardableResult
    func refresh() async -> Bool {
        guard isSessionValid, !Task.isCancelled else { return false }
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        loading = true
        storedError = nil
        let original = storedConfig
        let revision = configRevision
        let config = original?.excluding(storedInsights?.thermostatIDs ?? [])
        let known = storedInsights?.roomSensorIDs
        let fetch = self.fetch
        let sessionCheck = self.sessionCheck
        let task = Task {
            try await Self.load(config: config, known: known, sessionCheck: sessionCheck, fetch: fetch)
        }
        loadTask = task
        defer {
            if loadGeneration == generation {
                loading = false
                loadTask = nil
            }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard loadGeneration == generation, isSessionValid else { return false }
            storedInsights = result.insights
            storedNotice = result.notice
            let final = result.config?.excluding(result.insights.thermostatIDs)
            if final != original, storedConfig == original {
                storedConfig = final
                configStore?.save(final)
            }
            if configRevision == revision { appliedRevision = revision }
            return true
        } catch {
            guard !Task.isCancelled, loadGeneration == generation, isSessionValid else { return false }
            if case PlacementRequestError.http(let code) = error {
                storedError = "Could not load sensor placement (HTTP \(code))."
            } else {
                storedError = "Could not load sensor placement. Please try again."
            }
            return false
        }
    }

    /// Fetches with the config. If the server rejects it (HTTP 400, e.g. a stale sensor id), drops
    /// unknown sensors and retries, falling back to unconfigured insights rather than a dead end.
    private static func load(
        config: PlacementConfig?, known: Set<String>?, sessionCheck: @escaping SessionCheck, fetch: Fetch
    ) async throws -> Outcome {
        do {
            return Outcome(insights: try await fetch(config, sessionCheck), config: config, notice: nil)
        } catch PlacementRequestError.http(400) where config != nil {
            guard let config else { throw PlacementRequestError.http(400) }
            // Retries with a pruned config; nil when the server rejects that too.
            func retry(_ pruned: PlacementConfig) async throws -> Outcome? {
                do {
                    let insights = try await fetch(pruned, sessionCheck)
                    return Outcome(insights: insights, config: pruned, notice: prunedNotice)
                } catch PlacementRequestError.http(400) { return nil }
            }
            // Try the cached sensor list first, then the fresh unconfigured response, which may
            // show that a sensor the cache still lists is gone. An empty list may be a temporary
            // discovery failure, so it never prunes: the saved setup is kept for when sensors return.
            var tried = config
            if let known, !known.isEmpty, case let pruned = config.pruned(to: known), pruned != config {
                if let outcome = try await retry(pruned) { return outcome }
                tried = pruned
            }
            let fresh = try await fetch(nil, sessionCheck)
            let available = fresh.roomSensorIDs
            guard !available.isEmpty else {
                return Outcome(insights: fresh, config: config, notice: sensorsUnavailableNotice)
            }
            let pruned = config.pruned(to: available)
            if pruned != config, pruned != tried, let outcome = try await retry(pruned) { return outcome }
            return Outcome(insights: fresh, config: config, notice: rejectedNotice)
        }
    }

    static func currentSessionCheck() -> SessionCheck {
        let origin = AuthManager.shared.widgetSessionID()
        return {
            // Make SwiftUI observe sign-in changes as well as checking the shared keychain session.
            _ = AuthManager.shared.authState
            return origin != nil && AuthManager.shared.widgetSessionID() == origin
        }
    }
}
