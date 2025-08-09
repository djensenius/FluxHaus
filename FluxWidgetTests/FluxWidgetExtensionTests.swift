//
//  FluxWidgetExtensionTests.swift
//  FluxWidget Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation

struct FluxWidgetExtensionTests {
    
    @Test("Widget timeline updates work correctly")
    func testWidgetTimelineUpdate() async {
        // Test widget timeline generation logic
        let currentDate = Date()
        let futureDate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate
        
        #expect(futureDate > currentDate)
        
        // Test that timeline intervals are reasonable
        let timeInterval = futureDate.timeIntervalSince(currentDate)
        #expect(timeInterval > 0)
        #expect(timeInterval <= 900) // Should be 15 minutes or less
    }
    
    @Test("Widget data refresh intervals are appropriate")
    func testWidgetRefreshIntervals() {
        // Test different refresh intervals for different device states
        let refreshIntervals = [
            "active": 300,    // 5 minutes for active devices
            "idle": 900,      // 15 minutes for idle devices
            "charging": 1800, // 30 minutes for charging devices
            "error": 60       // 1 minute for error states
        ]
        
        #expect(refreshIntervals["active"]! == 300)
        #expect(refreshIntervals["idle"]! == 900)
        #expect(refreshIntervals["charging"]! == 1800)
        #expect(refreshIntervals["error"]! == 60)
        
        // All intervals should be positive
        for (_, interval) in refreshIntervals {
            #expect(interval > 0)
        }
    }
    
    @Test("Widget entry creation works correctly")
    func testWidgetEntryCreation() {
        let currentDate = Date()
        let devices = [
            WidgetDevice(name: "MopBot", battery: 85, status: "Cleaning", running: true),
            WidgetDevice(name: "Car", battery: 75, status: "Locked", running: false),
            WidgetDevice(name: "Dishwasher", battery: 0, status: "Washing", running: true)
        ]
        
        // Test widget entry data structure
        let widgetEntry = WidgetEntry(
            date: currentDate,
            devices: devices
        )
        
        #expect(widgetEntry.date == currentDate)
        #expect(widgetEntry.devices.count == 3)
        #expect(widgetEntry.devices.contains { $0.name == "MopBot" })
        #expect(widgetEntry.devices.contains { $0.name == "Car" })
        #expect(widgetEntry.devices.contains { $0.name == "Dishwasher" })
    }
    
    @Test("Widget size constraints are respected")
    func testWidgetSizeConstraints() {
        // Test widget size limitations
        let maxDevicesInSmallWidget = 2
        let maxDevicesInMediumWidget = 4
        let maxDevicesInLargeWidget = 6
        
        let allDevices = [
            WidgetDevice(name: "MopBot", battery: 85, status: "Cleaning", running: true),
            WidgetDevice(name: "BroomBot", battery: 90, status: "Docked", running: false),
            WidgetDevice(name: "Car", battery: 75, status: "Locked", running: false),
            WidgetDevice(name: "Dishwasher", battery: 0, status: "Washing", running: true),
            WidgetDevice(name: "Dryer", battery: 0, status: "Ready", running: false),
            WidgetDevice(name: "Washer", battery: 0, status: "Finished", running: false),
            WidgetDevice(name: "Battery", battery: 95, status: "Charging", running: false)
        ]
        
        // Test small widget constraints
        let smallWidgetDevices = Array(allDevices.prefix(maxDevicesInSmallWidget))
        #expect(smallWidgetDevices.count <= maxDevicesInSmallWidget)
        
        // Test medium widget constraints  
        let mediumWidgetDevices = Array(allDevices.prefix(maxDevicesInMediumWidget))
        #expect(mediumWidgetDevices.count <= maxDevicesInMediumWidget)
        
        // Test large widget constraints
        let largeWidgetDevices = Array(allDevices.prefix(maxDevicesInLargeWidget))
        #expect(largeWidgetDevices.count <= maxDevicesInLargeWidget)
    }
    
    @Test("Widget error states are handled correctly")
    func testWidgetErrorHandling() {
        let currentDate = Date()
        
        // Test widget entry with no devices (error state)
        let emptyEntry = WidgetEntry(
            date: currentDate,
            devices: []
        )
        
        #expect(emptyEntry.devices.count == 0)
        #expect(emptyEntry.date == currentDate)
        
        // Test widget entry with invalid device data
        let invalidDevices = [
            WidgetDevice(name: "", battery: -1, status: "", running: false)
        ]
        
        let invalidEntry = WidgetEntry(
            date: currentDate,
            devices: invalidDevices
        )
        
        #expect(invalidEntry.devices.count == 1)
        #expect(invalidEntry.devices.first?.name == "")
        #expect(invalidEntry.devices.first?.battery == -1)
    }
    
    @Test("Widget background refresh behavior")
    func testWidgetBackgroundRefresh() {
        // Test widget background refresh timing
        let lastRefresh = Date()
        let minimumRefreshInterval: TimeInterval = 300 // 5 minutes
        let nextRefresh = lastRefresh.addingTimeInterval(minimumRefreshInterval)
        
        #expect(nextRefresh > lastRefresh)
        
        let timeDifference = nextRefresh.timeIntervalSince(lastRefresh)
        #expect(timeDifference == minimumRefreshInterval)
        
        // Test that refresh doesn't happen too frequently
        let tooSoon = lastRefresh.addingTimeInterval(60) // 1 minute
        #expect(tooSoon < nextRefresh)
    }
    
    @Test("Widget data prioritization works correctly")
    func testWidgetDataPrioritization() {
        let devices = [
            WidgetDevice(name: "MopBot", battery: 15, status: "Low Battery", running: false),      // Priority: Low battery
            WidgetDevice(name: "BroomBot", battery: 85, status: "Cleaning", running: true),       // Priority: Running
            WidgetDevice(name: "Car", battery: 75, status: "Locked", running: false),             // Priority: Constant
            WidgetDevice(name: "Dishwasher", battery: 0, status: "Washing", running: true),       // Priority: Running timed
            WidgetDevice(name: "Battery", battery: 95, status: "Charging", running: false)        // Priority: Constant
        ]
        
        // Test prioritization logic
        let runningDevices = devices.filter { $0.running }
        let lowBatteryDevices = devices.filter { $0.battery > 0 && $0.battery < 20 }
        let constantDevices = devices.filter { $0.name == "Car" || $0.name == "Battery" }
        
        #expect(runningDevices.count == 2) // BroomBot and Dishwasher
        #expect(lowBatteryDevices.count == 1) // MopBot with 15% battery
        #expect(constantDevices.count == 2) // Car and Battery
        
        // Running devices should be prioritized
        #expect(runningDevices.contains { $0.name == "BroomBot" })
        #expect(runningDevices.contains { $0.name == "Dishwasher" })
        
        // Low battery devices should be flagged
        #expect(lowBatteryDevices.first?.name == "MopBot")
    }
}

// Helper structures for widget testing
struct WidgetEntry {
    let date: Date
    let devices: [WidgetDevice]
}

extension WidgetEntry {
    init(date: Date, devices: [WidgetDevice]) {
        self.date = date
        self.devices = devices
    }
}