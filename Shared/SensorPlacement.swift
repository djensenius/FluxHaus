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
              coverage.hvacHistoryStart.map({ Self.isoDate($0) != nil }) ?? true,
              sensors.allSatisfy({ $0.sampleCount >= 0 && !$0.id.isEmpty && !$0.name.isEmpty }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .coverage, in: values, debugDescription: "Invalid placement insights"
            )
        }
    }

    private static func isoDate(_ value: String) -> Date? {
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
        let hvacHistoryStart: String?
        let returnHistoryAvailable: Bool?
        let inferredMorningEvents: Int?

        var observedMorningEvents: Int? {
            inferredMorningEvents.map { morningEvents - $0 }
        }

        var detectedReturnEvents: Int? {
            returnHistoryAvailable == true ? returnEvents : nil
        }

        var hvacHistoryStartsAfterWindow: Bool? {
            guard hvacHistoryAvailable, let hvacHistoryStart,
                  let historyStart = PlacementInsights.isoDate(hvacHistoryStart),
                  let windowStart = PlacementInsights.isoDate(start) else { return nil }
            return historyStart > windowStart
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

    struct Recommendation: Decodable, Identifiable, Sendable {
        let id: String
        let severity: String
        let sensorId: String?
        let action: String
        let title: String
        let detail: String

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: PlacementRecommendationKeys.self)
            id = try values.decode(String.self, forKey: .id)
            severity = try values.decode(String.self, forKey: .severity)
            sensorId = try values.decode(String?.self, forKey: .sensorId)
            action = try values.decode(String.self, forKey: .action)
            title = try values.decode(String.self, forKey: .title)
            detail = try values.decode(String.self, forKey: .detail)
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
}

private enum PlacementRecommendationKeys: String, CodingKey {
    case id, severity, sensorId, action, title, detail
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

    private var storedInsights: PlacementInsights?
    private var loading = false
    private var storedError: String?
    private let sessionCheck: SessionCheck
    private let fetch: @MainActor (@escaping SessionCheck) async throws -> PlacementInsights

    var isSessionValid: Bool { sessionCheck() }
    var insights: PlacementInsights? { isSessionValid ? storedInsights : nil }
    var isLoading: Bool { isSessionValid && loading }
    var error: String? { isSessionValid ? storedError : nil }

    init(
        insights: PlacementInsights? = nil,
        sessionCheck: @escaping SessionCheck = SensorPlacementService.currentSessionCheck(),
        fetch: @escaping @MainActor (@escaping SessionCheck) async throws -> PlacementInsights = {
            try await SensorPlacementService.fetchInsights(sessionCheck: $0)
        }
    ) {
        self.storedInsights = insights
        self.sessionCheck = sessionCheck
        self.fetch = fetch
    }

    func refresh() async {
        guard isSessionValid, !loading else { return }
        loading = true
        storedError = nil
        defer { loading = false }
        do {
            let result = try await fetch(sessionCheck)
            try Task.checkCancellation()
            guard isSessionValid else { return }
            storedInsights = result
        } catch {
            guard !Task.isCancelled, isSessionValid else { return }
            if case PlacementRequestError.http(let code) = error {
                storedError = "Could not load sensor placement (HTTP \(code))."
            } else {
                storedError = "Could not load sensor placement. Please try again."
            }
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

    static func request(authorization: String) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/climate/placement-insights"
        components.queryItems = [URLQueryItem(name: "days", value: "14")]
        // The fixed URL components above always form a valid URL.
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    static func decode(data: Data, response: URLResponse) throws -> PlacementInsights {
        guard let response = response as? HTTPURLResponse else { throw PlacementRequestError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw PlacementRequestError.http(response.statusCode) }
        return try JSONDecoder().decode(PlacementInsights.self, from: data)
    }

    static func fetchInsights(
        sessionCheck: @escaping SessionCheck,
        authorization: @MainActor () -> String? = { AuthManager.shared.authorizationHeader() },
        hasOIDCToken: @MainActor () -> Bool = { AuthManager.shared.getAccessToken() != nil },
        ensureToken: @MainActor () async -> Bool = { await AuthManager.shared.ensureValidToken() },
        refreshToken: @MainActor () async -> Bool = { await AuthManager.shared.refreshTokenIfNeeded() },
        send: @MainActor (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) async throws -> PlacementInsights {
        try checkSession(sessionCheck)
        if hasOIDCToken() {
            _ = await ensureToken()
            try checkSession(sessionCheck)
        }
        guard let header = authorization() else { throw PlacementRequestError.unauthorized }
        try checkSession(sessionCheck)
        var (data, response) = try await send(request(authorization: header))
        try checkSession(sessionCheck)
        if (response as? HTTPURLResponse)?.statusCode == 401, hasOIDCToken() {
            let refreshed = await refreshToken()
            try checkSession(sessionCheck)
            guard refreshed, let newHeader = authorization() else { throw PlacementRequestError.unauthorized }
            try checkSession(sessionCheck)
            (data, response) = try await send(request(authorization: newHeader))
            try checkSession(sessionCheck)
        }
        return try decode(data: data, response: response)
    }

    private static func checkSession(_ check: SessionCheck) throws {
        try Task.checkCancellation()
        guard check() else { throw PlacementRequestError.sessionChanged }
    }
}
