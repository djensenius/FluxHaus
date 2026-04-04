//
//  CarHelper.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-04-01.
//

import Foundation

func relativeTimeString(from strDate: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

    if let date = dateFormatter.date(from: strDate) {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    if let date = dateFormatter.date(from: strDate) {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    return "Unknown"
}

func clockTimeString(from strDate: String) -> String {
    let dateFormatter = DateFormatter()
    let outputFormatter = DateFormatter()
    outputFormatter.timeStyle = .short
    outputFormatter.dateStyle = .none

    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    if let date = dateFormatter.date(from: strDate) {
        return outputFormatter.string(from: date)
    }

    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    if let date = dateFormatter.date(from: strDate) {
        return outputFormatter.string(from: date)
    }

    return "Unknown"
}
