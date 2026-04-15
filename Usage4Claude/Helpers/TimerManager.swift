//
//  TimerManager.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Unified timer manager
/// Responsible for creating, scheduling, and cleaning up all timers in the app, preventing memory leaks
/// Provides type-safe timer identifier management
class TimerManager {
    // MARK: - Properties

    /// Timer storage dictionary, key is identifier, value is Timer instance
    private var timers: [String: Timer] = [:]

    /// Thread-safe queue
    private let queue = DispatchQueue(label: "com.usage4claude.timer", attributes: .concurrent)

    // MARK: - Public Methods

    /// Schedule a timer
    /// - Parameters:
    ///   - identifier: Unique timer identifier
    ///   - interval: Time interval (seconds)
    ///   - repeats: Whether to repeat execution
    ///   - block: Closure to execute when the timer fires
    /// - Note: If a timer with the same identifier already exists, the old timer will be cancelled first
    func schedule(
        _ identifier: String,
        interval: TimeInterval,
        repeats: Bool = true,
        block: @escaping () -> Void
    ) {
        // Synchronously cancel old timer and create new timer to avoid race conditions
        queue.sync(flags: .barrier) {
            // Cancel old timer with the same identifier
            if let oldTimer = self.timers[identifier] {
                oldTimer.invalidate()
                self.timers.removeValue(forKey: identifier)
            }
        }

        // Create timer on main thread (Timer.scheduledTimer requires RunLoop)
        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: repeats
        ) { _ in
            block()
        }

        // Save new timer
        queue.async(flags: .barrier) {
            self.timers[identifier] = timer
        }

        Logger.menuBar.info("⏰ Timer scheduled: \(identifier) (interval: \(interval)s, repeats: \(repeats))")
    }

    /// Cancel a specific timer
    /// - Parameter identifier: Timer identifier
    func invalidate(_ identifier: String) {
        queue.sync(flags: .barrier) {
            if let timer = self.timers[identifier] {
                timer.invalidate()
                self.timers.removeValue(forKey: identifier)
                Logger.menuBar.info("⏹️ Timer invalidated: \(identifier)")
            }
        }
    }

    /// Cancel all timers
    /// - Note: Typically called on app exit or major state changes
    func invalidateAll() {
        queue.sync(flags: .barrier) {
            let count = self.timers.count
            self.timers.values.forEach { $0.invalidate() }
            self.timers.removeAll()
            Logger.menuBar.info("🛑 All timers invalidated (count: \(count))")
        }
    }

    /// Check if a specific timer is active
    /// - Parameter identifier: Timer identifier
    /// - Returns: true if the timer exists and is valid
    func isActive(_ identifier: String) -> Bool {
        return queue.sync {
            return timers[identifier]?.isValid ?? false
        }
    }

    /// Get the list of currently active timers
    /// - Returns: Array of active timer identifiers
    /// - Note: Primarily used for debugging and diagnostics
    func activeTimers() -> [String] {
        return queue.sync {
            return timers.keys.filter { timers[$0]?.isValid == true }
        }
    }

    // MARK: - Deinit

    deinit {
        invalidateAll()
    }
}

// MARK: - Timer Identifiers

/// Timer identifier namespace
/// Provides type-safe timer identifier constants
extension TimerManager {
    /// Timer identifier enum
    enum Identifier {
        /// Main data refresh timer
        static let mainRefresh = "mainRefresh"
        /// Popover real-time refresh timer (1-second interval)
        static let popoverRefresh = "popoverRefresh"
        /// Reset verification timer - 1 second after reset
        static let resetVerify1 = "resetVerify1"
        /// Reset verification timer - 10 seconds after reset
        static let resetVerify2 = "resetVerify2"
        /// Reset verification timer - 30 seconds after reset
        static let resetVerify3 = "resetVerify3"
        /// Daily update check timer
        static let dailyUpdate = "dailyUpdate"
    }
}
