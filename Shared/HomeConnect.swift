//
//  HomeConnect.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-14.
//

import Foundation
import OAuth2
import UIKit

// MARK: - Welcome
struct HomeConnectStruct: Codable {
    let data: DataClass
}

// MARK: - DataClass
struct DataClass: Codable {
    let key: String
    let options: [Option]
}

// MARK: - Option
struct Option: Codable {
    let key: String
    let value: Int
    let unit: String
}


class HomeConnect: ObservableObject {
    @Published var appliance = Appliance(name: "", timeRunning: 0, timeRemaining: 0, timeFinish: "", step: "", inUse: false)

    init() {
        print("Hi David");
        appliance = Appliance(name: "", timeRunning: 0, timeRemaining: 0, timeFinish: "", step: "", inUse: false)
        self.authorize()
    }

    func authorize() {
        print("Authin")
        let base = URL(string: "https://simulator.home-connect.com")!
        let url = base.appendingPathComponent("api/homeappliances/SIEMENS-HCS02DWH1-5C9E44517C1D/programs/active")

        var req = oauth2.request(forURL: url)
        req.setValue("application/vnd.bsh.sdk.v1+json", forHTTPHeaderField: "Accept")


        loader.perform(request: req) { response in
            do {
                DispatchQueue.main.async {
                    let decoder = JSONDecoder()
                    let activeProgram = try? decoder.decode(HomeConnectStruct.self, from: response.responseData())
                    if activeProgram == nil {
                        self.appliance = Appliance(name: "Dishwasher", timeRunning: 0, timeRemaining: 0, timeFinish: "", step: "", inUse: false)
                    } else {
                        let name = "Dishwasher"
                        let program = activeProgram!.data.key
                        var timeRunning = 0
                        var timeRemaining = 0
                        for option in activeProgram!.data.options {
                            if option.key == "BSH.Common.Option.RemainingProgramTime" {
                                timeRemaining = option.value
                            } else if option.key == "BSH.Common.Option.ElapsedProgramTime" {
                                timeRunning = option.value
                            }
                        }

                        let currentDate = Date()
                        let finishTime = Calendar.current.date(byAdding: .second, value: timeRemaining, to: currentDate) ?? currentDate
                        let formatter = DateFormatter()
                        formatter.dateFormat = "h:mm a"
                        let formatedTime = formatter.string(from: finishTime)

                        self.appliance = Appliance(
                            name: name,
                            timeRunning: timeRunning,
                            timeRemaining: timeRemaining,
                            timeFinish: formatedTime,
                            step: program,
                            inUse: true
                        )
                    }
                }
            }
        }
    }
}
