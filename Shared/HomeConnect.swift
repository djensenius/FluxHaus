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
        DispatchQueue.main.async {
            oauth2!.authConfig.authorizeEmbedded = true
            oauth2!.authConfig.ui.useAuthenticationSession = true
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene

            let rootViewController = scene?
                .windows.first(where: { $0.isKeyWindow })?
                .rootViewController
            oauth2!.authConfig.authorizeContext = rootViewController
        }
        self.authorize(boschAppliance: boschAppliance)
    }

    func authorize(boschAppliance: String) {
        let path = "api/homeappliances/\(boschAppliance)/programs/active"

        let base = URL(string: "https://api.home-connect.com")!
        let url = base.appendingPathComponent(path)

        var req = oauth2!.request(forURL: url)
        req.setValue("application/vnd.bsh.sdk.v1+json", forHTTPHeaderField: "Accept")

        loader!.perform(request: req) { response in
            do {
                DispatchQueue.main.async {
                    let decoder = JSONDecoder()
                    let activeProgram = try? decoder.decode(HomeConnectStruct.self, from: response.responseData())
                    if activeProgram == nil {
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
                    } else {
                        var options: [String] = []
                        let name = "Dishwasher"
                        let step = activeProgram!.data.name
                        var timeRunning = 0
                        var timeRemaining = 0
                        for option in activeProgram!.data.options {
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
                }
            }
        }
    }
}
