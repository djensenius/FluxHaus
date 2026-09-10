//
//  CarAnalytics.swift
//  FluxHaus
//
//  Server-backed historical car analytics shared by the app and App Intents.
//

import Foundation
import os

let carAnalyticsLogger = Logger(
    subsystem: "io.fluxhaus.FluxHaus",
    category: "CarAnalytics"
)

enum CarAnalyticsRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case year = "1y"
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    var spokenLabel: String {
        switch self {
        case .week: return "the last 7 days"
        case .month: return "the last 30 days"
        case .quarter: return "the last 90 days"
        case .year: return "the last year"
        case .all: return "all retained history"
        }
    }
}

enum CarAnalyticsTopic: String, CaseIterable, Codable, Sendable {
    case overview
    case charging
    case efficiency
    case weather
    case comparison
}

enum CarEfficiencyMethod: String, Codable, Sendable {
    case measured = "measured_kwh"
    case proxy = "battery_proxy"
    case unavailable
}

struct CarAnalyticsPeriod: Codable, Sendable {
    let range: String
    let requestedStart: String?
    let requestedEnd: String
    let effectiveStart: String?
    let effectiveEnd: String?
    let timezone: String
    let aggregationWindow: String
}

struct CarChargingSession: Codable, Identifiable, Sendable {
    let start: String
    let end: String
    let durationHours: Double
    let batteryAddedPercent: Double?

    var id: String { start }
}

struct CarChargingAnalytics: Codable, Sendable {
    let sessionCount: Int
    let averageIntervalDays: Double?
    let averageSessionHours: Double?
    let averageChargeAddedPercent: Double?
    let sessions: [CarChargingSession]
    let sessionsTruncated: Bool
}

struct CarEfficiencyResult: Codable, Sendable {
    let method: CarEfficiencyMethod
    let value: Double?
    let unit: String?
    let label: String
}

struct CarUsageAnalytics: Codable, Sendable {
    let distanceKm: Double
    let energyKWh: Double?
    let measuredEnergyDistanceKm: Double?
    let batteryUsedPercent: Double?
    let efficiency: CarEfficiencyResult
}

struct CarTemperatureBand: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let minimumC: Double?
    let maximumC: Double?
    let distanceKm: Double
    let efficiency: CarEfficiencyResult
}

struct CarWeatherAnalytics: Codable, Sendable {
    let averageTemperatureC: Double?
    let bands: [CarTemperatureBand]
    let estimatedImpactPercent: Double?
    let comparisonBands: [String]?
    let efficiencyMethod: CarEfficiencyMethod
}

struct CarAnalyticsComparison: Codable, Sendable {
    let periodStart: String
    let periodEnd: String
    let distanceChangePercent: Double?
    let chargingFrequencyChangePercent: Double?
    let efficiencyChangePercent: Double?
    let previousCoveragePercent: Double
    let previousEffectiveStart: String?
    let previousEffectiveEnd: String?
}

struct CarAnalyticsDataQuality: Codable, Sendable {
    let coveragePercent: Double
    let energyCoveragePercent: Double
    let telemetrySamples: Int
    let chargingSamples: Int
    let weatherSamples: Int
    let warnings: [String]
}

struct CarAnalyticsResponse: Codable, Sendable {
    let period: CarAnalyticsPeriod
    let summary: String
    let charging: CarChargingAnalytics
    let usage: CarUsageAnalytics
    let weather: CarWeatherAnalytics
    let comparison: CarAnalyticsComparison?
    let dataQuality: CarAnalyticsDataQuality

    func dialog(for topic: CarAnalyticsTopic, range: CarAnalyticsRange) -> String {
        let message: String
        switch topic {
        case .overview:
            message = summary
        case .charging:
            message = chargingDialog(range: range)
        case .efficiency:
            message = efficiencyDialog(range: range)
        case .weather:
            message = weatherDialog(range: range)
        case .comparison:
            message = comparisonDialog(range: range)
        }
        guard dataQuality.coveragePercent < 75 else { return message }
        return "\(message) Data coverage was \(format(dataQuality.coveragePercent)) percent."
    }

    private func chargingDialog(range: CarAnalyticsRange) -> String {
        var result = "You charged \(charging.sessionCount) "
        result += charging.sessionCount == 1 ? "time" : "times"
        result += " in \(range.spokenLabel)."
        if let interval = charging.averageIntervalDays {
            result += " That is about every \(format(interval)) days."
        }
        return result
    }

