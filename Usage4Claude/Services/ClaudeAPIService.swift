//
//  ClaudeAPIService.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Claude API service class
/// Handles communication with the Claude.ai API to retrieve user usage data
/// Includes request building, authentication handling, Cloudflare bypass, and data parsing
class ClaudeAPIService {
    // MARK: - Properties
    
    /// API base URL
    private let baseURL = "https://claude.ai/api/organizations"
    
    /// User settings instance, used to retrieve authentication info
    private let settings = UserSettings.shared
    
    /// Shared URLSession instance
    private let session: URLSession

    /// Currently executing network request task
    private var currentTask: URLSessionDataTask?

    // MARK: - Initialization
    
    init() {
        // Configure URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30  // Request timeout: 30 seconds
        configuration.timeoutIntervalForResource = 60 // Resource timeout: 60 seconds
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData  // Do not use cache
        
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    /// Fetch user's Claude usage (fetches main usage and Extra Usage in parallel)
    /// - Parameter completion: Completion callback containing successful UsageData or Error on failure
    /// - Note: Requests automatically add necessary headers to bypass Cloudflare protection
    /// - Important: Ensure user has configured valid credentials before calling
    /// - Note: Main and Extra Usage are fetched in parallel via `async let`. Main failure
    ///   propagates as the overall failure; Extra Usage failure is logged and treated as nil.
    func fetchUsage(completion: @escaping (Result<UsageData, Error>) -> Void) {
        #if DEBUG
        // Debug mode: Return mock data (immediate return, no delay)
        if settings.debugModeEnabled {
            let mockData = createMockData()
            DispatchQueue.main.async {
                completion(.success(mockData))
            }
            return
        }
        #endif

        // Cancel any in-flight network task so a fast manual refresh doesn't double-fire.
        currentTask?.cancel()

        guard settings.hasValidCredentials else {
            completion(.failure(UsageError.noCredentials))
            return
        }

        Task { @MainActor in
            do {
                async let main = fetchMainUsageAsync()
                async let extra = fetchExtraUsageQuietlyAsync()

                let mainData = try await main
                let extraData = await extra
                let merged = UsageData(
                    fiveHour: mainData.fiveHour,
                    sevenDay: mainData.sevenDay,
                    opus: mainData.opus,
                    sonnet: mainData.sonnet,
                    extraUsage: extraData
                )
                completion(.success(merged))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Async wrapper around `fetchMainUsage` for parallel orchestration.
    private func fetchMainUsageAsync() async throws -> UsageData {
        try await withCheckedThrowingContinuation { continuation in
            fetchMainUsage { continuation.resume(with: $0) }
        }
    }

    /// Extra Usage failures are downgraded to nil so they never break the main fetch.
    /// Sites that need to surface Extra Usage errors can call `fetchExtraUsage` directly.
    private func fetchExtraUsageQuietlyAsync() async -> ExtraUsageData? {
        await withCheckedContinuation { continuation in
            fetchExtraUsage { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    Logger.api.info("Extra Usage failed, continuing with main usage only: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Fetch main Usage API data (internal method)
    /// - Parameter completion: Completion callback
    private func fetchMainUsage(completion: @escaping (Result<UsageData, Error>) -> Void) {
        let urlString = "\(baseURL)/\(settings.organizationId)/usage"

        guard let url = URL(string: urlString) else {
            completion(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use unified header builder to add complete browser headers for Cloudflare bypass
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: settings.organizationId,
            sessionKey: settings.sessionKey
        )

        // Create and save task reference
        currentTask = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.debug("Network error: \(error.localizedDescription)")
                completion(.failure(UsageError.networkError))
                return
            }

            guard let data = data else {
                completion(.failure(UsageError.noData))
                return
            }

            // Print raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Main Usage API Response: \(jsonString)")
            }

            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("Main Usage HTTP Status: \(httpResponse.statusCode)")

                // Cloudflare challenges return HTML with text/html Content-Type, regardless
                // of HTTP status. Treat any HTML response as a Cloudflare block — the JSON
                // error mappings below assume application/json bodies.
                let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                if contentType.contains("text/html") {
                    Logger.api.debug("⚠️ Received HTML response, possibly intercepted by Cloudflare.")
                    completion(.failure(UsageError.cloudflareBlocked))
                    return
                }

                // Handle various HTTP error status codes
                switch httpResponse.statusCode {
                case 200...299:
                    // Successful response, continue processing
                    break
                case 401:
                    // Unauthorized, typically invalid credentials
                    completion(.failure(UsageError.unauthorized))
                    return
                case 403:
                    // 403 covers two distinct cases:
                    // - Cloudflare/bot block (HTML body, handled above)
                    // - Expired/invalid session (JSON body with permission_error)
                    if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                       errorResponse.error.type == "permission_error" {
                        completion(.failure(UsageError.sessionExpired))
                    } else {
                        completion(.failure(UsageError.cloudflareBlocked))
                    }
                    return
                case 429:
                    // Request rate too high
                    completion(.failure(UsageError.rateLimited))
                    return
                default:
                    // Other HTTP error
                    Logger.api.error("HTTP error: \(httpResponse.statusCode)")
                    completion(.failure(UsageError.httpError(statusCode: httpResponse.statusCode)))
                    return
                }
            }

            // Decode JSON response
            let decoder = JSONDecoder()

            // Check if error response
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data),
               errorResponse.error.type == "permission_error" {
                completion(.failure(UsageError.sessionExpired))
                return
            }

            // Parse successful response
            do {
                let response = try decoder.decode(UsageResponse.self, from: data)
                let usageData = response.toUsageData()
                completion(.success(usageData))
            } catch {
                Logger.api.debug("Decoding error: \(error.localizedDescription)")
                completion(.failure(UsageError.decodingError))
            }
        }

        // Start task
        currentTask?.resume()
    }

    /// Fetch user's organization list
    /// - Parameters:
    ///   - sessionKey: Optional sessionKey; if not provided, uses settings.sessionKey
    ///   - completion: Completion callback containing successful organization array or Error on failure
    /// - Note: Used to automatically fetch Organization ID, simplifying user configuration
    func fetchOrganizations(sessionKey: String? = nil, completion: @escaping (Result<[Organization], Error>) -> Void) {
        let urlString = "\(baseURL.replacingOccurrences(of: "/organizations", with: ""))/organizations"

        guard let url = URL(string: urlString) else {
            completion(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use unified header builder, only sessionKey is needed
        // Use provided sessionKey parameter if available, otherwise use settings.sessionKey
        let actualSessionKey = sessionKey ?? settings.sessionKey
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: nil,  // organizationId not needed for fetching organization list
            sessionKey: actualSessionKey
        )

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.debug("Network error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(UsageError.networkError))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(UsageError.noData))
                }
                return
            }

            // Print raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Organizations API Response: \(jsonString)")
            }

            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("HTTP Status Code: \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200...299:
                    // Successful response, continue processing
                    break
                case 401:
                    DispatchQueue.main.async {
                        completion(.failure(UsageError.unauthorized))
                    }
                    return
                case 403:
                    DispatchQueue.main.async {
                        completion(.failure(UsageError.cloudflareBlocked))
                    }
                    return
                default:
                    Logger.api.error("HTTP error: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        completion(.failure(UsageError.httpError(statusCode: httpResponse.statusCode)))
                    }
                    return
                }
            }

            // Decode JSON response
            let decoder = JSONDecoder()
            do {
                let organizations = try decoder.decode([Organization].self, from: data)
                DispatchQueue.main.async {
                    completion(.success(organizations))
                }
            } catch {
                Logger.api.debug("Decoding error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(UsageError.decodingError))
                }
            }
        }

        task.resume()
    }

    /// Fetch Extra Usage overage data
    /// - Parameter completion: Completion callback containing successful ExtraUsageData or Error on failure
    /// - Note: This method is optional; failure should not affect main functionality
    func fetchExtraUsage(completion: @escaping (Result<ExtraUsageData?, Error>) -> Void) {
        // Check authentication credentials
        guard settings.hasValidCredentials else {
            completion(.failure(UsageError.noCredentials))
            return
        }

        let urlString = "\(baseURL)/\(settings.organizationId)/overage_spend_limit"

        guard let url = URL(string: urlString) else {
            completion(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use unified header builder to add complete browser headers
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: settings.organizationId,
            sessionKey: settings.sessionKey
        )

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.debug("Extra Usage API network error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(UsageError.networkError))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(UsageError.noData))
                }
                return
            }

            // Print raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Extra Usage API Response: \(jsonString)")
            }

            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("Extra Usage HTTP Status: \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200...299:
                    // Successful response, continue processing
                    break
                case 403:
                    // 403 covers two cases (same pattern as fetchMainUsage):
                    // - permission_error body → expired session (propagate as failure so the
                    //   caller can re-auth)
                    // - anything else → Extra Usage feature not enabled / no permission for
                    //   this org (graceful degradation, return nil)
                    if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                       errorResponse.error.type == "permission_error" {
                        DispatchQueue.main.async {
                            completion(.failure(UsageError.sessionExpired))
                        }
                    } else {
                        Logger.api.info("Extra Usage not available (HTTP 403)")
                        DispatchQueue.main.async {
                            completion(.success(nil))
                        }
                    }
                    return
                case 404:
                    // Extra Usage endpoint not present for this org — feature unavailable.
                    Logger.api.info("Extra Usage not available (HTTP 404)")
                    DispatchQueue.main.async {
                        completion(.success(nil))
                    }
                    return
                case 401:
                    DispatchQueue.main.async {
                        completion(.failure(UsageError.unauthorized))
                    }
                    return
                default:
                    Logger.api.warning("Extra Usage HTTP error: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        completion(.success(nil))  // Graceful degradation
                    }
                    return
                }
            }

