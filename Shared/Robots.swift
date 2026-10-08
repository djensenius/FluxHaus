//
//  Robots.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation
import AppIntents
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Robots")

// Robot-specific logic and classes
// Note: Shared types are now defined in LoginStucts.swift

@MainActor
@Observable class Robots {
    var cleanBot = Robot(
        name: "Cleanbot",
        timestamp: "",
        batteryLevel: nil,
        binFull: nil,
        running: nil,
        charging: nil,
        docking: nil,
        paused: nil,
        timeStarted: nil
    )

    var apiResponse: Api?

    func setApiResponse(apiResponse: Api) {
        self.apiResponse = apiResponse
        self.fetchRobots()
    }

    func fetchRobots() {
        if let response = apiResponse?.response {
            cleanBot = normalizedCleanbot(response.cleanbot)
        }
    }

    private func normalizedCleanbot(_ robot: Robot) -> Robot {
        Robot(
            name: robot.name ?? "Cleanbot",
            timestamp: robot.timestamp,
            batteryLevel: robot.batteryLevel,
            binFull: robot.binFull,
            running: robot.running,
            charging: robot.charging,
            docking: robot.docking,
            paused: robot.paused,
            timeStarted: robot.timeStarted,
            progressPercent: robot.progressPercent,
            elapsedMinutes: robot.elapsedMinutes,
            estimatedRemainingMinutes: robot.estimatedRemainingMinutes,
            cleanedArea: robot.cleanedArea,
            cleaningMode: robot.cleaningMode,
            suctionLevel: robot.suctionLevel,
            currentRoom: robot.currentRoom,
            currentRoomId: robot.currentRoomId,
            cleanWaterTankStatus: robot.cleanWaterTankStatus,
            dirtyWaterTankStatus: robot.dirtyWaterTankStatus,
            dustBagStatus: robot.dustBagStatus,
            detergentStatus: robot.detergentStatus,
            lowWaterWarning: robot.lowWaterWarning,
            autoEmptyStatus: robot.autoEmptyStatus,
            drainageStatus: robot.drainageStatus,
            selfWashBaseStatus: robot.selfWashBaseStatus,
            maintenance: robot.maintenance,
            rooms: robot.rooms
        )
    }

    func cleanRoomBody(_ room: RobotRoom) -> [String: Any] {
        ["segments": [room.id]]
    }

    func cleanRoom(_ room: RobotRoom) {
        postRobotRequest(path: "/cleanbot/rooms", body: cleanRoomBody(room))
    }

    func performAction(action: String, robot: String) {
        let path: String
        switch action {
        case "start":
            path = "/turnOnCleanbot"
        case "stop":
            path = "/turnOffCleanbot"
        case "deepClean":
            path = "/turnOnDeepClean"
        default:
            path = "/"
        }

        postRobotRequest(path: path) { statusCode in
            if (200...299).contains(statusCode) {
                Task { await Self.donateRobotIntent(action: action) }
            }
        }
    }

    private func postRobotRequest(
        path: String,
        body: [String: Any]? = nil,
        completion: ((Int) -> Void)? = nil
    ) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = path
        guard let url = components.url else {
            return
        }

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
            if let body {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
            do {
                let session = URLSession(configuration: .default)
                let (_, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("Robot action \(path) completed with HTTP \(statusCode)")
                completion?(statusCode)
            } catch {
                logger.error("Robot action \(path) failed: \(error.localizedDescription)")
            }
        }
    }

    private static func donateRobotIntent(action: String) async {
        switch action {
        case "start":
            let intent = StartRobotIntent()
            intent.robot = .cleanBot
            await donateIntent(intent)
        case "stop":
            let intent = StopRobotIntent()
            intent.robot = .cleanBot
            await donateIntent(intent)
        case "deepClean":
            await donateIntent(DeepCleanIntent())
        default:
            break
        }
    }
}
