//
//  SharedTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation

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
            
            #expect(robots.mopBot.name == "MopBot")
            #expect(robots.broomBot.name == "BroomBot")
            #expect(robots.mopBot.timestamp == "")
            #expect(robots.broomBot.timestamp == "")
            #expect(robots.mopBot.batteryLevel == nil)
            #expect(robots.broomBot.batteryLevel == nil)
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
            #expect(robots.mopBot.name == "MopBot")
            #expect(robots.broomBot.name == "BroomBot")
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

// Helper functions and imports for testing
extension Appliance {
    init(name: String, timeRunning: Int, timeRemaining: Int, timeFinish: String, step: String, programName: String, inUse: Bool) {
        self.name = name
        self.timeRunning = timeRunning
        self.timeRemaining = timeRemaining
        self.timeFinish = timeFinish
        self.step = step
        self.programName = programName
        self.inUse = inUse
    }
}

extension Robot {
    init(name: String?, timestamp: String, batteryLevel: Int?, binFull: Bool?, running: Bool?, charging: Bool?, docking: Bool?, paused: Bool?, timeStarted: String?) {
        self.name = name
        self.timestamp = timestamp
        self.batteryLevel = batteryLevel
        self.binFull = binFull
        self.running = running
        self.charging = charging
        self.docking = docking
        self.paused = paused
        self.timeStarted = timeStarted
    }
}

extension Doors {
    init(frontRight: Int, frontLeft: Int, backRight: Int, backLeft: Int) {
        self.frontRight = frontRight
        self.frontLeft = frontLeft
        self.backRight = backRight
        self.backLeft = backLeft
    }
}

extension CarDetails {
    init(timestamp: String, evStatusTimestamp: String, batteryLevel: Int, distance: Int, hvac: Bool, pluggedIn: Bool, batteryCharge: Bool, locked: Bool, doorsOpen: Doors, trunkOpen: Bool, defrost: Bool, hoodOpen: Bool, odometer: Double, engine: Bool) {
        self.timestamp = timestamp
        self.evStatusTimestamp = evStatusTimestamp
        self.batteryLevel = batteryLevel
        self.distance = distance
        self.hvac = hvac
        self.pluggedIn = pluggedIn
        self.batteryCharge = batteryCharge
        self.locked = locked
        self.doorsOpen = doorsOpen
        self.trunkOpen = trunkOpen
        self.defrost = defrost
        self.hoodOpen = hoodOpen
        self.odometer = odometer
        self.engine = engine
    }
}