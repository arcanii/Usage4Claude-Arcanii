//
//  ClaudeAPIResponseModels.swift
//  Usage4Claude
//
//  Pure-data types for the Claude.ai API: wire models (`UsageResponse`,
//  `ExtraUsageResponse`, `ErrorResponse`, `Organization`) and the in-memory
//  models they decode into (`UsageData`, `ExtraUsageData`). Lives in Helpers/
//  so it can be cherry-picked into the SwiftPM test target — every symbol here
//  must stay free of `L.*`, `Logger`, `UserSettings`, or any UI dependency.
//
//  The display-side formatting (locale-aware reset strings, status colors,
//  etc.) lives in `UsageData+Formatting.swift` as extensions and is main-app
//  only.
//

import Foundation

// MARK: - Organization

/// Organization information model
/// Corresponds to the organization info returned by Claude API /api/organizations
nonisolated struct Organization: Codable, Sendable, Identifiable, Equatable {
    /// Organization numeric ID
    let id: Int
    /// Organization UUID (used for API calls)
    let uuid: String
    /// Organization name
    let name: String
    /// Creation time
    let created_at: String?
    /// Update time
    let updated_at: String?
    /// Organization capabilities list
    let capabilities: [String]?

    static func == (lhs: Organization, rhs: Organization) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}

// MARK: - Usage Response (wire model)

