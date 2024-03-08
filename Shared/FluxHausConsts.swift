//
//  FluxHausConsts.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation

struct FluxHausConsts {
    static let mieleClientId = ProcessInfo.processInfo.environment["mieleClientId"]!
    static let mieleSecretId = ProcessInfo.processInfo.environment["mieleSecretId"]!
    static let mieleAppliances = try! JSONSerialization.jsonObject(with: Data(ProcessInfo.processInfo.environment["mieleAppliances"]!.utf8)) as! [String]
    static let boschClientId = ProcessInfo.processInfo.environment["boschClientId"]!
    static let boschSecretId = ProcessInfo.processInfo.environment["boschSecretId"]!
    static let boschAppliance = ProcessInfo.processInfo.environment["boschAppliance"]!
    static let favouriteHomeKit = try! JSONSerialization.jsonObject(with: Data(ProcessInfo.processInfo.environment["favouriteHomeKit"]!.utf8)) as! [String]
}

