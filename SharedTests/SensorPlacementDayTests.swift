//
//  SensorPlacementDayTests.swift
//  FluxHaus Tests
//

import Foundation
import Testing
@testable import FluxHaus

private let placementDayJSON = Data("""
{
  "date": "2026-03-08", "timeZone": "America/Toronto", "unit": "°C",
  "timeline": [
    {"t": "2026-03-08T06:00:00-04:00", "setpoint": 20, "hvacAction": "heating",
     "hvacMode": "heat", "comfortSetting": "sleep", "average": 19,
     "rooms": {"bedroom": 18, "living": 19}, "occupied": {"bedroom": true}},
    {"t": "2026-03-08T06:15:00-04:00", "setpoint": 20, "hvacAction": "heating",
     "hvacMode": "heat", "comfortSetting": "sleep", "average": 19,
     "rooms": {"bedroom": null, "living": 19.2}, "occupied": {"bedroom": null}},
    {"t": "2026-03-08T06:30:00-04:00", "setpoint": 20, "hvacAction": "idle",
     "hvacMode": "heat", "comfortSetting": "home", "average": 19.1,
     "rooms": {"bedroom": 18.3, "living": 19.4}, "occupied": {"bedroom": false}},
    {"t": "2026-03-08T06:45:00-04:00", "setpoint": 20, "hvacAction": null,
     "hvacMode": "heat", "comfortSetting": "home", "average": null,
     "rooms": {"bedroom": 18.5, "living": 19.5}, "occupied": {"bedroom": false}},
    {"t": "2026-03-08T07:00:00-04:00", "setpoint": 20, "hvacAction": "idle",
     "hvacMode": "heat", "comfortSetting": "home", "average": 19.3,
     "rooms": {"bedroom": 18.7, "living": 19.6}, "occupied": {"bedroom": true}}
  ],
  "wake": {
    "at": "2026-03-08T06:30:00-04:00", "setpointBefore": 19, "setpointAfter": 20,
    "heatingMinutes": 30, "coolingMinutes": null, "unknownMinutes": 15,
    "contextComplete": false, "contextRetryable": true,
    "rooms": [{"sensorId": "bedroom", "atSwitch": 18.3, "peak": 18.7,
      "peakAt": "2026-03-08T07:00:00-04:00", "overSetpoint": null}],
    "context": {"from": "2026-03-08T06:00:00-04:00", "to": "2026-03-08T07:00:00-04:00"}
  },
  "sensors": [
    {"id": "bedroom", "name": "Bedroom", "isThermostat": false,
     "dayOffset": -1.2, "baselineOffset": -0.5, "deviation": -0.7, "unusual": null},
    {"id": "living", "name": "Living Room", "isThermostat": false,
     "dayOffset": 0.1, "baselineOffset": 0.2, "deviation": -0.1, "unusual": false}
  ],
  "findings": [{"id": "bedroom-cold", "severity": "medium", "title": "Bedroom ran colder",
    "detail": "The bedroom sensor was colder than its recent baseline.", "sensorIds": ["bedroom"]}],
  "coverage": {
    "start": "2026-03-08T00:00:00-05:00", "end": "2026-03-09T00:00:00-04:00",
    "expectedBuckets": 92, "completeBuckets": 90, "missingRoomReadings": 2,
    "unknownUnitWindows": 1, "missingHvacBuckets": 3, "missingAverageBuckets": 1,
    "reportedAverageBuckets": 89, "approximatedAverageBuckets": 1,
    "unknownUnitWindowsScope": "selected date, baseline and wake-context query", "hvacHistoryAvailable": true,
    "occupancyKnownReadings": 3, "occupancyExpectedReadings": 5, "baselineDays": 14,
    "incompleteSensorInventory": false,
    "unitAssumptions": {"setpoints": true, "reportedTemperature": true},
    "averageIsApproximationWhenReportedUnavailable": true
  }
}
""".utf8)

@MainActor
struct SensorPlacementDayTests {
    private func insights(from data: Data = placementDayJSON) throws -> PlacementDayInsights {
        try JSONDecoder().decode(PlacementDayInsights.self, from: data)
    }

