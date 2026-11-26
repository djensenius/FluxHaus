//
//  SensorPlacement.swift
//  FluxHaus
//
//  On-demand, server-generated placement insights.
//

import Foundation

struct PlacementInsights: Decodable, Sendable {
    let generatedAt: String?
    let windowDays: Int?
    let unit: String?
    let coverage: Coverage?
    let sensors: [Sensor]?
    let recommendations: [Recommendation]?

    struct Coverage: Decodable, Sendable {
        let start: String?
        let end: String?
        let hvacHistoryAvailable: Bool?
        let morningEvents: Int?
        let returnEvents: Int?
    }

    struct Sensor: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let isThermostat: Bool?
        let averageOffset: Double?
        let morningOffset: Double?
        let returnOffset: Double?
        let overshoot: Double?
        let sampleCount: Int?
        // Keep unknown server classifications instead of failing the entire response.
        let classification: String?

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
        let severity: String?
        let sensorId: String?
        let action: String?
        let title: String
        let detail: String

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
        (recommendations ?? []).enumerated().sorted {
            if $0.element.severityRank != $1.element.severityRank {
                return $0.element.severityRank < $1.element.severityRank
            }
            return $0.offset < $1.offset
        }.map(\.element)
    }
}

enum PlacementRequestError: Error {
    case invalidResponse
    case http(Int)
}

@MainActor
@Observable final class SensorPlacementService {
    private(set) var insights: PlacementInsights?
    private(set) var isLoading = false
    private(set) var error: String?
    private let fetch: () async throws -> PlacementInsights

    init(
        insights: PlacementInsights? = nil,
        fetch: @escaping () async throws -> PlacementInsights = SensorPlacementService.fetchInsights
    ) {
        self.insights = insights
        self.fetch = fetch
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await fetch()
            try Task.checkCancellation()
            insights = result
        } catch {
            guard !Task.isCancelled else { return }
            if case PlacementRequestError.http(let code) = error {
                self.error = "Could not load sensor placement (HTTP \(code))."
            } else {
                self.error = "Could not load sensor placement. Please try again."
            }
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

    static func fetchInsights() async throws -> PlacementInsights {
        let authorization: String
        if let header = AuthManager.shared.authorizationHeader() {
            authorization = header
        } else {
            let password = WhereWeAre.getPassword() ?? ""
            authorization = "Basic \(Data("demo:\(password)".utf8).base64EncodedString())"
        }
        let session = URLSession(configuration: .default)
        let (data, response) = try await session.data(for: request(authorization: authorization))
        return try decode(data: data, response: response)
    }
}
