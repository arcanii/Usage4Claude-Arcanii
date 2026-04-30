//
//  UserSettings.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import ServiceManagement
import OSLog

// MARK: - Display Modes

/// Menu bar icon display mode
enum IconDisplayMode: String, CaseIterable, Codable {
    /// Show percentage ring only
    case percentageOnly = "percentage_only"
    /// Show app icon only
    case iconOnly = "icon_only"
    /// Show both icon and percentage
    case both = "both"
    /// Unified concentric ring display combining 5h and 7d
    case unified = "unified"

    var localizedName: String {
        switch self {
        case .percentageOnly:
            return L.Display.percentageOnly
        case .iconOnly:
            return L.Display.iconOnly
        case .both:
            return L.Display.both
        case .unified:
            return L.Display.unified
        }
    }
}

/// Menu bar icon style mode
enum IconStyleMode: String, CaseIterable, Codable {
    /// Color translucent (default, colored without background)
    case colorTranslucent = "color_translucent"
    /// Color with background
    case colorWithBackground = "color_with_background"
    /// Monochrome (Template mode, follows system theme)
    case monochrome = "monochrome"
    
    var localizedName: String {
        switch self {
        case .colorTranslucent:
            return L.IconStyle.colorTranslucent
        case .colorWithBackground:
            return L.IconStyle.colorWithBackground
        case .monochrome:
            return L.IconStyle.monochrome
        }
    }
    
    var description: String {
        switch self {
        case .colorTranslucent:
            return L.IconStyle.colorTranslucentDesc
        case .colorWithBackground:
            return L.IconStyle.colorWithBackgroundDesc
        case .monochrome:
            return L.IconStyle.monochromeDesc
        }
    }
}

// MARK: - Refresh Modes

/// Refresh mode
enum RefreshMode: String, CaseIterable, Codable {
    /// Smart frequency (auto-adjusts based on usage)
    case smart = "smart"
    /// Fixed frequency (manually set by user)
    case fixed = "fixed"
    
    var localizedName: String {
        switch self {
        case .smart:
            return L.Refresh.smartMode
        case .fixed:
            return L.Refresh.fixedMode
        }
    }
}

/// Data refresh frequency
enum RefreshInterval: Int, CaseIterable, Codable {
    /// Refresh every 1 minute
    case oneMinute = 60
    /// Refresh every 3 minutes
    case threeMinutes = 180
    /// Refresh every 5 minutes
    case fiveMinutes = 300
    /// Refresh every 10 minutes
    case tenMinutes = 600
    
    var localizedName: String {
        switch self {
        case .oneMinute:
            return L.Refresh.oneMinute
        case .threeMinutes:
            return L.Refresh.threeMinutes
        case .fiveMinutes:
            return L.Refresh.fiveMinutes
        case .tenMinutes:
            return L.Refresh.tenMinutes
        }
    }
}

/// Monitoring mode (internal use, 4-tier modes under smart frequency)
enum MonitoringMode: String, Codable {
    /// Active mode - 1 minute refresh
    case active = "active"
    /// Short idle - 3 minute refresh
    case idleShort = "idle_short"
    /// Medium idle - 5 minute refresh
    case idleMedium = "idle_medium"
    /// Long idle - 10 minute refresh
    case idleLong = "idle_long"

    /// Get the corresponding refresh interval (seconds)
    var interval: Int {
        switch self {
        case .active:
            return 60      // 1 minute
        case .idleShort:
            return 180     // 3 minutes
        case .idleMedium:
            return 300     // 5 minutes
        case .idleLong:
            return 600     // 10 minutes
        }
    }
}

// MARK: - Limit Types

/// Limit type
enum LimitType: String, CaseIterable, Codable {
    /// 5-hour limit
    case fiveHour = "five_hour"
    /// 7-day limit
    case sevenDay = "seven_day"
    /// Extra Usage paid overage allowance
    case extraUsage = "extra_usage"
    /// Opus weekly limit
    case opusWeekly = "seven_day_opus"
    /// Sonnet weekly limit
    case sonnetWeekly = "seven_day_sonnet"

    /// Whether this is a circular icon (5-hour and 7-day)
    var isCircular: Bool {
        return self == .fiveHour || self == .sevenDay
    }

