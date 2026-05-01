//
//  ClaudeAPIHeaderBuilder.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Claude API HTTP request header builder
/// Provides unified header building logic for bypassing Cloudflare protection
/// Contains complete browser simulation headers
class ClaudeAPIHeaderBuilder {
    // MARK: - Public Methods

    /// Build standard HTTP headers for Claude API requests
    /// - Parameters:
    ///   - organizationId: Organization ID (optional, not needed for some APIs)
    ///   - sessionKey: Session key
    /// - Returns: HTTP headers dictionary
    /// - Note: These headers are used to bypass Cloudflare anti-bot detection
    /// - Important: Headers must match real browser requests to avoid triggering Cloudflare Challenge
    static func buildHeaders(
        organizationId: String?,
        sessionKey: String
    ) -> [String: String] {
        return [
            // Basic headers
            "accept": "*/*",
            "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
            "content-type": "application/json",

            // Anthropic platform identifier
            "anthropic-client-platform": "web_claude_ai",
            "anthropic-client-version": "1.0.0",

            // Browser identifier — bump periodically as real Chrome marches on, otherwise
            // Cloudflare's heuristics may flag a stale UA. Backlog has a recurring "bump
            // Chrome user-agent" item to track this.
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",

            // Origin and referrer information
            "origin": "https://claude.ai",
            "referer": "https://claude.ai/settings/usage",

            // Fetch API related (important: Cloudflare checks these fields)
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",

            // Authentication cookie
            "Cookie": "sessionKey=\(sessionKey)"
        ]
    }

    /// Apply standard headers to a URLRequest
    /// - Parameters:
    ///   - request: URLRequest to set headers on (inout parameter)
    ///   - organizationId: Organization ID (optional, not needed for some APIs)
    ///   - sessionKey: Session key
    /// - Note: Directly modifies the passed-in request object
    static func applyHeaders(
        to request: inout URLRequest,
        organizationId: String?,
        sessionKey: String
    ) {
        let headers = buildHeaders(organizationId: organizationId, sessionKey: sessionKey)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
