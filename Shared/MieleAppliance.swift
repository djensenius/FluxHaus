//
//  MieleAppliance.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-23.
//

import Foundation

// MARK: - New format
struct WasherDryer: Codable {
    var name: String
    var timeRunning: Int?
    var timeRemaining: Int?
    var step: String?
    var programName: String?
    var status: String?
    var inUse: Bool
}
