//
//  DataRefreshManager.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import OSLog

/// Data refresh manager
/// Responsible for managing all data refreshing, timers, update checks, and reset verification logic
class DataRefreshManager: ObservableObject {

    // MARK: - Dependencies

    /// Claude API service instance
    private let apiService = ClaudeAPIService()
    /// Timer manager
    private let timerManager = TimerManager()
    /// User settings instance
    private let settings = UserSettings.shared

    // MARK: - Published State

    /// Current usage data
    @Published var usageData: UsageData?
    /// Loading state
    @Published var isLoading = false
    /// Error message
    @Published var errorMessage: String?
    /// Refresh state manager
    let refreshState = RefreshState()

    // MARK: - Private State

    /// Last reset time (used to detect whether a reset has completed)
    private var lastResetsAt: Date?
    /// Last manual refresh time
    private var lastManualRefreshTime: Date?
    /// Last API request time
    private var lastAPIFetchTime: Date?
    /// Refresh animation start time (used to ensure minimum animation display duration)
    private var refreshAnimationStartTime: Date?
    /// Minimum animation display duration (seconds)
    private let minimumAnimationDuration: TimeInterval = 1.0
    /// Whether the most recent fetch failed with .sessionExpired. Used to prompt the user
    /// to re-login exactly once per expiry, instead of every 60-second refresh tick.
    private var sessionExpiredPrompted = false
    /// App Nap prevention activity token
    private var refreshActivity: NSObjectProtocol?

    // MARK: - Timer Identifiers

    /// Timer identifiers
    private enum TimerID {
        static let mainRefresh = "mainRefresh"
        static let popoverRefresh = "popoverRefresh"
        static let resetVerify1 = "resetVerify1"
        static let resetVerify2 = "resetVerify2"
        static let resetVerify3 = "resetVerify3"
    }

    // MARK: - Initialization

    init() {
        // App-update polling is owned by Sparkle (SPUStandardUpdaterController in
        // AppDelegate). This manager is now strictly about Claude usage data refresh.
    }

    // MARK: - Data Fetching

