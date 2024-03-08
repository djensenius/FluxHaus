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

// MARK: - Location services
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    private var status: CLAuthorizationStatus?

    private var location: CLLocation?

    @Published var weather: Weather?
    
    func fetchTheWeather() async {
        let location = self.location ?? CLLocation(latitude: 43.44, longitude: -80.49)
        let weatherService = WeatherService()
        let weather = try! await weatherService.weather(for: location)
        DispatchQueue.main.async {
            self.weather = weather
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


