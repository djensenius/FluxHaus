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

struct RainbowSnapshot: Decodable {
    let snapshot: Int
}

@MainActor
@Observable class RadarService {
    var pastFrames: [RadarFrame] = []
    var nowcastFrames: [RadarFrame] = []
    var isLoaded = false
    private(set) var tileURLBuilder: TileURLBuilder = { _, _, _, _ in nil }

    private let apiKey: String = "YOUR_RAINBOW_API_KEY"
    private let baseURL = "https://api.rainbow.ai/tiles/v1"

    func fetchFrames() async {
        guard let url = URL(string: "\(baseURL)/snapshot?token=\(apiKey)") else {
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(RainbowSnapshot.self, from: data)
            let snapshot = response.snapshot
            let base = baseURL
            let key = apiKey

            tileURLBuilder = { path, zoom, col, row in
                URL(string: "\(base)/precip/\(path)/\(zoom)/\(col)/\(row)?token=\(key)")
            }

            // Past frames: 2 hours back in 10-min steps
            var past: [RadarFrame] = []
            for step in stride(from: -12, through: 0, by: 1) {
                let offset = step * 600
                let frameTime = snapshot + offset
                past.append(RadarFrame(
                    id: past.count,
                    time: frameTime,
                    path: "\(snapshot)/\(offset)"
                ))
            }
            pastFrames = past

            // Forecast frames: up to 4 hours ahead in 10-min steps
            var forecast: [RadarFrame] = []
            for step in 1...24 {
                let offset = step * 600
                let frameTime = snapshot + offset
                forecast.append(RadarFrame(
                    id: past.count + forecast.count,
                    time: frameTime,
                    path: "\(snapshot)/\(offset)"
                ))
            }
            nowcastFrames = forecast
            isLoaded = true
        } catch {
            logger.error("Rainbow.ai fetch failed: \(error.localizedDescription)")
            // Fallback to RainViewer (past only)
            await fetchRainViewerFallback()
        }
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
