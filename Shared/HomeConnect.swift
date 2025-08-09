//
//  HomeConnect.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-14.
//

import Foundation
import UIKit

// HomeConnect-specific logic and classes
// Note: Shared types are now defined in LoginStucts.swift

@MainActor
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
