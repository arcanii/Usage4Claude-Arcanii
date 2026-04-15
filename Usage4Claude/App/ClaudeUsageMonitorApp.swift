//
//  ClaudeUsageMonitorApp.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import Combine

/// Usage4Claude application main entry point
@main
struct ClaudeUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Application delegate class
/// Responsible for application lifecycle management, resource initialization and cleanup
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
    /// Menu bar manager, responsible for all menu bar related functionality
    private var menuBarManager: MenuBarManager!
    
    /// Welcome window, displayed on first launch
    private var welcomeWindow: NSWindow?
    
    /// User settings instance
    private let settings = UserSettings.shared

    /// Combine subscription set, used for automatic observer lifecycle management
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Application Lifecycle
    
    /// Called when the application has finished launching
    /// Initializes the menu bar manager, shows the welcome window on first launch or starts data refresh
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Request notification permission
        NotificationManager.shared.requestPermission()

        menuBarManager = MenuBarManager()

        if settings.isFirstLaunch || !settings.hasValidCredentials {
            showWelcomeWindow()
        } else {
            menuBarManager.startRefreshing()
        }

        // Use Combine to subscribe to notifications, automatically managing lifecycle
        NotificationCenter.default.publisher(for: .openSettings)
            .sink { [weak self] notification in
                self?.openSettingsFromNotification(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.settings.syncLaunchAtLoginStatus()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Private Methods
    
    /// Show the welcome window
    /// Called on first launch or when authentication credentials are not configured
    private func showWelcomeWindow() {
        NSApp.setActivationPolicy(.regular)

        let welcomeView = WelcomeView()
        let hostingController = NSHostingController(rootView: welcomeView)

        welcomeWindow = NSWindow(
            contentViewController: hostingController
        )
        welcomeWindow?.title = L.Window.welcomeTitle
        welcomeWindow?.styleMask = [.titled, .closable]
        welcomeWindow?.level = .floating

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = welcomeWindow?.frame ?? NSRect.zero
            let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
            welcomeWindow?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Use Combine to subscribe to window close notification
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: welcomeWindow)
            .sink { _ in
                NSApp.setActivationPolicy(.accessory)
            }
            .store(in: &cancellables)

        welcomeWindow?.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Handle the open settings notification
    /// Closes the welcome window and starts refresh based on authentication configuration status
    private func openSettingsFromNotification(_ notification: Notification) {
        welcomeWindow?.close()
        welcomeWindow = nil

        if settings.hasValidCredentials {
            menuBarManager.startRefreshing()
        }
    }
    
    /// Called when the application is about to terminate
    /// Cleans up timers and window resources
    /// Note: Combine subscriptions are automatically cleaned up when cancellables are deallocated
    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager?.cleanup()
        welcomeWindow?.close()
        welcomeWindow = nil
        cancellables.removeAll()
    }
}
