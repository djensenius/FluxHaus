//
//  LoginStucts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-08-03.
//

import Foundation

struct LoginRequest: Encodable {
    let password: String
}

struct LoginResponse: Decodable {
    let timestamp: String
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
