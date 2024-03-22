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
        let weather = try! await weatherService.weather(for: location)
        DispatchQueue.main.async {
            self.weather = weather
            self.getPrecipitationSummary()
        }
    }
    
    func getPrecipitationSummary() {
        if self.weather != nil {
            let weather = self.weather!
            var forecast: ForecastInfo? = nil

            // CHECK IF IT IS HAPPENING
            if weather.minuteForecast?[0].precipitation != Precipitation.none {
                for index in 1...59 {
                    let minuteForecast = weather.minuteForecast?[index]
                    if minuteForecast?.precipitation == Precipitation.none {
                        forecast = ForecastInfo(
                            type: weather.minuteForecast![0].precipitation,
                            chance: weather.minuteForecast![0].precipitationChance,
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
                if ((self.weather?.dailyForecast[1].precipitationChance)! > 0.1) {
                    // TODAY IT WILL HAPPEN
                } else if ((self.weather?.dailyForecast[1].precipitationChance)! > 0.1) {
                    // TOMORROW IT WILL HAPPEN
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
        if (weather == nil) {
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
        if (self.location?.coordinate.longitude != location.coordinate.longitude ||
                self.location?.coordinate.latitude != location.coordinate.latitude) {
            self.location = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        debugPrint(error)
    }
}


