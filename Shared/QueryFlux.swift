//
//  QueryFlux.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "QueryFlux")

private struct CsrfResponse: Decodable {
    let csrfToken: String
}

func fetchCsrfToken() async -> String? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fluxhaus.io"
    components.path = "/auth/csrf-token"

    guard let url = components.url else { return nil }

    var request = URLRequest(url: url)
    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    do {
        let session = URLSession(configuration: .default)
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(CsrfResponse.self, from: data)
        return response.csrfToken
    } catch {
        logger.error("Failed to fetch CSRF token: \(error.localizedDescription)")
        return nil
    }
}

class BasicAuthDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let user: String
    let password: String

    init(user: String, password: String) {
        self.user = user
        self.password = password
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic {
            if challenge.previousFailureCount == 0 {
                let credential = URLCredential(user: user, password: password, persistence: .forSession)
                return (.useCredential, credential)
            }
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.performDefaultHandling, nil)
    }
}

func queryFlux(password: String) {
    let scheme: String = "https"
    let host: String = "api.fluxhaus.io"
    let path = "/"

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path

    guard let url = components.url else {
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "get"

    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")

    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        // Fallback for demo login
        let credentialData = Data("demo:\(password)".utf8)
        let base64Credential = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credential)", forHTTPHeaderField: "Authorization")
    }
    let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
    let task = session.dataTask(with: request) { data, response, error in
        let httpResponse = response as? HTTPURLResponse
        if httpResponse?.statusCode == 401 {
            handleUnauthorized(password: password)
            return
        }
        handleQueryFluxResponse(data: data, error: error, password: password)
    }
    task.resume()
}

private func handleUnauthorized(password: String) {
    if AuthManager.shared.getAccessToken() != nil {
        logger.info("handleUnauthorized: 401 with OIDC token, requesting refresh (thread=\(Thread.current))")
        Task { @MainActor in
            let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
            if refreshed {
                logger.info("handleUnauthorized: refresh succeeded, retrying queryFlux")
                queryFlux(password: password)
            } else {
                logger.error("handleUnauthorized: refresh FAILED — signing out")
                AuthManager.shared.signOut()
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["loginError": "Session expired. Please sign in again."]
                )
            }
        }
    } else {
        logger.error("handleUnauthorized: demo auth failed — signing out and posting loginError")
        DispatchQueue.main.async {
            AuthManager.shared.signOut()
            NotificationCenter.default.post(
                name: Notification.Name.loginsUpdated,
                object: nil,
                userInfo: ["loginError": "Incorrect Password"]
            )
        }
    }
}

private func handleQueryFluxResponse(data: Data?, error: Error?, password: String) {
    if let data = data {
        do {
            let response = try JSONDecoder().decode(LoginResponse.self, from: data)
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
        } catch {
            logger.error("JSON decode failed: \(error)")
            if let jsonStr = String(data: data, encoding: .utf8) {
                logger.error("Response body: \(jsonStr.prefix(500))")
            }
            DispatchQueue.main.async {
                AuthManager.shared.signOut()
                NotificationCenter.default.post(
                    name: Notification.Name.loginsUpdated,
                    object: nil,
                    userInfo: ["loginError": "Incorrect Password"]
                )
            }
        }
    } else {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name.loginsUpdated,
                object: nil,
                userInfo: ["loginError": error?.localizedDescription ?? "Network error"]
            )
        }
    }
}

func getFlux(password: String) async throws -> LoginResponse? {
    let scheme: String = "https"
    let host: String = "api.fluxhaus.io"
    let path = "/"

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path

    let url = components.url!

    var request = URLRequest(url: url)
    if let authHeader = AuthManager.shared.authorizationHeader() {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    } else {
        let credentialData = Data("demo:\(password)".utf8)
        let base64Credential = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credential)", forHTTPHeaderField: "Authorization")
    }

    let session = URLSession(configuration: .default)
    let (data, response) = try await session.data(for: request)

    // If 401 and we have an OIDC token, try refreshing and retry once
    if let httpResponse = response as? HTTPURLResponse,
       httpResponse.statusCode == 401,
       AuthManager.shared.getAccessToken() != nil {
        let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
        if refreshed {
            var retryRequest = URLRequest(url: url)
            if let newAuth = AuthManager.shared.authorizationHeader() {
                retryRequest.setValue(newAuth, forHTTPHeaderField: "Authorization")
            }
            let (retryData, _) = try await session.data(for: retryRequest)
            return try JSONDecoder().decode(LoginResponse.self, from: retryData)
        }
    }

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

    var car: CarDetails?
    if let fluxCar = response.car, let evStatus = response.carEvStatus {
        car = CarDetails(
            timestamp: fluxCar.timestamp,
            evStatusTimestamp: evStatus.timestamp,
            batteryLevel: evStatus.batteryStatus,
            distance: evStatus.drvDistance[0].rangeByFuel.evModeRange.value,
            hvac: fluxCar.airCtrlOn,
            pluggedIn: evStatus.batteryPlugin == 0 ? false : true,
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

    if let car = fluxData.car {
        returnValue.append(
            WidgetDevice(
                name: "Car",
                progress: car.batteryLevel,
                icon: "car",
                trailingText: "Range \(car.distance) km ⋅ \(car.batteryLevel)% ",
                shortText: "\(car.distance) km",
                running: false
            )
        )
    }

    return returnValue
}
