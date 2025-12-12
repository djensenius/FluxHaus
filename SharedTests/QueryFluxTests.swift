//
//  QueryFluxTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation
@testable import FluxHaus

struct QueryFluxTests {

    @Test("FluxData model can be created with all properties")
    func testFluxDataModel() {
        let mopBot = Robot(
            name: "MopBot",
            timestamp: "2024-12-01T12:00:00Z",
            batteryLevel: 85,
            binFull: false,
            running: true,
            charging: false,
            docking: false,
            paused: false,
            timeStarted: "2024-12-01T11:30:00Z"
        )

        let broomBot = Robot(
            name: "BroomBot",
            timestamp: "2024-12-01T12:00:00Z",
            batteryLevel: 92,
            binFull: false,
            running: false,
            charging: true,
            docking: true,
            paused: false,
            timeStarted: nil
        )

        let car = CarDetails(
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

        let dishwasher = DishWasher(
            status: "Running",
            program: "Quick Wash",
            remainingTime: 3600,
            remainingTimeUnit: "seconds",
            remainingTimeEstimate: true,
            programProgress: 25.0,
            operationState: .run,
            doorState: "Closed",
            selectedProgram: "QuickWash45",
            activeProgram: .quick45,
            startInRelative: nil,
            startInRelativeUnit: nil
        )

        let dryer = WasherDryer(
            name: "Dryer",
            timeRunning: nil,
            timeRemaining: nil,
            step: nil,
            programName: nil,
            status: "Inactive",
            inUse: false
        )

        let washer = WasherDryer(
            name: "Washer",
            timeRunning: 45,
            timeRemaining: 0,
            step: "Finished",
            programName: "Cotton",
            status: "Finished",
            inUse: false
        )

        let fluxData = FluxData(
            mopBot: mopBot,
            broomBot: broomBot,
            car: car,
            dishwasher: dishwasher,
            dryer: dryer,
            washer: washer
        )

        #expect(fluxData.mopBot?.name == "MopBot")
        #expect(fluxData.broomBot?.name == "BroomBot")
        #expect(fluxData.car?.batteryLevel == 75)
        #expect(fluxData.dishwasher?.operationState == .run)
        #expect(fluxData.dryer?.inUse == false)
        #expect(fluxData.washer?.inUse == false)
    }

    @Test("WidgetDevice model can be created and compared")
    func testWidgetDeviceModel() {
        let device1 = WidgetDevice(
            name: "TestDevice",
            battery: 85,
            status: "Running"
        )

        let device2 = WidgetDevice(
            name: "TestDevice",
            battery: 85,
            status: "Running"
        )

        let device3 = WidgetDevice(
            name: "DifferentDevice",
            battery: 70,
            status: "Idle"
        )

        #expect(device1.name == "TestDevice")
        #expect(device1.progress == 85)
        #expect(device1.trailingText == "Running")

        // Test equality
        #expect(device1 == device2)
        #expect(device1 != device3)

        // Test hashability
        let deviceSet = Set([device1, device2, device3])
        #expect(deviceSet.count == 2) // device1 and device2 should be considered the same
    }

    @Test("Network request components are formed correctly")
    func testNetworkRequestComponents() {
        // Test URL component formation (without actually making network calls)
        let scheme = "https"
        let host = "api.fluxhaus.io"
        let path = "/"
        let user = "admin"
        let password = "testPassword"

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.user = user
        components.password = password

        let url = components.url
        #expect(url != nil)
        #expect(url?.scheme == "https")
        #expect(url?.host == "api.fluxhaus.io")
        #expect(url?.path == "/")
        #expect(url?.user == "admin")
        #expect(url?.password == "testPassword")
    }

    @Test("HTTP request configuration is correct")
    func testHTTPRequestConfiguration() {
        // Test HTTP request setup without making actual network calls
        let url = URL(string: "https://api.fluxhaus.io/")!
        var request = URLRequest(url: url)
        request.httpMethod = "get"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        #expect(request.url?.absoluteString == "https://api.fluxhaus.io/")
        #expect(request.httpMethod?.lowercased() == "get")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }
}

// Helper extensions for testing
// FluxData extension removed as memberwise init should be accessible via @testable import

extension WidgetDevice {
    init(name: String, battery: Int, status: String) {
        self = WidgetDevice(
            name: name,
            progress: battery,
            icon: "circle",
            trailingText: status,
            shortText: status,
            running: false
        )
    }
}
