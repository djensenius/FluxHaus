//
//  WidgetData.swift
//  FluxWidget
//
//  Fetching, caching, and derived state shared by the FluxHaus widgets.
//

import Foundation
import os

private let widgetLogger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Widget")

/// Car state as shown by the widgets.
struct CarSnapshot: Codable, Equatable {
    var battery: Int
    var range: Int
    var locked: Bool
    var climateOn: Bool
    var pluggedIn: Bool
    var charging: Bool
    var openings: [String]

    init(details: CarDetails) {
        battery = details.batteryLevel
        range = details.distance
        locked = details.locked
        climateOn = details.hvac
        pluggedIn = details.pluggedIn
        charging = details.batteryCharge
        var open: [String] = []
        let doors = details.doorsOpen
        if doors.frontLeft != 0 || doors.frontRight != 0 || doors.backLeft != 0 || doors.backRight != 0 {
            open.append("Door")
        }
        if details.trunkOpen { open.append("Trunk") }
        if details.hoodOpen { open.append("Hood") }
        openings = open
    }

    init(battery: Int, range: Int, locked: Bool, climateOn: Bool, pluggedIn: Bool, charging: Bool) {
        self.battery = battery
        self.range = range
        self.locked = locked
        self.climateOn = climateOn
        self.pluggedIn = pluggedIn
        self.charging = charging
        self.openings = []
    }
}

/// Everything the widgets know about the house at one moment.
struct FluxSnapshot: Codable {
    var fetchedAt: Date
    var devices: [WidgetDevice]
    var car: CarSnapshot?
    /// When each appliance was last seen to finish (device name → date).
    var finishedAt: [String: Date]
}

/// Coalesces concurrent fetches for the same auth session (several widgets and controls
/// often refresh together) without suppressing later, separately requested refreshes.
private actor SnapshotFetcher {
    private var inFlight: [String: (id: UUID, task: Task<FluxSnapshot?, Never>)] = [:]

    func fetch(session: String) async -> FluxSnapshot? {
        if let existing = inFlight[session] { return await existing.task.value }
        let id = UUID()
        let task = Task { await FluxWidgetNetwork.performFetch(session: session) }
        inFlight[session] = (id, task)
        let result = await task.value
        // Only clear our own record, never a newer request's.
        if inFlight[session]?.id == id { inFlight[session] = nil }
        return result
    }
}

enum FluxWidgetNetwork {
    private static let cacheKey = "FluxWidget.snapshot"
    private static let fetcher = SnapshotFetcher()

    /// Fetches the latest snapshot. Never crashes: on any auth/network/decoding failure
    /// it falls back to the last good snapshot for the same session. Nil when signed out.
    static func fetchSnapshot() async -> FluxSnapshot? {
        guard let session = await WidgetCache.currentSession() else {
            // Signed out: never show the previous session's data.
            widgetLogger.warning("Widget: no credentials available")
            WidgetCache.clear(key: cacheKey)
            return nil
        }
        return await fetcher.fetch(session: session)
    }

    fileprivate static func performFetch(session: String) async -> FluxSnapshot? {
        let cached = WidgetCache.load(FluxSnapshot.self, key: cacheKey, session: session)
        do {
            guard let response = try await getFlux(password: WhereWeAre.getPassword() ?? ""),
                  WidgetCache.isCurrent(session) else {
                return WidgetCache.load(FluxSnapshot.self, key: cacheKey, session: session)
            }
            let snapshot = makeSnapshot(from: response, previous: cached)
            WidgetCache.save(snapshot, key: cacheKey, session: session)
            return snapshot
        } catch {
            widgetLogger.error("Widget: fetch failed: \(error.localizedDescription)")
            return WidgetCache.load(FluxSnapshot.self, key: cacheKey, session: session)
        }
    }

    static func makeSnapshot(
        from response: LoginResponse,
        previous: FluxSnapshot?,
        now: Date = Date()
    ) -> FluxSnapshot {
        let fluxData = convertLoginResponseToAppData(response: response)
        let devices = classifyWidgetData(devices: convertDataToWidgetDevices(fluxData: fluxData))
        var finishedAt = previous?.finishedAt ?? [:]
        let wasRunning = Set((previous?.devices ?? []).filter(isActive).map(\.name))
        for device in devices where device.name != "Car" {
            if device.running {
                finishedAt[device.name] = nil
            } else if wasRunning.contains(device.name) {
                finishedAt[device.name] = now
            }
        }
        return FluxSnapshot(
            fetchedAt: now,
            devices: devices,
            car: fluxData.car.map(CarSnapshot.init(details:)),
            finishedAt: finishedAt
        )
    }

    static func classifyWidgetData(devices: [WidgetDevice]) -> [WidgetDevice] {
        var constantDevices: [WidgetDevice] = []
        var timedRunningDevices: [WidgetDevice] = []
        var runningDevices: [WidgetDevice] = []
        var offDevices: [WidgetDevice] = []

        devices.forEach { device in
            switch device.name {
            case "Car", "Battery":
                constantDevices.append(device)
            case "Cleanbot":
                if device.running, device.endsAt != nil {
                    // A cleaning run with an estimated end competes with the appliances.
                    timedRunningDevices.append(device)
                } else if device.running {
                    runningDevices.append(device)
                } else {
                    offDevices.append(device)
                }
            default:
                if device.running {
                    timedRunningDevices.append(device)
                } else {
                    offDevices.append(device)
                }
            }
        }
        return sortTimedDevices(devices: timedRunningDevices) + runningDevices + constantDevices + offDevices
    }

    /// Soonest to finish first: devices with a known end time (earliest first), then the
    /// rest by most progressed. Two separate orders keep the comparison transitive.
    static func sortTimedDevices(devices: [WidgetDevice]) -> [WidgetDevice] {
        let timed = devices.filter { $0.endsAt != nil }.sorted { ($0.endsAt ?? 0) < ($1.endsAt ?? 0) }
        let untimed = devices.filter { $0.endsAt == nil }.sorted { $0.progress > $1.progress }
        return timed + untimed
    }

    /// Refresh more often while an appliance is running and back off when idle to
    /// preserve the WidgetKit budget. Also re-fetch shortly after a cycle should end.
    static func nextRefresh(for devices: [WidgetDevice], from date: Date) -> Date {
        let minutes = devices.contains(where: isActive) ? 15 : 30
        var next = date.addingTimeInterval(TimeInterval(minutes * 60))
        if let soonestEnd = devices.compactMap(\.endDate).filter({ $0 > date }).min() {
            next = min(next, soonestEnd.addingTimeInterval(120))
        }
        return next
    }

    /// Moments the rendering changes without new data: when a cycle reaches its expected
    /// end, plus every 5 minutes while timed cycles run so gauges that can't animate on
    /// their own (circular complications) keep advancing.
    static func transitionDates(for devices: [WidgetDevice], from date: Date, until end: Date) -> [Date] {
        let timed = devices.filter { $0.running && $0.endDate != nil }
        var dates = Set(timed.compactMap(\.endDate))
        if !timed.isEmpty {
            var next = date.addingTimeInterval(300)
            while next < end {
                dates.insert(next)
                next = next.addingTimeInterval(300)
            }
        }
        return dates.filter { $0 > date && $0 < end }.sorted()
    }
}

/// A device that is doing something right now (excludes always-on constants like Car).
func isActive(_ device: WidgetDevice) -> Bool {
    device.running && device.name != "Car" && device.name != "Battery"
}
