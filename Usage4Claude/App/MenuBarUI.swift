//
//  MenuBarUI.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit
import Combine

/// Menu bar UI manager
/// Manages the menu bar icon, popover, menu creation, and icon rendering
/// Contains the complete UI layer logic, implementing all UI-related responsibilities extracted from MenuBarManager
class MenuBarUI {

    // MARK: - UI Components

    /// System menu bar status item
    private(set) var statusItem: NSStatusItem!
    /// Detail popover
    private(set) var popover: NSPopover!
    /// Popover close observer - monitors mouse click events
    private var popoverCloseObserver: Any?
    /// App resign active observer - used to close popover when app loses focus
    private var appResignActiveObserver: NSObjectProtocol?

    // MARK: - Icon Cache

    /// Icon cache: key is "mode_style_percentage_appearance", value is the cached icon
    private var iconCache: [String: NSImage] = [:]
    /// Maximum cache entries
    private let maxCacheSize = 50

    // MARK: - Settings Reference

    /// User settings instance
    private let settings = UserSettings.shared

    // MARK: - Icon Renderer

    /// Icon renderer - handles all icon drawing logic
    private let iconRenderer = MenuBarIconRenderer()

    // MARK: - Initialization

    init() {
        setupStatusItem()
        setupPopover()
    }

    // MARK: - Status Item Setup

