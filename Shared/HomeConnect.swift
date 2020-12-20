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
        if let x = try? container.decode(Bool.self) {
            self = .bool(x)
            return
        }
        if let x = try? container.decode(Int.self) {
            self = .integer(x)
            return
        }
        throw DecodingError.typeMismatch(Value.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Value"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let x):
            try container.encode(x)
        case .integer(let x):
            try container.encode(x)
        }
    }

    var intValue: Int {
        switch self {
        case .integer(let s):
            return s
        case .bool(let s):
            if s == true {
                return 1
            }
            return 0
        }
    }
}

class HomeConnect: ObservableObject {
    @Published var appliance = Appliance(name: "", timeRunning: 0, timeRemaining: 0, timeFinish: "", step: "", programName: "", inUse: false)

    init() {
        print("Hi David");
        appliance = Appliance(name: "", timeRunning: 0, timeRemaining: 0, timeFinish: "", step: "", programName: "", inUse: false)
        self.authorize()
    }

    func authorize() {
        print("Authin")
        let base = URL(string: "https://api.home-connect.com")!
        let url = base.appendingPathComponent("api/homeappliances/\(FluxHausConsts.boschAppliance)/programs/active")
        // oauth2.logger = OAuth2DebugLogger(.trace)

        var req = oauth2.request(forURL: url)
        req.setValue("application/vnd.bsh.sdk.v1+json", forHTTPHeaderField: "Accept")


        loader.perform(request: req) { response in
            do {
                DispatchQueue.main.async {
                    let decoder = JSONDecoder()
                    let activeProgram = try? decoder.decode(HomeConnectStruct.self, from: response.responseData())
                    if activeProgram == nil {
                        self.appliance = Appliance(name: "Dishwasher", timeRunning: 0, timeRemaining: 0, timeFinish: "", step: "", programName: "", inUse: false)
                    } else {
                        let name = "Dishwasher"
                        let program = activeProgram!.data.key
                        var timeRunning = 0
                        var timeRemaining = 0
                        for option in activeProgram!.data.options {
                            if option.key == "BSH.Common.Option.RemainingProgramTime" {
                                timeRemaining = option.value.intValue
                            } else if option.key == "BSH.Common.Option.ElapsedProgramTime" {
                               timeRunning = option.value.intValue
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
                            programName: "",
                            inUse: true
                        )
                    }
                }
            }
        }
    }
}
