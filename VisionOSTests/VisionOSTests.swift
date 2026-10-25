//
//  VisionOSTests.swift
//  VisionOSTests
//
//  Created by David Jensenius on 2024-03-03.
//

import XCTest
@testable import FluxHaus

class VisionOSTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete.
        // Check the results with assertions afterwards.
    }

    func testCompletedMieleDoesNotRemainActiveWithRetainedTime() throws {
        for status in ["End programmed", "program_ended", "Off", "Idle", "Programmed", "waiting_to_start"] {
            let appliance = WasherDryer(name: "Washer", timeRunning: 59, timeRemaining: 1, status: status, inUse: true)
            let data = FluxData(cleanBot: nil, car: nil, dishwasher: nil, dryer: appliance, washer: appliance)
            let devices = convertDataToWidgetDevices(fluxData: data).filter { ["Washer", "Dryer"].contains($0.name) }
            XCTAssertEqual(devices.count, 2)
            for device in devices {
                XCTAssertFalse(device.running, status)
                XCTAssertNil(device.endsAt, status)
                XCTAssertNil(device.startedAt, status)
            }
        }
    }

    func testDisconnectedAppliancePreservesPriorCycleWithoutStartingNewOnes() throws {
        let running = WasherDryer(name: "Washer", timeRemaining: 20, status: "Running", inUse: true)
        let priorData = FluxData(cleanBot: nil, car: nil, dishwasher: nil, dryer: nil, washer: running)
        let prior = convertDataToWidgetDevices(fluxData: priorData)
        for status in ["Not Connected", "unavailable", "unknown"] {
            let offline = WasherDryer(name: "Washer", status: status)
            let data = FluxData(cleanBot: nil, car: nil, dishwasher: nil, dryer: nil, washer: offline)
            let devices = convertDataToWidgetDevices(fluxData: data)
            let resolved = resolvedLiveActivityDevices(devices, previous: prior)
            let washer = try XCTUnwrap(resolved.first { $0.name == "Washer" })
            XCTAssertTrue(washer.running, status)
            XCTAssertEqual(washer.shortText, "Offline")
            XCTAssertNil(washer.endsAt)
            XCTAssertFalse(resolvedLiveActivityDevices(devices, previous: []).contains { $0.name == "Washer" })
        }
    }

    func testUnavailableRobotAndDishwasherPreserveKnownJobs() throws {
        let previousData = FluxData(
            cleanBot: Robot(running: true, stateKnown: true), car: nil,
            dishwasher: DishWasher(operationState: .run, stateKnown: true), dryer: nil, washer: nil
        )
        let unavailableData = FluxData(
            cleanBot: Robot(running: false, stateKnown: false), car: nil,
            dishwasher: DishWasher(operationState: .inactive, stateKnown: false), dryer: nil, washer: nil
        )
        let resolved = resolvedLiveActivityDevices(
            convertDataToWidgetDevices(fluxData: unavailableData),
            previous: convertDataToWidgetDevices(fluxData: previousData)
        )
        for name in ["Cleanbot", "Dishwasher"] {
            let device = try XCTUnwrap(resolved.first { $0.name == name })
            XCTAssertTrue(device.running)
            XCTAssertEqual(device.shortText, "Offline")
            XCTAssertNil(device.endsAt)
        }
    }

    func testPausedMieleRemainsVisibleWithoutCountingDown() throws {
        let appliance = WasherDryer(name: "Washer", timeRunning: 10, timeRemaining: 20, status: "Pause", inUse: true)
        let data = FluxData(cleanBot: nil, car: nil, dishwasher: nil, dryer: nil, washer: appliance)
        let washer = try XCTUnwrap(convertDataToWidgetDevices(fluxData: data).first { $0.name == "Washer" })
        XCTAssertTrue(washer.running)
        XCTAssertNil(washer.endsAt)
    }

    func testInactiveDishwasherIgnoresRetainedProgress() throws {
        for state: OperationState in [.inactive, .ready, .finished, .delayedStart] {
            let dishwasher = DishWasher(remainingTime: 60, programProgress: 100, operationState: state)
            let data = FluxData(cleanBot: nil, car: nil, dishwasher: dishwasher, dryer: nil, washer: nil)
            let device = try XCTUnwrap(convertDataToWidgetDevices(fluxData: data).first { $0.name == "Dishwasher" })
            XCTAssertFalse(device.running, state.rawValue)
            XCTAssertNil(device.endsAt)
        }
    }

    func testRobotPauseAndDockingAreNotCompletion() throws {
        for docking in [false, true] {
            let robot = Robot(
                name: "Cleanbot", timestamp: "now", batteryLevel: 81, running: false,
                docking: docking, paused: !docking, progressPercent: 32, estimatedRemainingMinutes: 14
            )
            let data = FluxData(cleanBot: robot, car: nil, dishwasher: nil, dryer: nil, washer: nil)
            let device = try XCTUnwrap(convertDataToWidgetDevices(fluxData: data).first { $0.name == "Cleanbot" })
            XCTAssertTrue(device.running)
            XCTAssertEqual(device.shortText, docking ? "Returning to dock" : "Paused")
            XCTAssertEqual(device.progress, 32)
            XCTAssertEqual(device.battery, 81)
            XCTAssertEqual(device.cleaning, false)
            XCTAssertNil(device.endsAt)
        }
    }

    func testDockedRobotIsNotActive() throws {
        let robot = Robot(name: "Cleanbot", timestamp: "now", running: false, docking: false, paused: false)
        let data = FluxData(cleanBot: robot, car: nil, dishwasher: nil, dryer: nil, washer: nil)
        let device = try XCTUnwrap(convertDataToWidgetDevices(fluxData: data).first { $0.name == "Cleanbot" })
        XCTAssertFalse(device.running)
        XCTAssertEqual(device.shortText, "Off")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
