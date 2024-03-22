//
//  Weather.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import SwiftUI

struct WeatherView: View {
    @ObservedObject var lm = LocationManager.init()
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
                        await lm.startMonitoring()
                        await lm.fetchTheWeather()
                        let _ = self.updateTimer
                    }
                    .font(.subheadline)
                if ((lm.weather) != nil) {
                    Image(systemName: "wind")
                    Text((lm.weather!.currentWeather.wind.speed.description))
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
            if (lm.forecast != nil) {
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
                if lm.weather?.weatherAlerts?.count ?? 0 > 0 {
                    Button(action: {
                        self.showModal = true
                    }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .symbolRenderingMode(.multicolor)
                        Text("OMG ALERT")
                            .font(.subheadline)
                    }.sheet(isPresented: self.$showModal) {
                        WeatherAlertView(alerts: lm.weather!.weatherAlerts!)
                    }
                    .padding(.trailing)
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
                await lm.fetchTheWeather()
            }
        }
    }

    func weatherIcon() -> String {
        if (lm.weather == nil) {
            return "thermometer"

        }
        let currentWeather = lm.weather!.currentWeather
        return currentWeather.symbolName
    }

    func makeWeatherReport() -> String {
        if (lm.weather == nil) {
            return "Loading"
        }
        let currentWeather = lm.weather!.currentWeather
        let currentTemp = currentWeather.temperature.formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        let weatherDescription = currentWeather.condition.description
        return "\(currentTemp), \(weatherDescription)"
    }

    func getFeels() -> String {
        if (lm.weather == nil) {
            return "Loading"
        }
        let currentWeather = lm.weather!.currentWeather
        let humidity = currentWeather.humidity
        let feelsLike = currentWeather.apparentTemperature.formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        return "Feels Like \(feelsLike), \(humidity)% Humidity"

    }

    func getMin() -> String {
        if (lm.weather == nil) {
            return "Loading"
        }
        let min = lm.weather!.dailyForecast[0].lowTemperature.formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        return String("\(min)")
    }

    func getMax() -> String {
        if (lm.weather == nil) {
            return "Loading"
        }
        let max = lm.weather!.dailyForecast[0].highTemperature.formatted(.measurement(numberFormatStyle: .number.precision(.fractionLength(0))))
        return String("\(max)")
    }
    
    func forecastIcon() -> String {
        if (lm.forecast == nil) {
            return "thermometer"

        }
        return lm.forecast!.symbolName
    }
    
    func getTime(time: Int, type: TimeType) -> String {
        if (time > 1) {
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
        let forecast = lm.forecast!
        let percent = "\(forecast.chance * 100)%"
        let type = forecast.type
        var theWhen = ""
        if (forecast.endingNumber != nil) {
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
