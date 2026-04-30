//
//  MenuBarManager.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit
import Combine
import OSLog

/// Refresh state manager
/// Used to synchronize refresh state across views, supporting reactive updates
class RefreshState: ObservableObject {
    /// Whether a refresh is in progress
    @Published var isRefreshing = false
    /// Whether refresh is allowed (debounce control)
    @Published var canRefresh = true
    /// Notification message
    @Published var notificationMessage: String?
    /// Notification type
    @Published var notificationType: NotificationType = .loading
    
    /// Notification type
    enum NotificationType {
        case loading          // Rainbow loading animation
        case updateAvailable  // Rainbow text notification
    }
}

/// Menu bar manager
/// Coordinates the UI and data layers, manages the settings window
class MenuBarManager: ObservableObject {
    // MARK: - Properties

    /// UI manager
    private let ui = MenuBarUI()
    /// Data refresh manager
    private let dataManager = DataRefreshManager()
    /// Settings window
    private var settingsWindow: NSWindow?
    /// User settings instance
    @ObservedObject private var settings = UserSettings.shared
    /// Combine subscription set
    private var cancellables = Set<AnyCancellable>()
    /// Window close observer
    private var windowCloseObserver: NSObjectProtocol?
    /// Language change observer
    private var languageChangeObserver: NSObjectProtocol?

    /// Current usage data (synced from dataManager)
    @Published var usageData: UsageData?
    /// Loading state (synced from dataManager)
    @Published var isLoading = false
    /// Error message (synced from dataManager)
    @Published var errorMessage: String?
    /// Whether an update is available (synced from dataManager)
    @Published var hasAvailableUpdate = false
    /// Latest version number (synced from dataManager)
    @Published var latestVersion: String?
    /// Version number acknowledged by user (recorded after clicking check for updates)
    private var acknowledgedVersion: String?

    /// Refresh state manager (referenced from dataManager)
    var refreshState: RefreshState {
        return dataManager.refreshState
    }

    /// Whether to show the badge and notification (only when user has not acknowledged)
    var shouldShowUpdateBadge: Bool {
        guard hasAvailableUpdate, let latest = latestVersion else { return false }
        return acknowledgedVersion != latest
    }

    // MARK: - Initialization

