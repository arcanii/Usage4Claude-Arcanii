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

            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                throw UsageError.unauthorized
            case 403:
                throw UsageError.cloudflareBlocked
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
