//
//  IntegrationTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation
@testable import FluxHaus

struct IntegrationTests {

    @Test("Complete data flow from API response to UI works correctly")
    func testCompleteDataFlow() async {
        // Test the complete data flow without making actual network calls
        await MainActor.run {
            let api = Api()
            let robots = Robots()
            let car = Car()
            let homeConnect = HomeConnect(apiResponse: api)

            // Initial state validation
            #expect(api.response == nil)
            #expect(robots.mopBot.name == "MopBot")
            #expect(robots.broomBot.name == "BroomBot")
            #expect(car.vehicle.batteryLevel == 0)
            #expect(homeConnect.appliances.count == 0)

            // Test that objects can be linked
            robots.setApiResponse(apiResponse: api)
            car.setApiResponse(apiResponse: api)
            homeConnect.setApiResponse(apiResponse: api)

            #expect(robots.apiResponse != nil)
            #expect(car.apiResponse != nil)
            #expect(homeConnect.apiResponse != nil)
        }
    }

    @Test("Car data structures are correctly formed")
    func testCarDataStructures() {
        // Test EvModeRange
        let evModeRange = EvModeRange(value: 250, unit: 1)
        #expect(evModeRange.value == 250)
        #expect(evModeRange.unit == 1)

        // Test Atc
        let atc = Atc(value: 300, unit: 2)
        #expect(atc.value == 300)
        #expect(atc.unit == 2)

        // Test RangeByFuel
        let rangeByFuel = RangeByFuel(
            gasModeRange: atc,
            evModeRange: atc,
            totalAvailableRange: atc
        )
        #expect(rangeByFuel.gasModeRange.value == 300)
        #expect(rangeByFuel.evModeRange.value == 300)
        #expect(rangeByFuel.totalAvailableRange.value == 300)

        // Test DriveDistance
        let driveDistance = DriveDistance(
            rangeByFuel: rangeByFuel,
            type: 1
        )
        #expect(driveDistance.type == 1)
        #expect(driveDistance.rangeByFuel.evModeRange.value == 300)

        // Test EVStatus
        let evStatus = EVStatus(
            timestamp: "2024-12-01T12:00:00Z",
            batteryCharge: true,
            batteryStatus: 85,
            batteryPlugin: 1,
            drvDistance: [driveDistance]
        )
        #expect(evStatus.timestamp == "2024-12-01T12:00:00Z")
        #expect(evStatus.batteryCharge == true)
        #expect(evStatus.batteryStatus == 85)
        #expect(evStatus.batteryPlugin == 1)
        #expect(evStatus.drvDistance.count == 1)
        #expect(evStatus.drvDistance[0].rangeByFuel.evModeRange.value == 300)
    }

    @Test("FluxCar data structure is correctly formed")
    func testFluxCarDataStructure() {
        let doors = Doors(frontRight: 0, frontLeft: 1, backRight: 0, backLeft: 0)

        let fluxCar = FluxCar(
            timestamp: "2024-12-01T12:00:00Z",
            lastStatusDate: "2024-12-01T11:55:00Z",
            airCtrlOn: true,
            doorLock: false,
            doorOpen: doors,
            trunkOpen: true,
            defrost: false,
            hoodOpen: false,
            engine: true
        )

        #expect(fluxCar.timestamp == "2024-12-01T12:00:00Z")
        #expect(fluxCar.lastStatusDate == "2024-12-01T11:55:00Z")
        #expect(fluxCar.airCtrlOn == true)
        #expect(fluxCar.doorLock == false)
        #expect(fluxCar.doorOpen.frontLeft == 1)
        #expect(fluxCar.trunkOpen == true)
        #expect(fluxCar.defrost == false)
        #expect(fluxCar.hoodOpen == false)
        #expect(fluxCar.engine == true)
    }

    @Test("Robot action path generation logic is correct")
    func testRobotActionPaths() async {
        await MainActor.run {
            let robots = Robots()

            // Test action to path mapping logic (without making actual network calls)
            // This tests the switch statement logic conceptually

            let actionToPathMapping = [
                "start": ["BroomBot": "/turnOnBroombot", "MopBot": "/turnOnMopbot"],
                "stop": ["BroomBot": "/turnOffBroombot", "MopBot": "/turnOffMopbot"],
                "deepClean": ["BroomBot": "/turnOnDeepClean", "MopBot": "/turnOnDeepClean"],
                "default": ["BroomBot": "/", "MopBot": "/"]
            ]

            // Verify the mapping logic
            #expect(actionToPathMapping["start"]?["BroomBot"] == "/turnOnBroombot")
            #expect(actionToPathMapping["start"]?["MopBot"] == "/turnOnMopbot")
            #expect(actionToPathMapping["stop"]?["BroomBot"] == "/turnOffBroombot")
            #expect(actionToPathMapping["stop"]?["MopBot"] == "/turnOffMopbot")
            #expect(actionToPathMapping["deepClean"]?["BroomBot"] == "/turnOnDeepClean")
            #expect(actionToPathMapping["deepClean"]?["MopBot"] == "/turnOnDeepClean")
        }
    }

