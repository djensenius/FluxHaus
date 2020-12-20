//
//  Weather.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import SwiftUI

struct Weather: View {
    @ObservedObject var lm = LocationManager.init()

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(weatherIcon())
                    .font(.subheadline)
                Text(makeWeatherReport())
                    .accentColor(.white)
                    .onAppear(perform: {
                        lm.startMonitoring()
                        let _ = self.updateTimer
                    })
                    .font(.subheadline)
                    .padding(.trailing)
            }
            HStack {
                Spacer()
                Text(getFeels())
                    .accentColor(.white)
                    .font(.subheadline)
                    .padding(.horizontal)
            }
            HStack {
                Spacer()
                Image(systemName: "arrow.down.to.line.alt")
                    .accentColor(.white)
                    .font(.subheadline)
                Text(getMin())
                    .accentColor(.white)
                    .font(.subheadline)
                Image(systemName: "arrow.up.to.line.alt")
                    .accentColor(.white)
                    .font(.subheadline)
                Text(getMax())
                    .accentColor(.white)
                    .font(.subheadline)
                    .padding(.trailing)
            }
        }
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true,
                             block: {_ in
                                lm.fetchTheWeather()
                             })
    }

    func weatherIcon() -> Image {
        if (lm.weather.current == nil) {
            return Image(systemName: "thermometer")
                .renderingMode(.original)

        }

        let currentWeather = lm.weather.current!
        switch currentWeather.weather[0].icon {
        case "01d":
            return Image(systemName: "sun.max.min")
                .renderingMode(.original)
        case "02d":
            return Image(systemName: "cloud.sun.fill")
                .renderingMode(.original)
        case "03d":
            return Image(systemName: "cloud.fill")
                .renderingMode(.original)
        case "04d":
            return Image(systemName: "cloud.fill")
                .renderingMode(.original)
        case "09d":
            return Image(systemName: "cloud.rain.fill")
                .renderingMode(.original)
        case "10d":
            return Image(systemName: "cloud.sun.rain.fill")
                .renderingMode(.original)
        case "11d":
            return Image(systemName: "cloud.sun.bolt.fill")
                .renderingMode(.original)
        case "13d":
            return Image(systemName: "snow")
                .renderingMode(.original)
        case "50d":
            return Image(systemName: "cloud.fog.fill")
                .renderingMode(.original)
        case "01n":
            return Image(systemName: "moon.fill")
        case "02n":
            return Image(systemName: "cloud.moon.fill")
                .renderingMode(.original)
        case "03n":
            return Image(systemName: "cloud.fill")
                .renderingMode(.original)
        case "04n":
            return Image(systemName: "cloud.fill")
                .renderingMode(.original)
        case "09n":
            return Image(systemName: "cloud.rain.fill")
                .renderingMode(.original)
        case "10n":
            return Image(systemName: "cloud.moon.rain.fill")
                .renderingMode(.original)
        case "11n":
            return Image(systemName: "cloud.moon.bolt.fill")
                .renderingMode(.original)
        case "13n":
            return Image(systemName: "cloud.snow.fill")
                .renderingMode(.original)
        case "50n":
            return Image(systemName: "cloud.fog.fill")
                .renderingMode(.original)
        default:
            return Image(systemName: "thermometer")
                .renderingMode(.original)
        }
    }

    func makeWeatherReport() -> String {
        if (lm.weather.current == nil) {
            return ""
        }
        let currentWeather = lm.weather.current!
        let currentTemp = Int(round(currentWeather.temp - 273.15))
        let weatherDescription = currentWeather.weather[0].weatherDescription
        return "\(currentTemp)°, \(weatherDescription.capitalized)"
    }

    func getFeels() -> String {
        if (lm.weather.current == nil) {
            return ""
        }
        let currentWeather = lm.weather.current!
        let humidity = currentWeather.humidity
        let feelsLike = Int(round(currentWeather.feelsLike - 273.15))
        return "Feels Like \(feelsLike)°, \(humidity)% Humidity"

    }

    func getMin() -> String {
        if (lm.weather.current == nil) {
            return ""
        }
        let min = Int(round(lm.weather.daily[0].temp.min - 273.15))
        return String("\(min)°")
    }

    func getMax() -> String {
        if (lm.weather.current == nil) {
            return ""
        }
        let max = Int(round(lm.weather.daily[0].temp.max - 273.15))
        return String("\(max)°")
    }

}

struct Weather_Previews: PreviewProvider {
    static var previews: some View {
        Weather()
    }
}
