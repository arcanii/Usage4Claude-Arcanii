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

        let loginView = WebLoginView(onAccountCreated: onAccountCreated)
        let hostingView = NSHostingView(rootView: loginView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = L.WebLogin.windowTitle
        window.minSize = NSSize(width: 600, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        self.loginWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the login window
    func closeLoginWindow() {
        loginWindow?.close()
        loginWindow = nil
    }
}
