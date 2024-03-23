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

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: weatherIcon())
                    .font(.subheadline)
                    .symbolRenderingMode(.multicolor)
                Text(makeWeatherReport())
                    .task {
                        await lman.startMonitoring()
                        await lman.fetchTheWeather()
                        _ = self.updateTimer
                    }
                    .font(.subheadline)
                if (lman.weather) != nil {
                    Image(systemName: "wind")
                    Text((lman.weather!.currentWeather.wind.speed.description))
                        .font(.subheadline)
                        .padding(.trailing)
                }
            }
            HStack {
                Spacer()
                Text(getFeels())
                    .font(.subheadline)
                    .padding(.horizontal)
            }
            HStack {
                Spacer()
                Image(systemName: "arrow.down.to.line.alt")
                    .font(.subheadline)
                Text(getMin())
                    .font(.subheadline)
                Image(systemName: "arrow.up.to.line.alt")
                    .font(.subheadline)
                Text(getMax())
                    .font(.subheadline)
                    .padding(.trailing)
            }
            if lman.forecast != nil {
                HStack {
                    Spacer()
                    Image(systemName: forecastIcon())
                        .symbolRenderingMode(.multicolor)
                    Text(buildForecast())
                        .padding(.trailing)
                        .font(.subheadline)
                }
            }
            HStack {
                Spacer()
                if lman.weather?.weatherAlerts?.count ?? 0 > 0 {
                    Button(action: {
                        self.showModal = true
                    }, label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .symbolRenderingMode(.multicolor)
                        Text("OMG ALERT")
                            .font(.subheadline)
                    }).sheet(isPresented: self.$showModal) {
                        WeatherAlertView(alerts: lman.weather!.weatherAlerts!)
                    }
                    .font(.subheadline)
                }
                Link("Details", destination: URL(string: "weather://")!)
                    .padding(.trailing)
                    .font(.subheadline)
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
            .formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        let weatherDescription = currentWeather.condition.description
        return "\(currentTemp), \(weatherDescription)"
    }

    func getFeels() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let currentWeather = lman.weather!.currentWeather
        let humidity = currentWeather.humidity
        let feelsLike = currentWeather.apparentTemperature
            .formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        return "Feels Like \(feelsLike), \(humidity)% Humidity"

    }

    func getMin() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let min = lman.weather!.dailyForecast[0].lowTemperature
            .formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        return String("\(min)")
    }

    func getMax() -> String {
        if lman.weather == nil {
            return "Loading"
        }
        let max = lman.weather!.dailyForecast[0].highTemperature
            .formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        return String("\(max)")
    }

    func forecastIcon() -> String {
        if lman.forecast == nil {
            return "thermometer"

        }
        return lman.forecast!.symbolName
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
        let percent = "\(forecast.chance * 100)%"
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

struct Weather_Previews: PreviewProvider {
    static var previews: some View {
        WeatherView()
    }
}
