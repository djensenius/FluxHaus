//
//  HomeAPI.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation
import OAuth2
import UIKit

// MARK: - Miele

class Miele: ObservableObject {
    @Published var appliances: [Appliance] = []

    init() {
        appliances = []
        DispatchQueue.main.async {
            oauth2Miele!.authConfig.authorizeEmbedded = true
            oauth2Miele!.authConfig.ui.useAuthenticationSession = true
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene

            let rootViewController = scene?
                .windows.first(where: { $0.isKeyWindow })?
                .rootViewController
            oauth2Miele!.authConfig.authorizeContext = rootViewController
        }
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
    func updateAppliance(mApps: MieleAppliances) {
        let inUse = (
            mApps.stateType.status.valueLocalized == "Off" ||
            mApps.stateType.status.valueLocalized == "Not connected"
        ) ? false: true
        let programName = mApps.stateType.programID.valueLocalized
        let currentDate = Date()
        var finishTime: Date
        if mApps.stateType.remainingTime.count > 0 {
            finishTime = Calendar.current.date(
                byAdding: .minute,
                value: mApps.stateType.remainingTime[1] + (60 * mApps.stateType.remainingTime[0]),
                to: currentDate
            ) ?? currentDate
        } else {
            finishTime = currentDate
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let formatedTime = formatter.string(from: finishTime)
        var name = mApps.ident.type.valueLocalized ?? ""
        if mApps.ident.type.valueLocalized == "Washing Machine" {
            name = "Washer"
        } else if mApps.ident.type.valueLocalized == "Clothes Dryer" {
            name = "Dryer"
        }
        var timeRemaining0 = 0
        var timeRemaining1 = 0
        if mApps.stateType.remainingTime.count > 1 {
            timeRemaining0 = mApps.stateType.remainingTime[0]
            timeRemaining1 = mApps.stateType.remainingTime[1]
        }

        var elapsedTime = 0
        if mApps.stateType.elapsedTime.count > 1 {
            elapsedTime = mApps.stateType.elapsedTime[1]
        }
        let appliance = Appliance(
            name: name,
            timeRunning: elapsedTime,
            timeRemaining: (timeRemaining0 * 60) + timeRemaining1,
            timeFinish: formatedTime,
            step: mApps.stateType.programPhase.valueLocalized ?? "",
            programName: programName!,
            inUse: inUse
        )
        setAppliance(appliance: appliance)
    }

    func fetchAppliance(appliance: String) {
        let base = URL(string: "https://api.mcs3.miele.com")!
        let url = base.appendingPathComponent("v1/devices/\(appliance)?language=en")

        var req = oauth2Miele!.request(forURL: url)
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
       // oauth2Miele.logger = OAuth2DebugLogger(.trace)

        loaderMiele!.perform(request: req) { response in
            do {
                let decoder = JSONDecoder()
                if let mApps = try? decoder.decode(MieleAppliances.self, from: response.responseData()) {
                    self.updateAppliance(mApps: mApps)
                } else {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name.loginsUpdated,
                            object: nil,
                            userInfo: ["mieleComplete": true]
                        )
                    }
                }
            }
        }
    }
}
