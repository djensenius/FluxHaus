//
//  Api.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-08-07.
//

import Foundation

@MainActor
class Api: ObservableObject {
    @Published var response: LoginResponse?

    func setApiResponse(apiResponse: LoginResponse) {
        self.response = apiResponse
    }
}

#if DEBUG
@MainActor
struct MockData {
    static let loginResponse = LoginResponse(
        timestamp: "2024-12-13T12:00:00Z",
        favouriteHomeKit: ["Light 1", "Light 2"],
        broombot: Robot(
            name: "BroomBot",
            timestamp: "2024-12-13T11:00:00Z",
            batteryLevel: 85,
            binFull: false,
            running: false,
            charging: true,
            docking: false,
            paused: false,
            timeStarted: "2024-12-13T10:00:00Z"
        ),
        mopbot: Robot(
            name: "MopBot",
            timestamp: "2024-12-13T11:00:00Z",
            batteryLevel: 90,
            binFull: false,
            running: true,
            charging: false,
            docking: false,
            paused: false,
            timeStarted: "2024-12-13T11:30:00Z"
        ),
        car: FluxCar(
            timestamp: "2024-12-13T11:55:00Z",
            lastStatusDate: "2024-12-13T11:55:00Z",
            airCtrlOn: false,
            doorLock: true,
            doorOpen: Doors(frontRight: 0, frontLeft: 0, backRight: 0, backLeft: 0),
            trunkOpen: false,
            defrost: false,
            hoodOpen: false,
            engine: false
        ),
        carEvStatus: EVStatus(
            timestamp: "2024-12-13T11:55:00Z",
            batteryCharge: false,
            batteryStatus: 75,
            batteryPlugin: 0,
            drvDistance: [
                DriveDistance(
                    rangeByFuel: RangeByFuel(
                        gasModeRange: Atc(value: 0, unit: 1),
                        evModeRange: Atc(value: 350, unit: 1),
                        totalAvailableRange: Atc(value: 350, unit: 1)
                    ),
                    type: 2
                )
            ]
        ),
        carOdometer: 15000.0,
        dishwasher: DishWasher(
            status: "Ready",
            program: "Eco50",
            remainingTime: 0,
            remainingTimeUnit: "min",
            remainingTimeEstimate: true,
            programProgress: 0,
            operationState: .ready,
            doorState: "Closed",
            selectedProgram: "Eco50",
            activeProgram: nil,
            startInRelative: 0,
            startInRelativeUnit: "min"
        ),
        dryer: WasherDryer(
            name: "Dryer",
            timeRunning: 0,
            timeRemaining: 0,
            step: "Finished",
            programName: "Cotton",
            status: "Finished",
            inUse: false
        ),
        washer: WasherDryer(
            name: "Washer",
            timeRunning: 45,
            timeRemaining: 15,
            step: "Rinse",
            programName: "Cotton 60",
            status: "Running",
            inUse: true
        )
    )

    static func createApi() -> Api {
        let api = Api()
        api.setApiResponse(apiResponse: loginResponse)
        return api
    }

    static func createCar() -> Car {
        let car = Car()
        let api = createApi()
        car.setApiResponse(apiResponse: api)
        return car
    }

    static func createHomeConnect() -> HomeConnect {
        let api = createApi()
        return HomeConnect(apiResponse: api)
    }

    static func createMiele() -> Miele {
        let api = createApi()
        return Miele(apiResponse: api)
    }

    static func createRobots() -> Robots {
        let robots = Robots()
        let api = createApi()
        robots.setApiResponse(apiResponse: api)
        return robots
    }

    static func createBattery() -> Battery {
        return Battery()
    }
}
#endif
