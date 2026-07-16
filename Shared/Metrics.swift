//
//  Metrics.swift
//  FluxHaus
//
//  Fetches server-defined metric catalog and time-series data for the
//  metrics dashboard. The app only references metric ids — all queries
//  (Flux / PromQL) are defined server-side.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Metrics")

public enum MetricRange: String, CaseIterable, Identifiable {
    case hour = "1h"
    case sixHours = "6h"
    case day = "24h"
    case week = "7d"
    case month = "30d"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hour: return "1H"
        case .sixHours: return "6H"
        case .day: return "24H"
        case .week: return "7D"
        case .month: return "30D"
        }
    }
}

public struct MetricCatalogItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let unit: String
    public let group: String
}

private struct MetricCatalogResponse: Codable {
    let metrics: [MetricCatalogItem]
}

public struct MetricPoint: Codable, Hashable, Sendable {
    public let time: String
    public let value: Double

    enum CodingKeys: String, CodingKey {
        case time = "t"
        case value = "v"
    }

    public var date: Date? {
        MetricPoint.parse(time)
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        formatter.date(from: value) ?? plainFormatter.date(from: value)
    }
}

public struct MetricSeries: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let points: [MetricPoint]
}

public struct MetricSeriesResponse: Codable, Sendable {
    public let metric: String
    public let title: String
    public let unit: String
    public let range: String
    public let series: [MetricSeries]
}

@MainActor
@Observable class MetricsService {
    var catalog: [MetricCatalogItem] = []
    var series: [String: MetricSeriesResponse] = [:]
    var selectedRange: MetricRange = .day
    var isLoading = false
    var isRefreshing = false
    var lastError: String?

    var groupedCatalog: [(group: String, metrics: [MetricCatalogItem])] {
        let visible = catalog.filter { $0.group.lowercased() != "system" }
        let groups = Dictionary(grouping: visible, by: { $0.group })
        return groups.keys.sorted(by: MetricsService.groupSort).map { key in
            (group: key, metrics: groups[key] ?? [])
        }
    }

    /// Preferred group ordering: Environment first, then Car, then the rest
    /// alphabetically. "System" is filtered out entirely.
    private static func groupSort(_ lhs: String, _ rhs: String) -> Bool {
        func rank(_ group: String) -> Int {
            switch group.lowercased() {
            case "environment": return 0
            case "car": return 1
            default: return 2
            }
        }
        let lRank = rank(lhs), rRank = rank(rhs)
        if lRank != rRank { return lRank < rRank }
        return lhs < rhs
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        await loadCatalog()
        await loadAllSeries()
        isLoading = false
    }

    func loadCatalog() async {
        guard let data = await get(path: "/metrics/catalog", query: []) else { return }
        do {
            let decoded = try JSONDecoder().decode(MetricCatalogResponse.self, from: data)
            catalog = decoded.metrics
        } catch {
            logger.error("Failed to decode metric catalog: \(error.localizedDescription)")
            lastError = "Could not load metrics"
        }
    }

    func loadAllSeries() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let range = selectedRange
        var results: [String: MetricSeriesResponse] = [:]
        for metric in catalog {
            if let response = await fetchSeries(metricId: metric.id, range: range) {
                results[metric.id] = response
            }
        }
        // The range may have changed while requests were in flight; discard
        // results that no longer match the current selection so the UI never
        // shows series for the wrong range.
        guard range == selectedRange else { return }
        series = results
    }

    func fetchSeries(metricId: String, range: MetricRange) async -> MetricSeriesResponse? {
        let query = [
            URLQueryItem(name: "metric", value: metricId),
            URLQueryItem(name: "range", value: range.rawValue)
        ]
        guard let data = await get(path: "/metrics/series", query: query) else { return nil }
        do {
            return try JSONDecoder().decode(MetricSeriesResponse.self, from: data)
        } catch {
            logger.error("Failed to decode series \(metricId): \(error.localizedDescription)")
            return nil
        }
    }

    private func get(path: String, query: [URLQueryItem]) async -> Data? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let authHeader = AuthManager.shared.authorizationHeader() {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        } else {
            let password = WhereWeAre.getPassword() ?? ""
            let base64 = Data("demo:\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }

        do {
            let session = URLSession(configuration: .default)
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode) else {
                logger.error("Metrics GET \(path) returned HTTP \(statusCode)")
                lastError = "Could not load metrics (HTTP \(statusCode))"
                return nil
            }
            lastError = nil
            return data
        } catch {
            logger.error("Metrics GET \(path) failed: \(error.localizedDescription)")
            lastError = "Could not load metrics"
            return nil
        }
    }
}
