//
//  NotificationManager.swift
//  Usage4Claude
//
//  Created by Claude Code on 2026-02-17.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import UserNotifications
import OSLog

/// Usage notification manager
/// Responsible for sending macOS system notifications when usage reaches thresholds or resets
class NotificationManager {
    // MARK: - Singleton

    static let shared = NotificationManager()

    // MARK: - Constants

    /// Usage warning threshold (90%)
    private let warningThreshold: Double = 90.0

    /// 7-day limit early warning threshold (75%)
    private let sevenDayEarlyWarningThreshold: Double = 75.0

    /// Reset detection threshold: a percentage drop exceeding this value is treated as a reset
    private let resetDropThreshold: Double = 30.0

    // MARK: - State

    /// Notification records (prevent duplicate notifications within the same cycle)
    /// key = LimitType.rawValue, value = true means a warning has been sent
    private var notifiedWarnings: [String: Bool] = [:]

    /// Whether UNUserNotificationCenter is usable (requires App Sandbox or proper signing)
    private lazy var notificationsAvailable: Bool = {
        // Check if the app is running in a sandbox — UNUserNotificationCenter traps without one
        let environment = ProcessInfo.processInfo.environment
        if environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            return true
        }
        // Also allow if the app has a proper code signature (not ad-hoc)
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if !bundleID.isEmpty, let teamID = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String, !teamID.isEmpty {
            // Try to access notification center — if properly signed, this won't trap
            // But since we can't catch EXC_BREAKPOINT, be conservative
        }
        Logger.menuBar.info("Notifications unavailable: app not running in sandbox")
        return false
    }()

    private init() {}

    // MARK: - Permission

    /// Request notification permission
    func requestPermission() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Logger.menuBar.error("Notification permission request failed: \(error.localizedDescription)")
            }
            Logger.menuBar.info("Notification permission: \(granted ? "granted" : "denied")")
        }
    }

    // MARK: - Check & Notify

    /// Check usage data and send notifications when needed
    /// - Parameters:
    ///   - usageData: Latest usage data
    ///   - previousData: Previous usage data (for comparing changes)
    func checkAndNotify(usageData: UsageData, previousData: UsageData?) {
        // Check each limit type
        checkLimit(
            type: .fiveHour,
            current: usageData.fiveHour?.percentage,
            previous: previousData?.fiveHour?.percentage,
            currentResetsAt: usageData.fiveHour?.resetsAt,
            previousResetsAt: previousData?.fiveHour?.resetsAt
        )
        checkLimit(
            type: .sevenDay,
            current: usageData.sevenDay?.percentage,
            previous: previousData?.sevenDay?.percentage,
            currentResetsAt: usageData.sevenDay?.resetsAt,
            previousResetsAt: previousData?.sevenDay?.resetsAt
        )
        checkLimit(
            type: .opusWeekly,
            current: usageData.opus?.percentage,
            previous: previousData?.opus?.percentage,
            currentResetsAt: usageData.opus?.resetsAt,
            previousResetsAt: previousData?.opus?.resetsAt
        )
        checkLimit(
            type: .sonnetWeekly,
            current: usageData.sonnet?.percentage,
            previous: previousData?.sonnet?.percentage,
            currentResetsAt: usageData.sonnet?.resetsAt,
            previousResetsAt: previousData?.sonnet?.resetsAt
        )

        // Handle Extra Usage separately
        checkLimit(
            type: .extraUsage,
            current: usageData.extraUsage?.percentage,
            previous: previousData?.extraUsage?.percentage,
            currentResetsAt: nil,
            previousResetsAt: nil
        )
    }

    // MARK: - Private Methods

    /// Check usage changes for a single limit type
    private func checkLimit(
        type: LimitType,
        current: Double?,
        previous: Double?,
        currentResetsAt: Date?,
        previousResetsAt: Date?
    ) {
        guard let currentPct = current else { return }

        // Detect reset: sharp percentage drop or resetsAt changed
        if let previousPct = previous, isReset(
            currentPct: currentPct,
            previousPct: previousPct,
            currentResetsAt: currentResetsAt,
            previousResetsAt: previousResetsAt
        ) {
            sendResetNotification(limitType: type)
            notifiedWarnings.removeValue(forKey: type.rawValue)
            notifiedWarnings.removeValue(forKey: "\(type.rawValue)_75")
            return
        }

        let previousPct = previous ?? 0

        // Additional 75% threshold check for 7-day limit
        if type == .sevenDay {
            let earlyKey = "\(type.rawValue)_75"
            let alreadyNotifiedEarly = notifiedWarnings[earlyKey] ?? false
            if !alreadyNotifiedEarly && previousPct < sevenDayEarlyWarningThreshold && currentPct >= sevenDayEarlyWarningThreshold {
                sendUsageWarning(limitType: type, percentage: currentPct)
                notifiedWarnings[earlyKey] = true
            }
        }

        // Detect if the 90% threshold was crossed
        let alreadyNotified = notifiedWarnings[type.rawValue] ?? false
        if !alreadyNotified && previousPct < warningThreshold && currentPct >= warningThreshold {
            sendUsageWarning(limitType: type, percentage: currentPct)
            notifiedWarnings[type.rawValue] = true
        }
    }

    /// Determine if a reset has occurred
    private func isReset(
        currentPct: Double,
        previousPct: Double,
        currentResetsAt: Date?,
        previousResetsAt: Date?
    ) -> Bool {
        // Sharp percentage drop (from higher value to lower value)
        if previousPct >= warningThreshold && (previousPct - currentPct) > resetDropThreshold {
            return true
        }

        // resetsAt changed (new reset cycle)
        if let current = currentResetsAt, let previous = previousResetsAt {
            if abs(current.timeIntervalSince(previous)) > 1.0 {
                // resetsAt changed and percentage also dropped, confirming a reset
                if currentPct < previousPct {
                    return true
                }
            }
        }

        return false
    }

    /// Send usage warning notification
    private func sendUsageWarning(limitType: LimitType, percentage: Double) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = L.UsageNotification.warningTitle
        content.body = L.UsageNotification.warningBody(limitType.displayName, Int(percentage))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage_warning_\(limitType.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.menuBar.error("Failed to deliver usage-warning notification: \(error.localizedDescription)")
            }
        }

        Logger.menuBar.info("Usage warning delivered: \(limitType.displayName) \(Int(percentage))%")
    }

    /// Send usage reset notification
    private func sendResetNotification(limitType: LimitType) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = L.UsageNotification.resetTitle
        content.body = L.UsageNotification.resetBody(limitType.displayName)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage_reset_\(limitType.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.menuBar.error("Failed to deliver reset notification: \(error.localizedDescription)")
            }
        }

        Logger.menuBar.info("Reset notification delivered: \(limitType.displayName)")
    }

    /// Reset all notification records
    func resetAllNotificationStates() {
        notifiedWarnings.removeAll()
    }
}
