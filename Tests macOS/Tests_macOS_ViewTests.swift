//
//  Tests_macOS_ViewTests.swift
//  Tests macOS
//
//  Created by Copilot on 2026-03-02.
//

// swiftlint:disable file_length

import Testing
import AppKit
import SwiftUI
import Carbon

/// Drains pending DispatchQueue.main.async blocks so data population completes.
@MainActor
private func drainMainQueueForViews() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

/// Creates a LoginResponse with all device fields nil.
private func emptyViewResponse() -> LoginResponse {
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

// MARK: - macOS View Smoke Tests (NSHostingController)

struct MacOSViewSmokeTests {

    @Test("LoginView renders login form without crashing")
    @MainActor func testLoginViewLogin() {
        let view = LoginView(needLoginView: true)
        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("LoginView renders loading state without crashing")
    @MainActor func testLoginViewLoading() {
        let view = LoginView(needLoginView: false)
        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("ContentView renders with mock data without crashing")
    @MainActor func testContentViewWithMockData() async {
        let config = FluxHausConsts()
        config.setConfig(config: FluxHausConfig(
            favouriteHomeKit: ["Light 1"],
            favouriteScenes: []
        ))

        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueueForViews()

        let view = ContentView(
            fluxHausConsts: config,
            hconn: hconn,
            miele: miele,
            robots: robots,
            battery: MockData.createBattery(),
            car: car,
            apiResponse: MockData.createApi(),
            chat: Chat()
        )

        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("SettingsView renders without crashing")
    @MainActor func testSettingsView() {
        let view = SettingsView()
        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("Quick Chat view renders without crashing")
    @MainActor func testQuickChatView() {
        let view = ChatView(chat: Chat(), style: .quick)
        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("Expanded Quick Chat view renders without crashing")
    @MainActor func testExpandedQuickChatView() {
        let view = ChatView(chat: Chat(), style: .quick, initialQuickChatExpanded: true)
        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("DashboardView renders with mock data without crashing")
    @MainActor func testDashboardView() async {
        let config = FluxHausConsts()
        config.setConfig(config: FluxHausConfig(
            favouriteHomeKit: [],
            favouriteScenes: ["Good Morning"]
        ))

        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueueForViews()

        let view = DashboardView(
            fluxHausConsts: config,
            hconn: hconn,
            miele: miele,
            robots: robots,
            battery: MockData.createBattery(),
            car: car,
            apiResponse: MockData.createApi(),
            locationManager: LocationManager(),
            radarService: RadarService(),
            onNavigate: { _ in }
        )

        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("MenuBarView renders without crashing")
    @MainActor func testMenuBarView() async {
        let hconn = MockData.createHomeConnect()
        let miele = MockData.createMiele()
        let robots = MockData.createRobots()
        let car = MockData.createCar()
        await drainMainQueueForViews()

        let view = MenuBarView(
            car: car,
            robots: robots,
            miele: miele,
            hconn: hconn,
            favouriteScenes: ["Good Morning"]
        )

        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }
}

// MARK: - SidebarItem Tests

struct SidebarItemTests {

    @Test("SidebarItem has all expected cases")
    func testAllCases() {
        let items = SidebarItem.allCases
        #expect(items.count == 8)
        #expect(items.contains(.dashboard))
        #expect(items.contains(.weather))
        #expect(items.contains(.scenes))
        #expect(items.contains(.appliances))
        #expect(items.contains(.car))
        #expect(items.contains(.scooter))
        #expect(items.contains(.robots))
        #expect(items.contains(.assistant))
    }

    @Test("SidebarItem has correct display names")
    func testDisplayNames() {
        #expect(SidebarItem.dashboard.rawValue == "Dashboard")
        #expect(SidebarItem.weather.rawValue == "Weather")
        #expect(SidebarItem.scenes.rawValue == "Scenes")
        #expect(SidebarItem.appliances.rawValue == "Appliances")
        #expect(SidebarItem.car.rawValue == "Car")
        #expect(SidebarItem.scooter.rawValue == "Scooter")
        #expect(SidebarItem.robots.rawValue == "Robots")
        #expect(SidebarItem.assistant.rawValue == "Assistant")
    }

    @Test("SidebarItem has correct icons")
    func testIcons() {
        #expect(SidebarItem.dashboard.icon == "house.fill")
        #expect(SidebarItem.weather.icon == "cloud.sun.fill")
        #expect(SidebarItem.scenes.icon == "lightbulb.fill")
        #expect(SidebarItem.appliances.icon == "washer.fill")
        #expect(SidebarItem.car.icon == "car.fill")
        #expect(SidebarItem.scooter.icon == "scooter")
        #expect(SidebarItem.robots.icon == "fan.fill")
        #expect(
            SidebarItem.assistant.icon
            == "bubble.left.and.bubble.right.fill"
        )
    }

    @Test("SidebarItem ids are unique")
    func testUniqueIds() {
        let ids = SidebarItem.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

struct QuickChatShortcutTests {

    @Test("Quick chat shortcut titles are stable")
    func testShortcutTitles() {
        #expect(QuickChatShortcut.defaultShortcut.title == "⌥␣")
        #expect(QuickChatShortcut.disabled.title == "Disabled")
    }

    @Test("Quick chat shortcut migrates old preset values")
    func testShortcutMigration() {
        #expect(QuickChatShortcut.fromStored("shiftCommandSpace").title == "⇧⌘␣")
        #expect(QuickChatShortcut.fromStored("controlSpace").title == "⌃␣")
        #expect(QuickChatShortcut.fromStored("optionCommandSpace").title == "⌥⌘␣")
    }

    @Test("Quick chat shortcut fallback uses default")
    func testShortcutFallback() {
        #expect(QuickChatShortcut.fromStored("invalid-shortcut").title == "⌥␣")
    }

    @Test("Quick chat shortcut round-trips custom values")
    func testShortcutRoundTrip() {
        let shortcut = QuickChatShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | optionKey),
            displayKey: "K"
        )
        #expect(QuickChatShortcut.fromStored(shortcut.rawValue) == shortcut)
        #expect(shortcut.title == "⌥⌘K")
    }

    @Test("Quick chat shortcut preserves unshifted number row labels")
    func testShortcutUnshiftedNumberRowLabel() {
        let shortcut = QuickChatShortcut(
            keyCode: UInt32(kVK_ANSI_9),
            carbonModifiers: UInt32(shiftKey | cmdKey),
            displayKey: "9"
        )
        #expect(shortcut.title == "⇧⌘9")
    }
}

// MARK: - HomeScene Model Tests

struct HomeSceneModelTests {

    @Test("HomeScene encoding and decoding roundtrip")
    func testCodableRoundtrip() throws {
        let scene = HomeScene(
            entityId: "scene.bedroom_off",
            name: "Bedroom Off",
            isActive: false
        )
        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(
            HomeScene.self, from: data
        )
        #expect(decoded.entityId == "scene.bedroom_off")
        #expect(decoded.name == "Bedroom Off")
        #expect(decoded.isActive == false)
        #expect(decoded.id == "scene.bedroom_off")
    }

    @Test("HomeScene decodes from server JSON")
    func testDecodingFromJSON() throws {
        let json = Data("""
        {"entityId":"scene.comfy","name":"Comfy","isActive":null}
        """.utf8)

        let scene = try JSONDecoder().decode(
            HomeScene.self, from: json
        )
        #expect(scene.entityId == "scene.comfy")
        #expect(scene.name == "Comfy")
        #expect(scene.isActive == nil)
    }

    @Test("HomeScene array decodes correctly")
    func testArrayDecoding() throws {
        let json = Data("""
        [
          {"entityId":"scene.a","name":"A","isActive":false},
          {"entityId":"scene.b","name":"B","isActive":true}
        ]
        """.utf8)

        let scenes = try JSONDecoder().decode(
            [HomeScene].self, from: json
        )
        #expect(scenes.count == 2)
        #expect(scenes[0].id == "scene.a")
        #expect(scenes[1].isActive == true)
    }
}

// MARK: - SceneManager Tests

struct SceneManagerTests {

    @Test("SceneManager initial state is empty")
    @MainActor func testInitialState() {
        let manager = SceneManager()
        #expect(manager.scenes.isEmpty)
        #expect(manager.favourites.isEmpty)
        #expect(manager.activatingSceneId == nil)
        #expect(manager.loadError == nil)
        #expect(manager.hasLoaded == false)
    }
}

// MARK: - Battery Platform Tests

struct BatteryPlatformTests {

    @Test("Battery model enum has all platform types")
    func testModelEnum() {
        let models: [Model] = [.iPhone, .iPad, .visionPro, .mac]
        #expect(models.count == 4)
    }

    @Test("Battery initializes with valid range")
    @MainActor func testBatteryInit() {
        let battery = Battery()
        #expect(battery.percent >= 0)
        #expect(battery.percent <= 100)
    }

    @Test("Battery percent assignment works")
    @MainActor func testPercentAssignment() {
        let battery = Battery()
        battery.percent = 42
        #expect(battery.percent == 42)

        battery.percent = 0
        #expect(battery.percent == 0)

        battery.percent = 100
        #expect(battery.percent == 100)
    }

    @Test("Battery model on macOS defaults correctly")
    @MainActor func testMacOSModel() {
        let battery = Battery()
        #expect(battery.model == .mac)
    }
}

// MARK: - Nil/Missing Data Resilience

struct MacOSNilDataResilienceTests {

    @Test("Views handle nil car and appliance data")
    @MainActor func testNilDeviceData() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyViewResponse())

        let car = Car()
        car.setApiResponse(apiResponse: api)
        let hconn = HomeConnect(apiResponse: api)
        let miele = Miele(apiResponse: api)
        await drainMainQueueForViews()

        #expect(car.vehicle.batteryLevel == 0)
        #expect(car.vehicle.distance == 0)
        #expect(hconn.appliances.count == 1)
        #expect(hconn.appliances.first?.inUse == false)
        #expect(miele.appliances.count == 0)
    }

    @Test("Robots with nil status have default values")
    @MainActor func testNilRobotData() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyViewResponse())
        let robots = Robots()
        robots.setApiResponse(apiResponse: api)
        await drainMainQueueForViews()

        #expect(robots.broomBot.batteryLevel == nil)
        #expect(robots.broomBot.running == nil)
        #expect(robots.mopBot.batteryLevel == nil)
        #expect(robots.mopBot.running == nil)
    }

    @Test("ContentView renders with empty data without crashing")
    @MainActor func testContentViewMinimalData() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyViewResponse())

        let hconn = HomeConnect(apiResponse: api)
        let miele = Miele(apiResponse: api)
        let robots = Robots()
        robots.setApiResponse(apiResponse: api)
        let car = Car()
        car.setApiResponse(apiResponse: api)
        await drainMainQueueForViews()

        let view = ContentView(
            fluxHausConsts: FluxHausConsts(),
            hconn: hconn, miele: miele, robots: robots,
            battery: Battery(), car: car, apiResponse: api, chat: Chat()
        )
        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }

    @Test("DashboardView renders with empty data without crashing")
    @MainActor func testDashboardMinimalData() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyViewResponse())

        let hconn = HomeConnect(apiResponse: api)
        let miele = Miele(apiResponse: api)
        let robots = Robots()
        robots.setApiResponse(apiResponse: api)
        let car = Car()
        car.setApiResponse(apiResponse: api)
        await drainMainQueueForViews()

        let view = DashboardView(
            fluxHausConsts: FluxHausConsts(),
            hconn: hconn, miele: miele, robots: robots,
            battery: Battery(), car: car, apiResponse: api,
            locationManager: LocationManager(),
            radarService: RadarService(),
            onNavigate: { _ in }
        )
        let controller = NSHostingController(rootView: view)
        controller.loadView()
        #expect(controller.view.frame.width >= 0)
    }
}

