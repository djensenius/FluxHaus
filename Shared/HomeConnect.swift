//
//  HomeConnect.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-14.
//

import Foundation
import UIKit

// MARK: - New Format
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

// MARK: - Welcome
struct HomeConnectStruct: Codable {
    let data: DataClass
}

// MARK: - DataClass
struct DataClass: Codable {
    let key: String
    let options: [Option]
    let name: String
}

// MARK: - Option
struct Option: Codable {
    let key: String
    let value: Value
    let unit: String?
    let name: String
}

enum Value: Codable {
    case bool(Bool)
    case integer(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decoded = try? container.decode(Bool.self) {
            self = .bool(decoded)
            return
        }
        if let decoded = try? container.decode(Int.self) {
            self = .integer(decoded)
            return
        }
        throw DecodingError.typeMismatch(
            Value.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let decoded):
            try container.encode(decoded)
        case .integer(let decoded):
            try container.encode(decoded)
        }
    }

    var intValue: Int {
        switch self {
        case .integer(let thes):
            return thes
        case .bool(let thes):
            if thes == true {
                return 1
            }
            return 0
        }
    }
}

class HomeConnect: ObservableObject {
    @Published var appliances: [Appliance] = []

    init(boschAppliance: String) {
        appliances = []
        self.authorize(boschAppliance: boschAppliance)
    }

    func nilProgram() {
        self.appliances.append(
            Appliance(
                name: "Dishwasher",
                timeRunning: 0,
                timeRemaining: 0,
                timeFinish: "",
                step: "",
                programName: "",
                inUse: false
            )
        )
        NotificationCenter.default.post(
            name: Notification.Name.loginsUpdated,
            object: nil,
            userInfo: ["homeConnectComplete": true]
        )
    }

    func setProgram(program: DishWasher) {
        var options: [String] = []
        let name = "Dishwasher"
        let step = program.program ?? ""
        let timeRunning = 0
        var timeRemaining = 0

        /*
        for option in program.options {
            if option.key == "BSH.Common.Option.RemainingProgramTime" {
                timeRemaining = Int(round(Double(option.value.intValue / 60)))
            } else if option.key == "BSH.Common.Option.ElapsedProgramTime" {
                timeRunning = option.value.intValue
            } else {
                if option.value.intValue == 1 {
                    options.append(option.name)
                }
            }
        }
         */
        timeRemaining = (program.remainingTime ?? 0) / 60
        if program.activeProgram != nil {
            options = [program.activeProgram!.rawValue]
        }

        let currentDate = Date()
        let finishTime = Calendar.current.date(
            byAdding: .minute,
            value: timeRemaining,
            to: currentDate
        ) ?? currentDate
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let formatedTime = formatter.string(from: finishTime)
        self.appliances.removeAll()
        self.appliances.append(Appliance(
            name: name,
            timeRunning: timeRunning,
            timeRemaining: timeRemaining,
            timeFinish: formatedTime,
            step: step,
            programName: options.joined(separator: ", "),
            inUse: true
        ))
        NotificationCenter.default.post(
            name: Notification.Name.loginsUpdated,
            object: nil,
            userInfo: ["homeConnectComplete": true]
        )
    }

    func authorize(boschAppliance: String) {
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

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data {
                let response = try? JSONDecoder().decode(LoginResponse.self, from: data)
                if let response = response {
                    DispatchQueue.main.async {
                        if response.dishwasher.operationState.rawValue != "Inactive" {
                            self.setProgram(program: response.dishwasher)
                        } else {
                            self.nilProgram()
                        }
                    }
                }
            }
        }
        task.resume()
    }
}
