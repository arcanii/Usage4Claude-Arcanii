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

    // MARK: - Claude OAuth single-flight & cache
    //
    // A Claude OAuth refresh_token rotates on every renewal (the old value is
    // immediately invalidated). Concurrent refresh calls could reuse the same
    // refresh_token, making later callers hit 401. Single-flight coalescing
    // ensures one refresh_token triggers only one network request; the rest wait
    // and reuse the result.

    private let oauthLock = NSLock()
    private var oauthRefreshInFlight = false
    private var oauthRefreshInFlightToken: String?
    private var oauthRefreshWaiters: [(Result<String, Error>) -> Void] = []

    /// Cached access_token and its expiry (avoids refreshing on every fetch).
    private var cachedOAuthAccessToken: String?
    private var cachedOAuthTokenExpiry: Date?
    private var cachedOAuthForRefreshToken: String?

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

    // MARK: - Claude OAuth Support

    /// Whether a credential is a Claude OAuth refresh_token (starts with "sk-ant-ort01-").
    static func isOAuthRefreshToken(_ credential: String) -> Bool {
        credential.hasPrefix("sk-ant-ort01-")
    }

    /// Clear the cached OAuth access_token (call on account switch or on 401).
    func clearOAuthTokenCache() {
        oauthLock.lock()
        cachedOAuthAccessToken = nil
        cachedOAuthTokenExpiry = nil
        cachedOAuthForRefreshToken = nil
        oauthLock.unlock()
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

        // OAuth accounts: the credential is a refresh_token, so use the
        // /api/oauth/usage path and skip the Cloudflare cookie flow entirely.
        if Self.isOAuthRefreshToken(settings.sessionKey) {
            fetchOAuthUsage(completion: completion)
            return
        }

        Task { @MainActor in
            do {
                async let main = fetchMainUsageAsync()
                async let extra = fetchExtraUsageQuietlyAsync()

                let mainData = try await main
                let extraData = await extra
                // Re-wrap with the primary initializer so the weekly slots and the
                // scoped model list survive verbatim — the compat init would flatten
                // the resolved slots into `legacyOpus`/`legacySonnet` and drop
                // `scopedWeeklyModels`, losing model names and any 3rd+ model.
                let merged = UsageData(
                    fiveHour: mainData.fiveHour,
                    sevenDay: mainData.sevenDay,
                    legacyOpus: mainData.legacyOpus,
                    legacySonnet: mainData.legacySonnet,
                    scopedWeeklyModels: mainData.scopedWeeklyModels,
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
        // Force HTTP/2 over TCP. macOS may opportunistically pick HTTP/3 (QUIC,
        // UDP) which slips around system proxies that only intercept TCP — see
        // upstream Usage4Claude commit 9feb1fc.
        request.assumesHTTP3Capable = false

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

    /// Fetch the user's organization list.
    /// - Parameter sessionKey: Optional override; falls back to `settings.sessionKey` when nil.
    /// - Returns: The decoded `[Organization]` for the session.
    /// - Throws: `UsageError` mapped from HTTP status / decode failures.
    /// - Note: Used to automatically fetch Organization IDs after WebLogin or
    ///   when validating a manually-pasted session key.
    func fetchOrganizations(sessionKey: String? = nil) async throws -> [Organization] {
        let urlString = "\(baseURL.replacingOccurrences(of: "/organizations", with: ""))/organizations"

        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false  // see fetchUsage for rationale

        let actualSessionKey = sessionKey ?? settings.sessionKey
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: nil,  // organizationId not needed for fetching organization list
            sessionKey: actualSessionKey
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Logger.api.debug("Network error: \(error.localizedDescription)")
            throw UsageError.networkError
        }

        if let jsonString = String(data: data, encoding: .utf8) {
            Logger.api.debug("Organizations API Response: \(jsonString)")
        }

        if let httpResponse = response as? HTTPURLResponse {
            Logger.api.debug("HTTP Status Code: \(httpResponse.statusCode)")

            // Cloudflare challenges return HTML with a text/html Content-Type regardless
            // of status. Treat any HTML body as a Cloudflare block — the JSON error
            // mapping below assumes application/json. Mirrors `fetchMainUsage`.
            let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if contentType.contains("text/html") {
                Logger.api.debug("⚠️ Received HTML response, possibly intercepted by Cloudflare.")
                throw UsageError.cloudflareBlocked
            }

            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                throw UsageError.unauthorized
            case 403:
                // 403 covers two distinct cases:
                // - Cloudflare/bot block (HTML body, handled above)
                // - Expired/invalid session (JSON body with permission_error)
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                   errorResponse.error.type == "permission_error" {
                    throw UsageError.sessionExpired
                } else {
                    throw UsageError.cloudflareBlocked
                }
            case 429:
                throw UsageError.rateLimited
            default:
                Logger.api.error("HTTP error: \(httpResponse.statusCode)")
                throw UsageError.httpError(statusCode: httpResponse.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode([Organization].self, from: data)
        } catch {
            Logger.api.debug("Decoding error: \(error.localizedDescription)")
            throw UsageError.decodingError
        }
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
        request.assumesHTTP3Capable = false  // see fetchUsage for rationale

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

    // MARK: - OAuth Usage Path

    /// OAuth accounts: exchange the refresh_token for an access_token, then call
    /// /api/oauth/usage.
    /// - Parameter retryOnUnauthorized: whether a 401 clears the cache and retries
    ///   once (forcing a fresh access_token), so the user isn't stuck on an error
    ///   state until the next scheduled refresh.
    private func fetchOAuthUsage(retryOnUnauthorized: Bool = true, completion: @escaping (Result<UsageData, Error>) -> Void) {
        let refreshToken = settings.sessionKey
        fetchOAuthAccessToken(refreshToken: refreshToken) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let accessToken):
                self.fetchClaudeOAuthUsageData(accessToken: accessToken, retryOnUnauthorized: retryOnUnauthorized, completion: completion)
            }
        }
    }

    /// Get an access_token from the refresh_token, with caching + single-flight coalescing.
    private func fetchOAuthAccessToken(refreshToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Cache hit: token not yet expired (with a 5-minute margin).
        oauthLock.lock()
        if let cached = cachedOAuthAccessToken, !cached.isEmpty,
           let expiry = cachedOAuthTokenExpiry,
           cachedOAuthForRefreshToken == refreshToken,
           expiry > Date().addingTimeInterval(5 * 60) {
            let remaining = Int(expiry.timeIntervalSinceNow / 60)
            oauthLock.unlock()
            Logger.api.debug("Claude OAuth: using cached access_token (~\(remaining) min remaining)")
            completion(.success(cached))
            return
        }
        // A refresh for the same refresh_token is already in flight: queue up and reuse its result.
        if oauthRefreshInFlight, oauthRefreshInFlightToken == refreshToken {
            oauthRefreshWaiters.append(completion)
            oauthLock.unlock()
            return
        }
        oauthRefreshInFlight = true
        oauthRefreshInFlightToken = refreshToken
        oauthLock.unlock()

        ClaudeOAuthService.refresh(refreshToken: refreshToken) { [weak self] result in
            guard let self else { return }

            let finalResult: Result<String, Error>
            switch result {
            case .failure(let error):
                Logger.api.error("Claude OAuth refresh failed: \(error.localizedDescription)")
                finalResult = .failure(error)

            case .success(let tokens):
                // refresh_token rotation: if the response carries a new value, write it back silently.
                let newRefresh = tokens.refreshToken.isEmpty ? refreshToken : tokens.refreshToken
                if newRefresh != refreshToken {
                    Logger.api.notice("Claude OAuth: refresh_token rotated, writing back silently")
                    DispatchQueue.main.async {
                        UserSettings.shared.silentlyUpdateCurrentClaudeSessionToken(newRefresh)
                    }
                }

                let accessToken = tokens.accessToken
                // expires_in is usually 3600s; conservatively use 30 minutes when absent.
                let expiry = tokens.expiresAt ?? Date().addingTimeInterval(30 * 60)
                self.oauthLock.lock()
                self.cachedOAuthAccessToken = accessToken
                self.cachedOAuthTokenExpiry = expiry
                self.cachedOAuthForRefreshToken = newRefresh
                self.oauthLock.unlock()
                finalResult = .success(accessToken)
            }

            // Clear the single-flight state and wake any waiters.
            self.oauthLock.lock()
            let waiters = self.oauthRefreshWaiters
            self.oauthRefreshWaiters.removeAll()
            self.oauthRefreshInFlight = false
            self.oauthRefreshInFlightToken = nil
            self.oauthLock.unlock()

            completion(finalResult)
            for waiter in waiters { waiter(finalResult) }
        }
    }

    /// Call /api/oauth/usage with the access_token and parse into UsageData.
    private func fetchClaudeOAuthUsageData(accessToken: String, retryOnUnauthorized: Bool, completion: @escaping (Result<UsageData, Error>) -> Void) {
        guard let url = URL(string: ClaudeOAuthConfig.usageURL) else {
            completion(.failure(UsageError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(ClaudeOAuthConfig.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                Logger.api.error("Claude OAuth usage network error: \(error.localizedDescription)")
                completion(.failure(UsageError.networkError))
                return
            }
            guard let data = data else {
                completion(.failure(UsageError.noData))
                return
            }
            if let http = response as? HTTPURLResponse {
                Logger.api.debug("Claude OAuth usage HTTP \(http.statusCode)")
                switch http.statusCode {
                case 200...299: break
                case 401:
                    // access_token is invalid; clear the cache so a fresh fetch
                    // re-exchanges via the refresh_token, instead of hammering a
                    // bad token for the 5-minute cache window.
                    self?.clearOAuthTokenCache()
                    if retryOnUnauthorized {
                        // Self-heal: immediately re-exchange the refresh_token for a
                        // fresh access_token and retry once, so the user isn't stuck
                        // on an error until the next scheduled refresh.
                        Logger.api.info("Claude OAuth usage 401 — cleared cache, retrying once with a fresh access_token")
                        self?.fetchOAuthUsage(retryOnUnauthorized: false, completion: completion)
                    } else {
                        completion(.failure(UsageError.unauthorized))
                    }
                    return
                case 429:
                    completion(.failure(UsageError.rateLimited))
                    return
                default:
                    completion(.failure(UsageError.httpError(statusCode: http.statusCode)))
                    return
                }
            }
            if let raw = String(data: data, encoding: .utf8) {
                Logger.api.debug("Claude OAuth usage response: \(raw.prefix(500))")
            }

            let decoder = JSONDecoder()
            do {
                // Reuse the existing UsageResponse decoder (five_hour/seven_day/opus/sonnet
                // field names match).
                let baseResponse = try decoder.decode(UsageResponse.self, from: data)
                var usageData = baseResponse.toUsageData()

                // Additionally decode the extra_usage field. Issue #64: the previous
                // four-layer `try?` silently swallowed the failure reason, so it was
                // impossible to tell "field absent" from "field renamed" from "shape
                // mismatch". Use an explicit branch that logs each outcome.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let extraJson = json["extra_usage"] as? [String: Any] {
                        // Log the keys even on success: ExtraUsageResponse's fields are all
                        // optional, so a renamed field won't throw — it silently produces a
                        // "disabled" (all-nil) result.
                        Logger.api.debug("Claude OAuth usage extra_usage keys=\(Array(extraJson.keys).sorted())")
                        if let extraData = try? JSONSerialization.data(withJSONObject: extraJson) {
                            do {
                                let extraResponse = try decoder.decode(ExtraUsageResponse.self, from: extraData)
                                let extraUsageData = extraResponse.toExtraUsageData()
                                Logger.api.debug("Claude OAuth usage extra_usage parsed: enabled=\(extraUsageData?.enabled ?? false)")
                                // Primary init: preserve the weekly slots and scoped
                                // model list (see the session-key merge site above).
                                usageData = UsageData(
                                    fiveHour: usageData.fiveHour,
                                    sevenDay: usageData.sevenDay,
                                    legacyOpus: usageData.legacyOpus,
                                    legacySonnet: usageData.legacySonnet,
                                    scopedWeeklyModels: usageData.scopedWeeklyModels,
                                    extraUsage: extraUsageData
                                )
                            } catch {
                                Logger.api.error("Claude OAuth usage extra_usage decode failed: \(error.localizedDescription), keys=\(Array(extraJson.keys))")
                            }
                        } else {
                            Logger.api.error("Claude OAuth usage extra_usage field could not be re-serialized to JSON, keys=\(Array(extraJson.keys))")
                        }
                    } else {
                        Logger.api.info("Claude OAuth usage has no extra_usage field, top-level keys=\(Array(json.keys))")
                    }
                }

                DispatchQueue.main.async { completion(.success(usageData)) }
            } catch {
                Logger.api.error("Claude OAuth usage decode failed: \(error.localizedDescription)")
                completion(.failure(UsageError.decodingError))
            }
        }.resume()
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
            return L.Error.httpError(statusCode)
        }
    }
}
