//
//  LiveActivityManager.swift
//  FluxHaus
//
//  Created by David Jensenius on 2025-03-09.
//

#if os(iOS)
import ActivityKit
import Foundation
import UIKit
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "LiveActivityManager")

struct FluxWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var device: WidgetDevice
    }

    var name: String
}

@MainActor
class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activities: [String: Activity<FluxWidgetAttributes>] = [:]
    private var pushTokenTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func reconcile(devices: [WidgetDevice]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let runningDevices = devices.filter { $0.running }
        let runningNames = Set(runningDevices.map { $0.name })

        // End activities for devices that are no longer running
        for (name, activity) in activities where !runningNames.contains(name) {
            let device = devices.first { $0.name == name }
            endActivity(name: name, activity: activity, finalDevice: device)
        }

        // Start or update activities for running devices
        for device in runningDevices {
            if let activity = activities[device.name] {
                updateActivity(activity: activity, device: device)
            } else {
                startActivity(device: device)
            }
        }
    }

    private func startActivity(device: WidgetDevice) {
        let attributes = FluxWidgetAttributes(name: device.name)
        let state = FluxWidgetAttributes.ContentState(device: device)

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(900)
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            activities[device.name] = activity
            logger.info("Started Live Activity for \(device.name)")
            observePushToken(for: device.name, activity: activity)
        } catch {
            logger.error("Failed to start Live Activity for \(device.name): \(error)")
        }
    }

    private func updateActivity(activity: Activity<FluxWidgetAttributes>, device: WidgetDevice) {
        let state = FluxWidgetAttributes.ContentState(device: device)
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(900)
        )

        Task {
            await activity.update(content)
        }
    }

    private func endActivity(
        name: String,
        activity: Activity<FluxWidgetAttributes>,
        finalDevice: WidgetDevice?
    ) {
        let device = finalDevice ?? WidgetDevice(
            name: name,
            progress: 0,
            icon: iconForDevice(name),
            trailingText: "Done",
            shortText: "Done",
            running: false
        )
        let state = FluxWidgetAttributes.ContentState(device: device)
        let content = ActivityContent(
            state: state,
            staleDate: Date()
        )

        Task {
            await activity.end(content, dismissalPolicy: .default)
        }

        activities.removeValue(forKey: name)
        pushTokenTasks[name]?.cancel()
        pushTokenTasks.removeValue(forKey: name)
        logger.info("Ended Live Activity for \(name)")
    }

    private func observePushToken(for deviceName: String, activity: Activity<FluxWidgetAttributes>) {
        pushTokenTasks[deviceName]?.cancel()
        pushTokenTasks[deviceName] = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                logger.info("Push token for \(deviceName): \(token.prefix(8))...")
                await registerPushToken(token: token, activityType: deviceName.lowercased())
            }
        }
    }

    private func registerPushToken(token: String, activityType: String) async {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/push-tokens"

        guard let url = components.url else { return }

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

        let body: [String: String] = [
            "pushToken": token,
            "activityType": activityType,
            "deviceName": UIDevice.current.name
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let session = URLSession(configuration: .default)
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                logger.info("Push token registered for \(activityType)")
            }
        } catch {
            logger.error("Failed to register push token: \(error)")
        }
    }

    private func iconForDevice(_ name: String) -> String {
        switch name {
        case "Dishwasher": return "dishwasher"
        case "Washer": return "washer"
        case "Dryer": return "dryer"
        case "BroomBot": return "fan"
        case "MopBot": return "humidifier.and.droplets"
        default: return "house"
        }
    }
}
#endif
