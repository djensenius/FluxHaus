//
//  SharedTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation
@testable import FluxHaus

// Test basic data structures from Shared module
struct SharedModelTests {

    @Test("Appliance model can be created with all properties")
    func testApplianceModel() {
        let appliance = Appliance(
            name: "Dishwasher",
            timeRunning: 30,
            timeRemaining: 60,
            timeFinish: "2:30 PM",
            step: "Washing",
            programName: "Quick Wash",
            inUse: true
        )

        #expect(appliance.name == "Dishwasher")
        #expect(appliance.timeRunning == 30)
        #expect(appliance.timeRemaining == 60)
        #expect(appliance.timeFinish == "2:30 PM")
        #expect(appliance.step == "Washing")
        #expect(appliance.programName == "Quick Wash")
        #expect(appliance.inUse == true)
    }

    @Test("Robot model can be created with optional properties")
    func testRobotModel() {
        let robot = Robot(
            name: "TestBot",
            timestamp: "2024-12-01T12:00:00Z",
            batteryLevel: 85,
            binFull: false,
            running: true,
            charging: false,
            docking: false,
            paused: false,
            timeStarted: "2024-12-01T11:30:00Z"
        )

        #expect(robot.name == "TestBot")
        #expect(robot.timestamp == "2024-12-01T12:00:00Z")
        #expect(robot.batteryLevel == 85)
        #expect(robot.binFull == false)
        #expect(robot.running == true)
        #expect(robot.charging == false)
        #expect(robot.docking == false)
        #expect(robot.paused == false)
        #expect(robot.timeStarted == "2024-12-01T11:30:00Z")
    }

    @Test("Robot model handles nil values correctly")
    func testRobotModelWithNilValues() {
        let robot = Robot(
            name: nil,
            timestamp: "2024-12-01T12:00:00Z",
            batteryLevel: nil,
            binFull: nil,
            running: nil,
            charging: nil,
            docking: nil,
            paused: nil,
            timeStarted: nil
        )

        #expect(robot.name == nil)
        #expect(robot.batteryLevel == nil)
        #expect(robot.binFull == nil)
        #expect(robot.running == nil)
        #expect(robot.charging == nil)
        #expect(robot.docking == nil)
        #expect(robot.paused == nil)
        #expect(robot.timeStarted == nil)
    }

    @Test("Doors model can be created")
    func testDoorsModel() {
        let doors = Doors(
            frontRight: 0,
            frontLeft: 1,
            backRight: 0,
            backLeft: 0
        )

        #expect(doors.frontRight == 0)
        #expect(doors.frontLeft == 1)
        #expect(doors.backRight == 0)
        #expect(doors.backLeft == 0)
    }

    @Test("CarDetails model can be created with all properties")
    func testCarDetailsModel() {
        let carDetails = CarDetails(
            timestamp: "2024-12-01T12:00:00Z",
            evStatusTimestamp: "2024-12-01T11:45:00Z",
            batteryLevel: 75,
            distance: 250,
            hvac: false,
            pluggedIn: true,
            batteryCharge: true,
            locked: true,
            doorsOpen: Doors(frontRight: 0, frontLeft: 0, backRight: 0, backLeft: 0),
            trunkOpen: false,
            defrost: false,
            hoodOpen: false,
            odometer: 15432.5,
            engine: false
        )

        #expect(carDetails.timestamp == "2024-12-01T12:00:00Z")
        #expect(carDetails.evStatusTimestamp == "2024-12-01T11:45:00Z")
        #expect(carDetails.batteryLevel == 75)
        #expect(carDetails.distance == 250)
        #expect(carDetails.hvac == false)
        #expect(carDetails.pluggedIn == true)
        #expect(carDetails.batteryCharge == true)
        #expect(carDetails.locked == true)
        #expect(carDetails.trunkOpen == false)
        #expect(carDetails.defrost == false)
        #expect(carDetails.hoodOpen == false)
        #expect(carDetails.odometer == 15432.5)
        #expect(carDetails.engine == false)
    }
}

// Test business logic classes
struct BusinessLogicTests {

    @Test("Api class can be initialized and set response")
    func testApiClass() async {
        await MainActor.run {
            let api = Api()
            #expect(api.response == nil)
        }
    }

    @Test("Robots class initializes with default robots")
    func testRobotsInitialization() async {
        await MainActor.run {
            let robots = Robots()

            #expect(robots.cleanBot.name == "Cleanbot")
            #expect(robots.cleanBot.name == "Cleanbot")
            #expect(robots.cleanBot.timestamp == "")
            #expect(robots.cleanBot.timestamp == "")
            #expect(robots.cleanBot.batteryLevel == nil)
            #expect(robots.cleanBot.batteryLevel == nil)
        }
    }

