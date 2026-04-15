//
//  SensitiveDataRedactor.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Sensitive data redaction utility
/// Provides unified sensitive information redaction methods for logging and diagnostic reports
/// Supports redaction of Organization IDs, Session Keys, and sensitive information in text
class SensitiveDataRedactor {
    // MARK: - Public Methods

    /// Redact Organization ID
    /// - Parameter id: Original Organization ID
    /// - Returns: Redacted string
    /// - Note: For IDs shorter than 8 characters, all characters are replaced with asterisks; otherwise the first 4 and last 4 characters are preserved
    /// - Example: "12345678-1234-1234-1234-123456789012" -> "1234...9012"
    static func redactOrganizationId(_ id: String) -> String {
        guard id.count > 8 else {
            return String(repeating: "*", count: id.count)
        }
        let prefix = id.prefix(4)
        let suffix = id.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    /// Redact Session Key
    /// - Parameter key: Original Session Key
    /// - Returns: Redacted string
    /// - Note: For keys starting with sk-ant-, the prefix is preserved and the length is shown; otherwise returns "***"
    /// - Example: "sk-ant-sid01-XXXXX..." -> "sk-ant-***...*** (128 chars)"
    static func redactSessionKey(_ key: String) -> String {
        guard key.count > 20 else {
            return "***"
        }

        // Preserve prefix "sk-ant-"
        if key.hasPrefix("sk-ant-") {
            return "sk-ant-***...*** (\(key.count) chars)"
        }

        // Other key formats
        return "***...*** (\(key.count) chars)"
    }

    /// Redact sensitive information in text
    /// Uses regular expressions to find and replace Organization IDs and Session Keys in text
    /// - Parameter text: Original text containing sensitive information
    /// - Returns: Redacted text
    /// - Note: Used for log and diagnostic output, automatically identifies and redacts common formats
    static func redactText(_ text: String) -> String {
        var sanitized = text

        // Redact Session Key (preserve first 4 and last 4 characters)
        // Match pattern: sessionKey=xxx or sessionKey: xxx
        let sessionKeyPattern = "sessionKey[=:]\\s*[\"']?([a-zA-Z0-9-]{20,})[\"']?"
        if let regex = try? NSRegularExpression(pattern: sessionKeyPattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "sessionKey=***REDACTED***"
            )
        }

        // Redact Organization ID (UUID format)
        // Match pattern: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        let orgIdPattern = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        if let regex = try? NSRegularExpression(pattern: orgIdPattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "********-****-****-****-************"
            )
        }

        // Redact sessionKey in Cookie
        // Match pattern: Cookie: sessionKey=xxx
        let cookiePattern = "Cookie:\\s*sessionKey=([a-zA-Z0-9-]{20,})"
        if let regex = try? NSRegularExpression(pattern: cookiePattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "Cookie: sessionKey=***REDACTED***"
            )
        }

        return sanitized
    }
}
