//
//  CarHelper.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-04-01.
//

import Foundation

func getCarTime(strDate: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

    if let date = dateFormatter.date(from: strDate) {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(
            for: date,
            relativeTo: Date()
        )
    }

    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    if let date = dateFormatter.date(from: strDate) {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(
            for: date,
            relativeTo: Date()
        )
    }

    return "Unknown"
}
