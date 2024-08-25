//
//  QueryFlux.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation

func queryFlux(password: String, user: String?) {
    let scheme: String = "https"
    let host: String = "api.fluxhaus.io"
    let path = "/"

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path
    components.user = user != nil ? user : "admin"
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
                    NotificationCenter.default.post(
                        name: Notification.Name.dataUpdated,
                        object: nil,
                        userInfo: ["data": response]
                    )
                }
            } else if user == nil {
                queryFlux(password: password, user: "demo")
            } else if user != nil {
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

func formatTimeRemaining(timeRemaining: Int) -> String {
    let minutesRemaining = Int(timeRemaining/60)
    if minutesRemaining < 60 {
        return "\(timeRemaining)m"
    }

    let currentDate = Date()
    let finishTime = Calendar.current.date(
        byAdding: .second,
        value: timeRemaining,
        to: currentDate
    ) ?? currentDate
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateFormat = .none
    let formatedTime = formatter.string(from: finishTime)
    return formatedTime
}

// swiftlint:disable:next function_body_length
func convertDataToWidgetDevices(fluxData: FluxData) -> [WidgetDevice] {
    var returnValue: [WidgetDevice] = []

    let dishWasherReminingTime = formatTimeRemaining(timeRemaining: fluxData.dishwasher?.remainingTime ?? 0 )
    var dishwasherTrailingText = dishWasherReminingTime
    if fluxData.dishwasher != nil && fluxData.dishwasher?.activeProgram != nil {
        dishwasherTrailingText = "\(fluxData.dishwasher?.activeProgram?.rawValue ?? "") ⋅ \(dishwasherTrailingText)"
    }
    if fluxData.dishwasher != nil && fluxData.dishwasher?.operationState.rawValue != "Run" {
        dishwasherTrailingText = fluxData.dishwasher!.operationState.rawValue + " ⋅ \(dishwasherTrailingText)"
    }

    if fluxData.dishwasher?.operationState.rawValue == "Finished" {
        returnValue.append(
            WidgetDevice(
                name: "Dishwasher",
                progress: 0,
                icon: "dishwasher",
                trailingText: "",
                shortText: "",
                running: false
            )
        )
    } else {
        returnValue.append(
            WidgetDevice(
                name: "Dishwasher",
                progress: Int(fluxData.dishwasher?.programProgress ?? 0),
                icon: "dishwasher",
                trailingText: dishwasherTrailingText,
                shortText: "\(fluxData.dishwasher?.remainingTime ?? 0)m",
                running: fluxData.dishwasher?.programProgress ?? 0 > 0
            )
        )
    }

    let washerTimeRunning = fluxData.washer?.timeRunning ?? 0
    let washerTimeRemaining = fluxData.washer?.timeRemaining ?? 0
    var washerProrgress = 0
    if washerTimeRunning > 0 {
        washerProrgress = Int(Double(washerTimeRunning) / Double(washerTimeRemaining + washerTimeRunning) * 100)
    }

    let washerReminingTime = formatTimeRemaining(timeRemaining: (fluxData.washer?.timeRemaining ?? 0 * 60))
    var washerTrailingText = "\(fluxData.washer?.programName ?? "") ⋅ \(washerReminingTime)"
    if fluxData.washer != nil && fluxData.washer?.status != "In use" {
        washerTrailingText = fluxData.washer!.status! + " ⋅ \(washerTrailingText)"
    }

    returnValue.append(
        WidgetDevice(
            name: "Washer",
            progress: washerProrgress,
            icon: "washer",
            trailingText: washerTrailingText,
            shortText: "\(fluxData.washer?.timeRemaining ?? 0)m",
            running: fluxData.washer?.timeRemaining ?? 0 > 0
        )
    )

    let dryerTimeRunning = fluxData.dryer?.timeRunning ?? 0
    let dryerTimeRemaining = fluxData.dryer?.timeRemaining ?? 1
    var dryerProgress = 0
    if dryerTimeRunning  > 0 {
        dryerProgress = Int(Double(dryerTimeRunning) / Double(dryerTimeRemaining + dryerTimeRunning) * 100)
    }
    let dryerReminingTime = formatTimeRemaining(timeRemaining: (fluxData.dryer?.timeRemaining ?? 0 * 60))
    var dryerTrailingText = "\(fluxData.dryer?.programName ?? "") ⋅ \(dryerReminingTime)"
    if fluxData.dryer != nil && fluxData.dryer?.status != "In use" {
        dryerTrailingText = fluxData.dryer!.status! + " ⋅ \(dryerTrailingText)"
    }

    returnValue.append(
        WidgetDevice(
            name: "Dryer",
            progress: dryerProgress,
            icon: "dryer",
            trailingText: dryerTrailingText,
            shortText: "\(fluxData.dryer?.timeRemaining ?? 0)m",
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
            trailingText: "Range \(fluxData.car!.distance) km ⋅ \(fluxData.car?.batteryLevel ?? 0)% ",
            shortText: "\(fluxData.car!.distance) km",
            running: false
        )
    )

    return returnValue
}
