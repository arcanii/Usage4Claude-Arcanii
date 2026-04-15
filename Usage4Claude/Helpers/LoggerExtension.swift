//
//  LoggerExtension.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-11-10.
//  Copyright © 2025 f-is-h. All rights reserved.
//


import OSLog

extension Logger {
    /// Unified subsystem identifier for the app
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.arcanii.Usage4Claude"

    /// Menu bar manager log
    /// Used to log menu bar, refresh, update check, and related operations
    static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")

    /// User settings log
    /// Used to log settings changes, smart mode switching, launch at login, and related operations
    static let settings = Logger(subsystem: subsystem, category: "Settings")

    /// Keychain management log
    /// Used to log storage, retrieval, and deletion operations for sensitive information
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")

    /// API service log
    /// Used to log API requests, responses, and errors
    static let api = Logger(subsystem: subsystem, category: "API")

    /// Localization management log
    /// Used to log language switching and localization-related operations
    static let localization = Logger(subsystem: subsystem, category: "Localization")
}

// MARK: - Log Level Reference
/*
 OSLog provides 5 log levels; Release builds automatically disable lower-level logs:

 1. .debug    - Debug info, only output during development, not executed in Release
 2. .info     - General info, not persisted by default
 3. .notice   - Important events, persisted by default
 4. .error    - Error info, always persisted
 5. .fault    - Critical errors, always persisted

 Usage examples:
 ```swift
 Logger.menuBar.debug("Debug info")
 Logger.menuBar.info("General info")
 Logger.menuBar.notice("Important event")
 Logger.menuBar.error("Error: \(error.localizedDescription)")
 Logger.menuBar.fault("Critical error")
 ```

 Viewing logs:
 1. Xcode Console (during development)
 2. Console.app (search subsystem:com.arcanii.Usage4Claude)
 3. Command line: log show --predicate 'subsystem == "com.arcanii.Usage4Claude"' --last 1h
 */