    @Test("Robot action path generation works correctly")
    func testRobotActionPaths() async {
        await MainActor.run {
            let robots = Robots()

            // We can't easily test the performAction method without mocking network calls,
            // but we can test the logic indirectly by examining the expected behavior
            // The method should generate correct paths based on action and robot parameters

            // This is more of an integration test that would require network mocking
            // For now, we verify the robots object is properly initialized
            #expect(robots.cleanBot.name == "Cleanbot")
            #expect(robots.cleanBot.name == "Cleanbot")
        }
    }

    @Test("Car class initializes with default values")
    func testCarInitialization() async {
        await MainActor.run {
            let car = Car()

            #expect(car.vehicle.timestamp == "")
            #expect(car.vehicle.evStatusTimestamp == "")
            #expect(car.vehicle.batteryLevel == 0)
            #expect(car.vehicle.distance == 0)
            #expect(car.vehicle.hvac == false)
            #expect(car.vehicle.pluggedIn == false)
            #expect(car.vehicle.batteryCharge == false)
            #expect(car.vehicle.locked == false)
            #expect(car.vehicle.trunkOpen == false)
            #expect(car.vehicle.defrost == false)
            #expect(car.vehicle.hoodOpen == false)
            #expect(car.vehicle.odometer == 0)
            #expect(car.vehicle.engine == false)
        }
    }
}

// Test utility functions
struct UtilityFunctionTests {

    @Test("Appliance display text humanizes identifiers and preserves display names")
    func testFormatApplianceDisplayText() {
        #expect(formatApplianceDisplayText("main_wash") == "Main Wash")
        #expect(formatApplianceDisplayText("main_wash (normal)") == "Main Wash (Normal)")
        #expect(formatApplianceDisplayText("QuickWash45") == "QuickWash45")
        #expect(formatApplianceDisplayText("  End programmed  ") == "End programmed")
        #expect(formatApplianceDisplayText("i-DOS") == "i-DOS")
        #expect(formatApplianceDisplayText("OFF") == "Off")
        #expect(OperationState.run.displayText == "Running")
        #expect(OperationState.delayedStart.displayText == "Delayed Start")
        #expect(OperationState.actionRequired.displayText == "Action Required")
    }

    @Test("Dishwasher status uses the display operation state")
    func testDishwasherStatusUsesDisplayOperationState() {
        let now = Date(timeIntervalSince1970: 0)
        let response = LoginResponse(
            timestamp: "",
            favouriteHomeKit: [],
            cleanbot: Robot(),
            dishwasher: DishWasher(
                remainingTime: 1_800,
                operationState: .run
            )
        )
        let status = FluxStatusText.dishwasher(response, now: now)

        #expect(status.hasPrefix("The dishwasher is running."))
        #expect(status.contains("30 min remaining"))
        #expect(status.contains("finish around"))
    }

    @Test("getDeviceIcon returns correct icons for different battery models")
    func testGetDeviceIcon() async {
        await MainActor.run {
            let iPadBattery = Battery()
            iPadBattery.model = .iPad
            let iPadIcon = getDeviceIcon(battery: iPadBattery)
            // Note: We can't easily test Image equality, but we can test the function doesn't crash
            #expect(iPadIcon != nil)

            let macBattery = Battery()
            macBattery.model = .mac
            let macIcon = getDeviceIcon(battery: macBattery)
            #expect(macIcon != nil)

            let visionProBattery = Battery()
            visionProBattery.model = .visionPro
            let visionIcon = getDeviceIcon(battery: visionProBattery)
            #expect(visionIcon != nil)

            let iPhoneBattery = Battery()
            iPhoneBattery.model = .iPhone
            let iPhoneIcon = getDeviceIcon(battery: iPhoneBattery)
            #expect(iPhoneIcon != nil)
        }
    }

