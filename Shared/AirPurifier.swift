//
//  AirPurifier.swift
//  FluxHaus
//
//  Blue Pure air purifier control and status.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "AirPurifier")

public struct AirPurifierState: Codable {
    public let timestamp: String?
    public let online: Bool
    public let fanOn: Bool
    public let fanSpeed: Int?
    public let presetMode: String?
    public let presetModes: [String]
    public let lightOn: Bool
    public let brightness: Int?
    public let pm25: Double?
    public let filterLife: Double?

    public init(
        timestamp: String? = nil,
        online: Bool = false,
        fanOn: Bool = false,
        fanSpeed: Int? = nil,
        presetMode: String? = nil,
        presetModes: [String] = [],
        lightOn: Bool = false,
        brightness: Int? = nil,
        pm25: Double? = nil,
        filterLife: Double? = nil
    ) {
        self.timestamp = timestamp
        self.online = online
        self.fanOn = fanOn
        self.fanSpeed = fanSpeed
        self.presetMode = presetMode
        self.presetModes = presetModes
        self.lightOn = lightOn
        self.brightness = brightness
        self.pm25 = pm25
        self.filterLife = filterLife
    }
}

@MainActor
@Observable class AirPurifier {
    var apiResponse: Api?
    var status = AirPurifierState()

    func setApiResponse(apiResponse: Api) {
        self.apiResponse = apiResponse
        fetchDetails()
    }

    func fetchDetails() {
        if let purifier = apiResponse?.response?.airPurifier {
            status = purifier
        }
    }

    var isAuto: Bool { status.presetMode == "auto" }
    var isNight: Bool { status.presetMode == "night" }

    var formattedPm25: String {
        guard let pm25 = status.pm25 else { return "—" }
        return String(format: "%.0f µg/m³", pm25)
    }

    var formattedFilterLife: String {
        guard let filter = status.filterLife else { return "—" }
        return String(format: "%.0f%%", filter)
    }

    var brightnessPercent: Double {
        guard let brightness = status.brightness else { return 0 }
        return (Double(brightness) / 255.0) * 100.0
    }

    // MARK: - Actions

    func setFan(on isOn: Bool) {
        performAction(path: "/airPurifierFan", body: ["on": isOn])
    }

    func setSpeed(percentage: Int) {
        performAction(path: "/airPurifierSpeed", body: ["percentage": percentage])
    }

    func setPreset(mode: String) {
        performAction(path: "/airPurifierPreset", body: ["mode": mode])
    }

    func setLight(on isOn: Bool) {
        performAction(path: "/airPurifierLight", body: ["on": isOn])
    }

    func setBrightness(percentage: Int) {
        performAction(path: "/airPurifierLight", body: ["brightness": percentage])
    }

    private func performAction(path: String, body: [String: Any]) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = path
        guard let url = components.url else { return }

        Task {
            let csrfToken = await fetchCsrfToken()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            if let authHeader = AuthManager.shared.authorizationHeader() {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            if let csrfToken = csrfToken {
                request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let session = URLSession(configuration: .default)
                let (_, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("Air purifier action \(path) completed with HTTP \(statusCode)")
                if (200...299).contains(statusCode) {
                    queryFlux(password: WhereWeAre.getPassword() ?? "")
                }
            } catch {
                logger.error("Air purifier action \(path) failed: \(error.localizedDescription)")
            }
        }
    }
}
