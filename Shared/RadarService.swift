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
        // Past frames: 2 hours back in 10-min steps
        var past: [RadarFrame] = []
        for step in stride(from: -12, through: 0, by: 1) {
            let offset = step * 600
            past.append(RadarFrame(
                id: past.count, time: snapshot + offset,
                path: "\(snapshot)/\(offset)"
            ))
        }
        pastFrames = past

        // Forecast frames: up to 4 hours ahead in 10-min steps
        var forecast: [RadarFrame] = []
        for step in 1...24 {
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
