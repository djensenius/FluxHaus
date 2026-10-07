//
//  LoginStucts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-08-03.
//

import Foundation

public struct LoginRequest: Encodable {
    public let password: String

    public init(password: String) {
        self.password = password
    }
}

// MARK: - Shared Type Definitions
// These types are shared across multiple files and defined here for accessibility

public struct Doors: Codable {
    public let frontRight: Int
    public let frontLeft: Int
    public let backRight: Int
    public let backLeft: Int

    public init(
        frontRight: Int = 0,
        frontLeft: Int = 0,
        backRight: Int = 0,
        backLeft: Int = 0
    ) {
        self.frontRight = frontRight
        self.frontLeft = frontLeft
        self.backRight = backRight
        self.backLeft = backLeft
    }
}

public struct EvModeRange: Codable {
    public let value: Int
    public let unit: Int

    public init(value: Int, unit: Int) {
        self.value = value
        self.unit = unit
    }
}

public struct DriveDistance: Codable {
    public let rangeByFuel: RangeByFuel
    public let type: Int

    public init(rangeByFuel: RangeByFuel, type: Int) {
        self.rangeByFuel = rangeByFuel
        self.type = type
    }
}

public struct RangeByFuel: Codable {
    public let gasModeRange, evModeRange, totalAvailableRange: Atc

    public init(gasModeRange: Atc, evModeRange: Atc, totalAvailableRange: Atc) {
        self.gasModeRange = gasModeRange
        self.evModeRange = evModeRange
        self.totalAvailableRange = totalAvailableRange
    }
}

public struct Atc: Codable {
    public let value, unit: Int

    public init(value: Int, unit: Int) {
        self.value = value
        self.unit = unit
    }
}

public struct EVStatus: Codable {
    public let timestamp: String
    public let batteryCharge: Bool
    public let batteryStatus: Int
    public let batteryPlugin: Int
    public let drvDistance: [DriveDistance]

    public init(
        timestamp: String,
        batteryCharge: Bool,
        batteryStatus: Int,
        batteryPlugin: Int,
        drvDistance: [DriveDistance]
    ) {
        self.timestamp = timestamp
        self.batteryCharge = batteryCharge
        self.batteryStatus = batteryStatus
        self.batteryPlugin = batteryPlugin
        self.drvDistance = drvDistance
    }
}

public struct FluxCar: Codable {
    public let timestamp: String
    public let lastStatusDate: String
    public let airCtrlOn: Bool
    public let doorLock: Bool
    public let doorOpen: Doors
    public let trunkOpen: Bool
    public let defrost: Bool
    public let hoodOpen: Bool
    public let engine: Bool

    public init(
        timestamp: String,
        lastStatusDate: String,
        airCtrlOn: Bool,
        doorLock: Bool,
        doorOpen: Doors,
        trunkOpen: Bool,
        defrost: Bool,
        hoodOpen: Bool,
        engine: Bool
    ) {
        self.timestamp = timestamp
        self.lastStatusDate = lastStatusDate
        self.airCtrlOn = airCtrlOn
        self.doorLock = doorLock
        self.doorOpen = doorOpen
        self.trunkOpen = trunkOpen
        self.defrost = defrost
        self.hoodOpen = hoodOpen
        self.engine = engine
    }
}

public struct RobotRoom: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let icon: String?

    public init(id: Int, name: String, icon: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
    }
}

public struct RobotMaintenance: Codable {
    public let mainBrushPercent: Double?
    public let sideBrushPercent: Double?
    public let filterPercent: Double?
    public let sensorPercent: Double?
    public let wheelPercent: Double?

    public init(
        mainBrushPercent: Double? = nil,
        sideBrushPercent: Double? = nil,
        filterPercent: Double? = nil,
        sensorPercent: Double? = nil,
        wheelPercent: Double? = nil
    ) {
        self.mainBrushPercent = mainBrushPercent
        self.sideBrushPercent = sideBrushPercent
        self.filterPercent = filterPercent
        self.sensorPercent = sensorPercent
        self.wheelPercent = wheelPercent
    }
}

public struct Robot: Codable {
    public let name: String?
    public let timestamp: String
    public let batteryLevel: Int?
    public let binFull: Bool?
    public let running: Bool?
    public let charging: Bool?
    public let docking: Bool?
    public let paused: Bool?
    public let timeStarted: String?
    public let progressPercent: Double?
    public let elapsedMinutes: Double?
    public let estimatedRemainingMinutes: Double?
    public let cleanedArea: Double?
    public let cleaningMode: String?
    public let suctionLevel: String?
    public let currentRoom: String?
    public let currentRoomId: Int?
    public let cleanWaterTankStatus: String?
    public let dirtyWaterTankStatus: String?
    public let dustBagStatus: String?
    public let detergentStatus: String?
    public let lowWaterWarning: String?
    public let autoEmptyStatus: String?
    public let drainageStatus: String?
    public let selfWashBaseStatus: String?
    public let maintenance: RobotMaintenance?
    public let rooms: [RobotRoom]?