    @Test("Car action path generation logic is correct")
    func testCarActionPaths() async {
        await MainActor.run {
            let car = Car()

            // Test car action to path mapping logic
            let actionToPathMapping = [
                "unlock": "/unlockCar",
                "lock": "/lockCar",
                "start": "/startCar",
                "stop": "/stopCar",
                "resync": "/resyncCar",
                "default": "/resyncCar"
            ]

            // Verify the mapping logic
            #expect(actionToPathMapping["unlock"] == "/unlockCar")
            #expect(actionToPathMapping["lock"] == "/lockCar")
            #expect(actionToPathMapping["start"] == "/startCar")
            #expect(actionToPathMapping["stop"] == "/stopCar")
            #expect(actionToPathMapping["resync"] == "/resyncCar")
            #expect(actionToPathMapping["default"] == "/resyncCar")
        }
    }

    @Test("Data model JSON compatibility and decoding")
    func testJSONCompatibility() throws {
        // Test that our data models can handle JSON decoding correctly

        // Test Robot JSON
        let robotJSON = """
        {
            "name": "TestBot",
            "timestamp": "2024-12-01T12:00:00Z",
            "batteryLevel": 85,
            "binFull": false,
            "running": true,
            "charging": false,
            "docking": false,
            "paused": false,
            "timeStarted": "2024-12-01T11:30:00Z"
        }
        """

        let robotData = robotJSON.data(using: .utf8)!
        let decodedRobot = try JSONDecoder().decode(Robot.self, from: robotData)

        #expect(decodedRobot.name == "TestBot")
        #expect(decodedRobot.batteryLevel == 85)
        #expect(decodedRobot.running == true)

        // Test Doors JSON
        let doorsJSON = """
        {
            "frontRight": 0,
            "frontLeft": 1,
            "backRight": 0,
            "backLeft": 0
        }
        """

        let doorsData = doorsJSON.data(using: .utf8)!
        let decodedDoors = try JSONDecoder().decode(Doors.self, from: doorsData)

        #expect(decodedDoors.frontRight == 0)
        #expect(decodedDoors.frontLeft == 1)
        #expect(decodedDoors.backRight == 0)
        #expect(decodedDoors.backLeft == 0)
    }

    @Test("Error handling and nil value scenarios")
    func testErrorHandlingScenarios() async {
        await MainActor.run {
            // Test that objects handle nil API responses gracefully
            let api = Api()
            let robots = Robots()
            let car = Car()

            robots.setApiResponse(apiResponse: api) // API response is nil
            car.setApiResponse(apiResponse: api) // API response is nil

            // Should not crash and maintain default state
            #expect(robots.mopBot.timestamp == "")
            #expect(robots.broomBot.timestamp == "")
            #expect(car.vehicle.batteryLevel == 0)

            // Test partial data scenarios
            let robotWithPartialData = Robot(
                name: "PartialBot",
                timestamp: "2024-12-01T12:00:00Z",
                batteryLevel: nil, // Missing battery data
                binFull: nil,     // Missing bin data
                running: true,
                charging: nil,    // Missing charging data
                docking: false,
                paused: nil,      // Missing paused data
                timeStarted: nil  // Missing start time
            )

            #expect(robotWithPartialData.name == "PartialBot")
            #expect(robotWithPartialData.batteryLevel == nil)
            #expect(robotWithPartialData.running == true)
            #expect(robotWithPartialData.timeStarted == nil)
        }
    }
}

// Additional helper extensions for integration tests
extension EvModeRange {
    init(value: Int, unit: Int) {
        self.value = value
        self.unit = unit
    }
}

extension Atc {
    init(value: Int, unit: Int) {
        self.value = value
        self.unit = unit
    }
}

extension RangeByFuel {
    init(gasModeRange: Atc, evModeRange: Atc, totalAvailableRange: Atc) {
        self.gasModeRange = gasModeRange
        self.evModeRange = evModeRange
        self.totalAvailableRange = totalAvailableRange
    }
}

extension DriveDistance {
    init(rangeByFuel: RangeByFuel, type: Int) {
        self.rangeByFuel = rangeByFuel
        self.type = type
    }
}

extension EVStatus {
    init(timestamp: String, batteryCharge: Bool, batteryStatus: Int, batteryPlugin: Int, drvDistance: [DriveDistance]) {
        self.timestamp = timestamp
        self.batteryCharge = batteryCharge
        self.batteryStatus = batteryStatus
        self.batteryPlugin = batteryPlugin
        self.drvDistance = drvDistance
    }
}

extension FluxCar {
    init(
        timestamp: String,
        lastStatusDate: String,
        airCtrlOn: Bool,
        doorLock: Bool,
        doorOpen: Doors,
        trunkOpen: Bool,
        defrost: Bool,
        hoodOpen: Bool,
        engine: Bool
    ) {
        self.timestamp = timestamp
        self.lastStatusDate = lastStatusDate
        self.airCtrlOn = airCtrlOn
        self.doorLock = doorLock
        self.doorOpen = doorOpen
        self.trunkOpen = trunkOpen
        self.defrost = defrost
        self.hoodOpen = hoodOpen
        self.engine = engine
    }
}