    private func response(_ status: Int) -> URLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.fluxhaus.io/climate/placement-insights/day")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    @Test("Day analysis keeps null evidence unknown and validates the server's house date")
    func decodingAndValidation() throws {
        let day = try insights()
        #expect(day.date == "2026-03-08")
        #expect(day.timeZone == "America/Toronto")
        #expect(day.timeline[1].rooms.keys.contains("bedroom"))
        let missingRoomValue = try #require(day.timeline[1].rooms["bedroom"])
        #expect(missingRoomValue == nil)
        #expect(day.wake?.coolingMinutes == nil)
        #expect(day.wake?.rooms.first?.overSetpoint == nil)
        #expect(day.sensors.first?.unusual == nil)
        #expect(day.coverage.completeBuckets == 90)
        #expect(day.coverage.unitAssumptionNotices.count == 2)

        let source = try #require(String(data: placementDayJSON, encoding: .utf8))
        for invalid in [
            source.replacingOccurrences(of: "2026-03-08", with: "2026-02-30"),
            source.replacingOccurrences(of: "America/Toronto", with: "Not/A_Timezone"),
            source.replacingOccurrences(of: "\"completeBuckets\": 90", with: "\"completeBuckets\": 93"),
            source.replacingOccurrences(of: "\"unknownMinutes\": 15", with: "\"unknownMinutes\": -1")
        ] {
            #expect(throws: DecodingError.self) {
                try insights(from: Data(invalid.utf8))
            }
        }
    }

    @Test("House-calendar navigation crosses DST without using elapsed 24-hour days")
    func houseCalendarDST() throws {
        let zone = try #require(TimeZone(identifier: "America/Toronto"))
        let marchSeven = try #require(PlacementDayCalendar.date("2026-03-07", in: zone))
        let marchEight = try #require(PlacementDayCalendar.date("2026-03-08", in: zone))
        #expect(PlacementDayCalendar.shifted("2026-03-07", by: 1, in: zone) == "2026-03-08")
        #expect(PlacementDayCalendar.shifted("2026-03-08", by: -1, in: zone) == "2026-03-07")
        #expect(marchEight.timeIntervalSince(marchSeven) == 23 * 60 * 60)
        #expect(PlacementDayCalendar.shifted("2026-03-08", by: -364, in: zone) == "2025-03-09")
        let octoberThirtyOne = try #require(PlacementDayCalendar.date("2026-10-31", in: zone))
        let novemberFirst = try #require(PlacementDayCalendar.date("2026-11-01", in: zone))
        #expect(novemberFirst.timeIntervalSince(octoberThirtyOne) == 25 * 60 * 60)
        #expect(PlacementDayCalendar.isValid("2024-02-29"))
        #expect(!PlacementDayCalendar.isValid("2026-02-29"))
    }

    @Test("Interval labels preserve minutes in the house time zone")
    func intervalTimeLabel() throws {
        let zone = try #require(TimeZone(identifier: "America/Toronto"))
        let date = try #require(PlacementInsights.isoDate("2026-03-08T06:05:00-04:00"))
        #expect(PlacementDayCalendar.intervalTimeLabel(date, in: zone).contains(":05"))
    }

    @Test("Bootstrap omits the phone date and carries the saved room and thermostat choices")
    func requestUsesSavedConfig() throws {
        let config = PlacementConfig(
            home: ["living", "bedroom"], sleep: ["bedroom"], away: [],
            followMe: true, thermostatHome: false, thermostatSleep: nil, thermostatAway: true
        )
        let request = PlacementDayAPI.request(authorization: "Bearer token", date: nil, config: config)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(components.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })
        #expect(values["date"] == nil)
        #expect(values["home"] == "bedroom,living")
        #expect(values["sleep"] == "bedroom")
        #expect(values["away"] == "")
        #expect(values["followMe"] == "true")
        #expect(values["thermostatHome"] == "false")
        #expect(values["thermostatSleep"] == nil)
        #expect(values["thermostatAway"] == "true")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test("Authentication refresh retries the day request with the saved setup")
    func authenticationRetry() async throws {
        let config = PlacementConfig.allIncluded(["bedroom"])
        var token = "Bearer old"
        var requests: [URLRequest] = []
        let result = try await PlacementDayAPI.fetch(
            date: nil,
            config: config,
            sessionCheck: { true },
            authorization: { token },
            hasOIDCToken: { true },
            ensureToken: { true },
            refreshToken: {
                token = "Bearer new"
                return true
            },
            send: { request in
                requests.append(request)
                let status = requests.count == 1 ? 401 : 200
                return (placementDayJSON, self.response(status))
            }
        )
        #expect(result.date == "2026-03-08")
        #expect(requests.count == 2)
        let authorization = requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(authorization == ["Bearer old", "Bearer new"])
        #expect(requests.allSatisfy { $0.url?.absoluteString.contains("bedroom") == true })
    }

    @Test("Day requests retry with fresh discovery and pruned saved choices")
    func unavailableSavedRoomFallback() async throws {
        let config = PlacementConfig.allIncluded(["bedroom", "missing"])
        let snapshot = PlacementConfigSnapshot(config: config, revision: "saved")
        var requests: [PlacementConfig?] = []
        let outcome = try await SensorPlacementService.loadDay(
            date: "2026-03-08",
            config: config,
            snapshot: snapshot,
            sessionCheck: { true },
            fetch: { _, requestConfig, _ in
                requests.append(requestConfig)
                if requestConfig == config { throw PlacementRequestError.http(400) }
                return try self.insights()
            }
        )
        #expect(requests == [config, nil, .allIncluded(["bedroom"])])
        #expect(outcome.notice == SensorPlacementService.reducedConfigNotice)
        #expect(outcome.snapshot == snapshot)
    }

    @Test("Older servers produce an explicit unsupported-capability state")
    func unsupportedStatus() throws {
        for status in [404, 405] {
            do {
                _ = try PlacementDayAPI.decode(data: Data(), response: response(status))
                Issue.record("Expected HTTP \(status) to be rejected")
            } catch {
                #expect(PlacementDayAPI.isUnsupported(error))
            }
        }
        #expect(!PlacementDayAPI.isUnsupported(PlacementRequestError.http(503)))
    }

    @Test("Chart segments break at missing readings and long data gaps")
    func chartGaps() throws {
        let day = try insights()
        let segments = PlacementDayChartBuilder.segments(for: day).filter { $0.id.hasPrefix("bedroom-") }
        #expect(segments.count == 2)
        #expect(segments.map { $0.points.count } == [1, 2])
        #expect(segments[0].points.first?.value == 18)
        #expect(segments[1].points.first?.value == 18.3)

        let dates = day.timeline.compactMap(\.date)
        let longGap = PlacementDayChartBuilder.split(
            seriesID: "test", name: "Test", times: [dates[0], dates[2]], values: [18, 19]
        )
        #expect(longGap.count == 2)
    }

    @Test("Chart series retain unique IDs when sensor display names collide")
    func duplicateSensorNames() throws {
        let source = try #require(String(data: placementDayJSON, encoding: .utf8))
        let day = try insights(from: Data(source.replacingOccurrences(of: "Living Room", with: "Bedroom").utf8))
        let segments = PlacementDayChartBuilder.segments(for: day)
        let roomSegments = segments.filter { $0.seriesID == "bedroom" || $0.seriesID == "living" }
        #expect(Set(roomSegments.map(\.seriesID)) == ["bedroom", "living"])
        #expect(Set(roomSegments.map(\.name)) == ["Bedroom (bedroom)", "Bedroom (living)"])

        let colors = MetricSeriesPalette.colorMap(
            forSeries: [("bedroom", "Bedroom"), ("living", "Bedroom")]
        )
        #expect(Set(colors.keys) == ["bedroom", "living"])
        #expect(colors["bedroom"] != colors["living"])

        let occupancyNames = PlacementDayChartBuilder.contextBands(for: day)
            .filter { $0.kind == .occupancy }
            .map(\.trackName)
        #expect(Set(occupancyNames) == ["Bedroom (bedroom) occupancy", "Bedroom (living) occupancy"])
    }

    @Test("Wake chart context bands align HVAC, comfort, and occupancy while preserving unknown")
    func chartContextBands() throws {
        let day = try insights()
        let bands = PlacementDayChartBuilder.contextBands(for: day)
        #expect(bands.filter { $0.kind == .hvac }.map(\.value) == ["Heating", "Heating", "Idle", "Unknown"])
        #expect(bands.filter { $0.kind == .comfort }.map(\.value) == ["Sleep", "Sleep", "Home", "Home"])
        #expect(bands.filter { $0.id.hasPrefix("occupancy-bedroom-") }.map(\.value)
                == ["Occupied", "Unknown", "Unoccupied", "Unoccupied"])
        #expect(bands.allSatisfy { $0.end > $0.start })
    }
}
