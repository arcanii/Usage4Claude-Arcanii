//
//  WebLoginWindowManager.swift
//  Usage4Claude
//
//  Created by Claude Code on 2026-02-06.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

/// Web login window manager singleton
/// Responsible for creating, showing, and closing the login window
final class WebLoginWindowManager {
    static let shared = WebLoginWindowManager()

    private var loginWindow: NSWindow?

    private init() {}

    /// Show the login window
    /// - Parameter onAccountCreated: Callback after account is successfully created
    func showLoginWindow(onAccountCreated: ((Account) -> Void)? = nil) {
        // If window already exists, bring it to front
        if let window = loginWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Use OAuth (system-browser) sign-in instead of the embedded WKWebView,
        // so Google / Microsoft / enterprise SSO / passkey logins work (Issue #49).
        // The WKWebView-based WebLoginView is kept in the tree as a fallback.
        let loginView = ClaudeOAuthLoginView(onAccountCreated: onAccountCreated)
        let hostingView = NSHostingView(rootView: loginView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = L.WebLogin.windowTitle
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        self.loginWindow = window

        // Release the window reference when the user closes via window chrome.
        // Without this, the WKWebView lives on indefinitely in the background,
        // continuing to poll cookies and consume resources.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.loginWindow = nil
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the login window
    func closeLoginWindow() {
        loginWindow?.close()
        loginWindow = nil
    }
}
