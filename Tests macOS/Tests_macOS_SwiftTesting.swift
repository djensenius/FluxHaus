//
//  Tests_macOS_SwiftTesting.swift
//  Tests macOS
//
//  Created by David Jensenius on 2020-12-13.
//  Updated to use Swift Testing framework
//

import Testing
import AppKit
import SwiftUI

/// Drains pending DispatchQueue.main.async blocks so data population completes.
@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

/// Creates a LoginResponse with all device fields nil (minimal/empty state).
private func emptyResponse() -> LoginResponse {
    let emptyRobot = Robot(
        name: nil, timestamp: "", batteryLevel: nil,
        binFull: nil, running: nil, charging: nil,
        docking: nil, paused: nil, timeStarted: nil
    )
    return LoginResponse(
        timestamp: "", favouriteHomeKit: [],
        favouriteScenes: [],
        broombot: emptyRobot, mopbot: emptyRobot,
        car: nil, carEvStatus: nil, carOdometer: nil,
        dishwasher: nil, dryer: nil, washer: nil
    )
}

// MARK: - MockData Validation

struct MacOSMockDataValidationTests {

    @Test("MockData login response has all required fields")
    @MainActor func testMockLoginResponseCompleteness() {
        let response = MockData.loginResponse

        #expect(response.timestamp == "2024-12-13T12:00:00Z")
        #expect(response.favouriteHomeKit == ["Light 1", "Light 2"])
        #expect(response.broombot.name == "BroomBot")
        #expect(response.mopbot.name == "MopBot")
        #expect(response.car != nil)
        #expect(response.carEvStatus != nil)
        #expect(response.carOdometer == 15000.0)
        #expect(response.dishwasher != nil)
        #expect(response.dryer != nil)
        #expect(response.washer != nil)
    }

    @Test("MockData factories produce configured objects")
    @MainActor func testMockFactories() async {
        let api = MockData.createApi()
        #expect(api.response != nil)
        #expect(api.response?.broombot.name == "BroomBot")

        let car = MockData.createCar()
        let robots = MockData.createRobots()
        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        await drainMainQueue()

        #expect(car.vehicle.batteryLevel == 75)
        #expect(car.vehicle.distance == 350)
        #expect(car.vehicle.locked == true)

        #expect(robots.broomBot.batteryLevel == 85)
        #expect(robots.broomBot.charging == true)
        #expect(robots.mopBot.batteryLevel == 90)
        #expect(robots.mopBot.running == true)

        #expect(hconn.appliances.count > 0)
        #expect(miele.appliances.count == 2)
    }
}

// MARK: - Data Flow Tests

struct MacOSDataFlowTests {

    @Test("Api response flows correctly to Car")
    @MainActor func testApiToCarFlow() async {
        let api = MockData.createApi()
        let car = Car()
        car.setApiResponse(apiResponse: api)
        await drainMainQueue()

        #expect(car.vehicle.batteryLevel == 75)
        #expect(car.vehicle.distance == 350)
        #expect(car.vehicle.locked == true)
        #expect(car.vehicle.hvac == false)
        #expect(car.vehicle.engine == false)
        #expect(car.vehicle.trunkOpen == false)
        #expect(car.vehicle.hoodOpen == false)
        #expect(car.vehicle.defrost == false)
        #expect(car.vehicle.odometer == 15000.0)
    }

    @Test("Api response flows correctly to Robots")
    @MainActor func testApiToRobotsFlow() async {
        let api = MockData.createApi()
        let robots = Robots()
        robots.setApiResponse(apiResponse: api)
        await drainMainQueue()

        #expect(robots.broomBot.name == "BroomBot")
        #expect(robots.broomBot.batteryLevel == 85)
        #expect(robots.broomBot.charging == true)
        #expect(robots.broomBot.running == false)

        #expect(robots.mopBot.name == "MopBot")
        #expect(robots.mopBot.batteryLevel == 90)
        #expect(robots.mopBot.running == true)
        #expect(robots.mopBot.charging == false)
    }

    @Test("Api response flows correctly to HomeConnect")
    @MainActor func testApiToHomeConnectFlow() async {
        let api = MockData.createApi()
        let hconn = HomeConnect(apiResponse: api)
        await drainMainQueue()

        #expect(hconn.appliances.count > 0)
        let dishwasher = hconn.appliances.first
        #expect(dishwasher != nil)
        #expect(dishwasher?.name == "Dishwasher")
    }

    @Test("Api response flows correctly to Miele")
    @MainActor func testApiToMieleFlow() async {
        let api = MockData.createApi()
        let miele = Miele(apiResponse: api)
        await drainMainQueue()

        #expect(miele.appliances.count == 2)

        let washer = miele.appliances.first(where: { $0.name == "Washer" })
        #expect(washer != nil)
        #expect(washer?.inUse == true)
        #expect(washer?.programName == "Cotton 60")
        #expect(washer?.timeRemaining == 15)

        let dryer = miele.appliances.first(where: { $0.name == "Dryer" })
        #expect(dryer != nil)
        #expect(dryer?.inUse == false)
    }

    @Test("Updating Api response propagates to all services")
    @MainActor func testApiUpdatePropagation() async {
        let api = MockData.createApi()
        let car = Car()
        let robots = Robots()

        car.setApiResponse(apiResponse: api)
        robots.setApiResponse(apiResponse: api)
        await drainMainQueue()

        #expect(car.vehicle.batteryLevel == 75)
        #expect(robots.mopBot.running == true)

        let modified = LoginResponse(
            timestamp: "2024-12-13T13:00:00Z",
            favouriteHomeKit: ["Light 1"],
            favouriteScenes: [],
            broombot: Robot(
                name: "BroomBot",
                timestamp: "2024-12-13T12:00:00Z",
                batteryLevel: 50,
                binFull: true,
                running: false,
                charging: false,
                docking: false,
                paused: false,
                timeStarted: nil
            ),
            mopbot: MockData.loginResponse.mopbot
        )
        api.setApiResponse(apiResponse: modified)
        robots.setApiResponse(apiResponse: api)
        await drainMainQueue()

        #expect(robots.broomBot.batteryLevel == 50)
        #expect(robots.broomBot.binFull == true)
    }
}
