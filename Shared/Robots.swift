//
//  Robots.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

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
            DispatchQueue.main.async {
                self.mopBot = Robot(
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
                self.broomBot = Robot(
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
    }

    func performAction(action: String, robot: String) {
        let password = WhereWeAre.getPassword()
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

        var request = URLRequest(url: url)
        request.httpMethod = "get"

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let authHeader = AuthManager.shared.authorizationHeader() {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { @Sendable (data: Data?, _: URLResponse?, _: Error?) in
            if data != nil {
                print("Got Robot data \(path)")
            }
        }
        task.resume()
    }
}
