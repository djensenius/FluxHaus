//
//  Scooter.swift
//  FluxHaus
//

import Foundation

@MainActor
@Observable class Scooter {
    var apiResponse: Api?
    var summary = ScooterSummary()

    private static let gearNames: [Int: String] = [1: "Eco", 2: "Standard", 3: "Sport", 4: "Race"]

    static func gearName(_ mode: Int?) -> String {
        guard let mode = mode else { return "Unknown" }
        return gearNames[mode] ?? "Mode \(mode)"
    }

    func setApiResponse(apiResponse: Api) {
        self.apiResponse = apiResponse
        fetchScooterDetails()
    }

    func fetchScooterDetails() {
        if let response = apiResponse?.response,
           let scooterData = response.scooter {
            DispatchQueue.main.async {
                self.summary = scooterData
            }
        }
    }

    var formattedOdometer: String {
        guard let odo = summary.odometer else { return "—" }
        return String(format: "%.1f km", odo)
    }

    var formattedTotalRideTime: String {
        guard let seconds = summary.totalRideTime else { return "—" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var formattedLastRideDistance: String {
        guard let dist = summary.lastRide?.distance else { return "—" }
        return dist < 1 ? String(format: "%.0f m", dist * 1000) : String(format: "%.1f km", dist)
    }

    var formattedLastRideDate: String {
        guard let dateStr = summary.lastRide?.date else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr)
                ?? ISO8601DateFormatter().date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
