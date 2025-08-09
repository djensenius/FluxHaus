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

// MARK: - Shared Type Definitions
// These types are shared across multiple files and defined here for accessibility

struct Doors: Decodable {
    let frontRight: Int
    let frontLeft: Int
    let backRight: Int
    let backLeft: Int
}

struct EvModeRange: Decodable {
    let value: Int
    let unit: Int
}

struct DriveDistance: Codable {
    let rangeByFuel: RangeByFuel
    let type: Int
}

struct RangeByFuel: Codable {
    let gasModeRange, evModeRange, totalAvailableRange: Atc
}

struct Atc: Codable {
    let value, unit: Int
}

struct EVStatus: Decodable {
    let timestamp: String
    let batteryCharge: Bool
    let batteryStatus: Int
    let batteryPlugin: Int
    let drvDistance: [DriveDistance]
}

struct FluxCar: Decodable {
    let timestamp: String
    let lastStatusDate: String
    let airCtrlOn: Bool
    let doorLock: Bool
    let doorOpen: Doors
    let trunkOpen: Bool
    let defrost: Bool
    let hoodOpen: Bool
    let engine: Bool
}

struct Robot: Decodable {
    let name: String?
    let timestamp: String
    let batteryLevel: Int?
    let binFull: Bool?
    let running: Bool?
    let charging: Bool?
    let docking: Bool?
    let paused: Bool?
    let timeStarted: String?
}

enum DishWasherProgram: String, Codable {
    case preRinse = "PreRinse"
    case auto1 = "Auto1"
    case auto2 = "Auto2"
    case auto3 = "Auto3"
    case eco50 = "Eco50"
    case quick45 = "Quick45"
    case intensiv70 = "Intensiv70"
    case normal65 = "Normal65"
    case glas40 = "Glas40"
    case glassCare = "GlassCare"
    case nightWash = "NightWash"
    case quick65 = "Quick65"
    case normal45 = "Normal45"
    case intensiv45 = "Intensiv45"
    case autoHalfLoad = "AutoHalfLoad"
    case intensivPower = "IntensivPower"
    case magicDaily = "MagicDaily"
    case super60 = "Super60"
    case kurz60 = "Kurz60"
    case expressSparkle65 = "ExpressSparkle65"
    case machineCare = "MachineCare"
    case steamFresh = "SteamFresh"
    case maximumCleaning = "MaximumCleaning"
    case mixedLoad = "MixedLoad"
}

enum OperationState: String, Codable {
    case inactive = "Inactive"
    case ready = "Ready"
    case delayedStart = "DelayedStart"
    case run = "Run"
    case pause = "Pause"
    case actionRequired = "ActionRequired"
    case finished = "Finished"
    case error = "Error"
    case aborting = "Aborting"
}

struct DishWasher: Codable {
    var status: String?
    var program: String?
    var remainingTime: Int?
    var remainingTimeUnit: String?
    var remainingTimeEstimate: Bool?
    var programProgress: Double?
    var operationState: OperationState
    var doorState: String
    var selectedProgram: String?
    var activeProgram: DishWasherProgram?
    var startInRelative: Int?
    var startInRelativeUnit: String?
}

struct WasherDryer: Codable {
    var name: String
    var timeRunning: Int?
    var timeRemaining: Int?
    var step: String?
    var programName: String?
    var status: String?
    var inUse: Bool
}

struct CarDetails: Decodable {
    let timestamp: String
    let evStatusTimestamp: String
    let batteryLevel: Int
    let distance: Int
    let hvac: Bool
    let pluggedIn: Bool
    let batteryCharge: Bool
    let locked: Bool
    let doorsOpen: Doors
    let trunkOpen: Bool
    let defrost: Bool
    let hoodOpen: Bool
    let odometer: Double
    let engine: Bool
}

struct LoginResponse: Decodable {
    let timestamp: String
    let favouriteHomeKit: [String]
    let broombot: Robot
    let mopbot: Robot
    let car: FluxCar
    let carEvStatus: EVStatus
    let carOdometer: Double
    let dishwasher: DishWasher
    let dryer: WasherDryer
    let washer: WasherDryer
}

struct FluxObject {
    let name: String
    let object: LoginResponse
    let userInfo: [String: Bool]
}
