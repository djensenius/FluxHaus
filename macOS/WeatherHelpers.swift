//
//  WeatherHelpers.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import Foundation
import WeatherKit

enum WeatherHelpers {
    private nonisolated(unsafe) static let tempFormatter: MeasurementFormatter = {
        let fmt = MeasurementFormatter()
        fmt.numberFormatter.maximumFractionDigits = 0
        return fmt
    }()

    static func formatTemp(_ value: Double) -> String {
        tempFormatter.string(from: Measurement(
            value: value, unit: UnitTemperature.celsius
        ))
    }

    static func formatSpeed(_ value: Double) -> String {
        tempFormatter.string(from: Measurement(
            value: value, unit: UnitSpeed.kilometersPerHour
        ))
    }

    private static let conditionIcons: [WeatherCondition: String] = [
        .clear: "sun.max.fill", .mostlyClear: "sun.max.fill",
        .cloudy: "cloud.fill", .mostlyCloudy: "cloud.fill",
        .partlyCloudy: "cloud.sun.fill",
        .rain: "cloud.rain.fill", .heavyRain: "cloud.rain.fill",
        .drizzle: "cloud.drizzle.fill",
        .snow: "cloud.snow.fill", .heavySnow: "cloud.snow.fill", .flurries: "cloud.snow.fill",
        .sleet: "cloud.sleet.fill", .freezingRain: "cloud.sleet.fill",
        .thunderstorms: "cloud.bolt.fill",
        .foggy: "cloud.fog.fill", .haze: "cloud.fog.fill",
        .windy: "wind", .breezy: "wind"
    ]

    static func icon(for condition: WeatherCondition) -> String {
        conditionIcons[condition] ?? "cloud"
    }

    static func precipitationText(from forecast: ForecastInfo) -> String? {
        let chance = Int(forecast.chance * 100)
        if let endNum = forecast.endingNumber, let endType = forecast.endingType {
            let unit = endType == .minute ? "min" : "hr"
            return "\(forecast.type.description) ending in \(endNum) \(unit) (\(chance)%)"
        }
        if let startNum = forecast.startingNumber, let startType = forecast.startingType {
            if startType == .day {
                return "\(forecast.type.description) tomorrow (\(chance)%)"
            }
            let unit = startType == .minute ? "min" : "hr"
            return "\(forecast.type.description) in \(startNum) \(unit) (\(chance)%)"
        }
        return nil
    }
}