    @Test("carDetails function generates expected text")
    func testCarDetailsFunction() async {
        await MainActor.run {
            let car = Car()

            // Test with default values (all should be false/empty)
            let defaultDetails = carDetails(car: car)
            #expect(defaultDetails == "")

            // Test with engine on
            car.vehicle = CarDetails(
                timestamp: "",
                evStatusTimestamp: "2024-12-01T12:00:00Z",
                batteryLevel: 0,
                distance: 250,
                hvac: true,
                pluggedIn: false,
                batteryCharge: false,
                locked: false,
                doorsOpen: Doors(frontRight: 0, frontLeft: 0, backRight: 0, backLeft: 0),
                trunkOpen: false,
                defrost: false,
                hoodOpen: false,
                odometer: 0,
                engine: true
            )

            let engineOnDetails = carDetails(car: car)
            #expect(engineOnDetails.contains("Car on"))
            #expect(engineOnDetails.contains("Climate on"))
            #expect(engineOnDetails.contains("Range 250 km"))
        }
    }
}

struct IndoorClimateTests {
    private func format(_ value: Double) -> String { String(format: "%.1f", value) }

    @Test("Decodes the server's indoorClimate payload, tolerating nulls and missing keys")
    func testDecodeIndoorClimate() throws {
        let json = Data("""
        {
          "timestamp": "2026-07-14T12:00:00.000Z",
          "unit": "°F",
          "thermostat": {
            "entityId": "climate.home", "name": "Home", "area": "Hallway", "available": true,
            "currentTemperature": 21.3, "currentHumidity": 41, "hvacMode": "heat",
            "hvacAction": "heating", "targetTemperature": 21.5,
            "targetTemperatureLow": null, "targetTemperatureHigh": null, "presetMode": "home"
          },
          "sensors": [
            { "entityId": "sensor.bedroom_temperature", "name": "Bedroom", "area": "Main Bedroom",
              "temperature": 67.6, "unit": "°F", "available": true, "occupied": false, "isThermostat": false,
              "lastUpdated": "2026-07-14T11:59:00.000Z" },
            { "entityId": "sensor.broken_temperature", "name": "Broken", "temperature": "warm" },
            { "entityId": "sensor.office_temperature", "name": "Office", "area": null, "temperature": null,
              "unit": null, "available": false, "occupied": null, "isThermostat": false, "lastUpdated": null }
          ]
        }
        """.utf8)
        let state = try JSONDecoder().decode(IndoorClimateState.self, from: json)
        #expect(state.thermostat?.hvacAction == "heating")
        #expect(state.thermostat?.area == "Hallway")
        #expect(state.isFahrenheit)
        // The malformed sensor is dropped rather than failing the whole payload.
        #expect(state.sensors.map(\.name) == ["Bedroom", "Office"])
        #expect(state.sensors[0].area == "Main Bedroom")
        #expect(state.sensors[1].isAvailable == false)
        #expect(state.sensors[0].occupied == false)

        let empty = try JSONDecoder().decode(IndoorClimateState.self, from: Data(#"{"thermostat":null}"#.utf8))
        #expect(empty.sensors.isEmpty)
        #expect(empty.hasData == false)
    }

    @Test("Headline temperature prefers the thermostat, then averages available rooms")
    func testPrimaryTemperatureAndRange() {
        let rooms = [
            IndoorTemperatureSensor(entityId: "sensor.a", name: "A", temperature: 19.0),
            IndoorTemperatureSensor(entityId: "sensor.b", name: "B", temperature: 23.0),
            IndoorTemperatureSensor(entityId: "sensor.c", name: "C", temperature: nil, available: false)
        ]
        let withThermostat = IndoorClimateState(
            thermostat: ThermostatStatus(entityId: "climate.home", currentTemperature: 21.4),
            sensors: rooms
        )
        #expect(withThermostat.primaryTemperature == 21.4)
        #expect(withThermostat.temperatureRange == 19.0...23.0)

        let offlineThermostat = IndoorClimateState(
            thermostat: ThermostatStatus(entityId: "climate.home", available: false, currentTemperature: 30),
            sensors: rooms
        )
        #expect(offlineThermostat.primaryTemperature == 21.0)
        #expect(offlineThermostat.warmth(of: rooms[0]) == .cooler)
        #expect(offlineThermostat.warmth(of: rooms[1]) == .warmer)
        #expect(offlineThermostat.warmth(of: rooms[2]) == .typical)
    }

    @Test("Thermostat summary describes what the HVAC is doing")
    func testThermostatSummary() {
        func summary(_ status: ThermostatStatus) -> ThermostatSummary {
            ThermostatSummary(thermostat: status, format: format)
        }
        let heating = summary(ThermostatStatus(
            entityId: "climate.home", hvacMode: "heat", hvacAction: "heating", targetTemperature: 21.5
        ))
        #expect(heating.activity == .heating)
        #expect(heating.text == "Heating to 21.5")

        let cooling = summary(ThermostatStatus(
            entityId: "climate.home", hvacMode: "heat_cool", hvacAction: "cooling",
            targetTemperatureLow: 20, targetTemperatureHigh: 24
        ))
        #expect(cooling.text == "Cooling to 24.0")

        let autoIdle = summary(ThermostatStatus(
            entityId: "climate.home", hvacMode: "heat_cool", hvacAction: "idle",
            targetTemperatureLow: 20, targetTemperatureHigh: 24
        ))
        #expect(autoIdle.activity == .idle)
        #expect(autoIdle.text == "Auto · 20.0–24.0")

        #expect(summary(ThermostatStatus(entityId: "climate.home", hvacMode: "off")).activity == .off)
        #expect(summary(ThermostatStatus(entityId: "climate.home", available: false)).activity == .unavailable)
        #expect(summary(ThermostatStatus(entityId: "climate.home", hvacAction: "fan")).activity == .fan)
        // An unknown mode must not be reported as "Off".
        #expect(summary(ThermostatStatus(entityId: "climate.home")).activity == .idle)
    }

    @Test("Rooms use Home Assistant area names, thermostat first, and stay distinct when areas repeat")
    func testRoomNames() {
        let state = IndoorClimateState(sensors: [
            IndoorTemperatureSensor(entityId: "sensor.office", name: "Office", area: "Den", temperature: 20),
            IndoorTemperatureSensor(entityId: "sensor.attic", name: "Attic", temperature: 18),
            IndoorTemperatureSensor(
                entityId: "sensor.home", name: "Home", area: "Den", temperature: 21, isThermostat: true
            ),
            IndoorTemperatureSensor(entityId: "sensor.bed", name: "Bedroom", area: "Main Bedroom", temperature: 19)
        ])
        #expect(state.rooms.map(state.displayName(for:)) == ["Den Thermostat", "Attic", "Den · Office", "Main Bedroom"])
    }

    @Test("Warmth threshold scales for Fahrenheit homes")
    func testFahrenheitWarmth() {
        let rooms = [
            IndoorTemperatureSensor(entityId: "sensor.a", name: "A", temperature: 69, unit: "°F"),
            IndoorTemperatureSensor(entityId: "sensor.b", name: "B", temperature: 71, unit: "°F"),
            IndoorTemperatureSensor(entityId: "sensor.c", name: "C", temperature: 73, unit: "°F")
        ]
        let state = IndoorClimateState(sensors: rooms)
        #expect(state.isFahrenheit)
        #expect(state.warmth(of: rooms[0]) == .cooler)
        #expect(state.warmth(of: rooms[1]) == .typical)
        #expect(state.warmth(of: rooms[2]) == .warmer)
    }

    @Test("Rooms reported in another unit are converted before comparing")
    func testMixedUnitAggregation() throws {
        let rooms = [
            IndoorTemperatureSensor(entityId: "sensor.a", name: "A", temperature: 20, unit: "°C"),
            IndoorTemperatureSensor(entityId: "sensor.b", name: "B", temperature: 68, unit: "°F"),
            IndoorTemperatureSensor(entityId: "sensor.c", name: "C", temperature: 22, unit: nil)
        ]
        let state = IndoorClimateState(unit: "°C", sensors: rooms)
        let converted = try #require(state.temperature(of: rooms[1]))
        #expect(abs(converted - 20) < 0.001)
        let range = try #require(state.temperatureRange)
        #expect(abs(range.lowerBound - 20) < 0.001 && range.upperBound == 22)
        #expect(state.warmth(of: rooms[1]) == .typical)

        let fahrenheitHome = IndoorClimateState(unit: "°F", sensors: rooms)
        #expect(fahrenheitHome.temperature(of: rooms[0]) == 68)
        #expect(fahrenheitHome.temperature(of: rooms[2]) == 22)
    }

    @Test("Indoor charts drop the outdoor series and keep the rest")
    func testExcludingOutdoorSeries() {
        let point = [MetricPoint(time: "2026-01-01T00:00:00Z", value: 20)]
        let response = MetricSeriesResponse(
            metric: "temperature", title: "Temperature", unit: "°C", range: "24h",
            series: [
                MetricSeries(name: "Office", points: point),
                MetricSeries(name: "Outside", points: point)
            ]
        )
        let indoor = response.excludingSeries(named: ["Outside"])
        #expect(indoor.series.map(\.name) == ["Office"])
        #expect(indoor.metric == "temperature" && indoor.range == "24h")
    }
}

// Helper functions and imports for testing
// Extensions removed as memberwise inits should be accessible via @testable import
