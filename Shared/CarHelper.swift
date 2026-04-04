//
//  CarHelper.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-04-01.
//

import Foundation

private let posixLocale = Locale(identifier: "en_US_POSIX")

private let isoMillisFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.locale = posixLocale
    fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    return fmt
}()

private let isoSecondsFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.locale = posixLocale
    fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    return fmt
}()

private let shortTimeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.timeStyle = .short
    fmt.dateStyle = .none
    return fmt
}()

private func parseDateString(_ strDate: String) -> Date? {
    isoMillisFormatter.date(from: strDate) ?? isoSecondsFormatter.date(from: strDate)
}

func relativeTimeString(from strDate: String) -> String {
    guard let date = parseDateString(strDate) else { return "Unknown" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

func clockTimeString(from strDate: String) -> String {
    guard let date = parseDateString(strDate) else { return "Unknown" }
    return shortTimeFormatter.string(from: date)
}
