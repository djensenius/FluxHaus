//
//  Weather.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import SwiftUI

struct WeatherView: View {
    @ObservedObject var lman = LocationManager.init()
    @State private var showModal: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: weatherIcon())
                    .font(Theme.Fonts.bodyMedium)
                    .symbolRenderingMode(.multicolor)
                Text(makeWeatherReport())
                    .task {
                        await lman.startMonitoring()
                        await lman.fetchTheWeather()
                        _ = self.updateTimer
                    }
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                if (lman.weather) != nil {
                    Image(systemName: "wind")
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(getWind())
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.trailing)
                }
            }
            HStack {
                Spacer()
                Text(getFeels())
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.trailing)
            }
            HStack {
                Spacer()
                Image(systemName: "arrow.down.to.line.alt")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(getMin())
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Image(systemName: "arrow.up.to.line.alt")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(getMax())
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.trailing)
            }
            if lman.forecast != nil {
                HStack {
                    Spacer()
                    Image(systemName: forecastIcon())
                        .symbolRenderingMode(getRenderMode())
                        .font(Theme.Fonts.bodyMedium)
                    Text(buildForecast())
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.trailing)

                }
            }
            HStack {
                Spacer()
                if lman.weather?.weatherAlerts?.count ?? 0 > 0 {
                    Button(action: {
                        self.showModal = true
                    }, label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.Fonts.bodyMedium)
                            .symbolRenderingMode(.multicolor)
                        Text("OMG ALERT")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.error)
                    }).sheet(isPresented: self.$showModal) {
                        WeatherAlertView(alerts: lman.weather!.weatherAlerts!)
                    }
                    .font(Theme.Fonts.bodyMedium)
                }
                #if !os(visionOS)
                Link("Details", destination: URL(string: "weather://")!)
                    .padding(.trailing)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.accent)
                #endif
            }
        }
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {_ in
            Task {
                await lman.fetchTheWeather()
            }
        }
    }

    func weatherIcon() -> String {
        if lman.weather == nil {
            return "thermometer"
        }
        let currentWeather = lman.weather!.currentWeather
        return currentWeather.symbolName
    }

    func makeWeatherReport() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let currentWeather = lman.weather!.currentWeather
        let currentTemp = currentWeather.temperature
            .converted(to: .celsius)
            .formatted(.measurement(usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        let weatherDescription = currentWeather.condition.description
        return "\(currentTemp), \(weatherDescription)"
    }

    func getWind() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let currentWeather = lman.weather!.currentWeather
        let windSpeed = currentWeather.wind.speed
        let speedText = windSpeed
            .formatted()
        return speedText.description
    }

    func getFeels() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let currentWeather = lman.weather!.currentWeather
        let humidity = String(format: "%.0f", round(currentWeather.humidity * 100))
        let feelsLike = currentWeather.apparentTemperature
            .converted(to: .celsius)
            .formatted(.measurement(usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        return "Feels Like \(feelsLike), \(humidity)% Humidity"

    }

    func getMin() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let min = lman.weather!.dailyForecast[0].lowTemperature
            .converted(to: .celsius)
            .formatted(.measurement(usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        return String("\(min)")
    }

    func getMax() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let max = lman.weather!.dailyForecast[0].highTemperature
            .converted(to: .celsius)
            .formatted(.measurement(usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        return String("\(max)")
    }

    func forecastIcon() -> String {
        if lman.forecast == nil {
            return "thermometer"

        }
        if lman.forecast!.symbolName == "rain.fill" {
            return "cloud.rain.fill"
        }
        return lman.forecast!.symbolName
    }

    func getRenderMode() -> SymbolRenderingMode {
        var renderingMode: SymbolRenderingMode = .multicolor
        #if !os(visionOS)
        if colorScheme == .light {
            renderingMode = .monochrome
        }
        #endif
        return renderingMode
    }

    func getTime(time: Int, type: TimeType) -> String {
        if time > 1 {
            switch type {
            case .day:
                return "\(time) days"
            case .hour:
                return "\(time) hours"
            case .minute:
                return "\(time) minutes"
            }
        }
        switch type {
        case .day:
            return "\(time) day"
        case .hour:
            return "\(time) hour"
        case .minute:
            return "\(time) minute"
        }
    }

    func buildForecast() -> String {
        let forecast = lman.forecast!
        let percent = "\(String(format: "%.0f", forecast.chance * 100))%"
        let type = forecast.type
        var theWhen = ""
        if forecast.endingNumber != nil {
            theWhen = "ending in  \(getTime(time: forecast.endingNumber!, type: forecast.endingType!))"
        } else {
            theWhen = "starting in \(getTime(time: forecast.startingNumber!, type: forecast.startingType!))"
        }
        return "\(percent) chance of \(type) \(theWhen)"
    }
}

#Preview {
    WeatherView()
}
