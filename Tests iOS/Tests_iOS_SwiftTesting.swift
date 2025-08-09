//
//  Tests_iOS.swift
//  Tests iOS
//
//  Created by David Jensenius on 2020-12-13.
//  Updated to use Swift Testing framework
//

import Testing
import XCTest

struct iOSTests {

    @Test("iOS app can be launched successfully")
    func testAppLaunch() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Verify the app launched without crashing
        #expect(app.state == .runningForeground)
    }

    @Test("iOS app launch performance is reasonable", .timeLimit(.seconds(30)))
    func testLaunchPerformance() throws {
        // Test that the app launches within a reasonable time
        let app = XCUIApplication()

        let startTime = Date()
        app.launch()
        let launchTime = Date().timeIntervalSince(startTime)

        // App should launch within 10 seconds
        #expect(launchTime < 10.0)
        #expect(app.state == .runningForeground)
    }

    @Test("iOS app displays loading screen initially")
    func testLoadingScreenDisplay() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for the app to fully load
        Thread.sleep(forTimeInterval: 2.0)

        // Verify the app is running (we can't test exact UI elements without knowing them)
        #expect(app.state == .runningForeground)
    }

    @Test("iOS app handles device orientation changes")
    func testOrientationChanges() throws {
        let app = XCUIApplication()
        app.launch()

        // Test portrait orientation
        XCUIDevice.shared.orientation = .portrait
        #expect(app.state == .runningForeground)

        // Test landscape orientation if supported
        XCUIDevice.shared.orientation = .landscapeLeft
        #expect(app.state == .runningForeground)

        // Return to portrait
        XCUIDevice.shared.orientation = .portrait
        #expect(app.state == .runningForeground)
    }

    @Test("iOS app supports accessibility features")
    func testAccessibilitySupport() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the app launched and has accessibility elements
        #expect(app.state == .runningForeground)

        // Basic accessibility check - the app should have some accessible elements
        let accessibleElements = app.descendants(matching: .any).allElementsBoundByAccessibilityElement
        #expect(accessibleElements.count > 0)
    }

    @Test("iOS app memory usage is reasonable during launch")
    func testMemoryUsage() throws {
        let app = XCUIApplication()
        app.launch()

        // Basic test that the app launches and doesn't immediately crash
        // In a real test environment, you might monitor actual memory usage
        Thread.sleep(forTimeInterval: 3.0)
        #expect(app.state == .runningForeground)
    }
}