    /// Whether this is a rectangular icon (Opus and Sonnet)
    var isRectangular: Bool {
        return self == .opusWeekly || self == .sonnetWeekly
    }

    /// Whether this is a hexagonal icon (Extra Usage)
    var isHexagonal: Bool {
        return self == .extraUsage
    }

    /// Display name
    var displayName: String {
        switch self {
        case .fiveHour:
            return L.LimitTypes.fiveHour
        case .sevenDay:
            return L.LimitTypes.sevenDay
        case .opusWeekly:
            return L.LimitTypes.opusWeekly
        case .sonnetWeekly:
            return L.LimitTypes.sonnetWeekly
        case .extraUsage:
            return L.LimitTypes.extraUsage
        }
    }
}

// MARK: - Display Mode

/// Display mode (smart display vs custom display)
enum DisplayMode: String, CaseIterable, Codable {
    /// Smart display - automatically shows limit types with data
    case smart = "smart"
    /// Custom display - user manually selects which limit types to show
    case custom = "custom"

    var localizedName: String {
        switch self {
        case .smart:
            return L.DisplayOptions.smartDisplay
        case .custom:
            return L.DisplayOptions.customDisplay
        }
    }
}

/// Time format preference
enum TimeFormatPreference: String, CaseIterable, Codable {
    /// Follow system
    case system = "system"
    /// 12-hour format
    case twelveHour = "twelve_hour"
    /// 24-hour format
    case twentyFourHour = "twenty_four_hour"

    var localizedName: String {
        switch self {
        case .system:
            return L.TimeFormat.system
        case .twelveHour:
            return L.TimeFormat.twelveHour
        case .twentyFourHour:
            return L.TimeFormat.twentyFourHour
        }
    }
}

/// App appearance mode
enum AppAppearance: String, CaseIterable, Codable {
    /// Follow system
    case system = "system"
    /// Light
    case light = "light"
    /// Dark
    case dark = "dark"

    var localizedName: String {
        switch self {
        case .system:
            return L.Appearance.system
        case .light:
            return L.Appearance.light
        case .dark:
            return L.Appearance.dark
        }
    }

    /// Corresponding SwiftUI ColorScheme (system returns nil, meaning follow system)
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

/// App language options
enum AppLanguage: String, CaseIterable, Codable {
    /// English
    case english = "en"
    /// Japanese
    case japanese = "ja"
    /// Simplified Chinese
    case chinese = "zh-Hans"
    /// Traditional Chinese
    case chineseTraditional = "zh-Hant"
    /// Korean
    case korean = "ko"

    var localizedName: String {
        switch self {
        case .english:
            return L.Language.english
        case .japanese:
            return L.Language.japanese
        case .chinese:
            return L.Language.chinese
        case .chineseTraditional:
            return L.Language.chineseTraditional
        case .korean:
            return L.Language.korean
        }
    }
}

extension AppLanguage {
    /// Convert app language to the corresponding Locale
    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .japanese:
            return Locale(identifier: "ja_JP")
        case .chinese:
            return Locale(identifier: "zh_CN")
        case .chineseTraditional:
            return Locale(identifier: "zh_TW")
        case .korean:
            return Locale(identifier: "ko_KR")
        }
    }
}

// MARK: - User Settings

/// User settings management class
/// Manages all user configuration for the app, including authentication, display settings, language, etc.
/// Sensitive information (Organization ID and Session Key) is stored in Keychain
/// Non-sensitive settings are stored in UserDefaults
class UserSettings: ObservableObject {
    // MARK: - Singleton
    
    /// Singleton instance
    static let shared = UserSettings()
    
    // MARK: - Properties
    
    // Internal (not private) so extension files in this module can reach them.
    let defaults = UserDefaults.standard
    let keychain = KeychainManager.shared
    
    // MARK: - Multi-Account Support (v2.1.0)

    /// Account list (stored in Keychain)
    @Published var accounts: [Account] = [] {
        didSet {
            saveAccounts()
        }
    }

    /// Currently active account ID (stored in UserDefaults)
    @Published var currentAccountId: UUID? {
        didSet {
            if let id = currentAccountId {
                defaults.set(id.uuidString, forKey: "currentAccountId")
            } else {
                defaults.removeObject(forKey: "currentAccountId")
            }
        }
    }

