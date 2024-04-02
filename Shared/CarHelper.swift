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
    let date = dateFormatter.date(from: String(strDate))!.timeIntervalSince1970
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(
        for: Date.init(timeIntervalSince1970: TimeInterval(date)),
        relativeTo: Date()
    )
}
