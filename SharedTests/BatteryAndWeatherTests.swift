//
//  BatteryAndWeatherTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation
@testable import FluxHaus

struct BatteryAndWeatherTests {

    @Test("Model enum contains all expected device types")
    func testModelEnum() {
        let models: [Model] = [.iPhone, .iPad, .visionPro, .mac]

        #expect(models.count == 4)
        #expect(models.contains(.iPhone))
        #expect(models.contains(.iPad))
        #expect(models.contains(.visionPro))
        #expect(models.contains(.mac))
    }

    @Test("Battery class can be initialized")
    func testBatteryInitialization() async {
        await MainActor.run {
            let battery = Battery()

            // Test initial state
            #expect(battery.percent >= 0)
            #expect(battery.percent <= 100)

            // Test that model is set to a valid value
            let validModels: [Model] = [.iPhone, .iPad, .visionPro, .mac]
            #expect(validModels.contains(battery.model))
        }
    }

    @Test("Battery percentage is within valid range")
    func testBatteryPercentageRange() async {
        await MainActor.run {
            let battery = Battery()

            // Battery percentage should always be between 0 and 100
            #expect(battery.percent >= 0)
            #expect(battery.percent <= 100)

            // Test manual percentage setting
            battery.percent = 85
            #expect(battery.percent == 85)

            battery.percent = 0
            #expect(battery.percent == 0)

            battery.percent = 100
            #expect(battery.percent == 100)
        }
    }

    @Test("Battery model detection logic is consistent")
    func testBatteryModelDetection() async {
        await MainActor.run {
            let battery = Battery()

            // Test that model is one of the expected values
            let validModels: [Model] = [.iPhone, .iPad, .visionPro, .mac]
            #expect(validModels.contains(battery.model))

            // Test model assignment
            battery.model = .iPad
            #expect(battery.model == .iPad)

            battery.model = .mac
            #expect(battery.model == .mac)

            battery.model = .visionPro
            #expect(battery.model == .visionPro)

            battery.model = .iPhone
            #expect(battery.model == .iPhone)
        }
    }

    @Test("TimeType enum contains expected values")
    func testTimeTypeEnum() {
        let timeTypes: [TimeType] = [.minute, .hour, .day]

        #expect(timeTypes.count == 3)
        #expect(timeTypes.contains(.minute))
        #expect(timeTypes.contains(.hour))
        #expect(timeTypes.contains(.day))
    }

    @Test("ForecastInfo struct can be created")
    func testForecastInfoStruct() {
        let forecastInfo = ForecastInfo(
            type: .rain,
            chance: 0.75,
            symbolName: "cloud.rain",
            endingNumber: 30,
            endingType: .minute,
            startingNumber: 10,
            startingType: .minute
        )

        #expect(forecastInfo.type == .rain)
        #expect(forecastInfo.chance == 0.75)
        #expect(forecastInfo.symbolName == "cloud.rain")
        #expect(forecastInfo.endingNumber == 30)
        #expect(forecastInfo.endingType == .minute)
        #expect(forecastInfo.startingNumber == 10)
        #expect(forecastInfo.startingType == .minute)
    }

    @Test("ForecastInfo handles nil values correctly")
    func testForecastInfoWithNilValues() {
        let forecastInfo = ForecastInfo(
            type: .snow,
            chance: 0.25,
            symbolName: "cloud.snow",
            endingNumber: nil,
            endingType: nil,
            startingNumber: nil,
            startingType: nil
        )

        #expect(forecastInfo.type == .snow)
        #expect(forecastInfo.chance == 0.25)
        #expect(forecastInfo.symbolName == "cloud.snow")
        #expect(forecastInfo.endingNumber == nil)
        #expect(forecastInfo.endingType == nil)
        #expect(forecastInfo.startingNumber == nil)
        #expect(forecastInfo.startingType == nil)
    }

    @Test("Weather probability values are in valid range")
    func testWeatherProbabilityRange() {
        let validProbabilities = [0.0, 0.25, 0.5, 0.75, 1.0]

        for probability in validProbabilities {
            let forecast = ForecastInfo(
                type: .rain,
                chance: probability,
                symbolName: "cloud.rain",
                endingNumber: nil,
                endingType: nil,
                startingNumber: nil,
                startingType: nil
            )

            #expect(forecast.chance >= 0.0)
            #expect(forecast.chance <= 1.0)
            #expect(forecast.chance == probability)
        }
    }

    @Test("Weather symbol names are non-empty strings")
    func testWeatherSymbolNames() {
        let symbolNames = [
            "sun.max",
            "cloud.rain",
            "cloud.snow",
            "cloud.bolt",
            "wind",
            "thermometer"
        ]

        for symbolName in symbolNames {
            let forecast = ForecastInfo(
                type: .rain,
                chance: 0.5,
                symbolName: symbolName,
                endingNumber: nil,
                endingType: nil,
                startingNumber: nil,
                startingType: nil
            )

            #expect(!forecast.symbolName.isEmpty)
            #expect(forecast.symbolName == symbolName)
        }
    }

    @Test("Time values are positive when present")
    func testTimeValues() {
        let forecastWithTimes = ForecastInfo(
            type: .rain,
            chance: 0.6,
            symbolName: "cloud.rain",
            endingNumber: 45,
            endingType: .minute,
            startingNumber: 15,
            startingType: .minute
        )

        #expect(forecastWithTimes.endingNumber! > 0)
        #expect(forecastWithTimes.startingNumber! > 0)
        #expect(forecastWithTimes.endingNumber! > forecastWithTimes.startingNumber!)

        let forecastWithHours = ForecastInfo(
            type: .snow,
            chance: 0.3,
            symbolName: "cloud.snow",
            endingNumber: 3,
            endingType: .hour,
            startingNumber: 1,
            startingType: .hour
        )

        #expect(forecastWithHours.endingNumber! > 0)
        #expect(forecastWithHours.startingNumber! > 0)
        #expect(forecastWithHours.endingType == .hour)
        #expect(forecastWithHours.startingType == .hour)
    }
}

// Helper extensions for testing
import CoreLocation
@preconcurrency import WeatherKit

extension ForecastInfo {
    init(type: Precipitation, chance: Double, symbolName: String, endingNumber: Int?, endingType: TimeType?, startingNumber: Int?, startingType: TimeType?) {
        self.type = type
        self.chance = chance
        self.symbolName = symbolName
        self.endingNumber = endingNumber
        self.endingType = endingType
        self.startingNumber = startingNumber
        self.startingType = startingType
    }
}