/// API response data model
/// Corresponds to the JSON structure returned by Claude API
nonisolated struct UsageResponse: Codable, Sendable {
    /// 5-hour usage limit data
    let five_hour: LimitUsage
    /// 7-day usage limit data
    let seven_day: LimitUsage?
    /// 7-day OAuth apps usage (not yet used)
    let seven_day_oauth_apps: LimitUsage?
    /// 7-day Opus usage limit data
    let seven_day_opus: LimitUsage?
    /// 7-day Sonnet usage limit data (new field)
    let seven_day_sonnet: LimitUsage?

    /// Generic limit usage details (applicable to 5-hour, 7-day, and other limits)
    struct LimitUsage: Codable, Sendable {
        /// Current utilization rate (0-100, can be floating point)
        let utilization: Double
        /// Reset time (ISO 8601 format), nil means usage has not started yet
        let resets_at: String?
    }

    /// Convert API response to the internal UsageData model
    /// - Returns: Converted UsageData instance
    /// - Note: Automatically handles time rounding to ensure accurate display
    func toUsageData() -> UsageData {
        // Parse 5-hour limit data
        let fiveHourData = parseLimitData(five_hour)

        // Parse 7-day limit data (only when present and valid)
        let sevenDayData: UsageData.LimitData? = {
            guard let sevenDay = seven_day else {
                return nil
            }
            // If utilization is 0 and resets_at is nil, treat as no data
            if sevenDay.utilization == 0 && sevenDay.resets_at == nil {
                return nil
            }
            let parsed = parseLimitData(sevenDay)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Parse Opus limit data (only when present and valid)
        let opusData: UsageData.LimitData? = {
            guard let opus = seven_day_opus else {
                return nil
            }
            if opus.utilization == 0 && opus.resets_at == nil {
                return nil
            }
            let parsed = parseLimitData(opus)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Parse Sonnet limit data (only when present and valid)
        let sonnetData: UsageData.LimitData? = {
            guard let sonnet = seven_day_sonnet else {
                return nil
            }
            if sonnet.utilization == 0 && sonnet.resets_at == nil {
                return nil
            }
            let parsed = parseLimitData(sonnet)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        return UsageData(
            fiveHour: UsageData.LimitData(percentage: fiveHourData.percentage, resetsAt: fiveHourData.resetsAt),
            sevenDay: sevenDayData,
            opus: opusData,
            sonnet: sonnetData,
            extraUsage: nil  // Extra Usage will be fetched via a separate API
        )
    }

    /// Parse data for a single limit (5-hour or 7-day)
    /// - Parameter limit: LimitUsage structure
    /// - Returns: Tuple containing percentage and reset time
    /// - Note: Reset times are rounded to the nearest second to keep the UI
    ///   countdown stable across the .645 → 06:00:00 / 06:00:00.159 → 06:00:00
    ///   boundary the API returns inconsistently.
    private func parseLimitData(_ limit: LimitUsage) -> (percentage: Double, resetsAt: Date?) {
        let resetsAt: Date?
        if let resetString = limit.resets_at {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: resetString) {
                let interval = date.timeIntervalSinceReferenceDate
                let roundedInterval = round(interval)
                resetsAt = Date(timeIntervalSinceReferenceDate: roundedInterval)
            } else {
                resetsAt = nil
            }
        } else {
            resetsAt = nil
        }

        return (percentage: Double(limit.utilization), resetsAt: resetsAt)
    }
}

// MARK: - Extra Usage Response (wire model)

/// Extra Usage API response model
/// Used to parse data returned by the /api/organizations/{id}/overage_spend_limit endpoint
nonisolated struct ExtraUsageResponse: Codable, Sendable {
    /// Limit type (e.g., "organization")
    let limit_type: String?
    /// Whether enabled
    let is_enabled: Bool?
    /// Monthly credit limit (in cents)
    let monthly_credit_limit: Int?
    /// Currency unit (e.g., "EUR", "USD")
    let currency: String?
    /// Amount used (in cents)
    let used_credits: Int?
    /// Credits exhausted
    let out_of_credits: Bool?

    // MARK: - Legacy fields (backwards compatibility)
    let type: String?
    let spend_limit_currency: String?
    let spend_limit_amount_cents: Int?
    let balance_cents: Int?

    /// Convert to ExtraUsageData
    /// - Returns: Converted ExtraUsageData, returns nil if data is invalid
    func toExtraUsageData() -> ExtraUsageData? {
        // Prefer new API fields, fall back to legacy fields
        let resolvedCurrency = (currency ?? spend_limit_currency ?? "USD").uppercased()
        let limitCents = monthly_credit_limit ?? spend_limit_amount_cents
        let usedCents = used_credits ?? balance_cents

        // Use is_enabled field, fall back to limit check
        let enabled = is_enabled ?? (limitCents.map { $0 > 0 } ?? false)

        guard enabled, let limitCents = limitCents, limitCents > 0 else {
            return ExtraUsageData(
                enabled: false,
                used: nil,
                limit: nil,
                currency: resolvedCurrency
            )
        }

        let limit = Double(limitCents) / 100.0
        let used = usedCents.map { Double($0) / 100.0 } ?? 0.0

        return ExtraUsageData(
            enabled: true,
            used: used,
            limit: limit,
            currency: resolvedCurrency
        )
    }
}

// MARK: - Error Response (wire model)

/// API error response model
/// Corresponds to the error structure returned by Claude API
nonisolated struct ErrorResponse: Codable, Sendable {
    let type: String
    let error: ErrorDetail

    /// Error details
    struct ErrorDetail: Codable, Sendable {
        let type: String
        let message: String
    }
}

// MARK: - Usage Data (in-memory storage)

/// Usage data model
/// Standardized usage data structure for internal app use.
///
/// Storage-only here — all locale/UI formatting (resetsInHours, statusColor,
/// etc.) lives in `UsageData+Formatting.swift` as main-app extensions, so
/// this file can be compiled by the SwiftPM test target without dragging in
/// `LocalizationHelper` / `UserSettings`.
struct UsageData: Sendable {
    /// 5-hour limit data (optional)
    let fiveHour: LimitData?
    /// 7-day limit data (optional)
    let sevenDay: LimitData?
    /// Opus weekly limit data (optional)
    let opus: LimitData?
    /// Sonnet weekly limit data (optional)
    let sonnet: LimitData?
    /// Extra Usage allowance data (optional)
    let extraUsage: ExtraUsageData?

    /// Data for a single limit (5-hour, 7-day, Opus, Sonnet)
    struct LimitData: Sendable {
        /// Current usage percentage (0-100)
        let percentage: Double
        /// Usage reset time, nil means usage has not started yet
        let resetsAt: Date?

        /// Time remaining until reset (seconds)
        /// - Returns: Remaining seconds, returns nil if resetsAt is nil
        var resetsIn: TimeInterval? {
            guard let resetsAt = resetsAt else { return nil }
            return resetsAt.timeIntervalSinceNow
        }
    }

    /// Convenience accessor: Primary display data (prefers 5-hour, otherwise 7-day)
    var primaryLimit: LimitData? {
        return fiveHour ?? sevenDay
    }

    /// Whether both limit types have data
    var hasBothLimits: Bool {
        return fiveHour != nil && sevenDay != nil
    }

    /// Whether only 7-day limit data exists
    var hasOnlySevenDay: Bool {
        return fiveHour == nil && sevenDay != nil
    }

    // MARK: - Backward Compatible Properties (kept for legacy code)

    /// Current usage percentage (0-100)
    /// - Note: Backward compatible property, returns primary limit percentage
    var percentage: Double {
        return primaryLimit?.percentage ?? 0
    }

    /// Usage reset time, nil means usage has not started yet
    /// - Note: Backward compatible property, returns primary limit reset time
    var resetsAt: Date? {
        return primaryLimit?.resetsAt
    }

    /// Time remaining until reset (seconds)
    /// - Note: Backward compatible property
    var resetsIn: TimeInterval? {
        return primaryLimit?.resetsIn
    }
}

// MARK: - Extra Usage Data (in-memory storage)

/// Extra Usage data model
/// Extra paid usage data structure (amounts rather than percentages)
struct ExtraUsageData: Sendable {
    /// Whether Extra Usage is enabled
    let enabled: Bool
    /// Amount used (USD)
    let used: Double?
    /// Total limit (USD)
    let limit: Double?
    /// Currency unit
    let currency: String

    /// Usage percentage (for unified display)
    var percentage: Double? {
        guard let used = used, let limit = limit, limit > 0 else {
            return nil
        }
        return (used / limit) * 100.0
    }
}
