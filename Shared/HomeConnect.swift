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

class HomeConnect: ObservableObject {
    @Published var appliances: [Appliance] = []
    var apiResponse: Api?

    init(apiResponse: Api) {
        appliances = []
        self.apiResponse = apiResponse
        self.refresh()
    }

    func setApiResponse(apiResponse: Api) {
        self.apiResponse = apiResponse
        self.refresh()
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

    func refresh() {
        if let response = apiResponse?.response {
            DispatchQueue.main.async {
                if response.dishwasher.operationState.rawValue != "Inactive" &&
                    response.dishwasher.operationState.rawValue != "Finished" {
                    self.setProgram(program: response.dishwasher)
                } else {
                    self.nilProgram()
                }
            }
        }
    }
}