    public init(
        name: String? = nil,
        timestamp: String = "",
        batteryLevel: Int? = nil,
        binFull: Bool? = nil,
        running: Bool? = nil,
        charging: Bool? = nil,
        docking: Bool? = nil,
        paused: Bool? = nil,
        timeStarted: String? = nil,
        progressPercent: Double? = nil,
        elapsedMinutes: Double? = nil,
        estimatedRemainingMinutes: Double? = nil,
        cleanedArea: Double? = nil,
        cleaningMode: String? = nil,
        suctionLevel: String? = nil,
        currentRoom: String? = nil,
        currentRoomId: Int? = nil,
        cleanWaterTankStatus: String? = nil,
        dirtyWaterTankStatus: String? = nil,
        dustBagStatus: String? = nil,
        detergentStatus: String? = nil,
        lowWaterWarning: String? = nil,
        autoEmptyStatus: String? = nil,
        drainageStatus: String? = nil,
        selfWashBaseStatus: String? = nil,
        maintenance: RobotMaintenance? = nil,
        rooms: [RobotRoom]? = nil
    ) {
        self.name = name
        self.timestamp = timestamp
        self.batteryLevel = batteryLevel
        self.binFull = binFull
        self.running = running
        self.charging = charging
        self.docking = docking
        self.paused = paused
        self.timeStarted = timeStarted
        self.progressPercent = progressPercent
        self.elapsedMinutes = elapsedMinutes
        self.estimatedRemainingMinutes = estimatedRemainingMinutes
        self.cleanedArea = cleanedArea
        self.cleaningMode = cleaningMode
        self.suctionLevel = suctionLevel
        self.currentRoom = currentRoom
        self.currentRoomId = currentRoomId
        self.cleanWaterTankStatus = cleanWaterTankStatus
        self.dirtyWaterTankStatus = dirtyWaterTankStatus
        self.dustBagStatus = dustBagStatus
        self.detergentStatus = detergentStatus
        self.lowWaterWarning = lowWaterWarning
        self.autoEmptyStatus = autoEmptyStatus
        self.drainageStatus = drainageStatus
        self.selfWashBaseStatus = selfWashBaseStatus
        self.maintenance = maintenance
        self.rooms = rooms
    }
}

public enum DishWasherProgram: String, Codable {
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

    public var displayName: String {
        switch self {
        case .preRinse: return "Pre-Rinse"
        case .auto1: return "Auto 1"
        case .auto2: return "Auto 2"
        case .auto3: return "Auto 3"
        case .eco50: return "Eco 50°"
        case .quick45: return "Quick 45'"
        case .intensiv70: return "Intensive 70°"
        case .normal65: return "Normal 65°"
        case .glas40: return "Glass 40°"
        case .glassCare: return "Glass Care"
        case .nightWash: return "Night Wash"
        case .quick65: return "Quick 65'"
        case .normal45: return "Normal 45°"
        case .intensiv45: return "Intensive 45°"
        case .autoHalfLoad: return "Auto Half Load"
        case .intensivPower: return "Intensive Power"
        case .magicDaily: return "Magic Daily"
        case .super60: return "Super 60°"
        case .kurz60: return "Short 60'"
        case .expressSparkle65: return "Express Sparkle 65°"
        case .machineCare: return "Machine Care"
        case .steamFresh: return "Steam Fresh"
        case .maximumCleaning: return "Maximum Cleaning"
        case .mixedLoad: return "Mixed Load"
        }
    }
}

public enum OperationState: String, Codable {
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

public struct DishWasher: Codable {
    public var status: String?
    public var program: String?
    public var remainingTime: Int?
    public var remainingTimeUnit: String?
    public var remainingTimeEstimate: Bool?
    public var programProgress: Double?
    public var operationState: OperationState
    public var doorState: String
    public var selectedProgram: String?
    public var activeProgram: DishWasherProgram?
    public var startInRelative: Int?
    public var startInRelativeUnit: String?

    public init(
        status: String? = nil,
        program: String? = nil,
        remainingTime: Int? = nil,
        remainingTimeUnit: String? = nil,
        remainingTimeEstimate: Bool? = nil,
        programProgress: Double? = nil,
        operationState: OperationState = .inactive,
        doorState: String = "Unknown",
        selectedProgram: String? = nil,
        activeProgram: DishWasherProgram? = nil,
        startInRelative: Int? = nil,
        startInRelativeUnit: String? = nil
    ) {
        self.status = status
        self.program = program
        self.remainingTime = remainingTime
        self.remainingTimeUnit = remainingTimeUnit
        self.remainingTimeEstimate = remainingTimeEstimate
        self.programProgress = programProgress
        self.operationState = operationState
        self.doorState = doorState
        self.selectedProgram = selectedProgram
        self.activeProgram = activeProgram
        self.startInRelative = startInRelative
        self.startInRelativeUnit = startInRelativeUnit
    }
}

public struct WasherDryer: Codable {
    public var name: String
    public var timeRunning: Int?
    public var timeRemaining: Int?
    public var step: String?
    public var programName: String?
    public var status: String?
    public var inUse: Bool

