//
//  HomeAPI.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation
import UIKit

// MARK: - Miele

class Miele: ObservableObject {
    @Published var appliances: [Appliance] = []

    init() {
        appliances = []
    }

    func setAppliance(appliance: Appliance) {
        DispatchQueue.main.async {
            var found = false
            for (index, app) in self.appliances.enumerated() where app.name == appliance.name {
                self.appliances[index] = appliance
                found = true
            }
            if found == false {
                self.appliances.append(appliance)
            }
            NotificationCenter.default.post(
                name: Notification.Name.loginsUpdated,
                object: nil,
                userInfo: ["mieleComplete": true]
            )
        }
    }

    func updateAppliance(mApps: WasherDryer) {
        let inUse = mApps.inUse
        let programName = mApps.programName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentDate = Date()
        var finishTime: Date

        finishTime = Calendar.current.date(
            byAdding: .minute,
            value: mApps.timeRemaining ?? 0,
            to: currentDate
        ) ?? currentDate

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let formatedTime = formatter.string(from: finishTime)
        let name = mApps.name

        let elapsedTime = mApps.timeRunning
        let appliance = Appliance(
            name: name,
            timeRunning: elapsedTime ?? 0,
            timeRemaining: mApps.timeRemaining ?? 0,
            timeFinish: formatedTime,
            step: mApps.step?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            programName: programName!,
            inUse: inUse
        )
        setAppliance(appliance: appliance)
    }

    func fetchAppliance(appliance: String) {
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
                        NotificationCenter.default.post(
                            name: Notification.Name.loginsUpdated,
                            object: nil,
                            userInfo: ["mieleComplete": true]
                        )
                        self.updateAppliance(mApps: response.washer)
                        self.updateAppliance(mApps: response.dryer)
                        // self.updateAppliance(mApps: response.miele[appliance]!)
                    }
                }
            }
        }
        task.resume()
    }
}
