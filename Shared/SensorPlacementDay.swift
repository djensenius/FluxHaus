//
//  SensorPlacementDay.swift
//  FluxHaus
//

import Foundation

struct PlacementDayInsights: Decodable, Sendable {
    let date: String
    let timeZone: String
    let unit: String
    let timeline: [PlacementDayTimelinePoint]
    let wake: PlacementDayWake?
    let sensors: [Sensor]
    let findings: [Finding]
    let coverage: PlacementDayCoverage

    private enum CodingKeys: String, CodingKey {
        case date, timeZone, unit, timeline, wake, sensors, findings, coverage
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(String.self, forKey: .date)
        timeZone = try values.decode(String.self, forKey: .timeZone)
        unit = try values.decode(String.self, forKey: .unit)
        timeline = try values.decode([PlacementDayTimelinePoint].self, forKey: .timeline)
        wake = try values.decodeIfPresent(PlacementDayWake.self, forKey: .wake)
        sensors = try values.decode([Sensor].self, forKey: .sensors)
        findings = try values.decode([Finding].self, forKey: .findings)
        coverage = try values.decode(PlacementDayCoverage.self, forKey: .coverage)

        let times = timeline.compactMap { PlacementInsights.isoDate($0.timestamp) }
        guard PlacementDayCalendar.isValid(date),
              TimeZone(identifier: timeZone) != nil,
              !unit.isEmpty,
              times.count == timeline.count,
              zip(times, times.dropFirst()).allSatisfy({ $0.0 < $0.1 }),
              coverage.expectedBuckets >= 0,
              (0...coverage.expectedBuckets).contains(coverage.completeBuckets),
              coverage.missingRoomReadings >= 0,
              coverage.unknownUnitWindows >= 0,
              coverage.missingHvacBuckets >= 0,
              coverage.missingAverageBuckets >= 0,
              coverage.baselineDays >= 0,
              sensors.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }),
              Set(sensors.map(\.id)).count == sensors.count,
              findings.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }),
              wake.map({
                  ($0.heatingMinutes.map { $0 >= 0 } ?? true)
                      && ($0.coolingMinutes.map { $0 >= 0 } ?? true)
                      && $0.unknownMinutes >= 0
              }) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .coverage, in: values, debugDescription: "Invalid daily placement insights"
            )
        }
    }

    struct Sensor: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let isThermostat: Bool
        let dayOffset: Double?
        let baselineOffset: Double?
        let deviation: Double?
        let unusual: Bool?
    }

    struct Finding: Decodable, Identifiable, Sendable {
        let id: String
        let severity: String
        let title: String
        let detail: String
        let sensorIds: [String]
    }
}

struct PlacementDayTimelinePoint: Decodable, Identifiable, Sendable {
    let timestamp: String
    let setpoint: Double?
    let hvacAction: String?
    let hvacMode: String?
    let comfortSetting: String?
    let average: Double?
    let rooms: [String: Double?]
    let occupied: [String: Bool?]

    private enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case setpoint, hvacAction, hvacMode, comfortSetting, average, rooms, occupied
    }

    var id: String { timestamp }
    var date: Date? { PlacementInsights.isoDate(timestamp) }
}

struct PlacementDayWake: Decodable, Sendable {
    let timestamp: String
    let setpointBefore: Double?
    let setpointAfter: Double?
    let heatingMinutes: Double?
    let coolingMinutes: Double?
    let unknownMinutes: Double
    let contextComplete: Bool
    let contextRetryable: Bool
    let rooms: [PlacementDayWakeRoom]
    let context: PlacementDayWakeContext

    private enum CodingKeys: String, CodingKey {
        case timestamp = "at"
        case setpointBefore, setpointAfter, heatingMinutes, coolingMinutes, unknownMinutes
        case contextComplete, contextRetryable, rooms, context
    }
}

struct PlacementDayCoverage: Decodable, Sendable {
    let start: String
    let end: String
    let expectedBuckets: Int
    let completeBuckets: Int
    let missingRoomReadings: Int
    let unknownUnitWindows: Int
    let missingHvacBuckets: Int
    let missingAverageBuckets: Int
    let reportedAverageBuckets: Int
    let approximatedAverageBuckets: Int
    let unknownUnitWindowsScope: String
    let hvacHistoryAvailable: Bool
    let occupancyKnownReadings: Int
    let occupancyExpectedReadings: Int
    let baselineDays: Int
    let incompleteSensorInventory: Bool
    let unitAssumptions: PlacementDayUnitAssumptions
    let averageIsApproximation: Bool

