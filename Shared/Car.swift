//
//  Car.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import Foundation

struct Doors: Decodable {
    let frontRight: Int
    let frontLeft: Int
    let backRight: Int
    let backLeft: Int
}

struct EvModeRange: Decodable {
    let value: Int
    let unit: Int
}

struct DriveDistance: Codable {
    let rangeByFuel: RangeByFuel
    let type: Int
}

struct RangeByFuel: Codable {
    let gasModeRange, evModeRange, totalAvailableRange: Atc
}

struct Atc: Codable {
    let value, unit: Int
}

struct EVStatus: Decodable {
    let timestamp: String
    let batteryCharge: Bool
    let batteryStatus: Int
    let batteryPlugin: Int
    let drvDistance: [DriveDistance]
}

struct FluxCar: Decodable {
    let timestamp: String
    let lastStatusDate: String
    let airCtrlOn: Bool
    let doorLock: Bool
    let doorOpen: Doors
    let trunkOpen: Bool
    let defrost: Bool
    let hoodOpen: Bool
    let engine: Bool
}

struct CarDetails: Decodable {
    let timestamp: String
    let evStatusTimestamp: String
    let batteryLevel: Int
    let distance: Int
    let hvac: Bool
    let pluggedIn: Bool
    let batteryCharge: Bool
    let locked: Bool
    let doorsOpen: Doors
    let trunkOpen: Bool
    let defrost: Bool
    let hoodOpen: Bool
    let odometer: Double
    let engine: Bool
}

@MainActor
@Observable class Car {
    var apiResponse: Api?
    var vehicle = CarDetails(
        timestamp: "",
        evStatusTimestamp: "",
        batteryLevel: 0,
        distance: 0,
        hvac: false,
        pluggedIn: false,
        batteryCharge: false,
        locked: false,
        doorsOpen: Doors(frontRight: 0, frontLeft: 0, backRight: 0, backLeft: 0),
        trunkOpen: false,
        defrost: false,
        hoodOpen: false,
        odometer: 0,
        engine: false
    )

    func setApiResponse(apiResponse: Api) {
        self.apiResponse = apiResponse
        fetchCarDetails()
    }

    func fetchCarDetails() {
        if let response = apiResponse?.response {
            DispatchQueue.main.async {
                self.vehicle = CarDetails(
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
            }
        }
    }

    func performAction(action: String) {
        let password = WhereWeAre.getPassword()
        let scheme: String = "https"
        let host: String = "api.fluxhaus.io"
        var path = "/"

        switch action {
        case "unlock":
            path = "/unlockCar"
        case "lock":
            path = "/lockCar"
        case "start":
            path = "/startCar"
        case "stop":
            path = "/stopCar"
        case "resync":
            path = "/resyncCar"
        default:
            print("Default \(action)")
            path = "/resyncCar"
        }

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
        let task = URLSession.shared.dataTask(with: request) { [path] data, _, _ in
            if data != nil {
                print("Got data \(path)")
            }
        }
        task.resume()
    }
}
