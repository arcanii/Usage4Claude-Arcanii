//
//  TimeFormatHelper.swift
//  Usage4Claude
//
//  Created by Claude Code on 2026-02-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Unified time formatting helper
/// Provides consistent time formatting methods based on the user's time format preference
enum TimeFormatHelper {

    // MARK: - Format Strings

    /// Get time format string (hours:minutes)
    /// - Returns: "HH:mm" or "h:mm a" format string
    static var timeOnlyFormat: String {
        return uses24HourFormat ? "HH:mm" : "h:mm a"
    }

    /// Get hour format string (hour only)
    /// - Returns: "HH" or "h a" format string
    static var hourOnlyFormat: String {
        return uses24HourFormat ? "HH" : "h a"
    }

    /// Get date+time template
    /// - Parameter dateTemplate: Date portion template (e.g., "MMMd")
    /// - Returns: Complete date-time template
    static func dateTimeTemplate(dateTemplate: String) -> String {
        if uses24HourFormat {
            return "\(dateTemplate) HH:mm"
        } else {
            return "\(dateTemplate) h:mm a"
        }
    }

    /// Get date+hour template
    /// - Parameter dateTemplate: Date portion template (e.g., "MMMd")
    /// - Returns: Complete date+hour template
    static func dateHourTemplate(dateTemplate: String) -> String {
        if uses24HourFormat {
            return "\(dateTemplate) HH"
        } else {
            return "\(dateTemplate) h a"
        }
    }

    // MARK: - Formatting Methods

    /// Format time (hours:minutes)
    /// - Parameter date: Date to format
    /// - Returns: Formatted time string
    static func formatTimeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = timeOnlyFormat
        return formatter.string(from: date)
    }

    /// Format hour
    /// - Parameter date: Date to format
    /// - Returns: Formatted hour string
    static func formatHourOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = hourOnlyFormat
        return formatter.string(from: date)
    }

    /// Format date and time
    /// - Parameters:
    ///   - date: Date to format
    ///   - dateTemplate: Date portion template
    /// - Returns: Formatted date-time string
    static func formatDateTime(_ date: Date, dateTemplate: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate(dateTimeTemplate(dateTemplate: dateTemplate))
        return formatter.string(from: date)
    }

    /// Format date and hour
    /// - Parameters:
    ///   - date: Date to format
    ///   - dateTemplate: Date portion template
    /// - Returns: Formatted date+hour string
    static func formatDateHour(_ date: Date, dateTemplate: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current

        // Build format string based on language and time format
        let langCode = UserSettings.shared.appLocale.identifier
        let dateString: String
        let timeString: String

        // Date format
        let dateFormatter = DateFormatter()
        dateFormatter.locale = UserSettings.shared.appLocale
        dateFormatter.timeZone = TimeZone.current
        if langCode.hasPrefix("zh") || langCode.hasPrefix("ja") {
            dateFormatter.dateFormat = "M月d日"
        } else if langCode.hasPrefix("ko") {
            dateFormatter.dateFormat = "M월d일"
        } else {
            dateFormatter.dateFormat = "MMM d"
        }
        dateString = dateFormatter.string(from: date)

        // Time format (hour only)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = UserSettings.shared.appLocale
        timeFormatter.timeZone = TimeZone.current
        if uses24HourFormat {
            // 24-hour format: display "15h" or "15"
            if langCode.hasPrefix("zh") || langCode.hasPrefix("ja") {
                timeFormatter.dateFormat = "H时"
            } else if langCode.hasPrefix("ko") {
                timeFormatter.dateFormat = "H시"
            } else {
                timeFormatter.dateFormat = "HH':00'"
            }
        } else {
            // 12-hour format: use localized template
            timeFormatter.setLocalizedDateFormatFromTemplate("j")
        }
        timeString = timeFormatter.string(from: date)

        return "\(dateString) \(timeString)"
    }

    // MARK: - Detection

    /// Detect whether 24-hour format should be used
    /// - Returns: true for 24-hour format, false for 12-hour format
    static var uses24HourFormat: Bool {
        let preference = UserSettings.shared.timeFormatPreference

        switch preference {
        case .system:
            return detectSystem24HourFormat()
        case .twelveHour:
            return false
        case .twentyFourHour:
            return true
        }
    }

    /// Detect whether the system uses 24-hour format
    /// - Returns: true if the system uses 24-hour format
    static func detectSystem24HourFormat() -> Bool {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let timeString = formatter.string(from: Date())

        // If it contains AM/PM markers, it's 12-hour format
        // Check common AM/PM variants
        let ampmIndicators = ["AM", "PM", "am", "pm", "上午", "下午", "午前", "午後", "오전", "오후"]
        for indicator in ampmIndicators {
            if timeString.contains(indicator) {
                return false
            }
        }

        return true
    }
}
