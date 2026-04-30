//
//  NotificationNames.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Notification name extension
/// Provides type-safe notification name constants to avoid typos from hardcoded strings
/// All in-app notifications should use these constants instead of raw strings
extension Notification.Name {
    // MARK: - Settings Related

    /// Settings changed notification
    /// Sent when the user modifies any setting
    static let settingsChanged = Notification.Name("settingsChanged")

    /// Refresh interval changed notification
    /// Sent when the user modifies the refresh interval or refresh mode
    static let refreshIntervalChanged = Notification.Name("refreshIntervalChanged")

    /// Language changed notification
    /// Sent when the user switches the app language, triggering UI re-rendering
    static let languageChanged = Notification.Name("languageChanged")

    /// Account changed notification (v2.1.0)
    /// Sent when the user switches accounts, triggering data refresh
    static let accountChanged = Notification.Name("accountChanged")

    // MARK: - Window Related

    /// Open settings window notification
    /// Post this notification to open the settings window
    static let openSettings = Notification.Name("openSettings")

    /// Open settings window and navigate to a specific tab notification
    /// userInfo contains the "tab" key with a tab index value (Int)
    /// - Example: NotificationCenter.default.post(name: .openSettingsWithTab, object: nil, userInfo: ["tab": 1])
    static let openSettingsWithTab = Notification.Name("openSettingsWithTab")

    // MARK: - Error Related

    /// Launch at login error notification
    /// Sent when setting launch at login fails
    static let launchAtLoginError = Notification.Name("launchAtLoginError")

    /// Session-expired notification
    /// Posted by DataRefreshManager the first time a fetch fails with .sessionExpired
    /// after a previously valid session. Subscribers (MenuBarManager) react by
    /// presenting the WebLogin window so the user can re-authenticate.
    static let sessionExpired = Notification.Name("sessionExpired")
}

// MARK: - UserInfo Keys

/// Notification userInfo dictionary key constants
/// Provides type-safe userInfo key access
extension Notification {
    /// UserInfo key name enum
    enum UserInfoKey {
        /// Tab index key
        /// Used with the openSettingsWithTab notification, value type is Int
        static let tab = "tab"
    }
}