    /// Currently active account
    var currentAccount: Account? {
        guard let id = currentAccountId else { return accounts.first }
        return accounts.first { $0.id == id }
    }

    /// Claude Session Key (computed property, points to current account)
    var sessionKey: String {
        get { currentAccount?.sessionKey ?? "" }
        set {
            guard let id = currentAccountId,
                  let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].sessionKey = newValue
        }
    }

    /// Claude Organization ID (computed property, points to current account)
    var organizationId: String {
        get { currentAccount?.organizationId ?? "" }
        set {
            guard let id = currentAccountId,
                  let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].organizationId = newValue
        }
    }

    // MARK: - Non-Sensitive Settings (stored in UserDefaults)

    /// Organization list (kept for backward compatibility, now deprecated)
    /// Since v2.1.0, organization info is included in Account
    @Published var organizations: [Organization] = [] {
        didSet {
            saveOrganizations()
        }
    }
    
    /// Menu bar icon display mode
    @Published var iconDisplayMode: IconDisplayMode {
        didSet {
            defaults.set(iconDisplayMode.rawValue, forKey: "iconDisplayMode")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    /// Whether to show percentage numbers inside menu bar icons
    @Published var showIconNumbers: Bool {
        didSet {
            defaults.set(showIconNumbers, forKey: "showIconNumbers")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Menu bar icon style mode
    @Published var iconStyleMode: IconStyleMode {
        didSet {
            defaults.set(iconStyleMode.rawValue, forKey: "iconStyleMode")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    /// Refresh mode (smart/fixed)
    @Published var refreshMode: RefreshMode {
        didSet {
            defaults.set(refreshMode.rawValue, forKey: "refreshMode")
            NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
        }
    }
    
    /// Data refresh interval (seconds) - only used in fixed mode
    @Published var refreshInterval: Int {
        didSet {
            defaults.set(refreshInterval, forKey: "refreshInterval")
            NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
        }
    }
    
    /// App interface language
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    /// App appearance mode
    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Time format preference
    @Published var timeFormatPreference: TimeFormatPreference {
        didSet {
            defaults.set(timeFormatPreference.rawValue, forKey: "timeFormatPreference")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Display mode (smart display/custom display)
    @Published var displayMode: DisplayMode {
        didSet {
            defaults.set(displayMode.rawValue, forKey: "displayMode")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Custom display limit type set (only used in custom mode)
    @Published var customDisplayTypes: Set<LimitType> {
        didSet {
            let rawValues = customDisplayTypes.map { $0.rawValue }
            defaults.set(rawValues, forKey: "customDisplayTypes")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// First launch flag
    @Published var isFirstLaunch: Bool {
        didSet {
            defaults.set(isFirstLaunch, forKey: "isFirstLaunch")
        }
    }
    
    /// Whether usage notifications are enabled
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    /// Launch at login setting
    @Published var launchAtLogin: Bool {
        didSet {
            // Do not trigger enable/disable during sync, to avoid infinite loop
            guard !isSyncingLaunchStatus else { return }

            if launchAtLogin {
                enableLaunchAtLogin()
            } else {
                disableLaunchAtLogin()
            }
        }
    }
    
    /// Launch at login status (for UI display)
    @Published var launchAtLoginStatus: SMAppService.Status = .notRegistered

    /// Flag to prevent recursive calls during launch-at-login sync.
    /// Internal so the LaunchAtLogin extension can flip it.
    var isSyncingLaunchStatus: Bool = false

    // MARK: - Debug Mode (only available in Debug builds)

    #if DEBUG
    /// Whether debug mode is enabled (simulates different data scenarios)
    @Published var debugModeEnabled: Bool {
        didSet {
            defaults.set(debugModeEnabled, forKey: "debugModeEnabled")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug scenario type
    @Published var debugScenario: DebugScenario {
        didSet {
            defaults.set(debugScenario.rawValue, forKey: "debugScenario")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug 5-hour limit percentage (0-100)
    @Published var debugFiveHourPercentage: Double {
        didSet {
            defaults.set(debugFiveHourPercentage, forKey: "debugFiveHourPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug 7-day limit percentage (0-100)
    @Published var debugSevenDayPercentage: Double {
        didSet {
            defaults.set(debugSevenDayPercentage, forKey: "debugSevenDayPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Opus limit percentage (0-100)
    @Published var debugOpusPercentage: Double {
        didSet {
            defaults.set(debugOpusPercentage, forKey: "debugOpusPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Sonnet limit percentage (0-100)
    @Published var debugSonnetPercentage: Double {
        didSet {
            defaults.set(debugSonnetPercentage, forKey: "debugSonnetPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Extra Usage enabled state
    @Published var debugExtraUsageEnabled: Bool {
        didSet {
            defaults.set(debugExtraUsageEnabled, forKey: "debugExtraUsageEnabled")
        }
    }

    /// Debug Extra Usage amount used (USD)
    @Published var debugExtraUsageUsed: Double {
        didSet {
            defaults.set(debugExtraUsageUsed, forKey: "debugExtraUsageUsed")
        }
    }

    /// Debug Extra Usage total limit (USD)
    @Published var debugExtraUsageLimit: Double {
        didSet {
            defaults.set(debugExtraUsageLimit, forKey: "debugExtraUsageLimit")
        }
    }

    /// Debug Extra Usage percentage (0-100), syncs the used value
    @Published var debugExtraUsagePercentage: Double {
        didSet {
            defaults.set(debugExtraUsagePercentage, forKey: "debugExtraUsagePercentage")
            // Sync update the used value
            debugExtraUsageUsed = debugExtraUsageLimit * (debugExtraUsagePercentage / 100.0)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Whether to show all shape icons individually in menu bar (debug, for screenshots)
    @Published var debugShowAllShapesIndividually: Bool {
        didSet {
            defaults.set(debugShowAllShapesIndividually, forKey: "debugShowAllShapesIndividually")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Whether to keep the detail window always open (debug, for recording animations)
    @Published var debugKeepDetailWindowOpen: Bool {
        didSet {
            defaults.set(debugKeepDetailWindowOpen, forKey: "debugKeepDetailWindowOpen")
        }
    }

    /// Debug scenario enum
    enum DebugScenario: String, CaseIterable {
        case realData = "real"              // Real API data
        case fiveHourOnly = "five_hour"     // 5-hour limit only
        case sevenDayOnly = "seven_day"     // 7-day limit only
        case both = "both"                  // Both limits
        case allFive = "all_five"           // All 5 limit types (v2.0 test)

        var displayName: String {
            switch self {
            case .realData:
                return "Real Data"
            case .fiveHourOnly:
                return "5-Hour Limit Only"
            case .sevenDayOnly:
                return "7-Day Limit Only"
            case .both:
                return "Both Limits"
            case .allFive:
                return "All 5 Limit Types"
            }
        }
    }
    #endif

    // MARK: - Smart Mode Internal State (not persisted)
    
    /// Last detected percentage (used to detect changes)
    var lastUtilization: Double?
    
    /// Consecutive unchanged count
    var unchangedCount: Int = 0
    
    /// Current monitoring mode (used in smart mode)
    var currentMonitoringMode: MonitoringMode = .active
    
    // MARK: - Initialization
    
    /// Detect system language and map to app-supported language
    /// - Returns: AppLanguage that best matches the system language
    private static func detectSystemLanguage() -> AppLanguage {
        let systemLanguage = Locale.preferredLanguages.first ?? "en"

        // Match app-supported languages by system language prefix
        if systemLanguage.hasPrefix("zh-Hans") {
            return .chinese
        } else if systemLanguage.hasPrefix("zh-Hant") || systemLanguage.hasPrefix("zh-HK") || systemLanguage.hasPrefix("zh-TW") {
            return .chineseTraditional
        } else if systemLanguage.hasPrefix("ja") {
            return .japanese
        } else if systemLanguage.hasPrefix("ko") {
            return .korean
        } else {
            return .english  // Default to English
        }
    }
    
    /// Private initializer (singleton pattern)
    /// Loads sensitive info from Keychain and other settings from UserDefaults
    private init() {
        // MARK: - Load Multi-Account Data (v2.1.0)

        // Load account list from Keychain (using local variables to avoid initialization order issues)
        var loadedAccounts = keychain.loadAccounts() ?? []
        var loadedCurrentAccountId: UUID? = nil

        // Load current account ID
        if let idString = defaults.string(forKey: "currentAccountId"),
           let id = UUID(uuidString: idString) {
            loadedCurrentAccountId = id
        } else if let firstAccount = loadedAccounts.first {
            // If no current account ID saved, default to the first account
            loadedCurrentAccountId = firstAccount.id
        }

        // MARK: - Data Migration (v2.0.x to v2.1.0 multi-account)

        // Check if migration from single-account to multi-account is needed
        if loadedAccounts.isEmpty && !defaults.bool(forKey: "multiAccountMigrated") {
            // Attempt to migrate from old single-account data
            let oldSessionKey = keychain.loadSessionKey() ?? ""
            let oldOrgId = defaults.string(forKey: "organizationId") ?? ""

            if !oldSessionKey.isEmpty && !oldOrgId.isEmpty {
                Logger.settings.notice("[Migration] Migrating single account to multi-account system")

                // Get organization name (if cached)
                let cachedOrgs = Self.loadOrganizations(from: defaults)
                let orgName = cachedOrgs.first { $0.uuid == oldOrgId }?.name ?? "Account 1"

                // Create the first account
                let migratedAccount = Account(
                    sessionKey: oldSessionKey,
                    organizationId: oldOrgId,
                    organizationName: orgName
                )
                loadedAccounts = [migratedAccount]
                loadedCurrentAccountId = migratedAccount.id

                // Clean up old single-account data
                keychain.deleteSessionKey()
                defaults.removeObject(forKey: "organizationId")

                Logger.settings.notice("[Migration] Multi-account migration completed")
            }

            defaults.set(true, forKey: "multiAccountMigrated")
        }

        // Set accounts and currentAccountId
        self.accounts = loadedAccounts
        self.currentAccountId = loadedCurrentAccountId

        // MARK: - Legacy Migration (v1.x to v2.0.0, backward compatible)

        // Migrate Organization ID from Keychain to UserDefaults (legacy migration, now included in multi-account migration above)
        if !defaults.bool(forKey: "organizationIdMigrated") {
            if let oldOrgId = keychain.loadOrganizationId(), !oldOrgId.isEmpty {
                Logger.settings.notice("[Migration] Found Organization ID in old Keychain location")
                keychain.deleteOrganizationId()
            }
            defaults.set(true, forKey: "organizationIdMigrated")
        }

        // MARK: - Load Non-Sensitive Settings from UserDefaults

        // Load cached organization list (backward compatible)
        self.organizations = Self.loadOrganizations(from: defaults)
        
        if let modeString = defaults.string(forKey: "iconDisplayMode"),
           let mode = IconDisplayMode(rawValue: modeString) {
            self.iconDisplayMode = mode
        } else {
            self.iconDisplayMode = .percentageOnly
        }
        
        self.showIconNumbers = defaults.bool(forKey: "showIconNumbers")

        if let styleString = defaults.string(forKey: "iconStyleMode"),
           let style = IconStyleMode(rawValue: styleString) {
            self.iconStyleMode = style
        } else {
            self.iconStyleMode = .colorTranslucent  // Default: color translucent
        }
        
        // Load refresh mode, default to smart mode
        if let modeString = defaults.string(forKey: "refreshMode"),
           let mode = RefreshMode(rawValue: modeString) {
            self.refreshMode = mode
        } else {
            self.refreshMode = .smart
        }
        
        let savedRefreshInterval = defaults.integer(forKey: "refreshInterval")
        self.refreshInterval = savedRefreshInterval > 0 ? savedRefreshInterval : 180 // Default: 3 minutes
        
        if let langString = defaults.string(forKey: "language"),
           let lang = AppLanguage(rawValue: langString) {
            self.language = lang
        } else {
            // Use system language on first launch
            self.language = Self.detectSystemLanguage()
        }

        // Load appearance mode, default to follow system
        if let appearanceString = defaults.string(forKey: "appearance"),
           let loadedAppearance = AppAppearance(rawValue: appearanceString) {
            self.appearance = loadedAppearance
        } else {
            self.appearance = .system
        }

        // Load time format preference, default to follow system
        if let timeFormatString = defaults.string(forKey: "timeFormatPreference"),
           let timeFormat = TimeFormatPreference(rawValue: timeFormatString) {
            self.timeFormatPreference = timeFormat
        } else {
            self.timeFormatPreference = .system
        }

        // Load display mode, default to smart mode
        if let modeString = defaults.string(forKey: "displayMode"),
           let mode = DisplayMode(rawValue: modeString) {
            self.displayMode = mode
        } else {
            self.displayMode = .smart
        }

        // Load custom display types, default to 5-hour and 7-day limits
        if let rawValues = defaults.array(forKey: "customDisplayTypes") as? [String] {
            self.customDisplayTypes = Set(rawValues.compactMap { LimitType(rawValue: $0) })
        } else {
            self.customDisplayTypes = [.fiveHour, .sevenDay]
        }

        // Check if this is the first launch (first launch if credentials were never saved)
        if !defaults.bool(forKey: "hasLaunched") {
            self.isFirstLaunch = true
            defaults.set(true, forKey: "hasLaunched")
        } else {
            self.isFirstLaunch = false
        }
        
        // Load notification settings, default to enabled
        self.notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true

        // Initialize launch at login setting
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")

        // MARK: - Initialize Debug Mode Settings

        #if DEBUG
        self.debugModeEnabled = defaults.bool(forKey: "debugModeEnabled")
        self.debugScenario = DebugScenario(
            rawValue: defaults.string(forKey: "debugScenario") ?? "real"
        ) ?? .realData
        self.debugFiveHourPercentage = defaults.object(forKey: "debugFiveHourPercentage") as? Double ?? 55.0
        self.debugSevenDayPercentage = defaults.object(forKey: "debugSevenDayPercentage") as? Double ?? 66.0
        self.debugOpusPercentage = defaults.object(forKey: "debugOpusPercentage") as? Double ?? 77.0
        self.debugSonnetPercentage = defaults.object(forKey: "debugSonnetPercentage") as? Double ?? 88.0
        self.debugExtraUsageEnabled = defaults.object(forKey: "debugExtraUsageEnabled") as? Bool ?? true
        self.debugExtraUsageUsed = defaults.object(forKey: "debugExtraUsageUsed") as? Double ?? 30.50
        self.debugExtraUsageLimit = defaults.object(forKey: "debugExtraUsageLimit") as? Double ?? 50.0
        self.debugExtraUsagePercentage = defaults.object(forKey: "debugExtraUsagePercentage") as? Double ?? 61.0
        self.debugShowAllShapesIndividually = defaults.bool(forKey: "debugShowAllShapesIndividually")
        self.debugKeepDetailWindowOpen = defaults.bool(forKey: "debugKeepDetailWindowOpen")
        #endif

        // Sync actual system state
        syncLaunchAtLoginStatus()

        // Apply appearance settings to NSApp
        applyAppearance()

        // Listen for system appearance changes, auto-update in "Follow System" mode
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.appearance == .system else { return }
            self.applyAppearance()
        }
    }
    
    // MARK: - Computed Properties

    /// Current app Locale (based on user-selected language)
    var appLocale: Locale {
        return language.locale
    }

    /// Check if authentication credentials are configured
    /// - Returns: true if both Organization ID and Session Key are non-empty
    var hasValidCredentials: Bool {
        return !organizationId.isEmpty && !sessionKey.isEmpty
    }

    /// Validate Organization ID format
    /// - Parameter id: Organization ID to validate
    /// - Returns: true if the format is valid (UUID format)
    func isValidOrganizationId(_ id: String) -> Bool {
        // Organization ID should be in UUID format
        let uuidRegex = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", uuidRegex)
        return predicate.evaluate(with: id)
    }

    /// Validate Session Key format
    /// - Parameter key: Session Key to validate
    /// - Returns: true if the format is valid
    func isValidSessionKey(_ key: String) -> Bool {
        // Session Key should be non-empty and have a reasonable length
        // Typical session key length is between 20-200 characters
        return !key.isEmpty && key.count >= 20 && key.count <= 500
    }
    
    /// Get the currently effective refresh interval (seconds)
    /// - Returns: Smart mode returns current monitoring mode interval, fixed mode returns user-set interval
    var effectiveRefreshInterval: Int {
        switch refreshMode {
        case .smart:
            return currentMonitoringMode.interval
        case .fixed:
            return refreshInterval
        }
    }
    
    // MARK: - Public Methods
    
    /// Apply current appearance settings to NSApp globally
    /// Note: For menu bar apps (accessory activation policy), NSApp.appearance = nil cannot reliably follow system appearance
    /// Therefore in "Follow System" mode we actively read the system appearance and set it explicitly
    func applyAppearance() {
        DispatchQueue.main.async {
            switch self.appearance {
            case .system:
                let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
                NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Reset to default settings
    /// Only resets non-sensitive settings, does not affect authentication credentials
    func resetToDefaults() {
        appearance = .system
        iconDisplayMode = .percentageOnly
        showIconNumbers = false
        iconStyleMode = .colorTranslucent
        refreshMode = .smart
        refreshInterval = 180  // Fixed mode default: 3 minutes
        language = Self.detectSystemLanguage()
        timeFormatPreference = .system
        displayMode = .smart
        customDisplayTypes = [.fiveHour, .sevenDay, .extraUsage]
        notificationsEnabled = true

        // Reset smart mode state
        lastUtilization = nil
        unchangedCount = 0
        currentMonitoringMode = .active
    }
    
    /// Clear all authentication credentials
    /// Delete Organization ID and Session Key from Keychain
    func clearCredentials() {
        keychain.deleteCredentials()
        organizationId = ""
        sessionKey = ""
        Logger.settings.notice("Cleared all credentials")
    }
    
    /// Update smart monitoring mode
    /// Intelligently adjusts refresh frequency based on usage percentage changes
    /// - Parameter currentUtilization: Current usage percentage
    // MARK: - Organization Management (backward compatible)

    /// Save organization list to UserDefaults (backward compatible)
    private func saveOrganizations() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(organizations) {
            defaults.set(data, forKey: "cachedOrganizations")
        }
    }

    /// Load organization list from UserDefaults (backward compatible)
    /// - Parameter defaults: UserDefaults instance
    /// - Returns: Organization list, returns empty array if loading fails
    private static func loadOrganizations(from defaults: UserDefaults) -> [Organization] {
        guard let data = defaults.data(forKey: "cachedOrganizations") else {
            return []
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode([Organization].self, from: data)) ?? []
    }

    // MARK: - Display Logic Helper Methods (v2.0)

    /// Get the list of limit types that should currently be displayed
    /// - Parameter usageData: Usage data
    /// - Returns: Array of limit types to display, in display order
    func getActiveDisplayTypes(usageData: UsageData?) -> [LimitType] {
        switch displayMode {
        case .smart:
            // Smart mode: Show all types that have data
            guard let data = usageData else {
                return []
            }

            var types: [LimitType] = []

            // In canonical order: fiveHour -> sevenDay -> extraUsage -> opus -> sonnet
            if data.fiveHour != nil {
                types.append(.fiveHour)
            }
            if data.sevenDay != nil {
                types.append(.sevenDay)
            }
            if data.extraUsage?.enabled == true {
                types.append(.extraUsage)
            }
            if data.opus != nil {
                types.append(.opusWeekly)
            }
            if data.sonnet != nil {
                types.append(.sonnetWeekly)
            }

            return types

        case .custom:
            // Custom mode: Sort by user selection, show regardless of whether data exists
            let orderedTypes: [LimitType] = [.fiveHour, .sevenDay, .extraUsage, .opusWeekly, .sonnetWeekly]
            return orderedTypes.filter { customDisplayTypes.contains($0) }
        }
    }

    /// Determine if the current configuration can use the colored theme
    /// - Returns: true means the colored theme can be used
    func canUseColoredTheme(usageData: UsageData?) -> Bool {
        let activeTypes = getActiveDisplayTypes(usageData: usageData)

        // All limit types now support colored display
        // Colored theme can be used as long as there are icons
        return !activeTypes.isEmpty
    }
}

// MARK: - Notification Names

/// Settings-related notification name extensions
// Note: Notification names have been migrated to NotificationNames.swift
// Import kept for backward compatibility