    /// Fetch usage data
    /// Calls the API service to get the latest usage information
    func fetchUsage() {
        isLoading = true
        errorMessage = nil

        // Record this API request time
        lastAPIFetchTime = Date()

        apiService.fetchUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                // Ensure animation displays for at least the minimum duration
                self.endRefreshAnimationWithMinimumDuration {
                }

                switch result {
                case .success(let data):
                    let previousData = self.usageData
                    self.usageData = data
                    self.errorMessage = nil
                    self.sessionExpiredPrompted = false
                    UsageHistoryStore.shared.append(data)

                    // Check if usage notifications need to be sent
                    if self.settings.notificationsEnabled {
                        NotificationManager.shared.checkAndNotify(usageData: data, previousData: previousData)
                    }

                    // Smart mode: adjust refresh frequency based on percentage changes
                    self.settings.updateSmartMonitoringMode(currentUtilization: data.percentage)

                    // Detect whether the reset time has changed
                    let newResetsAt = data.resetsAt
                    let hasResetChanged = self.hasResetTimeChanged(from: self.lastResetsAt, to: newResetsAt)

                    if hasResetChanged {
                        // Reset time changed, cancel all pending verifications
                        self.cancelResetVerification()
                    } else {
                        // Reset time unchanged, schedule verification
                        if let resetsAt = newResetsAt {
                            self.scheduleResetVerification(resetsAt: resetsAt)
                        }
                    }

                    // Update the last reset time
                    self.lastResetsAt = newResetsAt

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    Logger.menuBar.error("API request failed: \(error.localizedDescription)")

                    // First sessionExpired hit → prompt user to re-login. Skip on subsequent
                    // ticks until a successful fetch resets the flag, so we don't re-pop
                    // the login window every 60 seconds.
                    if case UsageError.sessionExpired = error, !self.sessionExpiredPrompted {
                        self.sessionExpiredPrompted = true
                        NotificationCenter.default.post(name: .sessionExpired, object: nil)
                    }
                }
            }
        }
    }

    /// Start data refreshing
    /// Immediately fetches data once and starts the timer
    func startRefreshing() {
        beginRefreshActivity()
        fetchUsage()
        restartTimer()

        #if DEBUG
        // Test: ensure icon displays badge
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.objectWillChange.send()
        }
        #endif
    }

    /// Stop data refreshing
    func stopRefreshing() {
        timerManager.invalidate(TimerID.mainRefresh)
        endRefreshActivity()
    }

    /// Start the Popover refresh timer
    /// Used to trigger UI updates at 1-second intervals while the popover is open
    /// - Parameter updateHandler: Update closure called every second
    func startPopoverRefreshTimer(updateHandler: @escaping () -> Void) {
        timerManager.schedule(TimerID.popoverRefresh, interval: 1.0, repeats: true) {
            updateHandler()
        }
    }

    /// Stop the Popover refresh timer
    func stopPopoverRefreshTimer() {
        timerManager.invalidate(TimerID.popoverRefresh)
    }

    /// Restart the refresh timer
    /// Recreates the timer based on the user's configured refresh frequency
    private func restartTimer() {
        timerManager.invalidate(TimerID.mainRefresh)
        let interval = TimeInterval(settings.effectiveRefreshInterval)
        timerManager.schedule(TimerID.mainRefresh, interval: interval, repeats: true) { [weak self] in
            self?.fetchUsage()
        }
    }

    // MARK: - App Nap Prevention

    /// Begin background activity assertion to prevent macOS App Nap from freezing timers
    private func beginRefreshActivity() {
        guard refreshActivity == nil else { return }
        refreshActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Periodic usage data refresh"
        )
    }

    /// End background activity assertion
    private func endRefreshActivity() {
        if let activity = refreshActivity {
            ProcessInfo.processInfo.endActivity(activity)
            refreshActivity = nil
        }
    }

    // MARK: - Smart Refresh

    /// Smart refresh when opening the Popover
    /// Immediately refreshes data if more than 30 seconds since last refresh
    func refreshOnPopoverOpen() {
        let now = Date()

        // User opened the detail view, force switch to active mode (1-minute refresh)
        if settings.refreshMode == .smart {
            settings.currentMonitoringMode = .active
            settings.unchangedCount = 0
            Logger.menuBar.debug("Popover opened by user; switching to active mode")
        }

        // If less than 30 seconds since last refresh, skip
        if let lastFetch = lastAPIFetchTime,
           now.timeIntervalSince(lastFetch) < 30 {
            return
        }

        fetchUsage()
    }

    /// Handle manual refresh
    /// Debounce mechanism: only allows one refresh per 10 seconds (disabled in debug mode)
    func handleManualRefresh() {
        let now = Date()

        #if !DEBUG
        // Debounce check: only allow one refresh per 10 seconds (Release mode only)
        if let lastManual = lastManualRefreshTime,
           now.timeIntervalSince(lastManual) < 10 {
            return
        }
        #endif

        // User manually refreshed, force switch to active mode (1-minute refresh)
        if settings.refreshMode == .smart {
            settings.currentMonitoringMode = .active
            settings.unchangedCount = 0
            Logger.menuBar.debug("Manual refresh; switching to active mode")
        }

        // Update state
        lastManualRefreshTime = now
        refreshAnimationStartTime = now  // Record animation start time
        refreshState.isRefreshing = true

        #if DEBUG
        // Debug mode: immediately allow next refresh
        refreshState.canRefresh = true
        #else
        // Release mode: set debounce
        refreshState.canRefresh = false
        // Release debounce after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.refreshState.canRefresh = true
        }
        #endif

        // Trigger refresh
        fetchUsage()
    }

    /// End the refresh animation, ensuring it displays for at least the minimum duration
    /// - Parameter completion: Callback after the animation ends
    private func endRefreshAnimationWithMinimumDuration(completion: @escaping () -> Void) {
        guard let startTime = refreshAnimationStartTime else {
            // No start time recorded, end immediately
            refreshState.isRefreshing = false
            completion()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = minimumAnimationDuration - elapsed

        if remaining > 0 {
            // Animation duration insufficient, delay for remaining time before ending
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.refreshState.isRefreshing = false
                completion()
            }
        } else {
            // Animation duration sufficient, end immediately
            refreshState.isRefreshing = false
            completion()
        }

        // Clear start time record
        refreshAnimationStartTime = nil
    }

    // MARK: - Reset Verification

    /// Detect whether the reset time has changed
    /// - Parameters:
    ///   - oldTime: Previous reset time
    ///   - newTime: New reset time
    /// - Returns: true if the reset time has changed
    private func hasResetTimeChanged(from oldTime: Date?, to newTime: Date?) -> Bool {
        // If both are nil, no change
        if oldTime == nil && newTime == nil {
            return false
        }

        // If one is nil and the other is not, there is a change
        if (oldTime == nil) != (newTime == nil) {
            return true
        }

        // If both are non-nil, compare time values (allowing 1-second tolerance)
        if let old = oldTime, let new = newTime {
            return abs(old.timeIntervalSince(new)) > 1.0
        }

        return false
    }

    /// Cancel all reset verification timers
    private func cancelResetVerification() {
        timerManager.invalidate(TimerID.resetVerify1)
        timerManager.invalidate(TimerID.resetVerify2)
        timerManager.invalidate(TimerID.resetVerify3)
    }

    /// Schedule reset time verification
    /// Triggers a refresh at 1 second, 10 seconds, and 30 seconds after the reset time
    /// - Parameter resetsAt: Usage reset time
    private func scheduleResetVerification(resetsAt: Date) {
        // Clear old verification timers
        cancelResetVerification()

        // Calculate the interval until reset time
        let timeUntilReset = resetsAt.timeIntervalSinceNow

        // Only schedule verification if the reset time is in the future
        guard timeUntilReset > 0 else {
            Logger.menuBar.debug("Reset time already past; skipping verification scheduling")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone.current
        Logger.menuBar.debug("Scheduling reset verification — reset time: \(formatter.string(from: resetsAt))")

        // Verify 1 second after reset
        timerManager.schedule(TimerID.resetVerify1, interval: timeUntilReset + 1, repeats: false) { [weak self] in
            Logger.menuBar.debug("Reset verification +1s — refreshing")
            self?.fetchUsage()
        }

        // Verify 10 seconds after reset
        timerManager.schedule(TimerID.resetVerify2, interval: timeUntilReset + 10, repeats: false) { [weak self] in
            Logger.menuBar.debug("Reset verification +10s — refreshing")
            self?.fetchUsage()
        }

        // Verify 30 seconds after reset
        timerManager.schedule(TimerID.resetVerify3, interval: timeUntilReset + 30, repeats: false) { [weak self] in
            Logger.menuBar.debug("Reset verification +30s — refreshing")
            self?.fetchUsage()
        }
    }

    // MARK: - Cleanup

    /// Clean up all resources
    func cleanup() {
        timerManager.invalidateAll()
        endRefreshActivity()
    }

    deinit {
        cleanup()
    }
}
