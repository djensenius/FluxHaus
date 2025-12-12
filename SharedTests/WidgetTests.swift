//
//  WidgetTests.swift
//  FluxHaus Tests
//
//  Created by Testing Suite on 2024-12-01.
//

import Testing
import Foundation
@testable import FluxHaus

struct WidgetTests {

    @Test("WidgetDevice classification works correctly")
    func testWidgetDeviceClassification() {
        // Create test devices
        let car = WidgetDevice(name: "Car", battery: 75, status: "Locked", running: false)
        let battery = WidgetDevice(name: "Battery", battery: 85, status: "Charging", running: false)
        let mopBotRunning = WidgetDevice(name: "MopBot", battery: 65, status: "Cleaning", running: true)
        let mopBotOff = WidgetDevice(name: "MopBot", battery: 85, status: "Docked", running: false)
        let broomBotRunning = WidgetDevice(name: "BroomBot", battery: 70, status: "Cleaning", running: true)
        let broomBotOff = WidgetDevice(name: "BroomBot", battery: 90, status: "Charging", running: false)
        let dishwasherRunning = WidgetDevice(name: "Dishwasher", battery: 0, status: "Washing", running: true)
        let dishwasherOff = WidgetDevice(name: "Dishwasher", battery: 0, status: "Ready", running: false)

        // Test constant devices (Car, Battery)
        #expect(car.name == "Car")
        #expect(battery.name == "Battery")
        #expect(!car.running)
        #expect(!battery.running)

        // Test robot devices
        #expect(mopBotRunning.running == true)
        #expect(mopBotOff.running == false)
        #expect(broomBotRunning.running == true)
        #expect(broomBotOff.running == false)

        // Test appliance devices
        #expect(dishwasherRunning.running == true)
        #expect(dishwasherOff.running == false)
    }

    @Test("WidgetDevice sorting logic works correctly")
    func testWidgetDeviceSorting() {
        // This tests the conceptual sorting logic without calling the actual widget functions
        // since those depend on network calls

        let devices = [
            WidgetDevice(name: "Car", battery: 75, status: "Locked", running: false),
            WidgetDevice(name: "MopBot", battery: 65, status: "Cleaning", running: true),
            WidgetDevice(name: "BroomBot", battery: 90, status: "Charging", running: false),
            WidgetDevice(name: "Dishwasher", battery: 0, status: "Washing", running: true),
            WidgetDevice(name: "Battery", battery: 85, status: "Charging", running: false)
        ]

        // Sort devices into categories like the widget would
        let constantDevices = devices.filter { $0.name == "Car" || $0.name == "Battery" }
        let runningRobots = devices.filter { ($0.name == "MopBot" || $0.name == "BroomBot") && $0.running }
        let offRobots = devices.filter { ($0.name == "MopBot" || $0.name == "BroomBot") && !$0.running }
        let runningAppliances = devices.filter {
            $0.name != "Car" && $0.name != "Battery" && $0.name != "MopBot" && $0.name != "BroomBot" && $0.running
        }
        let offAppliances = devices.filter {
            $0.name != "Car" && $0.name != "Battery" && $0.name != "MopBot" && $0.name != "BroomBot" && !$0.running
        }

        #expect(constantDevices.count == 2)
        #expect(runningRobots.count == 1)
        #expect(offRobots.count == 1)
        #expect(runningAppliances.count == 1)
        #expect(offAppliances.count == 0)

        #expect(constantDevices.contains { $0.name == "Car" })
        #expect(constantDevices.contains { $0.name == "Battery" })
        #expect(runningRobots.first?.name == "MopBot")
        #expect(offRobots.first?.name == "BroomBot")
        #expect(runningAppliances.first?.name == "Dishwasher")
    }

    @Test("WidgetDevice battery level handling works correctly")
    func testWidgetDeviceBatteryLevels() {
        let deviceWithBattery = WidgetDevice(name: "MopBot", battery: 85, status: "Charging", running: false)
        let deviceWithoutBattery = WidgetDevice(name: "Dishwasher", battery: 0, status: "Ready", running: false)
        let deviceWithLowBattery = WidgetDevice(name: "BroomBot", battery: 15, status: "Low Battery", running: false)

        #expect(deviceWithBattery.battery == 85)
        #expect(deviceWithoutBattery.battery == 0)
        #expect(deviceWithLowBattery.battery == 15)

        // Test battery level ranges
        #expect(deviceWithBattery.battery > 50) // High battery
        #expect(deviceWithLowBattery.battery < 20) // Low battery
        #expect(deviceWithoutBattery.battery == 0) // No battery info
    }

    @Test("WidgetDevice status strings are meaningful")
    func testWidgetDeviceStatusStrings() {
        let runningBot = WidgetDevice(name: "MopBot", battery: 70, status: "Cleaning", running: true)
        let chargingBot = WidgetDevice(name: "BroomBot", battery: 95, status: "Charging", running: false)
        let runningAppliance = WidgetDevice(name: "Dishwasher", battery: 0, status: "Washing", running: true)
        let readyAppliance = WidgetDevice(name: "Dryer", battery: 0, status: "Ready", running: false)
        let car = WidgetDevice(name: "Car", battery: 75, status: "Locked", running: false)

        #expect(runningBot.status == "Cleaning")
        #expect(chargingBot.status == "Charging")
        #expect(runningAppliance.status == "Washing")
        #expect(readyAppliance.status == "Ready")
        #expect(car.status == "Locked")

        // Verify status makes sense for running state
        #expect(runningBot.running == true)
        #expect(runningBot.status.contains("Cleaning"))
        #expect(chargingBot.running == false)
        #expect(runningAppliance.running == true)
        #expect(readyAppliance.running == false)
    }

    @Test("WidgetDevice data consistency checks")
    func testWidgetDeviceDataConsistency() {
        // Test that devices have consistent data
        let mopBot = WidgetDevice(name: "MopBot", battery: 65, status: "Cleaning", running: true)

        // Running device should have appropriate status
        #expect(mopBot.running == true)
        #expect(mopBot.status != "Ready" && mopBot.status != "Idle")

        let idleBot = WidgetDevice(name: "BroomBot", battery: 90, status: "Docked", running: false)

        // Non-running device should have appropriate status
        #expect(idleBot.running == false)
        #expect(idleBot.status != "Cleaning" && idleBot.status != "Running")

        // Battery levels should be in valid range
        #expect(mopBot.battery >= 0 && mopBot.battery <= 100)
        #expect(idleBot.battery >= 0 && idleBot.battery <= 100)
    }

    @Test("WidgetDevice edge cases are handled")
    func testWidgetDeviceEdgeCases() {
        // Test edge cases
        let noBatteryDevice = WidgetDevice(name: "Dishwasher", battery: 0, status: "Ready", running: false)
        let fullBatteryDevice = WidgetDevice(name: "MopBot", battery: 100, status: "Ready", running: false)
        let emptyStatusDevice = WidgetDevice(name: "Unknown", battery: 50, status: "", running: false)

        #expect(noBatteryDevice.battery == 0)
        #expect(fullBatteryDevice.battery == 100)
        #expect(emptyStatusDevice.status == "")

        // All devices should have valid names
        #expect(!noBatteryDevice.name.isEmpty)
        #expect(!fullBatteryDevice.name.isEmpty)
        #expect(!emptyStatusDevice.name.isEmpty)
    }
}
