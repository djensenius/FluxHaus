//
//  Weather.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import Foundation
import CoreLocation
import SwiftUI
import os
@preconcurrency import WeatherKit

private let logger = Logger(
    subsystem: "io.fluxhaus.FluxHaus", category: "Weather"
)

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
@MainActor
@preconcurrency class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var status: CLAuthorizationStatus?
    private var location: CLLocation?
    @Published var weather: Weather?
    @Published var forecast: ForecastInfo?
    @Published var weatherError: String?
    private var retryCount = 0
    private static let maxRetries = 3

    var coordinate: CLLocationCoordinate2D {
        let loc = location ?? CLLocation(latitude: 43.44, longitude: -80.49)
        return loc.coordinate
    }

    func fetchTheWeather() async {
        let loc = self.location ?? CLLocation(
            latitude: 43.44, longitude: -80.49
        )
        let weatherService = WeatherService()
        do {
            let result = try await weatherService.weather(for: loc)
            self.weather = result
            self.weatherError = nil
            self.retryCount = 0
            getPrecipitationSummary()
        } catch {
            logger.error("WeatherKit error: \(error.localizedDescription)")
            if retryCount < Self.maxRetries {
                retryCount += 1
                let delay = UInt64(retryCount * 5)
                logger.info("Retrying weather fetch (\(self.retryCount)/\(Self.maxRetries)) in \(delay)s")
                try? await Task.sleep(for: .seconds(delay))
                await fetchTheWeather()
            } else {
                weatherError = error.localizedDescription
            }
        }
    }

    func precipitationSymbol(type: Precipitation) -> String {
        switch type {
        case .hail: return "cloud.hail.fill"
        case .mixed: return "cloud.sleet.fill"
        case .rain: return "rain.fill"
        case .sleet: return "cloud.sleet.fill"
        case .snow: return "cloud.snow.fill"
        default: return "thermostat"
        }
    }

    func precipitationNow(weather: Weather) {
        for index in 1...59 {
            let minuteForecast = weather.minuteForecast?[index]
            if minuteForecast?.precipitation == Precipitation.none {
                self.forecast = ForecastInfo(
                    type: weather.minuteForecast?[0].precipitation ?? .none,
                    chance: weather.minuteForecast?[0].precipitationChance ?? 0,
                    symbolName: precipitationSymbol(
                        type: weather.minuteForecast?[0].precipitation ?? .rain
                    ),
                    endingNumber: index, endingType: .minute,
                    startingNumber: nil, startingType: nil
                )
                break
            }
        }
        if self.forecast == nil {
            for index in 1...59 {
                let hourly = weather.hourlyForecast[index]
                if hourly.precipitation == Precipitation.none {
                    self.forecast = ForecastInfo(
                        type: weather.minuteForecast?[0].precipitation ?? .none,
                        chance: weather.minuteForecast?[0].precipitationChance ?? 0,
                        symbolName: precipitationSymbol(
                            type: weather.minuteForecast?[0].precipitation ?? .rain
                        ),
                        endingNumber: index, endingType: .hour,
                        startingNumber: nil, startingType: nil
                    )
                    break
                }
            }
        }
    }

    func precipitationToday(weather: Weather) {
        for index in 1...59 {
            let minuteForecast = weather.minuteForecast?[index]
            if minuteForecast?.precipitation != Precipitation.none {
                self.forecast = ForecastInfo(
                    type: weather.minuteForecast?[index].precipitation ?? .none,
                    chance: weather.minuteForecast?[index].precipitationChance ?? 0,
                    symbolName: precipitationSymbol(
                        type: weather.minuteForecast?[index].precipitation ?? .rain
                    ),
                    endingNumber: nil, endingType: nil,
                    startingNumber: index, startingType: .minute
                )
                break
            }
        }
        if self.forecast == nil {
            for index in 1...59 {
                let hourly = weather.hourlyForecast[index]
                if hourly.precipitation != Precipitation.none {
                    self.forecast = ForecastInfo(
                        type: hourly.precipitation,
                        chance: hourly.precipitationChance,
                        symbolName: precipitationSymbol(type: hourly.precipitation),
                        endingNumber: nil, endingType: nil,
                        startingNumber: index, startingType: .hour
                    )
                    break
                }
            }
        }
    }

    func getPrecipitationSummary() {
        guard let weather = self.weather else { return }

        if weather.minuteForecast?[0].precipitation != Precipitation.none {
            precipitationNow(weather: weather)
        }

        if self.forecast == nil {
            let todayChance = weather.dailyForecast[0].precipitationChance
            let tomorrowChance = weather.dailyForecast[1].precipitationChance
            if todayChance > 0.1 {
                precipitationToday(weather: weather)
            } else if tomorrowChance > 0.1 {
                self.forecast = ForecastInfo(
                    type: weather.dailyForecast[1].precipitation,
                    chance: tomorrowChance,
                    symbolName: precipitationSymbol(
                        type: weather.dailyForecast[1].precipitation
                    ),
                    endingNumber: nil, endingType: nil,
                    startingNumber: 1, startingType: .day
                )
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
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        Task { @MainActor in
            self.status = status
        }
    }
    #endif

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            if self.location?.coordinate.longitude != location.coordinate.longitude
                || self.location?.coordinate.latitude != location.coordinate.latitude {
                self.location = location
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        logger.error("Location error: \(error.localizedDescription)")
    }
}
