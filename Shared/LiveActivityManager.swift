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
    /// Cached channel IDs fetched from the server.
    private var channelIds: [String: String] = [:]
    private var pushToStartTask: Task<Void, Never>?

    private init() {
        restoreExistingActivities()
        observePushToStartToken()
        Task { await fetchChannelIds() }
    }

    /// Re-adopt activities that iOS kept alive while the app was killed.
    private func restoreExistingActivities() {
        for activity in Activity<FluxWidgetAttributes>.activities {
            let name = activity.attributes.name
            if activity.activityState == .active || activity.activityState == .stale {
                activities[name] = activity
                logger.info("Restored Live Activity for \(name)")
            }
        }
    }

    /// Observe the push-to-start token so the server can start activities remotely.
    private func observePushToStartToken() {
        if #available(iOS 17.2, *) {
            pushToStartTask = Task {
                for await tokenData in Activity<FluxWidgetAttributes>.pushToStartTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    logger.info("Push-to-start token: \(token.prefix(8))...")
                    await registerDeviceToken(token: token)
                }
            }
        }
    }

    /// Fetch broadcast channel IDs from the server for all device types.
    private func fetchChannelIds() async {
        let types = ["dishwasher", "washer", "dryer", "broombot", "mopbot"]
        for type in types {
            if let channelId = await fetchChannelId(for: type) {
                channelIds[type] = channelId
                logger.info("Channel for \(type): \(channelId.prefix(16))...")
            }
        }
    }

    private func fetchChannelId(for activityType: String) async -> String? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/channels/\(activityType)"

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let authHeader = AuthManager.shared.authorizationHeader() {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        do {
            let session = URLSession(configuration: .default)
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let channelId = json["channelId"] as? String {
                return channelId
            }
        } catch {
            logger.error("Failed to fetch channel for \(activityType): \(error)")
        }
        return nil
    }

    func reconcile(devices: [WidgetDevice]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        // Adopt any activities we don't track yet (e.g. from push-to-start)
        for activity in Activity<FluxWidgetAttributes>.activities {
            let name = activity.attributes.name
            if activities[name] == nil
                && (activity.activityState == .active || activity.activityState == .stale) {
                activities[name] = activity
                logger.info("Adopted Live Activity for \(name)")
            }
        }

        // Clean up activities that iOS has ended
        let ended = activities.filter { $0.value.activityState == .ended }
        for (name, _) in ended {
            activities.removeValue(forKey: name)
            logger.info("Cleaned up ended activity: \(name)")
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

        let activityType = device.name.lowercased().replacingOccurrences(of: " ", with: "")

        do {
            let activity: Activity<FluxWidgetAttributes>
            if #available(iOS 18.0, *), let channelId = channelIds[activityType] {
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: .channel(channelId)
                )
                logger.info("Started Live Activity for \(device.name) on channel")
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: .token
                )
                logger.info("Started Live Activity for \(device.name) with token")
            }
            activities[device.name] = activity
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
        logger.info("Ended Live Activity for \(name)")
    }

    private func registerDeviceToken(token: String) async {
        await postToServer(
            path: "/push-tokens/device",
            body: [
                "pushToStartToken": token,
                "deviceName": UIDevice.current.name
            ]
        )
    }

    private func postToServer(path: String, body: [String: String]) async {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = path

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

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let session = URLSession(configuration: .default)
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                logger.info("Registered token at \(path)")
            }
        } catch {
            logger.error("Failed to register token at \(path): \(error)")
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
