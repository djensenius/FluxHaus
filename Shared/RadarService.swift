//
//  RadarService.swift
//  FluxHaus
//
//  Created by Copilot on 2026-03-08.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "RadarService")

struct RadarFrame: Identifiable {
    let id: Int
    let time: Int
    let path: String
}

/// URL builder for radar tiles: (framePath, zoom, col, row) -> URL?
typealias TileURLBuilder = (String, Int, Int, Int) -> URL?

/// Response from FluxHaus server's /api/radar/config endpoint.
/// Server fetches Rainbow.ai snapshot and returns tile URL template.
private struct RadarConfig: Decodable {
    let snapshot: Int
    let tileBase: String // e.g. "https://api.rainbow.ai/tiles/v1/precip"
    let tileQuery: String // e.g. "token=ACTUAL_KEY"
}

@MainActor
@Observable class RadarService {
    var pastFrames: [RadarFrame] = []
    var nowcastFrames: [RadarFrame] = []
    var isLoaded = false
    private(set) var tileURLBuilder: TileURLBuilder = { _, _, _, _ in nil }

    func fetchFrames() async {
        // Fetch radar config from FluxHaus server (key stays server-side)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/api/radar/config"

        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            // Only OIDC users get radar forecast — server rejects Basic Auth
            guard let authHeader = AuthManager.shared.authorizationHeader() else {
                await fetchRainViewerFallback()
                return
            }
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            let config = try JSONDecoder().decode(RadarConfig.self, from: data)
            let base = config.tileBase
            let query = config.tileQuery

            tileURLBuilder = { path, zoom, col, row in
                URL(string: "\(base)/\(path)/\(zoom)/\(col)/\(row)?\(query)")
            }

            buildFrames(snapshot: config.snapshot)
            isLoaded = true
        } catch {
            logger.error("Radar config fetch failed: \(error.localizedDescription)")
            await fetchRainViewerFallback()
        }
    }

    private func buildFrames(snapshot: Int) {
        // 5 past frames at 10-min intervals (50 min history)
        var past: [RadarFrame] = []
        for step in stride(from: -5, through: 0, by: 1) {
            let pastSnapshot = snapshot + (step * 600)
            past.append(RadarFrame(
                id: past.count, time: pastSnapshot,
                path: "\(pastSnapshot)/0"
            ))
        }
        pastFrames = past

        // 5 forecast frames at 10-min intervals (50 min ahead)
        var forecast: [RadarFrame] = []
        for step in 1...5 {
            let offset = step * 600
            forecast.append(RadarFrame(
                id: past.count + forecast.count,
                time: snapshot + offset,
                path: "\(snapshot)/\(offset)"
            ))
        }
        nowcastFrames = forecast
    }

    private func fetchRainViewerFallback() async {
        guard let url = URL(
            string: "https://api.rainviewer.com/public/weather-maps.json"
        ) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(RainViewerFallback.self, from: data)
            let rvHost = response.host

            tileURLBuilder = { path, zoom, col, row in
                URL(string: "\(rvHost)\(path)/256/\(zoom)/\(col)/\(row)/6/1_1.png")
            }

            pastFrames = response.radar.past.enumerated().map { idx, frame in
                RadarFrame(id: idx, time: frame.time, path: frame.path)
            }
            nowcastFrames = []
            isLoaded = true
        } catch {
            logger.error("RainViewer fallback also failed: \(error.localizedDescription)")
        }
    }

    var latestPastFrame: RadarFrame? { pastFrames.last }
    var allFrames: [RadarFrame] { pastFrames + nowcastFrames }

    /// Human-readable relative time label for a frame (e.g. "1 hr 20 min ago")
    func relativeLabel(for frame: RadarFrame) -> String {
        let seconds = frame.time - Int(Date().timeIntervalSince1970)
        let absMinutes = abs(seconds) / 60
        if absMinutes < 2 { return "Now" }

        let hours = absMinutes / 60
        let mins = absMinutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if mins > 0 { parts.append("\(mins) min") }
        let timeStr = parts.joined(separator: " ")

        return seconds < 0 ? "\(timeStr) ago" : "in \(timeStr)"
    }

    /// Forecast confidence (1.0 at now, decreasing linearly to 0.3 at +4 hr)
    func confidence(for frame: RadarFrame) -> Double {
        let pastCount = pastFrames.count
        guard let idx = allFrames.firstIndex(where: { $0.id == frame.id }) else {
            return 1.0
        }
        if idx < pastCount { return 1.0 } // Past = observed data
        let forecastIdx = idx - pastCount
        let forecastTotal = max(nowcastFrames.count - 1, 1)
        return max(0.3, 1.0 - Double(forecastIdx) / Double(forecastTotal) * 0.7)
    }
}

private struct RainViewerFallback: Decodable {
    let host: String
    let radar: RadarData
    struct RadarData: Decodable {
        let past: [Frame]
    }
    struct Frame: Decodable {
        let time: Int
        let path: String
    }
}
