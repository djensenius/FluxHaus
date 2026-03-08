//
//  WeatherForecastView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-08.
//

import SwiftUI
@preconcurrency import WeatherKit

// MARK: - Hourly Forecast Row

struct HourlyForecastRow: View {
    let weather: Weather

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<24, id: \.self) { index in
                    let hour = weather.hourlyForecast[index]
                    VStack(spacing: 6) {
                        Text(hourLabel(for: hour.date, index: index))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Image(systemName: WeatherHelpers.icon(for: hour.condition))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 18))
                        Text(WeatherHelpers.formatTemp(hour.temperature.value))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                        if hour.precipitationChance > 0.05 {
                            Text("\(Int(hour.precipitationChance * 100))%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Theme.Colors.info)
                        }
                    }
                    .frame(width: 48)
                }
            }
            .padding(.horizontal)
        }
    }

    private func hourLabel(for date: Date, index: Int) -> String {
        if index == 0 { return "Now" }
        let fmt = DateFormatter()
        fmt.dateFormat = "ha"
        return fmt.string(from: date).lowercased()
    }
}

// MARK: - Daily Forecast List

struct DailyForecastList: View {
    let weather: Weather

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<min(10, weather.dailyForecast.count), id: \.self) { idx in
                let day = weather.dailyForecast[idx]
                dailyRow(day: day, index: idx)
                if idx < min(10, weather.dailyForecast.count) - 1 {
                    Divider().padding(.horizontal)
                }
            }
        }
    }

    private func dailyRow(day: DayWeather, index: Int) -> some View {
        HStack {
            Text(dayLabel(for: day.date, index: index))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 44, alignment: .leading)
            Image(systemName: WeatherHelpers.icon(for: day.condition))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 16))
                .frame(width: 28)
            precipBadge(chance: day.precipitationChance)
                .frame(width: 40)
            Spacer()
            tempBar(low: day.lowTemperature.value, high: day.highTemperature.value)
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    private func dayLabel(for date: Date, index: Int) -> String {
        if index == 0 { return "Today" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: date)
    }

    private func precipBadge(chance: Double) -> some View {
        Group {
            if chance > 0.05 {
                Text("\(Int(chance * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.info)
            } else {
                Text("")
            }
        }
    }

    private func tempBar(low: Double, high: Double) -> some View {
        let allDays = Array(weather.dailyForecast.prefix(10))
        let minTemp = allDays.map(\.lowTemperature.value).min() ?? low
        let maxTemp = allDays.map(\.highTemperature.value).max() ?? high
        let range = max(maxTemp - minTemp, 1)

        return HStack(spacing: 6) {
            Text(WeatherHelpers.formatTemp(low))
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 32, alignment: .trailing)
            GeometryReader { geo in
                let totalW = geo.size.width
                let startFrac = (low - minTemp) / range
                let endFrac = (high - minTemp) / range
                let barStart = totalW * startFrac
                let barWidth = max(totalW * (endFrac - startFrac), 4)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(tempGradient)
                        .frame(width: barWidth, height: 4)
                        .offset(x: barStart)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 80, height: 16)
            Text(WeatherHelpers.formatTemp(high))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 32, alignment: .leading)
        }
    }

    private var tempGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.Colors.info, Theme.Colors.warning],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

// MARK: - Combined Forecast Section

struct WeatherForecastSection: View {
    let weather: Weather

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Hourly Forecast", icon: "clock")
            HourlyForecastRow(weather: weather)
            Divider().padding(.horizontal)
            sectionHeader("10-Day Forecast", icon: "calendar")
            DailyForecastList(weather: weather)
        }
        .padding(.vertical)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal)
    }
}
