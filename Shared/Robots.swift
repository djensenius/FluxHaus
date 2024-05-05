//
//  Robots.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

struct Robot: Decodable {
    let name: String
    let timestamp: String
    let batteryLevel: Int?
    let binFull: Bool?
    let running: Bool?
    let charging: Bool?
    let docking: Bool?
    let paused: Bool?
    let timeStarted: String?
}

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

    func fetchRobots() {
        let password = WhereWeAre.getPassword()
        let scheme: String = "https"
        let host: String = "api.fluxhaus.io"
        let path = "/"

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.user = "admin"
        components.password = password

        guard let url = components.url else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "get"

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        print("Going to update robots")
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data {
                let response = try? JSONDecoder().decode(LoginResponse.self, from: data)

                if let response = response {
                    DispatchQueue.main.async {
                        print("Robots updated")
                        self.mopBot = response.mopbot
                        self.broomBot = response.broombot
                    }
                }
            }
        }
        task.resume()
    }

    func performAction(action: String, robot: String) {
        let password = WhereWeAre.getPassword()
        let scheme: String = "https"
        let host: String = "api.fluxhaus.io"
        var path = "/"

        switch action {
        case "start":
            path = "/turnOnBroombot"
            if robot == "MopBot" {
                path = "/turnOnMopbot"
            }
        case "stop":
            path = "/turnOffBroombot"
            if robot == "MopBot" {
                path = "/turnOffMopbot"
            }
        case "deepClean":
            path = "/turnOnDeepClean"
        default:
            path = "/"
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.user = "admin"
        components.password = password

        guard let url = components.url else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "get"

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if data != nil {
                print("Got data")
            }
        }
        task.resume()
    }
}
