//
//  Battery.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation
import UIKit

enum Model {
    case iPhone
    case iPad
    case visionPro
    case mac
}
@Observable class Battery {
    var percent = 0
    var state = UIDevice.BatteryState.unknown
    var model = Model.iPhone
    
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if UIDevice.current.model == "iPhone" {
            self.model = Model.iPhone
        } else if UIDevice.current.model == "iPad" {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                self.model = Model.mac
            } else {
                self.model = Model.iPad
            }
        } else {
            self.model = Model.visionPro
        }
        NotificationCenter.default.addObserver(self, selector: #selector(batteryLevelDidChange(notification:)), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryStateDidChange(notification:)), name: UIDevice.batteryStateDidChangeNotification, object: nil)
    }
    @objc func batteryLevelDidChange(notification: Notification) {
         percent = Int(UIDevice.current.batteryLevel * 100)
     }
     
     @objc func batteryStateDidChange(notification: Notification) {
         state = UIDevice.current.batteryState
     }
}