    /// Initialize the menu bar status item
    /// Set up click event handling
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Initial icon
            button.image = createSimpleCircleIcon()
        }
    }

    /// Configure the status item click handler
    /// - Parameters:
    ///   - target: Target object
    ///   - action: Click response method
    func configureClickHandler(target: AnyObject?, action: Selector) {
        guard let button = statusItem.button else { return }
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = target
    }

    // MARK: - Popover Setup

    /// Initialize the popover
    /// Set up window size and appearance
    private func setupPopover() {
        popover = NSPopover()
        // Fixed size to avoid layout jumps
        popover.contentSize = NSSize(width: 280, height: 240)
        // Set behavior, allowing custom appearance
        popover.behavior = .semitransient
    }

    /// Set the popover content view
    /// - Parameter contentView: SwiftUI view
    func setPopoverContent<Content: View>(_ contentView: Content) {
        let hostingController = NSHostingController(rootView: contentView)
        popover.contentViewController = hostingController
    }

    // MARK: - Popover Control

    /// Open the popover
    /// - Parameter button: Menu bar button
    func openPopover(relativeTo button: NSStatusBarButton) {
        // Activate the app so popover can properly respond to focus changes
        NSApp.activate(ignoringOtherApps: true)

        // Popover is attached to the system status bar, inheriting status bar appearance instead of NSApp.appearance
        // Must be explicitly set each time it opens to stay in sync with user preferences
        switch settings.appearance {
        case .system:
            let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            popover.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        case .light:
            popover.appearance = NSAppearance(named: .aqua)
        case .dark:
            popover.appearance = NSAppearance(named: .darkAqua)
        }

        // Show popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Configure popover window
        configurePopoverWindow()

        // Set up observers
        setupPopoverCloseObserver()
        setupAppResignActiveObserver()
    }

    /// Configure popover window properties
    private func configurePopoverWindow() {
        guard let popoverWindow = popover.contentViewController?.view.window else { return }

        // Set window level to ensure it appears above other windows
        popoverWindow.level = .popUpMenu

        // Make the window key window, showing focus state
        popoverWindow.makeKey()

        #if DEBUG
        // Set background color based on debug toggle
        if settings.debugKeepDetailWindowOpen {
            // When enabled: Solid white opaque background
            popoverWindow.backgroundColor = NSColor.white
            popoverWindow.isOpaque = true
            // Set the content view's background
            if let contentView = popover.contentViewController?.view {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.white.cgColor
            }
        } else {
            // When disabled: Use default transparent background
            popoverWindow.backgroundColor = NSColor.clear
            popoverWindow.isOpaque = false
            // Restore the content view's transparent background
            if let contentView = popover.contentViewController?.view {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
        #endif
    }

    /// Close the popover
    func closePopover() {
        // Ensure popover is closed
        if popover.isShown {
            popover.performClose(nil)
        }

        // Remove event observers
        removePopoverCloseObserver()
        removeAppResignActiveObserver()
    }

    /// Set up popover outside click observer
    /// Automatically closes when clicking outside the popover
    private func setupPopoverCloseObserver() {
        // Remove old observer first to prevent accumulation
        removePopoverCloseObserver()

        // Use global event monitor to listen for mouse click events
        popoverCloseObserver = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }

            #if DEBUG
            // Debug mode: If "Keep detail window open" is enabled, do not auto-close
            if UserSettings.shared.debugKeepDetailWindowOpen {
                return
            }
            #endif

            self.closePopover()
        }
    }

    /// Remove popover close observer
    private func removePopoverCloseObserver() {
        if let observer = popoverCloseObserver {
            NSEvent.removeMonitor(observer)
            popoverCloseObserver = nil
        }
    }

    /// Set up app resign active observer
    /// Automatically closes popover when the app loses focus
    private func setupAppResignActiveObserver() {
        // Remove old observer first to prevent accumulation
        removeAppResignActiveObserver()

        // Listen for app resign active events
        appResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }

            #if DEBUG
            // Debug mode: If "Keep detail window open" is enabled, do not auto-close
            if UserSettings.shared.debugKeepDetailWindowOpen {
                return
            }
            #endif

            self.closePopover()
        }
    }

    /// Remove app resign active observer
    private func removeAppResignActiveObserver() {
        if let observer = appResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignActiveObserver = nil
        }
    }

    // MARK: - Menu Management

    /// Create the standard menu
    /// Used for the right-click menu and the three-dot menu in the popover
    /// - Parameters:
    ///   - hasUpdate: Whether an update is available
    ///   - shouldShowBadge: Whether to show the update badge
    ///   - target: Menu item target object
    /// - Returns: Configured NSMenu instance
    func createStandardMenu(hasUpdate: Bool, shouldShowBadge: Bool, target: AnyObject?) -> NSMenu {
        let menu = NSMenu()

        // Account selection submenu (only shown when there are multiple accounts)
        if settings.accounts.count > 1 {
            let accountSubmenu = createAccountSubmenu(target: target)
            let currentAccountName = settings.currentAccountName ?? L.Menu.account
            let menuTitle = "\(L.Menu.accountPrefix) \(currentAccountName)"

            let accountItem = NSMenuItem(
                title: menuTitle,
                action: nil,
                keyEquivalent: ""
            )
            accountItem.submenu = accountSubmenu
            setMenuItemIcon(accountItem, systemName: "person.2")
            menu.addItem(accountItem)
            menu.addItem(NSMenuItem.separator())
        }

        // General settings
        let generalItem = NSMenuItem(
            title: L.Menu.generalSettings,
            action: #selector(MenuBarManager.openGeneralSettings),
            keyEquivalent: ","
        )
        generalItem.target = target
        setMenuItemIcon(generalItem, systemName: "gearshape")
        menu.addItem(generalItem)

        // Authentication
        let authItem = NSMenuItem(
            title: L.Menu.authSettings,
            action: #selector(MenuBarManager.openAuthSettings),
            keyEquivalent: "a"
        )
        authItem.target = target
        authItem.keyEquivalentModifierMask = [.command, .shift] as NSEvent.ModifierFlags
        setMenuItemIcon(authItem, systemName: "key.horizontal")
        menu.addItem(authItem)

        // Check for updates
        let updateItem = NSMenuItem(
            title: "",
            action: #selector(MenuBarManager.checkForUpdates),
            keyEquivalent: "u"
        )
        updateItem.target = target

        // Set different styles based on whether an update is available
        if hasUpdate {
            // Update available: Show rainbow text
            let baseText = L.Menu.checkUpdates
            let highlightText = L.Update.Notification.badgeMenu
            let title = "\(baseText)\t\(highlightText)"

            let highlightLocation = baseText.utf16.count + 1
            let highlightLength = highlightText.utf16.count
            let highlightRange = NSRange(location: highlightLocation, length: highlightLength)

            let attributedTitle = createRainbowText(title, highlightRange: highlightRange)
            updateItem.attributedTitle = attributedTitle

            // Badge icon: Only shown when user has not acknowledged
            if shouldShowBadge {
                if let badgeImage = createBadgeIcon() {
                    updateItem.image = badgeImage
                }
            } else {
                setMenuItemIcon(updateItem, systemName: "arrow.triangle.2.circlepath")
            }
        } else {
            // No update: Normal style
            updateItem.title = L.Menu.checkUpdates
            setMenuItemIcon(updateItem, systemName: "arrow.triangle.2.circlepath")
        }

        menu.addItem(updateItem)

        // About
        let aboutItem = NSMenuItem(
            title: L.Menu.about,
            action: #selector(MenuBarManager.openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = target
        setMenuItemIcon(aboutItem, systemName: "info.circle")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Visit Claude usage
        let webItem = NSMenuItem(
            title: L.Menu.webUsage,
            action: #selector(MenuBarManager.openWebUsage),
            keyEquivalent: "w"
        )
        webItem.target = target
        webItem.keyEquivalentModifierMask = [.command, .shift] as NSEvent.ModifierFlags
        setMenuItemIcon(webItem, systemName: "safari")
        menu.addItem(webItem)

        // Buy Me A Coffee
        let coffeeItem = NSMenuItem(
            title: L.Menu.coffee,
            action: #selector(MenuBarManager.openCoffee),
            keyEquivalent: ""
        )
        coffeeItem.target = target
        setMenuItemIcon(coffeeItem, systemName: "cup.and.saucer")
        menu.addItem(coffeeItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: L.Menu.quit,
            action: #selector(MenuBarManager.quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = target
        setMenuItemIcon(quitItem, systemName: "power")
        menu.addItem(quitItem)

        return menu
    }

    /// Set icon for a menu item
    /// - Parameters:
    ///   - item: Menu item
    ///   - systemName: SF Symbol icon name
    private func setMenuItemIcon(_ item: NSMenuItem, systemName: String) {
        if let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            item.image = image
        }
    }

    /// Create the account selection submenu
    /// - Parameter target: Menu item target object
    /// - Returns: Account selection submenu
    private func createAccountSubmenu(target: AnyObject?) -> NSMenu {
        let submenu = NSMenu()

        for account in settings.accounts {
            let item = NSMenuItem(
                title: account.displayName,
                action: #selector(MenuBarManager.switchAccount(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = account

            // Show checkmark for the currently selected account
            if account.id == settings.currentAccountId {
                item.state = .on
            }

            submenu.addItem(item)
        }

        return submenu
    }

    /// Create a rainbow text NSAttributedString
    /// - Parameters:
    ///   - text: Complete text
    ///   - highlightRange: Range to highlight
    /// - Returns: Attributed string with rainbow effect
    private func createRainbowText(_ text: String, highlightRange: NSRange) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)

        let font = NSFont.menuFont(ofSize: 0)
        attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.utf16.count))

        let paragraphStyle = NSMutableParagraphStyle()
        let nsText = text as NSString
        let baseText = nsText.substring(to: highlightRange.location)
        let baseTextSize = (baseText as NSString).size(withAttributes: [.font: font])

        let tabLocation = baseTextSize.width + 20
        let tabStop = NSTextTab(textAlignment: .left, location: tabLocation, options: [:])
        paragraphStyle.tabStops = [tabStop]

        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: text.utf16.count))

        let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
        let highlightText = nsText.substring(with: highlightRange) as String

        var utf16Offset = 0
        for (index, char) in highlightText.enumerated() {
            let charString = String(char)
            let charUtf16Count = charString.utf16.count
            let colorIndex = index % colors.count

            attributedString.addAttribute(
                .foregroundColor,
                value: colors[colorIndex],
                range: NSRange(location: highlightRange.location + utf16Offset, length: charUtf16Count)
            )

            utf16Offset += charUtf16Count
        }

        return attributedString
    }

    /// Create a badge icon (red dot)
    /// - Returns: Icon with badge
    private func createBadgeIcon() -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        if let icon = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
            icon.size = NSSize(width: 12, height: 12)
            icon.draw(in: NSRect(x: 0, y: 2, width: 12, height: 12))
        }

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 6, height: 6)).fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Icon Management

    /// Update the menu bar icon
    /// - Parameters:
    ///   - usageData: Usage data
    ///   - hasUpdate: Whether an update is available
    ///   - shouldShowBadge: Whether to show the update badge
    func updateMenuBarIcon(usageData: UsageData?, hasUpdate: Bool, shouldShowBadge: Bool) {
        guard let button = statusItem.button else { return }

        // Determine whether to actually show the badge
        let showBadge = hasUpdate && shouldShowBadge

        // Generate cache key
        let cacheKey = generateCacheKey(usageData: usageData, hasUpdate: showBadge)

        // Try to get from cache
        if let cachedImage = iconCache[cacheKey] {
            button.image = cachedImage
            return
        }

        // Cache miss, create new icon using IconRenderer
        let icon = iconRenderer.createIcon(
            usageData: usageData,
            hasUpdate: showBadge,
            button: button
        )

        // Store in cache
        if iconCache.count >= maxCacheSize {
            iconCache.removeValue(forKey: iconCache.keys.first!)
        }
        iconCache[cacheKey] = icon

        button.image = icon
    }

    /// Clear the icon cache
    func clearIconCache() {
        iconCache.removeAll()
    }

    /// Generate an icon cache key
    /// - Parameters:
    ///   - usageData: Usage data
    ///   - hasUpdate: Whether there is an update badge
    /// - Returns: Cache key string
    private func generateCacheKey(usageData: UsageData?, hasUpdate: Bool) -> String {
        guard let data = usageData else {
            return "no_data_\(settings.iconStyleMode.rawValue)_\(hasUpdate)"
        }

        var key = "\(settings.iconDisplayMode.rawValue)_\(settings.iconStyleMode.rawValue)_num\(settings.showIconNumbers)"

        // Include percentages for all limit types to ensure shape icons are also correctly cached
        if let fiveHour = data.fiveHour {
            key += "_5h\(Int(fiveHour.percentage))"
        }
        if let sevenDay = data.sevenDay {
            key += "_7d\(Int(sevenDay.percentage))"
        }
        if let opus = data.opus {
            key += "_opus\(Int(opus.percentage))"
        }
        if let sonnet = data.sonnet {
            key += "_sonnet\(Int(sonnet.percentage))"
        }
        if let extraUsage = data.extraUsage, extraUsage.enabled, let percentage = extraUsage.percentage {
            key += "_extra\(Int(percentage))"
        }

        if hasUpdate {
            key += "_badge"
        }

        return key
    }

    // MARK: - Utility Icons

    /// Create a simple circle icon (fallback)
    /// Used to initialize the status bar button
    private func createSimpleCircleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 3, y: 3, width: 12, height: 12)
        let path = NSBezierPath(ovalIn: rect)

        NSColor.labelColor.setStroke()
        path.lineWidth = 2.0
        path.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Cleanup

    /// Clean up all resources
    func cleanup() {
        removePopoverCloseObserver()
        removeAppResignActiveObserver()

        if popover.isShown {
            popover.performClose(nil)
        }
    }

    deinit {
        cleanup()
    }
}
