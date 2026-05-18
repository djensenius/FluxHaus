//
//  Car.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "Car")

// Car-specific logic and classes
// Note: Shared types are now defined in LoginStucts.swift

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
        if let response = apiResponse?.response,
           let fluxCar = response.car,
           let evStatus = response.carEvStatus {
            vehicle = CarDetails(
                timestamp: fluxCar.timestamp,
                evStatusTimestamp: evStatus.timestamp,
                batteryLevel: evStatus.batteryStatus,
                distance: evStatus.drvDistance[0].rangeByFuel.evModeRange.value,
                hvac: fluxCar.airCtrlOn,
                pluggedIn: evStatus.batteryPlugin != 0,
                batteryCharge: evStatus.batteryCharge,
                locked: fluxCar.doorLock,
                doorsOpen: Doors(
                    frontRight: fluxCar.doorOpen.frontRight,
                    frontLeft: fluxCar.doorOpen.frontLeft,
                    backRight: fluxCar.doorOpen.backRight,
                    backLeft: fluxCar.doorOpen.backLeft
                ),
                trunkOpen: fluxCar.trunkOpen,
                defrost: fluxCar.defrost,
                hoodOpen: fluxCar.hoodOpen,
                odometer: response.carOdometer ?? 0,
                engine: fluxCar.engine
            )
        }
    }

    private static let actionPaths: [String: String] = [
        "unlock": "/unlockCar",
        "lock": "/lockCar",
        "start": "/startCar",
        "stop": "/stopCar",
        "resync": "/resyncCar"
    ]

    func performAction(
        action: String,
        steeringWheel: Bool = false,
        seatFL: Bool = false,
        seatFR: Bool = false,
        seatRL: Bool = false,
        seatRR: Bool = false,
        defrost: Bool = false,
        temperature: Int? = nil
    ) {
        let scheme: String = "https"
        let host: String = "api.fluxhaus.io"
        let path = Self.actionPaths[action] ?? "/resyncCar"

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path

        guard let url = components.url else {
            return
        }

        Task {
            let csrfToken = await fetchCsrfToken()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            if let authHeader = AuthManager.shared.authorizationHeader() {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            if let csrfToken = csrfToken {
                request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
            }

            if action == "start" {
                var body: [String: Any] = [
                    "heatedFeatures": steeringWheel,
                    "seatFL": seatFL ? 1 : 0,
                    "seatFR": seatFR ? 1 : 0,
                    "seatRL": seatRL ? 1 : 0,
                    "seatRR": seatRR ? 1 : 0,
                    "defrost": defrost
                ]
                if let temp = temperature {
                    body["temp"] = temp
                }
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }

            do {
                let session = URLSession(configuration: .default)
                let (_, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("Car action \(path) completed with HTTP \(statusCode)")
            } catch {
                logger.error("Car action \(path) failed: \(error.localizedDescription)")
            }
        }
    }
}
