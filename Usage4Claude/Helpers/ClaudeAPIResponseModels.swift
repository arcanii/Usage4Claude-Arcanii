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
    /// 5-hour usage limit data.
    /// Free Tier accounts, and Team/Enterprise organizations that have not enabled the
    /// member usage dashboard, return null here (upstream issues #83 / #74). This was
    /// the only non-optional window, so a single null threw `valueNotFound` and aborted
    /// the entire decode — which surfaced as "check if your credentials are correct"
    /// and sent people re-authenticating credentials that were never the problem.
    let five_hour: LimitUsage?
    /// 7-day usage limit data
    let seven_day: LimitUsage?
    /// 7-day OAuth apps usage (not yet used)
    let seven_day_oauth_apps: LimitUsage?
    /// 7-day Opus usage limit data
    let seven_day_opus: LimitUsage?
    /// 7-day Sonnet usage limit data (new field)
    let seven_day_sonnet: LimitUsage?

    /// New-API unified limits array (Claude 5 era). Per-model weekly limits (e.g.
    /// Fable) may stop arriving in the dedicated `seven_day_opus`/`seven_day_sonnet`
    /// fields and instead appear here as entries carrying `scope.model.display_name`.
    /// Decoded as a forward-compat safety net so the weekly rows don't silently vanish
    /// if the API moves; the legacy fields still take precedence (see `toUsageData`).
    let limits: [LimitEntry]?

    /// Whether the organization exposes the usage dashboard to its members.
    /// Free Tier, and Team/Enterprise organizations that haven't enabled it, return
    /// false — and in that case every limit window is null.
    let member_dashboard_available: Bool?

    /// Whether the response carries no limit data at all: every window field is null
    /// and the new-API `limits` array is empty or absent.
    var hasNoLimitData: Bool {
        five_hour == nil
            && seven_day == nil
            && seven_day_oauth_apps == nil
            && seven_day_opus == nil
            && seven_day_sonnet == nil
            && (limits?.isEmpty ?? true)
    }

    /// Whether this account can't get usage data at all. This is not a credentials
    /// problem — the request returned HTTP 200, and `extra_usage` often still carries
    /// real values — so callers should say "this plan doesn't provide usage data"
    /// rather than asking the user to sign in again.
    ///
    /// The verdict deliberately looks only at the actual data and does not trust
    /// `member_dashboard_available`: that field's exact semantics are unverified, and
    /// if personal Pro/Max accounts also report false (meaning "not part of an org
    /// dashboard" rather than "no usage data"), trusting it would misjudge every
    /// healthy account as unavailable. The field is kept for logging and diagnostics.
    ///
    /// Note this does not collide with the day-one 7-day placeholder below: a brand-new
    /// account still returns a real `five_hour` window, so `hasNoLimitData` stays false.
    var isUsageDashboardUnavailable: Bool {
        hasNoLimitData
    }

    /// Generic limit usage details (applicable to 5-hour, 7-day, and other limits)
    struct LimitUsage: Codable, Sendable {
        /// Current utilization rate (0-100, can be floating point)
        let utilization: Double
        /// Reset time (ISO 8601 format), nil means usage has not started yet
        let resets_at: String?
    }

    /// A single entry in the new-API `limits` array.
    /// - `percent`: usage percentage (0-100)
    /// - `scope.model.display_name`: the model name when the limit is model-scoped (e.g. "Fable")
    struct LimitEntry: Codable, Sendable {
        let kind: String?
        let group: String?
        let percent: Double?
        let severity: String?
        let resets_at: String?
        let is_active: Bool?
        let scope: Scope?

        struct Scope: Codable, Sendable {
            let model: Model?
            let surface: String?

            struct Model: Codable, Sendable {
                let id: String?
                let display_name: String?
            }
        }
    }

    /// Convert API response to the internal UsageData model
    /// - Returns: Converted UsageData instance
    /// - Note: Automatically handles time rounding to ensure accurate display
    func toUsageData() -> UsageData {
        // Parse 5-hour limit data. When the field is null (an account with no usage
        // dashboard) keep it nil and let the UI take its existing "no 5-hour data"
        // branch — deliberately unlike `seven_day` below, which fakes a 0% placeholder,
        // because we don't know whether the account really has this limit.
        let fiveHourData: UsageData.LimitData? = five_hour.map { limit in
            let parsed = parseLimitData(limit)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }

        // Parse 7-day limit data. Every Claude account has a 7-day limit;
        // for brand-new accounts the API may return a missing field or
        // (utilization=0, resets_at=null). Emit a 0% placeholder either way
        // so the UI can show the row from day one. Backported from upstream
        // commit `1192f35`.
        let sevenDayData: UsageData.LimitData = {
            guard let sevenDay = seven_day else {
                return UsageData.LimitData(percentage: 0, resetsAt: nil)
            }
            let parsed = parseLimitData(sevenDay)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Parse Opus limit data — legacy dedicated field (only when present and valid)
        let legacyOpus: UsageData.LimitData? = {
            guard let opus = seven_day_opus else {
                return nil
            }
            if opus.utilization == 0 && opus.resets_at == nil {
                return nil
            }
            let parsed = parseLimitData(opus)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Parse Sonnet limit data — legacy dedicated field (only when present and valid)
        let legacySonnet: UsageData.LimitData? = {
            guard let sonnet = seven_day_sonnet else {
                return nil
            }
            if sonnet.utilization == 0 && sonnet.resets_at == nil {
                return nil
            }
            let parsed = parseLimitData(sonnet)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Weekly per-model limits from the new `limits` array (Claude 5 era, e.g. Fable).
        // These no longer arrive in the dedicated seven_day_opus / seven_day_sonnet
        // fields. Preserve wire order and the real display_name; drop entries with no
        // model name (the session / weekly_all scopes, whose `scope` is null) or no
        // percent. Slot resolution and overflow live on UsageData itself.
        let scopedModels: [UsageData.WeeklyModelLimit] = (limits ?? []).compactMap { entry in
            guard let name = entry.scope?.model?.display_name, !name.isEmpty,
                  let percent = entry.percent else { return nil }
            return UsageData.WeeklyModelLimit(
                modelName: name,
                limit: UsageData.LimitData(percentage: percent, resetsAt: parseResetDate(entry.resets_at))
            )
        }

        return UsageData(
            fiveHour: fiveHourData,
            sevenDay: sevenDayData,
            legacyOpus: legacyOpus,
            legacySonnet: legacySonnet,
            scopedWeeklyModels: scopedModels,
            extraUsage: nil  // Extra Usage will be fetched via a separate API
        )
    }

    /// Parse an ISO 8601 reset-time string into a Date (rounded to the second),
    /// matching `parseLimitData`'s handling. Used for `limits` array entries.
    private func parseResetDate(_ resetString: String?) -> Date? {
        guard let resetString = resetString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: resetString) else { return nil }
        let rounded = round(date.timeIntervalSinceReferenceDate)
        return Date(timeIntervalSinceReferenceDate: rounded)
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
    /// Monthly credit limit (in cents) — new API field name
    let monthly_limit: Int?
    /// Monthly credit limit (in cents) — legacy API field name
    let monthly_credit_limit: Int?
    /// Currency unit (e.g., "EUR", "USD")
    let currency: String?
    /// Amount used (in cents). The API may return a float such as `21.0`, so this
    /// is decoded as `Double` — decoding it as `Int` throws `typeMismatch` and
    /// drops the entire Extra Usage response, silently hiding the feature.
    let used_credits: Double?
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
        // Prefer the new `monthly_limit` name, then the legacy names — all in cents.
        let limitCents = monthly_limit ?? monthly_credit_limit ?? spend_limit_amount_cents
        // `used_credits` is already cents (Double); legacy `balance_cents` is Int.
        let usedCents = used_credits ?? balance_cents.map { Double($0) }

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
        let used = (usedCents ?? 0.0) / 100.0

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
    /// Legacy weekly slot 0 — the API's dedicated `seven_day_opus` field (optional).
    let legacyOpus: LimitData?
    /// Legacy weekly slot 1 — the API's dedicated `seven_day_sonnet` field (optional).
    let legacySonnet: LimitData?
    /// Weekly per-model limits from the API's `limits[]`, in wire order and never
    /// truncated (Claude 5 era, e.g. "Fable").
    ///
    /// Kept SEPARATE from the two legacy slots on purpose. Upstream's equivalent
    /// refactor (f-is-h `59f4efd`) folds both into a single array via `append`, but an
    /// array cannot express "slot 0 empty, slot 1 filled": an account with
    /// `seven_day_opus: null` and a real `seven_day_sonnet` then collapses Sonnet into
    /// the Opus slot. That is silent data corruption here — `UsageHistorySampleBridge`
    /// writes `opusPct: data.opus?.percentage` into the append-only NDJSON history on
    /// every fetch, so Sonnet's series would be permanently recorded under Opus.
    let scopedWeeklyModels: [WeeklyModelLimit]
    /// Extra Usage allowance data (optional)
    let extraUsage: ExtraUsageData?

    /// One weekly per-model limit: the API's model display name plus its usage.
    /// `modelName` is nil for the legacy dedicated fields, which carry no name — the UI
    /// then falls back to the localized per-slot label.
    struct WeeklyModelLimit: Sendable {
        let modelName: String?
        let limit: LimitData
    }

    // MARK: - Weekly slot resolution
    //
    // The menu bar has exactly two weekly shapes, so slots 0/1 stay addressable as
    // `opus` / `sonnet`. Each resolves legacy-first, then falls through to the scoped
    // models in wire order — matching the behavior shipped in v1.8.1.

    /// Weekly slot 0: the legacy Opus field, else the first scoped model.
    var opus: LimitData? { legacyOpus ?? scopedWeeklyModels.first?.limit }

    /// Display name for slot 0, or nil to use the localized "Opus Weekly" label.
    var opusModelName: String? { legacyOpus != nil ? nil : scopedWeeklyModels.first?.modelName }

    /// Index into `scopedWeeklyModels` that slot 1 draws from — slot 0 only consumes a
    /// scoped entry when the legacy Opus field is absent.
    private var sonnetScopedIndex: Int { legacyOpus == nil ? 1 : 0 }

    /// Weekly slot 1: the legacy Sonnet field, else the next unconsumed scoped model.
    var sonnet: LimitData? {
        if let legacySonnet = legacySonnet { return legacySonnet }
        guard scopedWeeklyModels.indices.contains(sonnetScopedIndex) else { return nil }
        return scopedWeeklyModels[sonnetScopedIndex].limit
    }

    /// Display name for slot 1, or nil to use the localized "Sonnet Weekly" label.
    var sonnetModelName: String? {
        if legacySonnet != nil { return nil }
        guard scopedWeeklyModels.indices.contains(sonnetScopedIndex) else { return nil }
        return scopedWeeklyModels[sonnetScopedIndex].modelName
    }

    /// Scoped models beyond the two menu-bar slots (a 3rd+ model, e.g. Fable arriving
    /// alongside Opus and Sonnet). Rendered as extra popover rows.
    var overflowWeeklyModels: [WeeklyModelLimit] {
        let consumed = (legacyOpus == nil ? 1 : 0) + (legacySonnet == nil ? 1 : 0)
        return Array(scopedWeeklyModels.dropFirst(min(consumed, scopedWeeklyModels.count)))
    }

    // MARK: - Initializers

    /// Primary initializer — used by the real decode path.
    init(
        fiveHour: LimitData?,
        sevenDay: LimitData?,
        legacyOpus: LimitData?,
        legacySonnet: LimitData?,
        scopedWeeklyModels: [WeeklyModelLimit],
        extraUsage: ExtraUsageData?
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.legacyOpus = legacyOpus
        self.legacySonnet = legacySonnet
        self.scopedWeeklyModels = scopedWeeklyModels
        self.extraUsage = extraUsage
    }

    /// Compatibility initializer for fixtures, mocks and SwiftUI previews that pass the
    /// two weekly slots directly. Values map to the legacy slots verbatim, so slot
    /// semantics are preserved exactly (no compaction).
    init(
        fiveHour: LimitData?,
        sevenDay: LimitData?,
        opus: LimitData?,
        sonnet: LimitData?,
        extraUsage: ExtraUsageData?
    ) {
        self.init(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            legacyOpus: opus,
            legacySonnet: sonnet,
            scopedWeeklyModels: [],
            extraUsage: extraUsage
        )
    }

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

    /// Currency symbol for `currency` (ISO 4217 code → glyph), falling back to
    /// the raw code for anything unmapped. Lets the formatting helpers render
    /// the user's actual billing currency instead of a hardcoded "$".
    var currencySymbol: String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "KRW": return "₩"
        case "CAD": return "CA$"
        case "AUD": return "A$"
        case "BRL": return "R$"
        case "INR": return "₹"
        default: return currency
        }
    }

    /// Usage percentage (for unified display)
    var percentage: Double? {
        guard let used = used, let limit = limit, limit > 0 else {
            return nil
        }
        return (used / limit) * 100.0
    }
}
