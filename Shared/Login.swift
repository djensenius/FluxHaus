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

struct FluxObject {
    let name: String
    let object: LoginResponse
    let userInfo: [String: Bool]
}

class LoginViewModel: ObservableObject {
    @Published var password: String = ""

    func login() {
        LoginAction(
            parameters: LoginRequest(
                password: password
            )
        ).call()
    }
}

struct LoginAction {
    
    var parameters: LoginRequest
    
    func call() {
        queryFlux(password: parameters.password)
    }
}
