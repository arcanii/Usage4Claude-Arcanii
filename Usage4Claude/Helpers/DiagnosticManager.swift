//
//  DiagnosticManager.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// Diagnostic manager
/// Responsible for executing connection tests, generating diagnostic reports, exporting reports, etc.
@MainActor
class DiagnosticManager: ObservableObject {

    // MARK: - Published Properties

    /// Whether a diagnostic test is in progress
    @Published var isTesting: Bool = false

    /// Latest diagnostic report
    @Published var latestReport: DiagnosticReport?

    /// Test status message
    @Published var statusMessage: String = ""

    // MARK: - Private Properties

    private let settings = UserSettings.shared

    // MARK: - Public Methods

    /// Execute a full diagnostic test
    func runDiagnosticTest() async {
        await MainActor.run {
            isTesting = true
            statusMessage = L.Diagnostic.testingConnection
        }

        // Check credentials
        guard settings.hasValidCredentials else {
            let report = createReportForMissingCredentials()
            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = L.Diagnostic.testCompleted
            }
            return
        }

        // Record start time
        let startTime = Date()

        // Build request
        guard let request = buildDiagnosticRequest() else {
            let report = createReportForInvalidURL()
            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = L.Diagnostic.testCompleted
            }
            return
        }

        // Execute request
        let session = URLSession(configuration: .default)

        do {
            let (data, response) = try await session.data(for: request)
            let responseTime = Date().timeIntervalSince(startTime) * 1000 // milliseconds

            // Analyze response
            let report = analyzeResponse(data: data, response: response, responseTime: responseTime)

            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = report.success ? L.Diagnostic.testSuccess : L.Diagnostic.testFailed
            }

        } catch {
            let responseTime = Date().timeIntervalSince(startTime) * 1000
            let report = createReportForNetworkError(error: error, responseTime: responseTime)

            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = L.Diagnostic.testFailed
            }
        }
    }

    /// Export diagnostic report to file
    /// - Returns: Exported file path, or nil on failure
    func exportReport() -> URL? {
        guard let report = latestReport else {
            return nil
        }

        // Generate Markdown content
        let markdown = report.toMarkdown()

        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "Usage4Claude_Diagnostic_\(formatFilenameDate()).md"
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to export report: \(error)")
            return nil
        }
    }

    /// Build a debug snapshot describing in-app credential state.
    /// Sensitive values are redacted (sessionKey is shown as length + prefix only).
    /// Intended for the user to copy and share when troubleshooting auth issues.
    func buildDebugSnapshot() -> String {
        var lines: [String] = []
        lines.append("=== Usage4Claude debug snapshot ===")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("App version: \(getAppVersion())")
        lines.append("OS: \(getOSVersion()) (\(getArchitecture()))")
        lines.append("")
        lines.append("--- UserSettings ---")
        lines.append("hasValidCredentials: \(settings.hasValidCredentials)")
        lines.append("accounts.count: \(settings.accounts.count)")
        if let currentId = settings.currentAccountId {
            lines.append("currentAccountId: \(currentId.uuidString)")
        } else {
            lines.append("currentAccountId: <nil>")
        }
        let resolved = settings.currentAccount
        lines.append("currentAccount resolved: \(resolved == nil ? "<nil>" : "yes")")
        lines.append("")

        for (i, account) in settings.accounts.enumerated() {
            let isCurrent = (account.id == settings.currentAccountId)
            lines.append("--- Account #\(i)\(isCurrent ? " (current)" : "") ---")
            lines.append("  id: \(account.id.uuidString)")
            lines.append("  organizationId: \(account.organizationId)")
            lines.append("  organizationName: \(account.organizationName)")
            lines.append("  alias: \(account.alias ?? "<nil>")")
            lines.append("  sessionKey.count: \(account.sessionKey.count)")
            lines.append("  sessionKey hasPrefix sk-ant-: \(account.sessionKey.hasPrefix("sk-ant-"))")
            lines.append("  sessionKey isValid: \(settings.isValidSessionKey(account.sessionKey))")
            lines.append("  organizationId isValid UUID: \(settings.isValidOrganizationId(account.organizationId))")
        }
        lines.append("")

        if let report = latestReport {
            lines.append("--- Last diagnostic test ---")
            lines.append("  success: \(report.success)")
            if let code = report.httpStatusCode {
                lines.append("  http status: \(code)")
            }
            lines.append("  responseType: \(report.responseType.rawValue)")
            lines.append("  cloudflareChallenge: \(report.cloudflareChallenge)")
            lines.append("  cfMitigated: \(report.cfMitigated)")
            if let err = report.errorType {
                lines.append("  errorType: \(err.rawValue)")
            }
            if let preview = report.responseBodyPreview, !preview.isEmpty {
                lines.append("  bodyPreview (sanitized):")
                let sanitized = SensitiveDataRedactor.redactText(preview)
                for line in sanitized.split(separator: "\n").prefix(20) {
                    lines.append("    \(line)")
                }
            }
        } else {
            lines.append("--- Last diagnostic test ---")
            lines.append("  <none — run the test button first>")
        }

        return lines.joined(separator: "\n")
    }

    /// Copy the debug snapshot to the system clipboard.
    func copyDebugSnapshotToClipboard() {
        let snapshot = buildDebugSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot, forType: .string)
    }

    /// Show save dialog and export report
    func saveReportWithDialog() {
        guard let report = latestReport else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = L.Diagnostic.exportTitle
        savePanel.message = L.Diagnostic.exportMessage
        savePanel.nameFieldStringValue = "Usage4Claude_Diagnostic_\(formatFilenameDate()).md"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                return
            }

            let markdown = report.toMarkdown()

            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)

                // Show success notification
                self.showSuccessNotification(url: url)

            } catch {
                // Show error notification
                self.showErrorNotification(error: error)
            }
        }
    }

    // MARK: - Private Methods - Request Building

    private func buildDiagnosticRequest() -> URLRequest? {
        let urlString = "https://claude.ai/api/organizations/\(settings.organizationId)/usage"

        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        // Use the unified header builder to add complete browser headers
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: settings.organizationId,
            sessionKey: settings.sessionKey
        )

        return request
    }

    // MARK: - Private Methods - Response Analysis

    private func analyzeResponse(data: Data, response: URLResponse, responseTime: Double) -> DiagnosticReport {
        guard let httpResponse = response as? HTTPURLResponse else {
            return createReportForUnknownResponse(data: data, responseTime: responseTime)
        }

        let statusCode = httpResponse.statusCode
        let headers = extractSafeHeaders(from: httpResponse)

        // Check if it's an HTML response (Cloudflare challenge)
        if let bodyString = String(data: data, encoding: .utf8) {
            let isHTML = bodyString.contains("<!DOCTYPE html>") || bodyString.contains("<html")
            let containsCloudflare = bodyString.localizedCaseInsensitiveContains("cloudflare") ||
                                     bodyString.contains("cf-mitigated") ||
                                     bodyString.contains("Just a moment")

            if isHTML && (statusCode == 403 || containsCloudflare) {
                return createReportForCloudflareBlock(
                    statusCode: statusCode,
                    headers: headers,
                    bodyPreview: String(bodyString.prefix(500)),
                    responseTime: responseTime
                )
            }

            // Try to parse JSON
            if let json = try? JSONDecoder().decode(UsageResponse.self, from: data) {
                return createReportForSuccess(
                    statusCode: statusCode,
                    headers: headers,
                    usageData: json,
                    responseTime: responseTime
                )
            }

            // JSON parsing failed
            return createReportForDecodingError(
                statusCode: statusCode,
                headers: headers,
                bodyPreview: String(bodyString.prefix(500)),
                responseTime: responseTime
            )
        }

        // Unable to read response body
        return createReportForUnknownResponse(
            data: data,
            responseTime: responseTime,
            statusCode: statusCode,
            headers: headers
        )
    }

    // MARK: - Private Methods - Report Generation

    private func createReportForSuccess(
        statusCode: Int,
        headers: [String: String],
        usageData: UsageResponse,
        responseTime: Double
    ) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.iconDisplayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: true,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .json,
            errorType: nil,
            errorDescription: nil,
            responseHeaders: headers,
            responseBodyPreview: "Valid usage data received (utilization: \(usageData.five_hour.utilization)%)",
            cloudflareChallenge: false,
            cfMitigated: headers["cf-mitigated"] != nil,
            diagnosis: DiagnosticMessage.diagnosisSuccess,
            suggestions: [DiagnosticMessage.suggestionSuccess],
            confidence: .high
        )
    }

    private func createReportForCloudflareBlock(
        statusCode: Int,
        headers: [String: String],
        bodyPreview: String,
        responseTime: Double
    ) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.iconDisplayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .html,
            errorType: .cloudflareBlocked,
            errorDescription: L.Error.cloudflareBlocked,
            responseHeaders: headers,
            responseBodyPreview: bodyPreview,
            cloudflareChallenge: true,
            cfMitigated: headers["cf-mitigated"] != nil,
            diagnosis: DiagnosticMessage.diagnosisCloudflare,
            suggestions: [
                DiagnosticMessage.suggestionVisitBrowser,
                DiagnosticMessage.suggestionWaitAndRetry,
                DiagnosticMessage.suggestionCheckVPN,
                DiagnosticMessage.suggestionUseSmartMode
            ],
            confidence: .high
        )
    }

    private func createReportForDecodingError(
        statusCode: Int,
        headers: [String: String],
        bodyPreview: String,
        responseTime: Double
    ) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.iconDisplayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .unknown,
            errorType: .decodingError,
            errorDescription: L.Error.decodingFailed,
            responseHeaders: headers,
            responseBodyPreview: bodyPreview,
            cloudflareChallenge: false,
            cfMitigated: headers["cf-mitigated"] != nil,
            diagnosis: DiagnosticMessage.diagnosisDecoding,
            suggestions: [
                DiagnosticMessage.suggestionVerifyCredentials,
                DiagnosticMessage.suggestionUpdateSessionKey,
                DiagnosticMessage.suggestionCheckBrowser
            ],
            confidence: .medium
        )
    }

    private func createReportForNetworkError(error: Error, responseTime: Double) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.iconDisplayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: nil,
            responseTime: responseTime,
            responseType: .unknown,
            errorType: .networkError,
            errorDescription: error.localizedDescription,
            responseHeaders: [:],
            responseBodyPreview: nil,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: DiagnosticMessage.diagnosisNetwork,
            suggestions: [
                DiagnosticMessage.suggestionCheckInternet,
                DiagnosticMessage.suggestionCheckFirewall,
                DiagnosticMessage.suggestionRetryLater
            ],
            confidence: .high
        )
    }

    private func createReportForMissingCredentials() -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.iconDisplayMode.rawValue,
            organizationIdRedacted: "Not configured",
            sessionKeyRedacted: "Not configured",
            success: false,
            httpStatusCode: nil,
            responseTime: nil,
            responseType: .unknown,
            errorType: .invalidCredentials,
            errorDescription: L.Error.noCredentials,
            responseHeaders: [:],
            responseBodyPreview: nil,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: DiagnosticMessage.diagnosisNoCredentials,
            suggestions: [DiagnosticMessage.suggestionConfigureAuth],
            confidence: .high
        )
    }

    private func createReportForInvalidURL() -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.iconDisplayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: nil,
            responseTime: nil,
            responseType: .unknown,
            errorType: .invalidCredentials,
            errorDescription: L.Error.invalidUrl,
            responseHeaders: [:],
            responseBodyPreview: nil,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: DiagnosticMessage.diagnosisInvalidUrl,
            suggestions: [DiagnosticMessage.suggestionCheckOrgId],
            confidence: .high
        )
    }

    private func createReportForUnknownResponse(
        data: Data,
        responseTime: Double,
        statusCode: Int? = nil,
        headers: [String: String] = [:]
    ) -> DiagnosticReport {
        let preview: String
        if let bodyString = String(data: data, encoding: .utf8) {
            preview = String(bodyString.prefix(500))
        } else {
            preview = "Unable to decode response"
        }

        return DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.iconDisplayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .unknown,
            errorType: .unknown,
            errorDescription: "Unknown response format",
            responseHeaders: headers,
            responseBodyPreview: preview,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: DiagnosticMessage.diagnosisUnknown,
            suggestions: [
                DiagnosticMessage.suggestionExportAndShare,
                DiagnosticMessage.suggestionContactSupport
            ],
            confidence: .low
        )
    }

    // MARK: - Private Methods - Data Redaction

    /// Redact Organization ID
    /// Example: "12345678-abcd-ef90-1234-567890abcdef" -> "1234...cdef"
    /// Redact Organization ID
    /// Uses the unified redaction utility
    private func redactOrganizationId(_ orgId: String) -> String {
        return SensitiveDataRedactor.redactOrganizationId(orgId)
    }

    /// Redact Session Key
    /// Uses the unified redaction utility
    private func redactSessionKey(_ sessionKey: String) -> String {
        return SensitiveDataRedactor.redactSessionKey(sessionKey)
    }

    /// Extract safe headers from HTTP response (filter out sensitive data)
    private func extractSafeHeaders(from response: HTTPURLResponse) -> [String: String] {
        var safeHeaders: [String: String] = [:]

        // Allowed headers list
        let allowedHeaders = [
            "content-type",
            "content-length",
            "cf-mitigated",
            "cf-ray",
            "server",
            "date",
            "cache-control",
            "x-request-id"
        ]

        for (key, value) in response.allHeaderFields {
            let keyStr = (key as? String ?? "").lowercased()
            if allowedHeaders.contains(keyStr) {
                safeHeaders[keyStr] = value as? String ?? ""
            }
        }

        return safeHeaders
    }

    // MARK: - Private Methods - System Information

    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func getArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func formatFilenameDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Private Methods - Notifications

    private func showSuccessNotification(url: URL) {
        let alert = NSAlert()
        alert.messageText = L.Diagnostic.exportSuccessTitle
        alert.informativeText = L.Diagnostic.exportSuccessMessage + "\n\n\(url.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.Update.okButton)
        alert.runModal()
    }

    private func showErrorNotification(error: Error) {
        let alert = NSAlert()
        alert.messageText = L.Diagnostic.exportErrorTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.Update.okButton)
        alert.runModal()
    }
}
