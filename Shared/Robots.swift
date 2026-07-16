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
    var mopBot = Robot(
        name: "MopBot",
        timestamp: "",
        batteryLevel: nil,
        binFull: nil,
        running: nil,
        charging: nil,
        docking: nil,
        paused: nil,
        timeStarted: nil
    )

    var broomBot = Robot(
        name: "BroomBot",
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
            mopBot = Robot(
                name: "MopBot",
                timestamp: response.mopbot.timestamp,
                batteryLevel: response.mopbot.batteryLevel,
                binFull: response.mopbot.binFull,
                running: response.mopbot.running,
                charging: response.mopbot.charging,
                docking: response.mopbot.docking,
                paused: response.mopbot.paused,
                timeStarted: response.mopbot.timeStarted
            )
            broomBot = Robot(
                name: "BroomBot",
                timestamp: response.broombot.timestamp,
                batteryLevel: response.broombot.batteryLevel,
                binFull: response.broombot.binFull,
                running: response.broombot.running,
                charging: response.broombot.charging,
                docking: response.broombot.docking,
                paused: response.broombot.paused,
                timeStarted: response.broombot.timeStarted
            )
        }
    }

    func performAction(action: String, robot: String) {
        let scheme: String = "https"
        let host: String = "api.fluxhaus.io"

        let path: String
        switch action {
        case "start":
            path = robot == "MopBot" ? "/turnOnMopbot" : "/turnOnBroombot"
        case "stop":
            path = robot == "MopBot" ? "/turnOffMopbot" : "/turnOffBroombot"
        case "deepClean":
            path = "/turnOnDeepClean"
        default:
            path = "/"
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
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
            do {
                let session = URLSession(configuration: .default)
                let (_, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("Robot action \(path) completed with HTTP \(statusCode)")
                if (200...299).contains(statusCode) {
                    await Self.donateRobotIntent(action: action, robot: robot)
                }
            } catch {
                logger.error("Robot action \(path) failed: \(error.localizedDescription)")
            }
        }
    }

    private static func donateRobotIntent(action: String, robot: String) async {
        let choice: RobotChoice = robot == "MopBot" ? .mopBot : .broomBot
        switch action {
        case "start":
            let intent = StartRobotIntent()
            intent.robot = choice
            _ = try? await intent.donate()
        case "stop":
            let intent = StopRobotIntent()
            intent.robot = choice
            _ = try? await intent.donate()
        case "deepClean":
            _ = try? await DeepCleanIntent().donate()
        default:
            break
        }
    }
}
