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

struct FluxWidgetMultiAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var devices: [WidgetDevice]
    }

    var name: String
}

@MainActor
class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// The single consolidated Live Activity
    private var consolidatedActivity: Activity<FluxWidgetMultiAttributes>?
    /// Task observing push token updates for the consolidated activity
    private var activityPushTokenTask: Task<Void, Never>?
    /// Cached channel IDs fetched from the server.
    private var channelIds: [String: String] = [:]
    private var pushToStartTask: Task<Void, Never>?

    /// User's subscription preferences (which device types to show)
    var subscribedDeviceTypes: Set<String> = Set(["Dishwasher", "Washer", "Dryer", "BroomBot", "MopBot"]) {
        didSet { saveSubscriptionPreferences() }
    }

    private init() {
        loadSubscriptionPreferences()
        observePushToStartToken()
        Task {
            await restoreExistingActivities()
            await fetchChannelIds()
        }
    }

    /// Re-adopt activities that iOS kept alive while the app was killed.
    private func restoreExistingActivities() async {
        // Restore consolidated activities
        for activity in Activity<FluxWidgetMultiAttributes>.activities {
            if activity.activityState == .active || activity.activityState == .stale {
                consolidatedActivity = activity
                observeActivityPushToken(activity: activity)
                logger.info("Restored consolidated Live Activity")
                break
            }
        }

        // End any legacy single-device activities
        for activity in Activity<FluxWidgetAttributes>.activities {
            if activity.activityState == .active || activity.activityState == .stale {
                await activity.end(nil, dismissalPolicy: .immediate)
                logger.info("Ended legacy single-device activity: \(activity.attributes.name)")
            }
        }
    }

    /// Observe and forward the per-activity push token so the server can send direct updates.
    private func observeActivityPushToken(activity: Activity<FluxWidgetMultiAttributes>) {
        activityPushTokenTask?.cancel()
        activityPushTokenTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                logger.info("Activity push token: \(token.prefix(8))...")
                await registerActivityToken(token: token)
            }
        }
    }

    private func registerActivityToken(token: String) async {
        await postToServer(
            path: "/push-tokens/activity",
            body: [
                "activityToken": token,
                "deviceName": UIDevice.current.name
            ]
        )
    }

    /// Observe the push-to-start token so the server can start activities remotely.
    private func observePushToStartToken() {
        if #available(iOS 17.2, *) {
            pushToStartTask = Task {
                for await tokenData in Activity<FluxWidgetMultiAttributes>.pushToStartTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    logger.info("Push-to-start token (multi): \(token.prefix(8))...")
                    pendingPushToStartToken = token
                    await registerPushToStartTokenWhenReady()
                }
            }
        }
    }

    /// Stored token waiting for auth to become available.
    private var pendingPushToStartToken: String?

    /// Register the push-to-start token, retrying until auth is available.
    private func registerPushToStartTokenWhenReady() async {
        guard let token = pendingPushToStartToken else { return }
        guard AuthManager.shared.authorizationHeader() != nil else {
            logger.info("Auth not ready — deferring push-to-start token registration")
            return
        }
        await registerDeviceToken(token: token)
        pendingPushToStartToken = nil
    }

    /// Called when auth becomes available to retry any pending registration.
    func retryPendingTokenRegistration() {
        Task { await registerPushToStartTokenWhenReady() }
    }

    /// Fetch broadcast channel IDs from the server for all device types.
    private func fetchChannelIds() async {
        let types = ["dishwasher", "washer", "dryer", "broombot", "mopbot", "consolidated"]
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

    /// Clean up ended/dismissed activities and adopt any push-to-started ones.
    private func cleanupAndAdoptActivities() async {
        // End any legacy single-device activities that might still be around
        for activity in Activity<FluxWidgetAttributes>.activities
        where activity.activityState == .active || activity.activityState == .stale {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        // Clean up stale/ended/dismissed consolidated activities to unblock push-to-start
        if let activity = consolidatedActivity {
            switch activity.activityState {
            case .ended, .dismissed:
                consolidatedActivity = nil
                activityPushTokenTask?.cancel()
                activityPushTokenTask = nil
                logger.info("Cleaned up ended/dismissed consolidated activity")
            default:
                break
            }
        }

        // Adopt consolidated activity from push-to-start if we don't track it
        if consolidatedActivity == nil {
            for activity in Activity<FluxWidgetMultiAttributes>.activities
            where activity.activityState == .active || activity.activityState == .stale {
                consolidatedActivity = activity
                observeActivityPushToken(activity: activity)
                logger.info("Adopted consolidated Live Activity")
                break
            }
        }

        // End any EXTRA consolidated activities (dedup — only keep the one we track)
        for activity in Activity<FluxWidgetMultiAttributes>.activities
        where activity.id != consolidatedActivity?.id
            && (activity.activityState == .active || activity.activityState == .stale) {
            await activity.end(nil, dismissalPolicy: .immediate)
            logger.info("Ended duplicate consolidated activity")
        }
    }

    func reconcile(devices: [WidgetDevice]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities are disabled — check Settings → FluxHaus → Live Activities")
            return
        }

        await cleanupAndAdoptActivities()

        // Filter by subscription preferences
        let runningDevices = devices.filter { $0.running && subscribedDeviceTypes.contains($0.name) }

        if runningDevices.isEmpty {
            // End the consolidated activity — immediate dismiss, no lingering
            if consolidatedActivity != nil {
                await endConsolidatedActivity()
            }
        } else if let activity = consolidatedActivity,
                  activity.activityState == .active || activity.activityState == .stale {
            // Update existing consolidated activity
            await updateConsolidatedActivity(devices: runningDevices)
        } else {
            // Start a new consolidated activity (only if none exists)
            consolidatedActivity = nil
            startConsolidatedActivity(devices: runningDevices)
        }
    }

    private func startConsolidatedActivity(devices: [WidgetDevice]) {
        let attributes = FluxWidgetMultiAttributes(name: "Appliances")
        let state = FluxWidgetMultiAttributes.ContentState(devices: devices)

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(900)
        )

        do {
            let activity: Activity<FluxWidgetMultiAttributes>
            if #available(iOS 18.0, *), let channelId = channelIds["consolidated"] {
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: .channel(channelId)
                )
                logger.info("Started consolidated Live Activity on channel (\(devices.count) devices)")
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: .token
                )
                logger.info("Started consolidated Live Activity with token (\(devices.count) devices)")
            }
            consolidatedActivity = activity
            observeActivityPushToken(activity: activity)
        } catch {
            logger.error("Failed to start consolidated Live Activity: \(error)")
        }
    }

    private func updateConsolidatedActivity(
        devices: [WidgetDevice]
    ) async {
        guard let activity = consolidatedActivity else { return }
        let state = FluxWidgetMultiAttributes.ContentState(devices: devices)
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(900)
        )

        await activity.update(content)
    }

    private func endConsolidatedActivity() async {
        guard let activity = consolidatedActivity else { return }
        activityPushTokenTask?.cancel()
        activityPushTokenTask = nil

        await activity.end(nil, dismissalPolicy: .immediate)

        consolidatedActivity = nil
        logger.info("Ended consolidated Live Activity (immediate dismiss)")
    }

    // MARK: - Subscription Preferences

    private func loadSubscriptionPreferences() {
        if let saved = UserDefaults.standard.stringArray(forKey: "liveActivitySubscriptions") {
            subscribedDeviceTypes = Set(saved)
        }
    }

    private func saveSubscriptionPreferences() {
        UserDefaults.standard.set(Array(subscribedDeviceTypes), forKey: "liveActivitySubscriptions")
        // Sync to server
        Task { await syncSubscriptionsToServer() }
    }

    private func syncSubscriptionsToServer() async {
        let deviceTypes = Array(subscribedDeviceTypes).map { $0.lowercased().replacingOccurrences(of: " ", with: "") }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.fluxhaus.io"
        components.path = "/push-tokens/subscriptions"

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
            let body = ["deviceTypes": deviceTypes]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let session = URLSession(configuration: .default)
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                logger.info("Synced subscriptions to server")
            }
        } catch {
            logger.error("Failed to sync subscriptions: \(error)")
        }
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

        guard let authHeader = AuthManager.shared.authorizationHeader() else {
            logger.warning("No auth header available — skipping POST to \(path)")
            return
        }

        let csrfToken = await fetchCsrfToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        if let csrfToken = csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let session = URLSession(configuration: .default)
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    logger.info("Registered token at \(path)")
                } else {
                    logger.error("Server returned \(httpResponse.statusCode) for \(path)")
                }
            }
        } catch {
            logger.error("Failed to register token at \(path): \(error)")
        }
    }
}
#endif
