//
//  DiagnosticReport.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Diagnostic report data model
/// Contains complete diagnostic information with all sensitive data automatically redacted
struct DiagnosticReport: Codable {
    // MARK: - Basic Information

    /// Report generation time
    let timestamp: Date

    /// App version
    let appVersion: String

    /// macOS version
    let osVersion: String

    /// System architecture (arm64/x86_64)
    let architecture: String

    /// User-configured interface language
    let locale: String

    // MARK: - Configuration

    /// Refresh mode (Smart/Fixed)
    let refreshMode: String

    /// Refresh interval (if in fixed mode)
    let refreshInterval: String?

    /// Display mode
    let displayMode: String

    /// Organization ID (redacted)
    let organizationIdRedacted: String

    /// Session Key (redacted)
    let sessionKeyRedacted: String

    // MARK: - Test Results

    /// Whether the test was successful
    let success: Bool

    /// HTTP status code
    let httpStatusCode: Int?

    /// Response time (milliseconds)
    let responseTime: Double?

    /// Response type (JSON/HTML/Unknown)
    let responseType: ResponseType

    /// Error type (if failed)
    let errorType: DiagnosticErrorType?

    /// Error description
    let errorDescription: String?

    // MARK: - Response Details

    /// Response headers (sensitive information filtered)
    let responseHeaders: [String: String]

    /// Response body preview (first 500 characters)
    let responseBodyPreview: String?

    /// Whether a Cloudflare challenge was detected
    let cloudflareChallenge: Bool

    /// Whether cf-mitigated header is present
    let cfMitigated: Bool

    // MARK: - Analysis Results

    /// Diagnosis of the issue
    let diagnosis: String

    /// Suggested solutions (array)
    let suggestions: [String]

    /// Confidence level (High/Medium/Low)
    let confidence: ConfidenceLevel

    // MARK: - Enum Definitions

    enum ResponseType: String, Codable {
        case json = "JSON"
        case html = "HTML"
        case unknown = "Unknown"
    }

    enum ConfidenceLevel: String, Codable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
    }

    // MARK: - Formatted Output

    /// Generate a complete report in Markdown format
    func toMarkdown() -> String {
        var report = """
        # Usage4Claude Diagnostic Report

        **⚠️ PRIVACY NOTICE**: All sensitive information has been automatically redacted.  
        **✅ Safe to share**: This report contains no complete credentials or personal data.  

        ---

        ## Test Result

        """
        report += "**Status**: \(success ? "✅ Success" : "❌ Failed")  \n"
        report += "**Timestamp**: \(formatTimestamp())  \n"
        report += "**Response Time**: \(formatResponseTime())  \n"
        report += """

        """

        if !success {
            report += """

            ### Error Information

            """
            report += "**Error Type**: \(errorType?.rawValue ?? "Unknown")  \n"
            report += "**Description**: \(errorDescription ?? "No description")  \n"
            report += """

            """
        }

        report += """

        ---

        ## System Information

        - **App Version**: \(appVersion)
        - **macOS Version**: \(osVersion)
        - **Architecture**: \(architecture)
        - **Locale**: \(locale)

        ## Configuration

        - **Refresh Mode**: \(refreshMode)
        """

        if let interval = refreshInterval {
            report += "\n- **Refresh Interval**: \(interval)"
        }

        report += """

        - **Display Mode**: \(displayMode)
        - **Organization ID**: `\(organizationIdRedacted)` (redacted)
        - **Session Key**: `\(sessionKeyRedacted)` (redacted)

        ---

        ## Connection Test Details

        ### Request

        ```http
        GET /api/organizations/\(organizationIdRedacted)/usage HTTP/2
        Host: claude.ai
        accept: */*
        user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36
        Cookie: sessionKey=\(sessionKeyRedacted)
        [... other headers omitted for brevity]
        ```

        ### Response

        """

        if let statusCode = httpStatusCode {
            report += "**HTTP Status**: \(statusCode)  \n"
        }

        report += "**Content Type**: \(responseType.rawValue)  \n"

        if cloudflareChallenge {
            report += "**Cloudflare Challenge**: ⚠️ Detected  \n"
        }

        if cfMitigated {
            report += "**CF-Mitigated Header**: Present  \n"
        }

        if !responseHeaders.isEmpty {
            report += "\n**Response Headers**:\n```\n"
            for (key, value) in responseHeaders.sorted(by: { $0.key < $1.key }) {
                report += "\(key): \(value)\n"
            }
            report += "```\n"
        }

        if let preview = responseBodyPreview, !preview.isEmpty {
            report += """

            **Response Body** (first 500 characters):
            ```
            \(preview)
            ```

            """
        }

        report += """

        ---

        ## Analysis

        """
        report += "**Diagnosis**: \(diagnosis)  \n"
        report += "**Confidence**: \(confidence.rawValue)  \n"
        report += """

        ### Suggested Actions

        """

        for (index, suggestion) in suggestions.enumerated() {
            report += "\(index + 1). \(suggestion)\n"
        }

        report += """

        ---

        ## Additional Information

        - Report generated by Usage4Claude v\(appVersion)
        - For help, visit: https://github.com/arcanii/Usage4Claude-Arcanii/issues
        - Include this report when reporting issues

        """

        return report
    }

    // MARK: - Private Helper Methods

    private func formatTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: timestamp)
    }

    private func formatResponseTime() -> String {
        guard let time = responseTime else {
            return "N/A"
        }
        return String(format: "%.0f ms", time)
    }
}

