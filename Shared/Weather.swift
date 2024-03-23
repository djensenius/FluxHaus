//
//  Weather.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import Foundation
import CoreLocation
import Combine
import WeatherKit

enum TimeType {
    case minute
    case hour
    case day
}

struct ForecastInfo {
    let type: Precipitation
    let chance: Double
    let symbolName: String
    let endingNumber: Int?
    let endingType: TimeType?
    let startingNumber: Int?
    let startingType: TimeType?
}

// MARK: - Location services
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    private var status: CLAuthorizationStatus?

    private var location: CLLocation?

    @Published var weather: Weather?
    @Published var forecast: ForecastInfo?

    func fetchTheWeather() async {
        let location = self.location ?? CLLocation(latitude: 43.44, longitude: -80.49)
        let weatherService = WeatherService()
        do {
            let weather = try await weatherService.weather(for: location)
            DispatchQueue.main.async {
                self.weather = weather
                self.getPrecipitationSummary()
            }
        } catch {
            print("Error fetching weather")
        }
    }

    func precipitationSymbol(type: Precipitation) -> String {
        switch type {
        case .hail:
            return "cloud.hail.fill"
        case .mixed:
            return "cloud.sleet.fill"
        case .rain:
            return "rain.fill"
        case .sleet:
            return "cloud.sleet.fill"
        case .snow:
            return "cloud.snow.fill"
        default:
            return "thermostat"
        }
    }

    func getPrecipitationSummary() {
        if self.weather != nil {
            let weather = self.weather!
            var forecast: ForecastInfo?

            // CHECK IF IT IS HAPPENING
            if weather.minuteForecast?[0].precipitation != Precipitation.none {
                for index in 1...59 {
                    let minuteForecast = weather.minuteForecast?[index]
                    if minuteForecast?.precipitation == Precipitation.none {
                        forecast = ForecastInfo(
                            type: weather.minuteForecast![0].precipitation,
                            chance: weather.minuteForecast![0].precipitationChance,
                            symbolName: precipitationSymbol(type: weather.minuteForecast![0].precipitation),
                            endingNumber: index,
                            endingType: .minute,
                            startingNumber: nil,
                            startingType: nil
                        )
                        DispatchQueue.main.async {
                            self.forecast = forecast
                        }
                        break
                    }
                }
                if forecast == nil {
                    for index in 1...59 {
                        let hourlyForecast = weather.hourlyForecast[index]
                        if hourlyForecast.precipitation == Precipitation.none {
                            forecast = ForecastInfo(
                                type: weather.minuteForecast![0].precipitation,
                                chance: weather.minuteForecast![0].precipitationChance,
                                symbolName: precipitationSymbol(type: weather.minuteForecast![0].precipitation),
                                endingNumber: index,
                                endingType: .hour,
                                startingNumber: nil,
                                startingType: nil
                            )
                            DispatchQueue.main.async {
                                self.forecast = forecast
                            }
                            break
                        }
                    }
                }
            }

            if forecast == nil {
                // Check today
                if (self.weather?.dailyForecast[0].precipitationChance)! > 0.1 {
                    for index in 1...59 {
                        let minuteForecast = weather.minuteForecast?[index]
                        if minuteForecast?.precipitation != Precipitation.none {
                            forecast = ForecastInfo(
                                type: weather.minuteForecast![index].precipitation,
                                chance: weather.minuteForecast![index].precipitationChance,
                                symbolName: precipitationSymbol(type: weather.minuteForecast![index].precipitation),
                                endingNumber: nil,
                                endingType: nil,
                                startingNumber: index,
                                startingType: .minute
                            )
                            DispatchQueue.main.async {
                                self.forecast = forecast
                            }
                            break
                        }
                    }
                    if forecast == nil {
                        for index in 1...59 {
                            let hourlyForecast = weather.hourlyForecast[index]
                            if hourlyForecast.precipitation != Precipitation.none {
                                forecast = ForecastInfo(
                                    type: weather.hourlyForecast[index].precipitation,
                                    chance: weather.hourlyForecast[index].precipitationChance,
                                    symbolName: precipitationSymbol(type: weather.hourlyForecast[index].precipitation),
                                    endingNumber: nil,
                                    endingType: nil,
                                    startingNumber: index,
                                    startingType: .hour
                                )
                                DispatchQueue.main.async {
                                    self.forecast = forecast
                                }
                                break
                            }
                        }
                    }
                } else if (self.weather?.dailyForecast[1].precipitationChance)! > 0.1 {
                    // TOMORROW IT WILL HAPPEN
                    forecast = ForecastInfo(
                        type: weather.dailyForecast[1].precipitation,
                        chance: weather.dailyForecast[1].precipitationChance,
                        symbolName: precipitationSymbol(type: weather.dailyForecast[1].precipitation),
                        endingNumber: nil,
                        endingType: nil,
                        startingNumber: 1,
                        startingType: .day
                    )
                    DispatchQueue.main.async {
                        self.forecast = forecast
                    }
                }
            }
        }
    }

    func startMonitoring() async {
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.locationManager.requestWhenInUseAuthorization()
        #if os(visionOS)
        self.locationManager.requestLocation()
        #endif
        #if !os(visionOS)
        self.locationManager.startMonitoringSignificantLocationChanges()
        #endif
        if weather == nil {
            await fetchTheWeather()
        }
    }

    #if !os(visionOS)
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.status = status
    }
    #endif

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if self.location?.coordinate.longitude != location.coordinate.longitude ||
                self.location?.coordinate.latitude != location.coordinate.latitude {
            self.location = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        debugPrint(error)
    }
}
