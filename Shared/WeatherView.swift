//
//  Weather.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import SwiftUI

struct Weather: View {
    @ObservedObject var lm = LocationManager.init()
    @State private var showModal: Bool = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(weatherIcon())
                    .font(.subheadline)
                Text(makeWeatherReport())
                    .onAppear(perform: {
                        lm.startMonitoring()
                        let _ = self.updateTimer
                    })
                    .font(.subheadline)
                if ((lm.weather.current) != nil) {
                    Image(systemName: "wind")
                    Text("\(Int(round((lm.weather.current!.windSpeed * 18) / 5))) km/h")
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
                if lm.weather.alerts?.count ?? 0 > 0 {
                    Button(action: {
                        self.showModal = true
                    }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                        Text("OMG ALERT")
                            .font(.subheadline)
                    }.sheet(isPresented: self.$showModal) {
                        // Hi
                        WeatherAlertView(alerts: lm.weather.alerts!)
                    }
                }
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

        }

        let currentWeather = lm.weather.current!
        switch currentWeather.weather[0].icon {
        case "01d":
            return Image(systemName: "sun.max.min")
        case "02d":
            return Image(systemName: "cloud.sun.fill")
        case "03d":
            return Image(systemName: "cloud.fill")
        case "04d":
            return Image(systemName: "cloud.fill")
        case "09d":
            return Image(systemName: "cloud.rain.fill")
        case "10d":
            return Image(systemName: "cloud.sun.rain.fill")
        case "11d":
            return Image(systemName: "cloud.sun.bolt.fill")
        case "13d":
            return Image(systemName: "snow")
        case "50d":
            return Image(systemName: "cloud.fog.fill")
        case "01n":
            return Image(systemName: "moon.fill")
        case "02n":
            return Image(systemName: "cloud.moon.fill")
        case "03n":
            return Image(systemName: "cloud.fill")
        case "04n":
            return Image(systemName: "cloud.fill")
        case "09n":
            return Image(systemName: "cloud.rain.fill")
        case "10n":
            return Image(systemName: "cloud.moon.rain.fill")
        case "11n":
            return Image(systemName: "cloud.moon.bolt.fill")
        case "13n":
            return Image(systemName: "cloud.snow.fill")
        case "50n":
            return Image(systemName: "cloud.fog.fill")
        default:
            return Image(systemName: "thermometer")
        }
    }

    func makeWeatherReport() -> String {
        if (lm.weather.current == nil) {
            return "Loading"
        }
        let currentWeather = lm.weather.current!
        let currentTemp = Int(round(currentWeather.temp - 273.15))
        let weatherDescription = currentWeather.weather[0].weatherDescription
        return "\(currentTemp)°, \(weatherDescription.capitalized)"
    }

    func getFeels() -> String {
        if (lm.weather.current == nil) {
            return "Loading"
        }
        let currentWeather = lm.weather.current!
        let humidity = currentWeather.humidity
        let feelsLike = Int(round(currentWeather.feelsLike - 273.15))
        return "Feels Like \(feelsLike)°, \(humidity)% Humidity"

    }

    func getMin() -> String {
        if (lm.weather.current == nil) {
            return "Loading"
        }
        let min = Int(round(lm.weather.daily[0].temp.min - 273.15))
        return String("\(min)°")
    }

    func getMax() -> String {
        if (lm.weather.current == nil) {
            return "Loading"
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
