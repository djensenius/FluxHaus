//
//  SensorPlacementTests.swift
//  FluxHaus Tests
//

import Foundation
import Testing
@testable import FluxHaus

private let placementJSON = Data("""
{
  "generatedAt": "2026-03-20T12:00:00.000Z", "windowDays": 14, "unit": "°C",
  "coverage": {"start": "2026-03-06T12:00:00Z", "end": "2026-03-20T12:00:00Z",
    "hvacHistoryAvailable": false, "morningEvents": 5, "returnEvents": 2},
  "sensors": [
    {"id": "bedroom", "name": "Bedroom", "isThermostat": false, "averageOffset": -0.5,
     "morningOffset": -1.2, "returnOffset": null, "overshoot": 0.8, "sampleCount": 60,
     "classification": "cold"},
    {"id": "hall", "name": "Hall", "isThermostat": true, "averageOffset": null,
     "morningOffset": null, "returnOffset": 0.4, "overshoot": null, "sampleCount": 1,
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
struct SensorPlacementTests {
    @Test("The endpoint contract decodes null offsets, coverage and future classifications")
    func decoding() throws {
        let result = try JSONDecoder().decode(PlacementInsights.self, from: placementJSON)
        #expect(result.windowDays == 14)
        #expect(result.unit == "°C")
        #expect(result.coverage?.hvacHistoryAvailable == false)
        #expect(result.coverage?.morningEvents == 5)
        #expect(result.coverage?.returnEvents == 2)
        #expect(result.sensors?.first?.morningOffset == -1.2)
        #expect(result.sensors?.first?.returnOffset == nil)
        #expect(result.sensors?.last?.isThermostat == true)
        #expect(result.sensors?.last?.classificationLabel == "Unknown")
        #expect(result.rankedRecommendations.map(\.id) == ["high", "low"])
        #expect(result.recommendations?.first?.sensorId == nil)
    }

    @Test("Partial data and an empty recommendation list remain distinct")
    func partial() throws {
        let missing = try JSONDecoder().decode(PlacementInsights.self, from: Data("{}".utf8))
        let empty = try JSONDecoder().decode(
            PlacementInsights.self,
            from: Data("{\"coverage\":{\"futureField\":true},\"sensors\":[],\"recommendations\":[]}".utf8)
        )
        #expect(missing.coverage == nil)
        #expect(missing.recommendations == nil)
        #expect(empty.recommendations?.isEmpty == true)
        #expect(empty.sensors?.isEmpty == true)
        #expect(empty.coverage?.hvacHistoryAvailable == nil)
    }

    @Test("Request uses the 14-day endpoint and supplied authentication")
    func request() throws {
        let request = SensorPlacementService.request(authorization: "Bearer example")
        #expect(request.url?.absoluteString == "https://api.fluxhaus.io/climate/placement-insights?days=14")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer example")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil))
        #expect(throws: PlacementRequestError.self) {
            try SensorPlacementService.decode(data: placementJSON, response: response)
        }
    }

    @Test("Loading is on demand; failures can be retried without treating empty data as an error")
    func retry() async throws {
        var calls = 0
        let empty = try JSONDecoder().decode(
            PlacementInsights.self, from: Data("{\"sensors\":[],\"recommendations\":[]}".utf8)
        )
        let service = SensorPlacementService {
            calls += 1
            if calls == 1 { throw PlacementRequestError.http(503) }
            return empty
        }
        #expect(calls == 0)
        await service.refresh()
        #expect(service.error == "Could not load sensor placement (HTTP 503).")
        #expect(service.insights == nil)
        await service.refresh()
        #expect(calls == 2)
        #expect(service.error == nil)
        #expect(service.insights?.recommendations?.isEmpty == true)
    }

    @Test("A cancelled request cannot publish a result or an error")
    func cancellation() async throws {
        let result = try JSONDecoder().decode(PlacementInsights.self, from: placementJSON)
        let service = SensorPlacementService {
            // Deliberately ignore cancellation, simulating a late network completion.
            try? await Task.sleep(for: .seconds(30))
            return result
        }
        let task = Task { await service.refresh() }
        while !service.isLoading { await Task.yield() }
        task.cancel()
        await task.value
        #expect(service.insights == nil)
        #expect(service.error == nil)
        #expect(!service.isLoading)
    }
}
