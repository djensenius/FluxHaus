//
//  HomeConnectTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation

struct HomeConnectTests {
    
    @Test("DishWasherProgram enum contains expected values")
    func testDishWasherProgramEnum() {
        // Test that all expected dishwasher programs are available
        let programs: [DishWasherProgram] = [
            .eco50, .auto45, .quickwash45, .auto65, .eco45, .intensiv70, 
            .kurz60, .expressSparkle65, .machineCare, .steamFresh, 
            .maximumCleaning, .mixedLoad
        ]
        
        #expect(programs.count == 12)
        #expect(DishWasherProgram.eco50.rawValue == "Eco50")
        #expect(DishWasherProgram.intensiv70.rawValue == "Intensiv70")
    }
    
    @Test("OperationState enum contains expected values")
    func testOperationStateEnum() {
        let states: [OperationState] = [
            .inactive, .ready, .delayedStart, .run, .pause, 
            .actionRequired, .finished, .error, .aborting
        ]
        
        #expect(states.count == 9)
        #expect(OperationState.inactive.rawValue == "Inactive")
        #expect(OperationState.run.rawValue == "Run")
        #expect(OperationState.finished.rawValue == "Finished")
    }
    
    @Test("HomeConnect initializes with empty appliances")
    func testHomeConnectInitialization() async {
        let mockApi = Api()
        
        await MainActor.run {
            let homeConnect = HomeConnect(apiResponse: mockApi)
            #expect(homeConnect.appliances.count == 0)
            #expect(homeConnect.apiResponse != nil)
        }
    }
    
    @Test("HomeConnect nilProgram creates inactive appliance")
    func testNilProgram() async {
        let mockApi = Api()
        
        await MainActor.run {
            let homeConnect = HomeConnect(apiResponse: mockApi)
            homeConnect.nilProgram()
            
            #expect(homeConnect.appliances.count == 1)
            let appliance = homeConnect.appliances.first!
            #expect(appliance.name == "Dishwasher")
            #expect(appliance.timeRunning == 0)
            #expect(appliance.timeRemaining == 0)
            #expect(appliance.timeFinish == "")
            #expect(appliance.step == "")
            #expect(appliance.programName == "")
            #expect(appliance.inUse == false)
        }
    }
    
    @Test("HomeConnect setProgram creates active appliance")
    func testSetProgram() async {
        let mockApi = Api()
        
        await MainActor.run {
            let homeConnect = HomeConnect(apiResponse: mockApi)
            
            let mockDishwasher = DishWasher(
                status: "Running",
                program: "Quick Wash",
                remainingTime: 3600, // 60 minutes in seconds
                remainingTimeUnit: "seconds",
                remainingTimeEstimate: true,
                programProgress: 25.0,
                operationState: .run,
                doorState: "Closed",
                selectedProgram: "QuickWash45",
                activeProgram: .quickwash45,
                startInRelative: nil,
                startInRelativeUnit: nil
            )
            
            homeConnect.setProgram(program: mockDishwasher)
            
            #expect(homeConnect.appliances.count == 1)
            let appliance = homeConnect.appliances.first!
            #expect(appliance.name == "Dishwasher")
            #expect(appliance.timeRunning == 0)
            #expect(appliance.timeRemaining == 60) // Should be converted from seconds to minutes
            #expect(appliance.step == "Quick Wash")
            #expect(appliance.programName == "QuickWash45")
            #expect(appliance.inUse == true)
            #expect(appliance.timeFinish != "") // Should have a finish time
        }
    }
    
    @Test("HomeConnect setProgram handles nil activeProgram")
    func testSetProgramWithNilActiveProgram() async {
        let mockApi = Api()
        
        await MainActor.run {
            let homeConnect = HomeConnect(apiResponse: mockApi)
            
            let mockDishwasher = DishWasher(
                status: "Ready",
                program: "Waiting",
                remainingTime: 0,
                remainingTimeUnit: nil,
                remainingTimeEstimate: nil,
                programProgress: nil,
                operationState: .ready,
                doorState: "Closed",
                selectedProgram: nil,
                activeProgram: nil,
                startInRelative: nil,
                startInRelativeUnit: nil
            )
            
            homeConnect.setProgram(program: mockDishwasher)
            
            #expect(homeConnect.appliances.count == 1)
            let appliance = homeConnect.appliances.first!
            #expect(appliance.programName == "") // Should be empty when activeProgram is nil
            #expect(appliance.inUse == true)
        }
    }
    
    @Test("HomeConnect time calculation works correctly")
    func testTimeCalculation() async {
        let mockApi = Api()
        
        await MainActor.run {
            let homeConnect = HomeConnect(apiResponse: mockApi)
            
            // Test with 2.5 hours remaining (9000 seconds)
            let mockDishwasher = DishWasher(
                status: "Running",
                program: "Long Wash",
                remainingTime: 9000,
                remainingTimeUnit: "seconds",
                remainingTimeEstimate: true,
                programProgress: 10.0,
                operationState: .run,
                doorState: "Closed",
                selectedProgram: "LongWash",
                activeProgram: .intensiv70,
                startInRelative: nil,
                startInRelativeUnit: nil
            )
            
            homeConnect.setProgram(program: mockDishwasher)
            
            #expect(homeConnect.appliances.count == 1)
            let appliance = homeConnect.appliances.first!
            #expect(appliance.timeRemaining == 150) // 9000 seconds = 150 minutes
        }
    }
}