            // Decode JSON response
            let decoder = JSONDecoder()
            do {
                let extraUsageResponse = try decoder.decode(ExtraUsageResponse.self, from: data)
                let extraUsageData = extraUsageResponse.toExtraUsageData()
                DispatchQueue.main.async {
                    completion(.success(extraUsageData))
                }
            } catch {
                Logger.api.debug("Extra Usage decoding error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.success(nil))  // Graceful degradation
                }
            }
        }

        task.resume()
    }

    /// Cancel all in-progress network requests
    /// Called when the app exits or requests need to be interrupted
    func cancelAllRequests() {
        currentTask?.cancel()
        currentTask = nil
        Logger.api.debug("Cancelled all network requests")
    }

    // MARK: - Debug Mock Data

    #if DEBUG
    /// Create a future time with minutes set to 00
    /// - Parameter hoursFromNow: Number of hours from now
    /// - Returns: Future date with minutes set to 00
    private func createResetTime(hoursFromNow: Double) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let targetDate = now.addingTimeInterval(3600 * hoursFromNow)
        
        // Get components of the target date
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: targetDate)
        components.minute = 0
        components.second = 0
        
        // Return time with minutes set to 00
        return calendar.date(from: components) ?? targetDate
    }
    
    /// Create mock data for debugging
    /// - Returns: Mock UsageData instance based on individual percentage slider values
    private func createMockData() -> UsageData {
        // Create corresponding limit data based on individual slider values
        let extraUsageData: ExtraUsageData? = {
            guard settings.debugExtraUsageEnabled else {
                return ExtraUsageData(enabled: false, used: nil, limit: nil, currency: "USD")
            }
            return ExtraUsageData(
                enabled: true,
                used: settings.debugExtraUsageUsed,
                limit: settings.debugExtraUsageLimit,
                currency: "USD"
            )
        }()

        return UsageData(
            fiveHour: UsageData.LimitData(
                percentage: settings.debugFiveHourPercentage,
                resetsAt: createResetTime(hoursFromNow: 1.8)  // Resets in 1.8 hours
            ),
            sevenDay: UsageData.LimitData(
                percentage: settings.debugSevenDayPercentage,
                resetsAt: createResetTime(hoursFromNow: 24 * 2.3)  // Resets in 2.3 days
            ),
            opus: UsageData.LimitData(
                percentage: settings.debugOpusPercentage,
                resetsAt: createResetTime(hoursFromNow: 24 * 4.5)  // Resets in 4.5 days
            ),
            sonnet: UsageData.LimitData(
                percentage: settings.debugSonnetPercentage,
                resetsAt: createResetTime(hoursFromNow: 24 * 5.2)  // Resets in 5.2 days
            ),
            extraUsage: extraUsageData
        )
    }
    #endif
}