    private func efficiencyDialog(range: CarAnalyticsRange) -> String {
        guard let value = usage.efficiency.value,
              let unit = usage.efficiency.unit else {
            return "There is not enough data to calculate car efficiency for \(range.spokenLabel)."
        }
        if usage.efficiency.method == .proxy {
            return "Estimated battery use was \(format(value)) \(unit) in \(range.spokenLabel). "
                + "This is a battery-based estimate, not measured energy efficiency."
        }
        return "Measured efficiency was \(format(value)) \(unit) in \(range.spokenLabel)."
    }

    private func weatherDialog(range: CarAnalyticsRange) -> String {
        if let impact = weather.estimatedImpactPercent {
            let direction = impact >= 0 ? "worse" : "better"
            let source = weather.efficiencyMethod == .proxy ? "estimated battery use" : "measured efficiency"
            return "Below freezing, \(source) was \(format(abs(impact))) percent \(direction) "
                + "than in mild weather during \(range.spokenLabel)."
        }
        if let temperature = weather.averageTemperatureC {
            return "The average outdoor temperature was \(format(temperature)) degrees Celsius, "
                + "but there is not enough comparable driving to measure a weather effect."
        }
        return "Outdoor temperature data is unavailable for \(range.spokenLabel)."
    }

    private func comparisonDialog(range: CarAnalyticsRange) -> String {
        guard let comparison else {
            return "A previous-period comparison is unavailable for \(range.spokenLabel)."
        }
        var changes: [String] = []
        if let distance = comparison.distanceChangePercent {
            changes.append(changeDescription(value: distance, subject: "distance"))
        }
        if let charging = comparison.chargingFrequencyChangePercent {
            changes.append(changeDescription(value: charging, subject: "charging frequency"))
        }
        if let efficiency = comparison.efficiencyChangePercent {
            changes.append(changeDescription(value: efficiency, subject: "efficiency"))
        }
        guard !changes.isEmpty else {
            return "There is not enough coverage to compare \(range.spokenLabel) with the previous period."
        }
        return changes.joined(separator: " ")
    }

    private func changeDescription(value: Double, subject: String) -> String {
        let direction = value >= 0 ? "increased" : "decreased"
        return "\(subject.capitalized) \(direction) by \(format(abs(value))) percent."
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

enum CarAnalyticsClientError: LocalizedError {
    case unsupportedServer
    case invalidURL
    case requestFailed(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedServer:
            return "Car analytics requires a newer FluxHaus Server."
        case .invalidURL:
            return "Could not build the car analytics request."
        case .requestFailed(let statusCode):
            return "Car analytics failed (HTTP \(statusCode))."
        case .invalidResponse:
            return "FluxHaus Server returned invalid car analytics."
        }
    }
}

struct CarAnalyticsClient {
    var session: URLSession = .shared

    @MainActor
    func fetch(
        range: CarAnalyticsRange,
        topic: CarAnalyticsTopic = .overview
    ) async throws -> CarAnalyticsResponse {
        guard AuthManager.shared.isSignedIn else {
            throw IntentError.notSignedIn
        }
        _ = await AuthManager.shared.ensureValidToken()
        guard let authorization = AuthManager.shared.authorizationHeader() else {
            throw IntentError.notSignedIn
        }

        var components = URLComponents()
        components.scheme = FluxIntentActions.scheme
        components.host = FluxIntentActions.host
        components.path = "/analytics/car"
        components.queryItems = [
            URLQueryItem(name: "range", value: range.rawValue),
            URLQueryItem(name: "topic", value: topic.rawValue),
            URLQueryItem(name: "comparison", value: range == .all ? "none" : "previous"),
            URLQueryItem(name: "timezone", value: TimeZone.current.identifier)
        ]
        guard let url = components.url else {
            throw CarAnalyticsClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if statusCode == 404 {
            throw CarAnalyticsClientError.unsupportedServer
        }
        guard (200...299).contains(statusCode) else {
            throw CarAnalyticsClientError.requestFailed(statusCode)
        }
        do {
            return try JSONDecoder().decode(CarAnalyticsResponse.self, from: data)
        } catch {
            carAnalyticsLogger.error("Failed to decode car analytics: \(error.localizedDescription)")
            throw CarAnalyticsClientError.invalidResponse
        }
    }
}