    private enum CodingKeys: String, CodingKey {
        case start, end, expectedBuckets, completeBuckets, missingRoomReadings, unknownUnitWindows
        case missingHvacBuckets, missingAverageBuckets, reportedAverageBuckets, approximatedAverageBuckets
        case unknownUnitWindowsScope, hvacHistoryAvailable, occupancyKnownReadings, occupancyExpectedReadings
        case baselineDays, incompleteSensorInventory, unitAssumptions
        case averageIsApproximation = "averageIsApproximationWhenReportedUnavailable"
    }
}

struct PlacementDayWakeRoom: Decodable, Identifiable, Sendable {
    let sensorId: String
    let atSwitch: Double?
    let peak: Double?
    let peakAt: String?
    let overSetpoint: Double?

    var id: String { sensorId }
}

struct PlacementDayWakeContext: Decodable, Sendable {
    let from: String
    let end: String

    private enum CodingKeys: String, CodingKey {
        case from
        case end = "to"
    }
}

struct PlacementDayUnitAssumptions: Decodable, Sendable {
    let setpoints: Bool
    let reportedTemperature: Bool
}

enum PlacementDayCalendar {
    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func isValid(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let utc = TimeZone(secondsFromGMT: 0) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == parts[0] && resolved.month == parts[1] && resolved.day == parts[2]
    }

    static func date(_ value: String, in timeZone: TimeZone) -> Date? {
        guard isValid(value) else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == parts[0] && resolved.month == parts[1] && resolved.day == parts[2] ? date : nil
    }

    static func string(from date: Date, in timeZone: TimeZone) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func shifted(_ value: String, by days: Int, in timeZone: TimeZone) -> String? {
        guard let date = date(value, in: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return string(from: shifted, in: timeZone)
    }

    static func today(in timeZone: TimeZone, now: Date = Date()) -> String? {
        string(from: now, in: timeZone)
    }

    static func dateLabel(_ value: String, in timeZone: TimeZone) -> String {
        guard let date = date(value, in: timeZone) else { return value }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    static func dateTimeLabel(_ value: String?, in timeZone: TimeZone) -> String {
        guard let value, let date = PlacementInsights.isoDate(value) else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func timeLabel(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "h a z"
        return formatter.string(from: date)
    }
}

@MainActor
enum PlacementDayAPI {
    static func request(
        authorization: String,
        date: String?,
        config: PlacementConfig?
    ) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/climate/placement-insights/day"
        var queryItems: [URLQueryItem] = []
        if let date { queryItems.append(URLQueryItem(name: "date", value: date)) }
        queryItems.append(contentsOf: config?.queryItems ?? [])
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    static func decode(data: Data, response: URLResponse) throws -> PlacementDayInsights {
        guard let response = response as? HTTPURLResponse else { throw PlacementRequestError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            throw PlacementRequestError.http(response.statusCode)
        }
        return try JSONDecoder().decode(PlacementDayInsights.self, from: data)
    }

    static func isUnsupported(_ error: Error) -> Bool {
        guard let error = error as? PlacementRequestError, case .http(let status) = error else { return false }
        return status == 404 || status == 405
    }

    static func fetch(
        date: String?,
        config: PlacementConfig?,
        sessionCheck: @escaping SensorPlacementService.SessionCheck,
        authorization: @MainActor () -> String? = { AuthManager.shared.authorizationHeader() },
        hasOIDCToken: @MainActor () -> Bool = { AuthManager.shared.getAccessToken() != nil },
        ensureToken: @MainActor () async -> Bool = { await AuthManager.shared.ensureValidToken() },
        refreshToken: @MainActor () async -> Bool = { await AuthManager.shared.refreshTokenIfNeeded() },
        send: @MainActor (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) async throws -> PlacementDayInsights {
        func checkSession() throws {
            try Task.checkCancellation()
            guard sessionCheck() else { throw PlacementRequestError.sessionChanged }
        }

        try checkSession()
        if hasOIDCToken() {
            _ = await ensureToken()
            try checkSession()
        }
        guard let header = authorization() else { throw PlacementRequestError.unauthorized }
        try checkSession()
        var (data, response) = try await send(request(authorization: header, date: date, config: config))
        try checkSession()
        if (response as? HTTPURLResponse)?.statusCode == 401, hasOIDCToken() {
            let refreshed = await refreshToken()
            try checkSession()
            guard refreshed, let newHeader = authorization() else { throw PlacementRequestError.unauthorized }
            try checkSession()
            (data, response) = try await send(request(authorization: newHeader, date: date, config: config))
            try checkSession()
        }
        return try decode(data: data, response: response)
    }
}