    init() {
        ui.configureClickHandler(target: self, action: #selector(handleClick))
        setupDataBindings()
        setupSettingsObservers()
    }

    /// Set up data bindings
    /// Synchronize dataManager state to MenuBarManager
    private func setupDataBindings() {
        dataManager.$usageData
            .sink { [weak self] data in
                self?.usageData = data
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        dataManager.$isLoading
            .assign(to: &$isLoading)

        dataManager.$errorMessage
            .assign(to: &$errorMessage)

        dataManager.$hasAvailableUpdate
            .sink { [weak self] hasUpdate in
                self?.hasAvailableUpdate = hasUpdate
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        dataManager.$latestVersion
            .assign(to: &$latestVersion)
    }
    
    /// Handle menu bar icon click event
    /// Left click toggles the popover, right click shows the menu
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            // If unable to get the current event, default to left click behavior
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// Show the right-click menu
    private func showMenu() {
        let menu = ui.createStandardMenu(hasUpdate: hasAvailableUpdate, shouldShowBadge: shouldShowUpdateBadge, target: self)
        ui.statusItem.menu = menu
        ui.statusItem.button?.performClick(nil)
        ui.statusItem.menu = nil
    }
    
    
    // MARK: - Menu Actions
    
    @objc func openWebUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    /// Handle menu actions
    /// Close the popover and perform the corresponding action
    private func handleMenuAction(_ action: UsageDetailView.MenuAction) {
        switch action {
        case .refresh:
            // Handle manual refresh
            dataManager.handleManualRefresh()
        case .generalSettings:
            closePopover()
            openSettingsWindow(tab: 0)
        case .authSettings:
            closePopover()
            openSettingsWindow(tab: 1)
        case .checkForUpdates:
            closePopover()
            checkForUpdates()
        case .about:
            closePopover()
            openSettingsWindow(tab: 2)
        case .webUsage:
            closePopover()
            openWebUsage()
        case .quit:
            quitApp()
        }
    }
    
    /// Set up settings change observers
    /// Listen for settings changes, refresh interval changes, and other notifications
    private func setupSettingsObservers() {
        NotificationCenter.default.publisher(for: .settingsChanged)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Clear icon cache when settings change (display mode may have changed)
                self.ui.clearIconCache()

                // Update icon immediately, no waiting needed
                self.updateMenuBarIcon()

                #if DEBUG
                // In debug mode, refresh data immediately (no debounce)
                self.dataManager.fetchUsage()

                // If simulated update settings changed, reapply update state
                if self.settings.simulateUpdateAvailable {
                    self.hasAvailableUpdate = true
                    self.latestVersion = "2.0.0"
                    Logger.menuBar.debug("Simulated update enabled")
                } else {
                    self.hasAvailableUpdate = false
                    self.latestVersion = ""
                    Logger.menuBar.debug("Simulated update disabled")
                }
                #endif
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .refreshIntervalChanged)
            .sink { [weak self] _ in
                // Restart data refresh timer
                self?.dataManager.stopRefreshing()
                self?.dataManager.startRefreshing()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .openSettings)
            .sink { [weak self] notification in
                let tab = notification.userInfo?["tab"] as? Int ?? 0
                self?.openSettingsWindow(tab: tab)
            }
            .store(in: &cancellables)

        // Listen for account change notifications
        NotificationCenter.default.publisher(for: .accountChanged)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Logger.menuBar.notice("Account switched; refreshing data")
                // Clear icon cache to ensure re-rendering when new data arrives
                self.ui.clearIconCache()
                // Refresh data immediately
                self.dataManager.fetchUsage()
                // Update menu bar icon
                self.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        // Session expired → present the WebLogin window so the user can re-authenticate
        // without having to navigate to Auth Settings manually. DataRefreshManager throttles
        // this to once per expiry, but WebLoginWindowManager additionally dedupes if the
        // window is already on screen.
        NotificationCenter.default.publisher(for: .sessionExpired)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                Logger.menuBar.notice("Session expired — presenting WebLogin")
                WebLoginWindowManager.shared.showLoginWindow()
            }
            .store(in: &cancellables)
    }

    // MARK: - Popover Management

    /// Toggle the popover display state
    @objc func togglePopover() {
        guard let button = ui.statusItem.button else { return }

        if ui.popover.isShown {
            closePopover()
        } else {
            openPopover(relativeTo: button)
        }
    }

    /// Open the popover
    private func openPopover(relativeTo button: NSStatusBarButton) {
        // Smart data refresh
        dataManager.refreshOnPopoverOpen()

        // Show update notification (if available)
        showUpdateNotificationIfNeeded()

        // Create and set the content view
        ui.setPopoverContent(UsageDetailView(
            usageData: Binding(
                get: { self.usageData },
                set: { self.usageData = $0 }
            ),
            errorMessage: Binding(
                get: { self.errorMessage },
                set: { self.errorMessage = $0 }
            ),
            refreshState: self.refreshState,
            onMenuAction: { [weak self] action in
                self?.handleMenuAction(action)
            },
            hasAvailableUpdate: Binding(
                get: { self.hasAvailableUpdate },
                set: { self.hasAvailableUpdate = $0 }
            ),
            shouldShowUpdateBadge: Binding(
                get: { self.shouldShowUpdateBadge },
                set: { _ in }
            )
        ))

        // Open popover
        ui.openPopover(relativeTo: button)

        // Start refresh timer
        startPopoverRefreshTimer()
    }

    /// Show update notification (if needed)
    private func showUpdateNotificationIfNeeded() {
        guard shouldShowUpdateBadge else { return }

        dataManager.refreshState.notificationMessage = L.Update.Notification.available
        dataManager.refreshState.notificationType = .updateAvailable

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dataManager.refreshState.notificationMessage = nil
        }
    }

    /// Close the popover
    private func closePopover() {
        ui.closePopover()

        // Clean up refresh timer
        dataManager.stopPopoverRefreshTimer()
    }

    /// Update the popover content
    private func updatePopoverContent() {
        objectWillChange.send()
    }

    /// Start the popover refresh timer
    private func startPopoverRefreshTimer() {
        dataManager.startPopoverRefreshTimer { [weak self] in
            self?.updatePopoverContent()
        }
    }
    
    // MARK: - Data Fetching

