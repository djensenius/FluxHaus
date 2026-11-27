//
//  SensorPlacementTests.swift
//  FluxHaus Tests
//

import Foundation
import Observation
import Testing
@testable import FluxHaus

private let placementJSON = Data("""
{
  "generatedAt": "2026-03-20T12:00:00.000Z", "windowDays": 14, "unit": "°C",
  "coverage": {"start": "2026-03-06T12:00:00Z", "end": "2026-03-20T12:00:00Z",
    "hvacHistoryAvailable": true, "hvacEarliestStateAt": "2026-03-01T12:00:00Z",
    "returnHistoryAvailable": false, "morningEvents": 5, "inferredMorningEvents": 2, "returnEvents": 0,
    "unknownUnitWindows": 3},
  "sensors": [
    {"id": "bedroom", "name": "Bedroom", "isThermostat": false, "averageOffset": -0.5,
     "morningOffset": -1.2, "returnOffset": null, "overshoot": null, "sampleCount": 60,
     "classification": "cold"},
    {"id": "hall", "name": "Hall", "isThermostat": true, "averageOffset": null,
     "morningOffset": null, "returnOffset": 0.4, "overshoot": 0.8, "sampleCount": 1,
     "classification": "future-classification"}
  ],
  "recommendations": [
    {"id": "low", "severity": "low", "sensorId": null, "action": "none", "title": "Wait", "detail": "Observe."},
    {"id": "high", "severity": "high", "sensorId": "bedroom", "action": "move",
     "title": "Check", "detail": "Consider moving."}
  ]
}
""".utf8)

@MainActor
@Observable private final class PlacementTestSession {
    var id: String? = "original"
}

private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    func set() {
        lock.lock()
        defer { lock.unlock() }
        changed = true
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return changed
    }
}

@MainActor
struct SensorPlacementTests {
    private func insights() throws -> PlacementInsights {
        try JSONDecoder().decode(PlacementInsights.self, from: placementJSON)
    }

