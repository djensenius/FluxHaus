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

struct RainViewerResponse: Decodable {
    let host: String
    let radar: RadarData

    struct RadarData: Decodable {
        let past: [Frame]
        let nowcast: [Frame]
    }

    struct Frame: Decodable {
        let time: Int
        let path: String
    }
}

@MainActor
@Observable class RadarService {
    var host = "https://tilecache.rainviewer.com"
    var pastFrames: [RadarFrame] = []
    var nowcastFrames: [RadarFrame] = []
    var isLoaded = false

    func fetchFrames() async {
        guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json") else {
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(RainViewerResponse.self, from: data)
            host = response.host
            pastFrames = response.radar.past.enumerated().map { idx, frame in
                RadarFrame(id: idx, time: frame.time, path: frame.path)
            }
            let offset = pastFrames.count
            nowcastFrames = response.radar.nowcast.enumerated().map { idx, frame in
                RadarFrame(id: offset + idx, time: frame.time, path: frame.path)
            }
            isLoaded = true
        } catch {
            logger.error("Failed to fetch radar frames: \(error.localizedDescription)")
        }
    }

    func tileURL(for frame: RadarFrame, zoom: Int, col: Int, row: Int) -> URL? {
        URL(string: "\(host)\(frame.path)/256/\(zoom)/\(col)/\(row)/6/1_1.png")
    }

    var latestPastFrame: RadarFrame? { pastFrames.last }
    var allFrames: [RadarFrame] { pastFrames + nowcastFrames }
}
