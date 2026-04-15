//
//  DiagnosticLogger.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Diagnostic logger
/// Provides detailed runtime logs to help track and diagnose issues
@MainActor
class DiagnosticLogger {

    // MARK: - Singleton

    static let shared = DiagnosticLogger()

    // MARK: - Properties

    /// Log level
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Log file URL
    private var logFileURL: URL?

    /// Log queue (for asynchronous writing)
    private let logQueue = DispatchQueue(label: "com.arcanii.Usage4Claude.logging", qos: .utility)

    /// Maximum log file size (5MB)
    private let maxLogFileSize: UInt64 = 5 * 1024 * 1024

    /// Whether logging is enabled
    private var isEnabled: Bool = true

    /// System logger
    private let osLogger = Logger(subsystem: "com.arcanii.Usage4Claude", category: "Diagnostics")

    // MARK: - Initialization

    private init() {
        setupLogFile()
    }

    // MARK: - Public Methods

    /// Log debug information
    func debug(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .debug, file: file, line: line, function: function)
    }

    /// Log general information
    func info(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .info, file: file, line: line, function: function)
    }

    /// Log warning information
    func warning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .warning, file: file, line: line, function: function)
    }

    /// Log error information
    func error(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .error, file: file, line: line, function: function)
    }

    /// Get the log file path
    func getLogFilePath() -> String? {
        return logFileURL?.path
    }

    /// Read log contents
    func readLogs(maxLines: Int = 1000) -> String {
        guard let logFileURL = logFileURL,
              FileManager.default.fileExists(atPath: logFileURL.path) else {
            return "No logs available"
        }

        do {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let recentLines = lines.suffix(maxLines)
            return recentLines.joined(separator: "\n")
        } catch {
            return "Error reading logs: \(error.localizedDescription)"
        }
    }

    /// Clear logs
    func clearLogs() {
        guard let logFileURL = logFileURL else { return }

        logQueue.async {
            do {
                try "".write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to clear logs: \(error)")
            }
        }
    }

    /// Export log file
    func exportLogs() -> URL? {
        return logFileURL
    }

    // MARK: - Private Methods

    /// Set up log file
    private func setupLogFile() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ Failed to get Application Support directory")
            return
        }

        let logDirectory = appSupport.appendingPathComponent("Usage4Claude/logs")

        // Create log directory
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create log directory: \(error)")
            return
        }

        // Set log file path
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logDirectory.appendingPathComponent("usage4claude_\(dateString).log")

        // Check and rotate logs
        checkAndRotateLogIfNeeded()
    }

    /// Core log recording method
    private func log(_ message: String, level: LogLevel, file: String, line: Int, function: String) {
        guard isEnabled else { return }

        // Release builds only log warning and error to reduce log size and privacy leaks
        #if !DEBUG
        guard level == .warning || level == .error else { return }
        #endif

        // Redact sensitive data
        let sanitizedMessage = sanitize(message)

        // Extract file name
        let fileName = (file as NSString).lastPathComponent

        // Build log message
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(sanitizedMessage)\n"

        // Output to console (Debug mode only)
        #if DEBUG
        print(logMessage, terminator: "")
        #endif

        // Output to system log
        osLogger.log(level: osLogLevel(for: level), "\(sanitizedMessage)")

        // Write to file asynchronously
        writeToFile(logMessage)
    }

    /// Write log to file
    private func writeToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        logQueue.async {
            do {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    // File exists, append content
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    defer { fileHandle.closeFile() }

                    if #available(macOS 10.15.4, *) {
                        try fileHandle.seekToEnd()
                        if let data = message.data(using: .utf8) {
                            try fileHandle.write(contentsOf: data)
                        }
                    } else {
                        fileHandle.seekToEndOfFile()
                        if let data = message.data(using: .utf8) {
                            fileHandle.write(data)
                        }
                    }
                } else {
                    // File does not exist, create new file
                    try message.write(to: logFileURL, atomically: true, encoding: .utf8)
                }

                // Check file size
                Task { @MainActor in
                    self.checkAndRotateLogIfNeeded()
                }
            } catch {
                print("❌ Failed to write log: \(error)")
            }
        }
    }

    /// Check and rotate log file if needed
    private func checkAndRotateLogIfNeeded() {
        guard let logFileURL = logFileURL else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize > maxLogFileSize {
                // File too large, perform rotation
                rotateLog()
            }
        } catch {
            // File does not exist or cannot be read, ignore
        }
    }

    /// Rotate log file
    private func rotateLog() {
        guard let logFileURL = logFileURL else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let archiveURL = logFileURL.deletingLastPathComponent()
            .appendingPathComponent("usage4claude_\(timestamp).log.old")

        do {
            // Rename current log file
            try FileManager.default.moveItem(at: logFileURL, to: archiveURL)

            // Delete old archive files (keep the most recent 5)
            cleanupOldLogs()
        } catch {
            print("❌ Failed to rotate log: \(error)")
        }
    }

    /// Clean up old log files
    private func cleanupOldLogs() {
        guard let logFileURL = logFileURL else { return }

        let logDirectory = logFileURL.deletingLastPathComponent()

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: logDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            // Only keep .old files
            let oldLogs = fileURLs.filter { $0.pathExtension == "old" }

            // Sort by creation date
            let sortedLogs = try oldLogs.sorted { url1, url2 in
                let date1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2
            }

            // Delete old logs exceeding 5
            if sortedLogs.count > 5 {
                for logURL in sortedLogs.dropFirst(5) {
                    try FileManager.default.removeItem(at: logURL)
                }
            }
        } catch {
            print("❌ Failed to cleanup old logs: \(error)")
        }
    }

    /// Redact sensitive information
    private func sanitize(_ message: String) -> String {
        // Use the unified sensitive data redaction utility
        return SensitiveDataRedactor.redactText(message)
    }

    /// Convert to system log level
    private func osLogLevel(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

// MARK: - Convenience Global Functions

/// Global convenience log functions
@MainActor
func logDebug(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.debug(message, file: file, line: line, function: function)
}

@MainActor
func logInfo(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.info(message, file: file, line: line, function: function)
}

@MainActor
func logWarning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.warning(message, file: file, line: line, function: function)
}

@MainActor
func logError(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.error(message, file: file, line: line, function: function)
}
