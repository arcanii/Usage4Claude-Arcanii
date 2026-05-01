//
//  UsageData+Formatting.swift
//  Usage4Claude
//
//  Locale-aware display formatting for `UsageData` / `ExtraUsageData`. Lives
//  outside `ClaudeAPIResponseModels.swift` because it depends on `L.*` and
//  `UserSettings.shared` — both main-app-only — and the response-models file
//  is shared with the SwiftPM test target.
//

import Foundation

// MARK: - UsageData.LimitData formatting

extension UsageData.LimitData {
    /// Formatted remaining time string (for 5-hour limit, shows X hours Y minutes)
    /// - Returns: Localized remaining time description (e.g., "2h 30m")
    var formattedResetsInHours: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.notStartedReset
        }

        let resetsIn = resetsAt.timeIntervalSinceNow

        guard resetsIn > 0 else {
            return L.UsageData.resettingSoon
        }

        // Round up to minutes (using ceil function)
        let totalMinutes = Int(ceil(resetsIn / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return L.UsageData.resetsInHours(hours, minutes)
        } else {
            return L.UsageData.resetsInMinutes(minutes)
        }
    }

    /// Formatted remaining time string (for 7-day limit, shows X days Y hours)
    /// - Returns: Localized remaining time description (e.g., "about 3 days 12 hours remaining")
    var formattedResetsInDays: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.notStartedReset
        }

        let resetsIn = resetsAt.timeIntervalSinceNow

        guard resetsIn > 0 else {
            return L.UsageData.resettingSoon
        }

        // Round up to hours
        let totalHours = Int(ceil(resetsIn / 3600))
        let days = totalHours / 24
        let hours = totalHours % 24

        if days > 0 {
            return L.UsageData.resetsInDays(days, hours)
        } else {
            // When less than 1 day, show "about X hours"
            return L.UsageData.resetsInHours(hours, 0)
        }
    }

    /// Formatted reset time string (short format, for 5-hour limit)
    /// - Returns: Localized reset time description (e.g., "Today 14:30" or "Tomorrow 09:00")
    var formattedResetTimeShort: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.unknown
        }

        var calendar = Calendar.current
        calendar.locale = UserSettings.shared.appLocale
        let timeString = TimeFormatHelper.formatTimeOnly(resetsAt)

        if calendar.isDateInToday(resetsAt) {
            return "\(L.UsageData.today) \(timeString)"
        } else if calendar.isDateInTomorrow(resetsAt) {
            return "\(L.UsageData.tomorrow) \(timeString)"
        } else {
            return TimeFormatHelper.formatDateTime(resetsAt, dateTemplate: "Md")
        }
    }

    /// Formatted reset time string (long format, for 7-day limit)
    /// - Returns: Localized reset date description (e.g., "Nov 29 2 PM")
    var formattedResetDateLong: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.unknown
        }

        return TimeFormatHelper.formatDateHour(resetsAt, dateTemplate: "MMMd")
    }

    // MARK: - Compact Formatting Methods (for dual-mode two-line display)

    /// Compact formatted remaining time (omits zero-value units)
    /// - Example: "45m", "1h30m", "3d12h"
    var formattedCompactRemaining: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        let resetsIn = resetsAt.timeIntervalSinceNow
        guard resetsIn > 0 else {
            return L.UsageData.compactResettingSoon
        }

        let totalMinutes = Int(ceil(resetsIn / 60))

        // If less than 1 hour, show minutes only
        if totalMinutes < 60 {
            return L.UsageData.compactRemainingMinutes(totalMinutes)
        }

        let totalHours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60

        // If less than 1 day, show hours + minutes
        if totalHours < 24 {
            return L.UsageData.compactRemainingHours(totalHours, remainingMinutes)
        }

        // More than 1 day, show days + hours
        let days = totalHours / 24
        let hours = totalHours % 24

        return L.UsageData.compactRemainingDays(days, hours)
    }

    /// Formatted reset time (for 5-hour limit)
    /// - Example: "Today 15:07" / "Today 3:07 PM", "Tomorrow 09:30" / "Tomorrow 9:30 AM"
    var formattedCompactResetTime: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        let calendar = Calendar.current

        // Determine if today or tomorrow
        let prefix: String
        if calendar.isDateInToday(resetsAt) {
            prefix = L.UsageData.today
        } else if calendar.isDateInTomorrow(resetsAt) {
            prefix = L.UsageData.tomorrow
        } else {
            // Other dates show month and day
            let formatter = DateFormatter()
            formatter.locale = UserSettings.shared.appLocale
            formatter.timeZone = TimeZone.current
            // Use different date formats based on language
            let langCode = UserSettings.shared.appLocale.identifier
            if langCode.hasPrefix("zh") || langCode.hasPrefix("ja") {
                formatter.dateFormat = "M月d日"  // Chinese/Japanese: 12月25日
            } else if langCode.hasPrefix("ko") {
                formatter.dateFormat = "M월d일"  // Korean: 12월25일
            } else {
                formatter.dateFormat = "MMM d"   // English: Dec 25
            }
            prefix = formatter.string(from: resetsAt)
        }

        let timeString = TimeFormatHelper.formatTimeOnly(resetsAt)

        return "\(prefix) \(timeString)"
    }

    /// Formatted reset date (for 7-day limit, precise to hour)
    /// - Example: "Dec 16 15:00" / "Dec 16 3 PM" (English), "12月16日 15时" (Chinese)
    var formattedCompactResetDate: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        return TimeFormatHelper.formatDateHour(resetsAt, dateTemplate: "MMMd")
    }
}

// MARK: - UsageData formatting (backward-compat shims)

extension UsageData {
    /// Formatted remaining time string
    /// - Note: Backward compatible property
    var formattedResetsIn: String {
        return primaryLimit?.formattedResetsInHours ?? L.UsageData.notStartedReset
    }

    /// Formatted reset time string
    /// - Note: Backward compatible property
    var formattedResetTime: String {
        return primaryLimit?.formattedResetTimeShort ?? L.UsageData.unknown
    }

    /// Returns status color based on usage percentage
    /// - Note: Backward compatible property
    var statusColor: String {
        let percentage = self.percentage
        if percentage < 50 {
            return "green"
        } else if percentage < 70 {
            return "yellow"
        } else if percentage < 90 {
            return "orange"
        } else {
            return "red"
        }
    }
}

// MARK: - ExtraUsageData formatting

extension ExtraUsageData {
    /// Formatted used amount / total limit string (default mode)
    /// - Returns: e.g., "$12.50 / $50.00"
    var formattedUsageAmount: String {
        guard enabled, let used = used, let limit = limit else {
            return L.ExtraUsage.notEnabled
        }
        return L.ExtraUsage.usageAmount(used, limit)
    }

    /// Formatted remaining amount string (remaining mode)
    /// - Returns: e.g., "remaining $37"
    var formattedRemainingAmount: String {
        guard enabled, let used = used, let limit = limit else {
            return L.ExtraUsage.notEnabled
        }
        let remaining = max(0, limit - used)
        return L.ExtraUsage.remainingAmount(remaining)
    }

    /// Compact formatted usage amount (for list display)
    /// - Returns: e.g., "$10/$25"
    var formattedCompactAmount: String {
        guard enabled, let used = used, let limit = limit else {
            return "-"
        }
        return String(format: "$%.2f/$%.0f", used, limit)
    }
}