/// Diagnostic error type
enum DiagnosticErrorType: String, Codable {
    case cloudflareBlocked = "Cloudflare Challenge"
    case authenticationFailed = "Authentication Failed"
    case networkError = "Network Error"
    case decodingError = "Data Parsing Error"
    case invalidCredentials = "Invalid Credentials"
    case timeout = "Request Timeout"
    case unknown = "Unknown Error"
}

// MARK: - English Diagnostic Messages (for export only, not localized)

/// English diagnostic messages for diagnostic reports
/// These are used in exported reports to maintain consistency across different locales
enum DiagnosticMessage {

    // MARK: - Diagnosis Messages

    static let diagnosisSuccess = "Connection is working properly. API returned valid usage data."
    static let diagnosisCloudflare = "Request was blocked by Cloudflare security system. This may be due to IP reputation or network configuration."
    static let diagnosisDecoding = "Server returned data but it couldn't be parsed. This usually means credentials are incorrect or don't match."
    static let diagnosisNetwork = "Network connection failed. Please check your internet connection."
    static let diagnosisNoCredentials = "Authentication credentials are not configured."
    static let diagnosisInvalidUrl = "Invalid Organization ID format."
    static let diagnosisUnknown = "Unknown error occurred. Please export and share this report with developers."

    // MARK: - Suggestion Messages

    static let suggestionSuccess = "Everything is working correctly. No action needed."
    static let suggestionVisitBrowser = "Visit claude.ai in your browser and complete any security challenges"
    static let suggestionWaitAndRetry = "Wait 5-10 minutes and try again"
    static let suggestionCheckVPN = "Check if VPN or proxy is affecting the connection"
    static let suggestionUseSmartMode = "Use Smart Refresh mode to reduce request frequency"
    static let suggestionVerifyCredentials = "Verify that Organization ID and Session Key are correct"
    static let suggestionUpdateSessionKey = "Your Session Key may have expired. Please update it from browser"
    static let suggestionCheckBrowser = "Verify you can access claude.ai/settings/usage in browser"
    static let suggestionCheckInternet = "Check your internet connection"
    static let suggestionCheckFirewall = "Check firewall or antivirus settings"
    static let suggestionRetryLater = "Try again later"
    static let suggestionConfigureAuth = "Please configure Organization ID and Session Key in the fields above"
    static let suggestionCheckOrgId = "Check if Organization ID format is correct (should be a UUID)"
    static let suggestionExportAndShare = "Export this diagnostic report and share it on GitHub Issues"
    static let suggestionContactSupport = "Contact developer for help at github.com/arcanii/Usage4Claude-Arcanii/issues"
}
