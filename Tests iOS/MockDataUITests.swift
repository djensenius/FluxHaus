//
//  MockDataUITests.swift
//  Tests iOS
//
//  Created by Copilot on 2025-02-20.
//

import Testing
import SwiftUI
import UIKit
@testable import FluxHaus

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

/// Creates an Appliances view instance with the given mock services.
@MainActor
private func mockAppliances(
    hconn: HomeConnect,
    miele: Miele,
    robots: Robots,
    car: Car,
    battery: Battery = Battery()
) -> Appliances {
    Appliances(
        fluxHausConsts: FluxHausConsts(),
        hconn: hconn, miele: miele,
        apiResponse: MockData.createApi(),
        robots: robots, battery: battery,
        car: car, locationManager: LocationManager()
    )
}

// MARK: - MockData Validation

struct MockDataValidationTests {

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

// MARK: - View Smoke Tests (UIHostingController)

struct ViewSmokeTests {

    @Test("LoadingView renders login form without crashing")
    @MainActor func testLoadingViewLogin() {
        let view = LoadingView(needLoginView: true)
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        #expect(controller.view != nil)
    }

    @Test("LoadingView renders loading state without crashing")
    @MainActor func testLoadingViewLoading() {
        let view = LoadingView(needLoginView: false)
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        #expect(controller.view != nil)
    }

    @Test("ContentView renders with mock data without crashing")
    @MainActor func testContentViewWithMockData() async {
        let config = FluxHausConsts()
        config.setConfig(config: FluxHausConfig(favouriteHomeKit: ["Light 1"], favouriteScenes: []))

        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueue()

        let view = ContentView(
            fluxHausConsts: config,
            hconn: hconn,
            miele: miele,
            robots: robots,
            battery: MockData.createBattery(),
            car: car,
            scooter: MockData.createScooter(),
            apiResponse: MockData.createApi()
        )

        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        #expect(controller.view != nil)
    }

    @Test("Appliances view renders with mock data without crashing")
    @MainActor func testAppliancesViewWithMockData() async {
        let config = FluxHausConsts()
        config.setConfig(config: FluxHausConfig(favouriteHomeKit: ["Light 1"], favouriteScenes: []))

        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueue()

        let view = Appliances(
            fluxHausConsts: config,
            hconn: hconn,
            miele: miele,
            apiResponse: MockData.createApi(),
            robots: robots,
            battery: MockData.createBattery(),
            car: car,
            locationManager: LocationManager()
        )

        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        #expect(controller.view != nil)
    }
}

// MARK: - Data Flow Tests

struct MockDataFlowTests {

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

        // Update with a modified response
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

// MARK: - Appliance Display Logic Tests

struct ApplianceDisplayTests {

    @Test("Appliance list contains all expected device types")
    @MainActor func testApplianceList() async {
        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueue()

        let view = mockAppliances(hconn: hconn, miele: miele, robots: robots, car: car)
        #expect(view.originalAppliances.count == 7)
        let names = view.originalAppliances.map { $0.name }
        #expect(names.contains("HomeConnect"))
        #expect(names.contains("Miele"))
        #expect(names.contains("BroomBot"))
        #expect(names.contains("MopBot"))
        #expect(names.contains("Car"))
        #expect(names.contains("Battery"))
    }

    @Test("Appliance names are correct for each type")
    @MainActor func testApplianceNames() async {
        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueue()

        let view = mockAppliances(hconn: hconn, miele: miele, robots: robots, car: car)
        #expect(view.getApplianceName(type: "MopBot", index: 0) == "MopBot")
        #expect(view.getApplianceName(type: "BroomBot", index: 0) == "BroomBot")
        #expect(view.getApplianceName(type: "Car", index: 0) == "Car")
        let batteryName = view.getApplianceName(type: "Battery", index: 0)
        #expect(["Phone", "iPad", "Computer", "Vision Pro"].contains(batteryName))
    }

    @Test("Time remaining shows correct values")
    @MainActor func testTimeRemaining() async {
        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueue()

        let view = mockAppliances(hconn: hconn, miele: miele, robots: robots, car: car)
        #expect(view.getTimeRemaining(type: "MopBot", index: 0) == "On")
        #expect(view.getTimeRemaining(type: "BroomBot", index: 0) == "Off")
        #expect(view.getTimeRemaining(type: "Car", index: 0) == "75%")
    }

    @Test("Robot status text includes battery info")
    @MainActor func testRobotStatusText() async {
        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueue()

        let view = mockAppliances(hconn: hconn, miele: miele, robots: robots, car: car)
        let broomText = view.getProgram(type: "BroomBot", index: 0)
        #expect(broomText.contains("Charging") && broomText.contains("85%"))
        let mopText = view.getProgram(type: "MopBot", index: 0)
        #expect(mopText.contains("Battery") && mopText.contains("90%"))
    }

    @Test("Car details text reflects vehicle state")
    @MainActor func testCarDetailsText() async {
        let car = MockData.createCar()
        await drainMainQueue()
        #expect(carDetails(car: car).contains("350 km"))
    }

    @Test("Miele appliance display values are correct")
    @MainActor func testMieleDisplayValues() async {
        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueue()

        let view = mockAppliances(hconn: hconn, miele: miele, robots: robots, car: car)
        #expect(view.getTimeRemaining(type: "Miele", index: 0) != "Off")
        #expect(view.getTimeRemaining(type: "Miele", index: 1) == "Off")
        #expect(view.getProgram(type: "Miele", index: 0).contains("Cotton 60"))
    }
}

// MARK: - Nil/Missing Data Resilience

struct NilDataResilienceTests {

    @Test("Views handle nil car and appliance data gracefully")
    @MainActor func testNilDeviceData() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyResponse())

        let car = Car()
        car.setApiResponse(apiResponse: api)
        let hconn = HomeConnect(apiResponse: api)
        let miele = Miele(apiResponse: api)
        await drainMainQueue()

        #expect(car.vehicle.batteryLevel == 0)
        #expect(car.vehicle.distance == 0)
        // nilProgram() creates a placeholder Dishwasher even when data is nil
        #expect(hconn.appliances.count == 1)
        #expect(hconn.appliances.first?.inUse == false)
        #expect(miele.appliances.count == 0)
    }

    @Test("Robots with nil status show Lost indicator")
    @MainActor func testNilRobotData() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyResponse())
        let robots = Robots()
        robots.setApiResponse(apiResponse: api)
        let hconn = HomeConnect(apiResponse: api)
        let miele = Miele(apiResponse: api)
        await drainMainQueue()

        let view = mockAppliances(
            hconn: hconn, miele: miele,
            robots: robots, car: Car()
        )
        #expect(view.getTimeRemaining(type: "MopBot", index: 0) == "Lost")
        #expect(view.getTimeRemaining(type: "BroomBot", index: 0) == "Lost")
    }

    @Test("ContentView renders with minimal data without crashing")
    @MainActor func testContentViewMinimalData() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyResponse())

        let hconn = HomeConnect(apiResponse: api)
        let miele = Miele(apiResponse: api)
        let robots = Robots()
        robots.setApiResponse(apiResponse: api)
        let car = Car()
        car.setApiResponse(apiResponse: api)
        await drainMainQueue()

        let view = ContentView(
            fluxHausConsts: FluxHausConsts(),
            hconn: hconn, miele: miele, robots: robots,
            battery: Battery(), car: car,
            scooter: MockData.createScooter(), apiResponse: api
        )
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        #expect(controller.view != nil)
    }
}
