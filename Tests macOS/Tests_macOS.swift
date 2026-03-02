//
//  Tests_macOS.swift
//  Tests macOS
//
//  Created by David Jensenius on 2020-12-13.
//

import XCTest
import SwiftUI

class TestsmacOS: XCTestCase {

    @MainActor
    func testMockDataCreation() async {
        let api = MockData.createApi()
        XCTAssertNotNil(api.response)
        XCTAssertEqual(
            api.response?.timestamp,
            "2024-12-13T12:00:00Z"
        )
    }

    @MainActor
    func testBatteryMacModel() async {
        let battery = Battery()
        battery.model = .mac
        XCTAssertEqual(battery.model, .mac)
    }
}
