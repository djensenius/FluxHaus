//
//  QueryFlux.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

func queryFlux(password: String) {
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

    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        if let data = data {
            let response = try? JSONDecoder().decode(LoginResponse.self, from: data)
            
            if let response = response {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: response,
                        userInfo: ["keysComplete": true]
                    )

                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: nil,
                        userInfo: ["updateKeychain": password]
                    )
                }
            } else {
                // Error: Unable to decode response JSON
                // This also happens if the password is wrong!
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: nil,
                        userInfo: ["loginError": "Incorrect Password"]
                    )
                }
            }
        }
    }
    task.resume()
}

