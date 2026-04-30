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
    /// Used for the right-click menu and the three-dot menu in the popover.
    /// Sparkle owns the "update available" prompt now, so the menu doesn't
    /// surface that state — "Check for updates…" always renders the same way.
    /// - Parameter target: Menu item target object
    /// - Returns: Configured NSMenu instance
    func createStandardMenu(target: AnyObject?) -> NSMenu {
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

        // Check for updates (Sparkle owns the prompt — no badge needed here)
        let updateItem = NSMenuItem(
            title: L.Menu.checkUpdates,
            action: #selector(MenuBarManager.checkForUpdates),
            keyEquivalent: "u"
        )
        updateItem.target = target
        setMenuItemIcon(updateItem, systemName: "arrow.triangle.2.circlepath")
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

        // Bind ⌘1..⌘9 to the first nine accounts so heavy users can switch without
        // navigating the right-click menu chain. Tenth and beyond have no shortcut.
        for (index, account) in settings.accounts.enumerated() {
            let shortcut = (index < 9) ? String(index + 1) : ""
            let item = NSMenuItem(
                title: account.displayName,
                action: #selector(MenuBarManager.switchAccount(_:)),
                keyEquivalent: shortcut
            )
            item.target = target
            item.representedObject = account
            item.keyEquivalentModifierMask = [.command]

            // Show checkmark for the currently selected account
            if account.id == settings.currentAccountId {
                item.state = .on
            }

            submenu.addItem(item)
        }

        return submenu
    }

    // MARK: - Icon Management

    /// Update the menu bar icon based on the latest usage data.
    /// (No update-badge state — Sparkle owns that surface now.)
    func updateMenuBarIcon(usageData: UsageData?) {
        guard let button = statusItem.button else { return }

        let cacheKey = generateCacheKey(usageData: usageData)

        if let cachedImage = iconCache[cacheKey] {
            button.image = cachedImage
            return
        }

        let icon = iconRenderer.createIcon(usageData: usageData, button: button)

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

    /// Generate an icon cache key from the current display settings + usage data.
    private func generateCacheKey(usageData: UsageData?) -> String {
        guard let data = usageData else {
            return "no_data_\(settings.iconStyleMode.rawValue)"
        }

        var key = "\(settings.iconDisplayMode.rawValue)_\(settings.iconStyleMode.rawValue)_num\(settings.showIconNumbers)"

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
