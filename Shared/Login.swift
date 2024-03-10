//
//  Login.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-09.
//

import Foundation

struct LoginRequest: Encodable {
    let password: String
}

struct Robot: Decodable {
    let timestamp: Int
    let batteryLevel: Int?
    let binFull: Bool?
    let running: Bool?
    let charging: Bool?
    let docking: Bool?
    let paused: Bool?
}

struct LoginResponse: Decodable {
    let mieleClientId: String
    let mieleSecretId: String
    let mieleAppliances: [String]
    let boschClientId: String
    let boschSecretId: String
    let boschAppliance: String
    let favouriteHomeKit: [String]
    let broombot: Robot
    let mopbot: Robot
}

class LoginViewModel: ObservableObject {
    @Published var password: String = ""

    func login() {
        LoginAction(
            parameters: LoginRequest(
                password: password
            )
        ).call() { _ in
            // Login successful, navigate to the Home screen
            // Send data back via notification
        }
    }
}

struct LoginAction {
    
    var parameters: LoginRequest
    
    func call(completion: @escaping (LoginResponse) -> Void) {
        print("Checking login")
        let scheme: String = "https"
        let host: String = "api.fluxhaus.io"
        let path = "/"
        
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.user = "admin"
        components.password = parameters.password
        print("Password is \(parameters.password)")
        
        guard let url = components.url else {
            print("BAD URL")
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
                    completion(response)
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
            } else {
                // Error: API request failed

                if let error = error {
                    print("Error: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }
}
