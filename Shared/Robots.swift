//
//  Robots.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

struct Robot: Decodable {
    let timestamp: Int
    let batteryLevel: Int?
    let binFull: Bool?
    let running: Bool?
    let charging: Bool?
    let docking: Bool?
    let paused: Bool?
}

@Observable class Robots {
    var mopBot = Robot(
        timestamp: 0,
        batteryLevel: nil,
        binFull: nil,
        running: nil,
        charging: nil,
        docking: nil,
        paused: nil
    )
    
    var broomBot = Robot(
        timestamp: 0,
        batteryLevel: nil,
        binFull: nil,
        running: nil,
        charging: nil,
        docking: nil,
        paused: nil
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
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
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
}
