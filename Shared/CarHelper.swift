//
//  CarHelper.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-04-01.
//

import Foundation

func getCarTime(strDate: String) -> String {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var date = isoFormatter.date(from: strDate)
    if date == nil {
        isoFormatter.formatOptions = [.withInternetDateTime]
        date = isoFormatter.date(from: strDate)
    }

    if let date {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(
            for: date,
            relativeTo: Date()
        )
    }

    return "Unknown"
}