    private func response(_ status: Int) -> URLResponse {
        HTTPURLResponse(url: URL(string: "https://api.fluxhaus.io")!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    @Test("The endpoint decodes coverage provenance, nullable fields and future classifications")
    func decoding() throws {
        let result = try insights()
        #expect(result.windowDays == 14)
        #expect(result.unit == "°C")
        #expect(result.coverage.hvacEarliestStateAt == "2026-03-01T12:00:00Z")
        #expect(result.coverage.unknownUnitWindows == 3)
        #expect(result.coverage.returnHistoryAvailable == false)
        #expect(result.coverage.returnEvents == 0)
        #expect(result.coverage.detectedReturnEvents == nil)
        #expect(result.coverage.morningEvents == 5)
        #expect(result.coverage.inferredMorningEvents == 2)
        #expect(result.coverage.observedMorningEvents == 3)
        #expect(result.sensors.first?.morningOffset == -1.2)
        #expect(result.sensors.first?.returnOffset == nil)
        #expect(result.sensors.first?.overshoot == nil)
        #expect(result.sensors.last?.isThermostat == true)
        #expect(result.sensors.last?.classificationLabel == "Unknown")
        #expect(result.rankedRecommendations.map(\.id) == ["high", "low"])
        #expect(result.recommendations.first?.sensorId == nil)
    }

    @Test("Malformed and incomplete contract responses are rejected; additions remain optional")
    func requiredFields() throws {
        for invalid in ["{}", "{\"sensors\":[],\"recommendations\":[]}"] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(PlacementInsights.self, from: Data(invalid.utf8))
            }
        }
        let original = try #require(String(data: placementJSON, encoding: .utf8))
        let missingOffset = original.replacingOccurrences(of: "\"returnOffset\": null,", with: "")
        let missingSensorID = original.replacingOccurrences(of: "\"sensorId\": null,", with: "")
        let badDate = original.replacingOccurrences(of: "2026-03-20T12:00:00.000Z", with: "not-a-date")
        let badUnits = original.replacingOccurrences(of: "\"unknownUnitWindows\": 3", with: """
        "unknownUnitWindows": -1
        """)
        let badInference = original.replacingOccurrences(of: "\"inferredMorningEvents\": 2", with: """
        "inferredMorningEvents": 6
        """)
        for invalid in [missingOffset, missingSensorID, badDate, badInference, badUnits] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(PlacementInsights.self, from: Data(invalid.utf8))
            }
        }
        let legacy = original
            .replacingOccurrences(of: "\"hvacEarliestStateAt\": \"2026-03-01T12:00:00Z\",", with: "")
            .replacingOccurrences(of: "\"returnHistoryAvailable\": false,", with: "")
            .replacingOccurrences(of: "\"inferredMorningEvents\": 2,", with: "")
            .replacingOccurrences(of: ",\n    \"unknownUnitWindows\": 3", with: "")
            .replacingOccurrences(of: "\"returnEvents\": 0", with: "\"returnEvents\": 0, \"futureField\": true")
        let decoded = try JSONDecoder().decode(PlacementInsights.self, from: Data(legacy.utf8))
        #expect(decoded.coverage.hvacEarliestStateAt == nil)
        #expect(decoded.coverage.unknownUnitWindows == nil)
        #expect(decoded.coverage.returnHistoryAvailable == nil)
        #expect(decoded.coverage.inferredMorningEvents == nil)
        #expect(decoded.coverage.observedMorningEvents == nil)
        #expect(decoded.coverage.detectedReturnEvents == nil)
        let available = original
            .replacingOccurrences(of: "\"returnHistoryAvailable\": false", with: "\"returnHistoryAvailable\": true")
            .replacingOccurrences(of: "\"hvacEarliestStateAt\": \"2026-03-01T12:00:00Z\"", with: """
            "hvacEarliestStateAt": null
            """)
        let availableResult = try JSONDecoder().decode(PlacementInsights.self, from: Data(available.utf8))
        #expect(availableResult.coverage.detectedReturnEvents == 0)
        #expect(availableResult.coverage.hvacEarliestStateAt == nil)
    }

    @Test("Gap-only HVAC history does not imply observable returns")
    func gapOnlyHistory() throws {
        let original = try #require(String(data: placementJSON, encoding: .utf8))
        let gapOnly = original
            .replacingOccurrences(of: "\"hvacHistoryAvailable\": true", with: "\"hvacHistoryAvailable\": false")
            .replacingOccurrences(of: "\"hvacEarliestStateAt\": \"2026-03-01T12:00:00Z\"", with: """
            "hvacEarliestStateAt": null
            """)
            .replacingOccurrences(of: "\"unknownUnitWindows\": 3", with: "\"unknownUnitWindows\": 0")
            .replacingOccurrences(of: "\"returnOffset\": 0.4", with: "\"returnOffset\": null")
            .replacingOccurrences(of: "\"overshoot\": 0.8", with: "\"overshoot\": null")
        let result = try JSONDecoder().decode(PlacementInsights.self, from: Data(gapOnly.utf8))
        #expect(!result.coverage.hvacHistoryAvailable)
        #expect(result.coverage.hvacEarliestStateAt == nil)
        #expect(result.coverage.returnHistoryAvailable == false)
        #expect(result.coverage.detectedReturnEvents == nil)
        #expect(result.coverage.unknownUnitWindows == 0)
        for sensor in result.sensors {
            #expect(sensor.returnOffset == nil)
            #expect(sensor.overshoot == nil)
            #expect(SensorPlacementView.offset(sensor.returnOffset, unit: result.unit) == "Unavailable")
            #expect(SensorPlacementView.offset(sensor.overshoot, unit: result.unit) == "Unavailable")
        }
    }

    @Test("Empty recommendations are successful, not an endpoint error")
    func emptyRecommendations() throws {
        let original = try #require(String(data: placementJSON, encoding: .utf8))
        let start = try #require(original.range(of: "\"recommendations\": ["))
        let empty = String(original[..<start.lowerBound]) + "\"recommendations\": []}"
        let decoded = try JSONDecoder().decode(PlacementInsights.self, from: Data(empty.utf8))
        #expect(decoded.recommendations.isEmpty)
    }

    @Test("Request uses the 14-day endpoint and supplied authentication")
    func request() throws {
        let request = SensorPlacementService.request(authorization: "Bearer example")
        #expect(request.url?.absoluteString == "https://api.fluxhaus.io/climate/placement-insights?days=14")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer example")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(throws: PlacementRequestError.self) {
            try SensorPlacementService.decode(data: placementJSON, response: response(503))
        }
    }

    @Test("Loading is on demand and a failure can be retried")
    func retry() async throws {
        var calls = 0
        let result = try insights()
        let service = SensorPlacementService(sessionCheck: { true }, fetch: { _ in
            calls += 1
            if calls == 1 { throw PlacementRequestError.http(503) }
            return result
        })
        #expect(calls == 0)
        await service.refresh()
        #expect(service.error == "Could not load sensor placement (HTTP 503).")
        #expect(service.insights == nil)
        await service.refresh()
        #expect(calls == 2)
        #expect(service.error == nil)
        #expect(service.insights != nil)
    }

    @Test("Sign-out and account replacement hide cached data and discard late completions")
    func sessionChanges() async throws {
        let result = try insights()
        for replacement in [nil, "another-account"] as [String?] {
            let session = PlacementTestSession()
            let origin = session.id
            var continuation: CheckedContinuation<PlacementInsights, Never>?
            var calls = 0
            let service = SensorPlacementService(insights: result, sessionCheck: { session.id == origin }, fetch: { _ in
                calls += 1
                return await withCheckedContinuation { continuation = $0 }
            })
            let task = Task { await service.refresh() }
            while continuation == nil { await Task.yield() }
            session.id = replacement
            #expect(!service.isSessionValid)
            #expect(service.insights == nil)
            continuation?.resume(returning: result)
            await task.value
            #expect(service.insights == nil)
            #expect(service.error == nil)
            await service.refresh()
            #expect(calls == 1)
        }
    }

    @Test("The screen observes a session replacement")
    func sessionObservation() {
        let session = PlacementTestSession()
        let origin = session.id
        let service = SensorPlacementService(sessionCheck: { session.id == origin })
        let flag = ObservationFlag()
        withObservationTracking {
            _ = service.isSessionValid
        } onChange: {
            flag.set()
        }
        session.id = "new"
        #expect(flag.value)
        #expect(!service.isSessionValid)
    }

    @Test("A cancelled request cannot publish a result or an error")
    func cancellation() async throws {
        let result = try insights()
        let service = SensorPlacementService(sessionCheck: { true }, fetch: { _ in
            try? await Task.sleep(for: .seconds(30))
            return result
        })
        let task = Task { await service.refresh() }
        while !service.isLoading { await Task.yield() }
        task.cancel()
        await task.value
        #expect(service.insights == nil)
        #expect(service.error == nil)
        #expect(!service.isLoading)
    }

    @Test("A replacement load runs while the cancelled load is still unwinding")
    func overlappingCancellation() async throws {
        let result = try insights()
        let json = try #require(String(data: placementJSON, encoding: .utf8))
        let stale = try JSONDecoder().decode(
            PlacementInsights.self, from: Data(json.replacingOccurrences(of: "\"windowDays\": 14",
                                                                          with: "\"windowDays\": 30").utf8)
        )
        var continuations: [CheckedContinuation<PlacementInsights, Never>] = []
        let service = SensorPlacementService(sessionCheck: { true }, fetch: { _ in
            await withCheckedContinuation { continuations.append($0) }
        })
        let first = Task { await service.refresh() }
        while continuations.count < 1 { await Task.yield() }
        first.cancel()

        let second = Task { await service.refresh() }
        while continuations.count < 2 { await Task.yield() }
        #expect(service.isLoading)
        continuations[0].resume(returning: result)
        await first.value
        #expect(service.isLoading)
        #expect(service.insights == nil)

        continuations[1].resume(returning: result)
        await second.value
        #expect(!service.isLoading)
        #expect(service.insights != nil)
        #expect(service.error == nil)

        let third = Task { await service.refresh() }
        while continuations.count < 3 { await Task.yield() }
        third.cancel()
        let fourth = Task { await service.refresh() }
        while continuations.count < 4 { await Task.yield() }
        continuations[3].resume(returning: result)
        await fourth.value
        continuations[2].resume(returning: stale)
        await third.value
        #expect(service.insights?.windowDays == 14)
        #expect(!service.isLoading)
    }

    @Test("OIDC 401 refreshes once and retries with the refreshed token")
    func oidcRetry() async throws {
        var token = "Bearer old"
        var headers: [String] = []
        var ensures = 0
        var refreshes = 0
        let result = try await SensorPlacementService.fetchInsights(
            sessionCheck: { true }, authorization: { token }, hasOIDCToken: { true },
            ensureToken: { ensures += 1; return true },
            refreshToken: { refreshes += 1; token = "Bearer refreshed"; return true },
            send: { request in
                headers.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                return (placementJSON, response(headers.count == 1 ? 401 : 200))
            }
        )
        #expect(result.windowDays == 14)
        #expect(ensures == 1)
        #expect(refreshes == 1)
        #expect(headers == ["Bearer old", "Bearer refreshed"])
    }

    @Test("Account replacement before or during refresh never retries with the new credentials")
    func noCrossSessionRetry() async {
        for switchBeforeRefresh in [true, false] {
            let session = PlacementTestSession()
            let origin = session.id
            var token = "Bearer old"
            var headers: [String] = []
            var refreshes = 0
            await #expect(throws: PlacementRequestError.self) {
                try await SensorPlacementService.fetchInsights(
                    sessionCheck: { session.id == origin }, authorization: { token }, hasOIDCToken: { true },
                    ensureToken: { true },
                    refreshToken: {
                        refreshes += 1
                        session.id = "new"
                        token = "Bearer new"
                        return true
                    },
                    send: { request in
                        headers.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                        if switchBeforeRefresh {
                            session.id = "new"
                            token = "Bearer new"
                        }
                        return (placementJSON, response(401))
                    }
                )
            }
            #expect(headers == ["Bearer old"])
            #expect(refreshes == (switchBeforeRefresh ? 0 : 1))
        }
    }

    @Test("An account switch during proactive refresh sends no placement request")
    func switchDuringPreflight() async {
        let session = PlacementTestSession()
        let origin = session.id
        var sends = 0
        await #expect(throws: PlacementRequestError.self) {
            try await SensorPlacementService.fetchInsights(
                sessionCheck: { session.id == origin }, authorization: { "Bearer new" }, hasOIDCToken: { true },
                ensureToken: { session.id = "new"; return true },
                refreshToken: { true },
                send: { _ in sends += 1; return (placementJSON, response(200)) }
            )
        }
        #expect(sends == 0)
    }

    @Test("Demo 401 does not attempt an OIDC refresh or retry")
    func demoUnauthorized() async {
        var sends = 0
        var refreshes = 0
        await #expect(throws: PlacementRequestError.self) {
            try await SensorPlacementService.fetchInsights(
                sessionCheck: { true }, authorization: { "Basic demo" }, hasOIDCToken: { false },
                ensureToken: { true },
                refreshToken: { refreshes += 1; return true },
                send: { _ in sends += 1; return (placementJSON, response(401)) }
            )
        }
        #expect(sends == 1)
        #expect(refreshes == 0)
    }

    @Test("A malformed successful HTTP response is surfaced as an error")
    func malformedSuccess() async {
        let service = SensorPlacementService(sessionCheck: { true }, fetch: { check in
            try await SensorPlacementService.fetchInsights(
                sessionCheck: check, authorization: { "Basic demo" }, hasOIDCToken: { false },
                send: { _ in (Data("{}".utf8), response(200)) }
            )
        })
        await service.refresh()
        #expect(service.insights == nil)
        #expect(service.error != nil)
    }
}