// MARK: - Data Models

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

    // MARK: - Equatable

    static func == (lhs: Organization, rhs: Organization) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}

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
    private func parseLimitData(_ limit: LimitUsage) -> (percentage: Double, resetsAt: Date?) {
        let resetsAt: Date?
        if let resetString = limit.resets_at {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: resetString) {
                // Round the time to the nearest second
                // Example: 05:59:59.645 -> 06:00:00
                //       06:00:00.159 → 06:00:00
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

/// Usage data model
/// Standardized usage data structure for internal app use
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

    // MARK: - Formatting Methods

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
        return String(format: "$%.0f/$%.0f", used, limit)
    }
}

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

/// Usage query related errors
enum UsageError: LocalizedError {
    case invalidURL
    case noData
    case sessionExpired
    case cloudflareBlocked
    case noCredentials
    case networkError
    case decodingError
    case unauthorized              // 401 Unauthorized
    case rateLimited               // 429 Rate limited
    case httpError(statusCode: Int)  // Other HTTP error

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L.Error.invalidUrl
        case .noData:
            return L.Error.noData
        case .sessionExpired:
            return L.Error.sessionExpired
        case .cloudflareBlocked:
            return L.Error.cloudflareBlocked
        case .noCredentials:
            return L.Error.noCredentials
        case .networkError:
            return L.Error.networkFailed
        case .decodingError:
            return L.Error.decodingFailed
        case .unauthorized:
            return L.Error.unauthorized
        case .rateLimited:
            return L.Error.rateLimited
        case .httpError(let statusCode):
            return "HTTP 错误: \(statusCode)"
        }
    }
}