    /// Start data refresh
    func startRefreshing() {
        dataManager.startRefreshing()
    }
    
    // MARK: - Settings Window
    
    @objc func openSettings() {
        openSettingsWindow(tab: 0)
    }

    @objc func openGeneralSettings() {
        openSettingsWindow(tab: 0)
    }

    @objc func openAuthSettings() {
        openSettingsWindow(tab: 1)
    }

    @objc func openAbout() {
        openSettingsWindow(tab: 2)
    }

    /// Switch account
    /// - Parameter sender: Menu item sender, representedObject contains the Account object
    @objc func switchAccount(_ sender: NSMenuItem) {
        guard let account = sender.representedObject as? Account else {
            Logger.menuBar.error("switchAccount: missing Account in menu item representedObject")
            return
        }

        settings.switchToAccount(account)
    }

    @objc func checkForUpdates() {
        // Record that the user has acknowledged the current version's update
        if let version = latestVersion {
            acknowledgedVersion = version
            // Trigger UI update (hide badge and notification)
            objectWillChange.send()
            // Update menu bar icon
            updateMenuBarIcon()
        }

        // Manually check for updates (will show dialog)
        dataManager.checkForUpdatesManually()
    }
    
    /// Open the settings window
    /// - Parameter tab: Tab index to display (0: General, 1: Authentication, 2: About)
    private func openSettingsWindow(tab: Int) {
        if settingsWindow == nil {
            // Switch to regular mode so the app appears in the Dock
            NSApp.setActivationPolicy(.regular)
            
            let settingsView = SettingsView(initialTab: tab)
            let hostingController = NSHostingController(rootView: settingsView)
            
            settingsWindow = NSWindow(
                contentViewController: hostingController
            )
            settingsWindow?.title = L.Window.settingsTitle
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setFrameAutosaveName("Usage4Claude.SettingsWindow")

            // Remove old observer (if it exists)
            if let observer = windowCloseObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            
            // Add window close observer
            windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: settingsWindow,
                queue: .main
            ) { [weak self] _ in
                // Switch back to accessory mode when window closes (hidden from Dock)
                NSApp.setActivationPolicy(.accessory)

                self?.settingsWindow = nil
                if self?.settings.hasValidCredentials == true && self?.usageData == nil {
                    self?.startRefreshing()
                }
            }

            // Add window focus observer - close popover when settings window becomes key window
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: settingsWindow,
                queue: .main
            ) { [weak self] _ in
                #if DEBUG
                // Debug mode: If "Keep detail window open" is enabled, do not auto-close
                if UserSettings.shared.debugKeepDetailWindowOpen {
                    return
                }
                #endif

                if self?.ui.popover.isShown == true {
                    self?.closePopover()
                }
            }

            // Remove old language change observer (if it exists)
            if let observer = languageChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            // Add language change observer - update window title when language switches
            languageChangeObserver = NotificationCenter.default.addObserver(
                forName: .languageChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.settingsWindow?.title = L.Window.settingsTitle
            }
        }

        // Activate the app first, then center and show the window
        NSApp.activate(ignoringOtherApps: true)

        // Delay briefly to ensure app activation completes before centering window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.settingsWindow?.center()
            self?.settingsWindow?.makeKeyAndOrderFront(nil)
        }

        if ui.popover.isShown {
            closePopover()
        }
    }
    
    // MARK: - Icon Management

    /// Update the menu bar icon
    private func updateMenuBarIcon() {
        ui.updateMenuBarIcon(usageData: usageData, hasUpdate: hasAvailableUpdate, shouldShowBadge: shouldShowUpdateBadge)
    }
    
    // MARK: - Cleanup
    
    /// Clean up all resources
    /// Called when the app exits, stops all timers and removes all observers
    func cleanup() {
        // Stop popover refresh timer
        dataManager.stopPopoverRefreshTimer()

        // Clean up window observer
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            windowCloseObserver = nil
        }

        // Clean up language change observer
        if let observer = languageChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            languageChangeObserver = nil
        }

        // Cancel all Combine subscriptions
        cancellables.removeAll()

        // Clean up UI
        ui.cleanup()

        // Clean up data manager
        dataManager.cleanup()

        // Close window
        settingsWindow?.close()
        settingsWindow = nil
    }
    
    deinit {
        cleanup()
    }
}
