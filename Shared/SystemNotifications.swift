//
//  SystemNotifications.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-09.
//

import Foundation

extension Notification.Name {
    // Send this notification when the LanguageCoordinator content is ready or updates language.
    static let loginsUpdated: Notification.Name = Notification.Name("LoginsUpdated")
    static let logout: Notification.Name = Notification.Name("logout")
    static let dataUpdated: Notification.Name = Notification.Name("DataUpdated")
    static let quickChatRequested: Notification.Name = Notification.Name("quickChatRequested")
    static let quickChatShortcutChanged: Notification.Name = Notification.Name("quickChatShortcutChanged")
    static let fullQuitRequested: Notification.Name = Notification.Name("fullQuitRequested")
    static let openMainAppRequested: Notification.Name = Notification.Name("openMainAppRequested")
    static let menuBarPreferenceChanged: Notification.Name = Notification.Name("menuBarPreferenceChanged")
}
