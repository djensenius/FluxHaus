//
//  QueryFlux.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

func queryFlux(password: String) {
    let scheme: String = "https"
    let host: String = "api.fluxhaus.io"
    let path = "/"

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path
    components.user = "admin"
    components.password = password

    guard let url = components.url else {
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "get"

    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")

    let task = URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data = data {
            let response = try? JSONDecoder().decode(LoginResponse.self, from: data)

            if let response = response {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: response,
                        userInfo: ["keysComplete": true]
                    )

                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: nil,
                        userInfo: ["updateKeychain": password]
                    )
                }
            } else {
                // Error: Unable to decode response JSON
                // This also happens if the password is wrong!
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name.loginsUpdated,
                        object: nil,
                        userInfo: ["loginError": "Incorrect Password"]
                    )
                }
            }
        }
    }
    task.resume()
}

func getFlux(password: String) async throws -> LoginResponse? {
    let scheme: String = "https"
    let host: String = "api.fluxhaus.io"
    let path = "/"

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path
    components.user = "admin"
    components.password = password

    let url = components.url

    let (data, _) = try await URLSession.shared.data(from: url!)
    let value = try JSONDecoder().decode(LoginResponse.self, from: data)
    return value
}

struct FluxData {
    var mopBot: Robot?
    var broomBot: Robot?
    var car: CarDetails?
    var dishwasher: DishWasher?
    var dryer: WasherDryer?
    let washer: WasherDryer?
}

// swiftlint:disable:next function_body_length
func convertLoginResponseToAppData(response: LoginResponse) -> FluxData {
    let mopBot = Robot(
        name: "MopBot",
        timestamp: response.mopbot.timestamp,
        batteryLevel: response.mopbot.batteryLevel,
        binFull: response.mopbot.binFull,
        running: response.mopbot.running,
        charging: response.mopbot.charging,
        docking: response.mopbot.docking,
        paused: response.mopbot.paused,
        timeStarted: response.mopbot.timeStarted
    )

    let broomBot = Robot(
        name: "BroomBot",
        timestamp: response.broombot.timestamp,
        batteryLevel: response.broombot.batteryLevel,
        binFull: response.broombot.binFull,
        running: response.broombot.running,
        charging: response.broombot.charging,
        docking: response.broombot.docking,
        paused: response.broombot.paused,
        timeStarted: response.broombot.timeStarted
    )

    let car = CarDetails(
        timestamp: response.car.timestamp,
        evStatusTimestamp: response.carEvStatus.timestamp,
        batteryLevel: response.carEvStatus.batteryStatus,
        distance: response.carEvStatus.drvDistance[0].rangeByFuel.evModeRange.value,
        hvac: response.car.airCtrlOn,
        pluggedIn: response.carEvStatus.batteryPlugin == 0 ? false : true,
        batteryCharge: response.carEvStatus.batteryCharge,
        locked: response.car.doorLock,
        doorsOpen: Doors(
            frontRight: response.car.doorOpen.frontRight,
            frontLeft: response.car.doorOpen.frontLeft,
            backRight: response.car.doorOpen.backRight,
            backLeft: response.car.doorOpen.backLeft
        ),
        trunkOpen: response.car.trunkOpen,
        defrost: response.car.defrost,
        hoodOpen: response.car.hoodOpen,
        odometer: response.carOdometer,
        engine: response.car.engine
    )

    let dishwasher = response.dishwasher

    let dryer = response.dryer

    let washer = response.washer

    return FluxData(
        mopBot: mopBot,
        broomBot: broomBot,
        car: car,
        dishwasher: dishwasher,
        dryer: dryer,
        washer: washer
    )
}

struct WidgetDevice: Codable, Equatable, Hashable {
    var name: String
    var progress: Int
    var icon: String
    var trailingText: String
    var shortText: String
    var running: Bool
}

// swiftlint:disable:next function_body_length
func convertDataToWidgetDevices(fluxData: FluxData) -> [WidgetDevice] {
    var returnValue =  [
        WidgetDevice(
            name: "Dishwasher",
            progress: Int(fluxData.dishwasher?.programProgress ?? 0 * 100),
            icon: "dishwasher",
            trailingText: "\(fluxData.dishwasher?.remainingTime ?? 0)",
            shortText: "\(fluxData.dishwasher?.remainingTime ?? 0)",
            running: fluxData.dishwasher?.programProgress ?? 0 > 0
        )
    ]

    let washerTimeRunning = fluxData.washer?.timeRunning ?? 0
    let washerTimeRemaining = fluxData.washer?.timeRemaining ?? 0
    var washerProrgress = 0
    if washerTimeRunning > 0 {
        washerProrgress = Int((washerTimeRunning / washerTimeRemaining) * 100)
    }

    returnValue.append(
        WidgetDevice(
            name: "Washer",
            progress: washerProrgress,
            icon: "washer",
            trailingText: "\(fluxData.washer?.timeRemaining ?? 0)",
            shortText: "\(fluxData.washer?.timeRemaining ?? 0)",
            running: fluxData.washer?.timeRemaining ?? 0 > 0
        )
    )

    let dryerTimeRunning = fluxData.dryer?.timeRunning ?? 0
    let dryerTimeRemaining = fluxData.dryer?.timeRemaining ?? 1
    var dryerProgress = 0
    if dryerTimeRunning  > 0 {
        dryerProgress = Int((dryerTimeRunning / dryerTimeRemaining) * 100)
    }

    returnValue.append(
        WidgetDevice(
            name: "Dryer",
            progress: dryerProgress,
            icon: "dryer",
            trailingText: "\(fluxData.dryer?.timeRemaining ?? 0)",
            shortText: "\(fluxData.dryer?.timeRemaining ?? 0)",
            running: fluxData.dryer?.timeRemaining ?? 0 > 0
        )
    )

    returnValue.append(
        WidgetDevice(
            name: "BroomBot",
            progress: fluxData.broomBot?.batteryLevel ?? 0,
            icon: "fan",
            trailingText: fluxData.broomBot?.running ?? false ? "On" : "Off",
            shortText: fluxData.broomBot?.running ?? false ? "On" : "Off",
            running: fluxData.broomBot?.running ?? false
        )
    )

    returnValue.append(
        WidgetDevice(
            name: "MopBot",
            progress: fluxData.mopBot?.batteryLevel ?? 0,
            icon: "humidifier.and.droplets",
            trailingText: fluxData.mopBot?.running ?? false ? "On" : "Off",
            shortText: fluxData.mopBot?.running ?? false ? "On" : "Off",
            running: fluxData.mopBot?.running ?? false
        )
    )

    returnValue.append(
        WidgetDevice(
            name: "Car",
            progress: fluxData.car?.batteryLevel ?? 0,
            icon: "car",
            trailingText: "Range \(fluxData.car!.distance) km",
            shortText: "\(fluxData.car!.distance) km",
            running: false
        )
    )

    return returnValue
}
