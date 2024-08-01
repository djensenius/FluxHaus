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
    let car: FluxCar
    let carEvStatus: EVStatus
    let carOdometer: Double
    let miele: [String: MieleAppliances]
    let dishwasher: DishWasher
    let dryer: WasherDryer
    let washer: WasherDryer
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