    public init(
        name: String,
        timeRunning: Int? = nil,
        timeRemaining: Int? = nil,
        step: String? = nil,
        programName: String? = nil,
        status: String? = nil,
        inUse: Bool = false
    ) {
        self.name = name
        self.timeRunning = timeRunning
        self.timeRemaining = timeRemaining
        self.step = step
        self.programName = programName
        self.status = status
        self.inUse = inUse
    }
}

public struct CarDetails: Codable {
    public let timestamp: String
    public let evStatusTimestamp: String
    public let batteryLevel: Int
    public let distance: Int
    public let hvac: Bool
    public let pluggedIn: Bool
    public let batteryCharge: Bool
    public let locked: Bool
    public let doorsOpen: Doors
    public let trunkOpen: Bool
    public let defrost: Bool
    public let hoodOpen: Bool
    public let odometer: Double
    public let engine: Bool

    public init(
        timestamp: String,
        evStatusTimestamp: String,
        batteryLevel: Int,
        distance: Int,
        hvac: Bool,
        pluggedIn: Bool,
        batteryCharge: Bool,
        locked: Bool,
        doorsOpen: Doors,
        trunkOpen: Bool,
        defrost: Bool,
        hoodOpen: Bool,
        odometer: Double,
        engine: Bool
    ) {
        self.timestamp = timestamp
        self.evStatusTimestamp = evStatusTimestamp
        self.batteryLevel = batteryLevel
        self.distance = distance
        self.hvac = hvac
        self.pluggedIn = pluggedIn
        self.batteryCharge = batteryCharge
        self.locked = locked
        self.doorsOpen = doorsOpen
        self.trunkOpen = trunkOpen
        self.defrost = defrost
        self.hoodOpen = hoodOpen
        self.odometer = odometer
        self.engine = engine
    }
}

public struct LoginResponse: Codable {
    public let timestamp: String
    public let favouriteHomeKit: [String]
    public let favouriteScenes: [String]?
    public let cleanbot: Robot
    public let car: FluxCar?
    public let carEvStatus: EVStatus?
    public let carOdometer: Double?
    public let dishwasher: DishWasher?
    public let dryer: WasherDryer?
    public let washer: WasherDryer?
    public let scooter: ScooterSummary?
    public let airPurifier: AirPurifierState?

    public init(
        timestamp: String,
        favouriteHomeKit: [String],
        favouriteScenes: [String]? = nil,
        cleanbot: Robot,
        car: FluxCar? = nil,
        carEvStatus: EVStatus? = nil,
        carOdometer: Double? = nil,
        dishwasher: DishWasher? = nil,
        dryer: WasherDryer? = nil,
        washer: WasherDryer? = nil,
        scooter: ScooterSummary? = nil,
        airPurifier: AirPurifierState? = nil
    ) {
        self.timestamp = timestamp
        self.favouriteHomeKit = favouriteHomeKit
        self.favouriteScenes = favouriteScenes
        self.cleanbot = cleanbot
        self.car = car
        self.carEvStatus = carEvStatus
        self.carOdometer = carOdometer
        self.dishwasher = dishwasher
        self.dryer = dryer
        self.washer = washer
        self.scooter = scooter
        self.airPurifier = airPurifier
    }
}

public struct ScooterLastRide: Codable {
    public let date: String?
    public let endDate: String?
    public let distance: Double?
    public let maxSpeed: Double?
    public let avgSpeed: Double?
    public let batteryUsed: Int?
    public let startBattery: Int?
    public let endBattery: Int?
    public let gearMode: Int?

    public init(
        date: String? = nil,
        endDate: String? = nil,
        distance: Double? = nil,
        maxSpeed: Double? = nil,
        avgSpeed: Double? = nil,
        batteryUsed: Int? = nil,
        startBattery: Int? = nil,
        endBattery: Int? = nil,
        gearMode: Int? = nil
    ) {
        self.date = date
        self.endDate = endDate
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.avgSpeed = avgSpeed
        self.batteryUsed = batteryUsed
        self.startBattery = startBattery
        self.endBattery = endBattery
        self.gearMode = gearMode
    }
}

public struct ScooterSummary: Codable {
    public let timestamp: String?
    public let battery: Int?
    public let estimatedRange: Double?
    public let odometer: Double?
    public let totalRideTime: Int?
    public let batteryCycles: Int?
    public let lastRide: ScooterLastRide?

    public init(
        timestamp: String? = nil,
        battery: Int? = nil,
        estimatedRange: Double? = nil,
        odometer: Double? = nil,
        totalRideTime: Int? = nil,
        batteryCycles: Int? = nil,
        lastRide: ScooterLastRide? = nil
    ) {
        self.timestamp = timestamp
        self.battery = battery
        self.estimatedRange = estimatedRange
        self.odometer = odometer
        self.totalRideTime = totalRideTime
        self.batteryCycles = batteryCycles
        self.lastRide = lastRide
    }
}

public struct FluxObject {
    public let name: String
    public let object: LoginResponse
    public let userInfo: [String: Bool]

    public init(
        name: String,
        object: LoginResponse,
        userInfo: [String: Bool]
    ) {
        self.name = name
        self.object = object
        self.userInfo = userInfo
    }
}