// MARK: - FluxHausConsts Tests

struct MacOSFluxHausConstsTests {

    @Test("FluxHausConsts stores favouriteScenes")
    @MainActor func testFavouriteScenes() {
        let consts = FluxHausConsts()
        consts.setConfig(config: FluxHausConfig(
            favouriteHomeKit: ["Light"],
            favouriteScenes: ["Morning", "Night"]
        ))
        #expect(consts.favouriteScenes == ["Morning", "Night"])
    }

    @Test("FluxHausConsts stores favouriteHomeKit")
    @MainActor func testFavouriteHomeKit() {
        let consts = FluxHausConsts()
        consts.setConfig(config: FluxHausConfig(
            favouriteHomeKit: ["Light 1", "Light 2"],
            favouriteScenes: []
        ))
        #expect(consts.favouriteHomeKit == ["Light 1", "Light 2"])
    }

    @Test("FluxHausConsts handles empty config")
    @MainActor func testEmptyConfig() {
        let consts = FluxHausConsts()
        consts.setConfig(config: FluxHausConfig(
            favouriteHomeKit: [],
            favouriteScenes: []
        ))
        #expect(consts.favouriteHomeKit.isEmpty)
        #expect(consts.favouriteScenes.isEmpty)
    }
}

// MARK: - Car Details Tests

struct MacOSCarDetailsTests {

    @Test("Car details text reflects vehicle state")
    @MainActor func testCarDetailsText() async {
        let car = MockData.createCar()
        await drainMainQueueForViews()
        #expect(carDetails(car: car).contains("350 km"))
    }

    @Test("Car with zero range omits range from details")
    @MainActor func testCarZeroRange() async {
        let api = Api()
        api.setApiResponse(apiResponse: emptyViewResponse())
        let car = Car()
        car.setApiResponse(apiResponse: api)
        await drainMainQueueForViews()
        let details = carDetails(car: car)
        #expect(!details.contains("km"))
    }
}
