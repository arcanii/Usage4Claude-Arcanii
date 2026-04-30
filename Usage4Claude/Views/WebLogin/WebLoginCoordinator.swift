//
//  WebLoginCoordinator.swift
//  Usage4Claude
//
//  Created by Claude Code on 2026-02-06.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import Combine
import Foundation
import WebKit
import os

/// WKWebView management and cookie detection core logic
/// Responsible for loading the claude.ai login page, monitoring sessionKey cookies, validating and creating accounts
final class WebLoginCoordinator: ObservableObject {

    // MARK: - Login State

    enum LoginState: Equatable {
        case loading
        case waitingForLogin
        case validating
        case success(accountName: String)
        case failed(message: String)
    }

    // MARK: - Published Properties

    @Published var loginState: LoginState = .loading
    @Published var loadProgress: Double = 0

    // MARK: - Properties

    private(set) var webView: WKWebView!
    private var cookieTimer: Timer?
    private var progressObservation: NSKeyValueObservation?
    private var onAccountCreated: ((Account) -> Void)?
    private var navigationDelegate: NavigationDelegate?

    /// List of domains allowed for navigation
    private let allowedDomains: Set<String> = [
        "claude.ai",
        "accounts.google.com",
        "appleid.apple.com",
        "login.microsoftonline.com",
        "github.com",
        "accounts.google.co.jp",
        "accounts.google.com.hk",
        "www.google.com",
        "challenges.cloudflare.com"
    ]

    /// Safari 17.6 macOS User-Agent
    private let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    // MARK: - Init

    init() {
        setupWebView()
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // Non-persistent DataStore - fresh session for each login
        config.websiteDataStore = .nonPersistent()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUserAgent
        webView.allowsBackForwardNavigationGestures = true

        let delegate = NavigationDelegate(coordinator: self)
        webView.navigationDelegate = delegate
        self.navigationDelegate = delegate

        // Monitor loading progress
        progressObservation = webView.observe(\.estimatedProgress) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.loadProgress = webView.estimatedProgress
            }
        }

        self.webView = webView
    }

    // MARK: - Public Methods

    /// Load the login page
    func loadLoginPage() {
        guard let url = URL(string: "https://claude.ai/login") else { return }
        loginState = .loading
        webView.load(URLRequest(url: url))
    }

    /// Set account creation callback
    func setOnAccountCreated(_ callback: @escaping (Account) -> Void) {
        self.onAccountCreated = callback
    }

    /// Clean up all WebView data
    func cleanup() {
        cookieTimer?.invalidate()
        cookieTimer = nil
        progressObservation = nil

        let dataStore = webView.configuration.websiteDataStore
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: allTypes) { records in
            dataStore.removeData(ofTypes: allTypes, for: records) {
                Logger.settings.info("WebLogin: cleared all WebView data")
            }
        }
    }

    // MARK: - Cookie Monitoring

    /// Start cookie polling timer
    fileprivate func startCookieMonitoring() {
        cookieTimer?.invalidate()
        cookieTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForSessionKey()
        }
    }

    /// Check if cookies contain a sessionKey
    private func checkForSessionKey() {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }

            let sessionCookie = cookies.first { cookie in
                cookie.name == "sessionKey" && cookie.domain.contains("claude.ai")
            }

            if let cookie = sessionCookie {
                let sessionKey = cookie.value
                Logger.settings.info("WebLogin: sessionKey cookie detected")

                DispatchQueue.main.async {
                    self.cookieTimer?.invalidate()
                    self.cookieTimer = nil
                    self.validateSessionKey(sessionKey)
                }
            }
        }
    }

    // MARK: - Validation

    /// Validate sessionKey and fetch organization info
    private func validateSessionKey(_ sessionKey: String) {
        loginState = .validating

        let apiService = ClaudeAPIService()
        apiService.fetchOrganizations(sessionKey: sessionKey) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let organizations):
                    if let firstOrg = organizations.first {
                        let candidate = Account(
                            sessionKey: sessionKey,
                            organizationId: firstOrg.uuid,
                            organizationName: firstOrg.name,
                            alias: nil
                        )

                        // addAccount returns the canonical entry — either the freshly inserted
                        // account or the existing same-org account refreshed with this sessionKey.
                        let stored = UserSettings.shared.addAccount(candidate)
                        UserSettings.shared.switchToAccount(stored)

                        self.loginState = .success(accountName: stored.displayName)
                        self.onAccountCreated?(stored)

                        Logger.settings.notice("WebLogin: account created — \(stored.displayName)")
                    } else {
                        self.loginState = .failed(message: L.Error.noOrganizationsFound)
                    }

                case .failure(let error):
                    let message: String
                    if let usageError = error as? UsageError {
                        message = usageError.localizedDescription
                    } else {
                        message = error.localizedDescription
                    }
                    self.loginState = .failed(message: message)
                    Logger.settings.error("WebLogin: validation failed — \(message)")

                    // Resume monitoring after validation failure
                    self.startCookieMonitoring()
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebLoginCoordinator {

    /// Separate NavigationDelegate class to avoid NSObject + ObservableObject conflict
    final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private weak var coordinator: WebLoginCoordinator?

        init(coordinator: WebLoginCoordinator) {
            self.coordinator = coordinator
            super.init()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard let coordinator = coordinator else { return }
            if coordinator.loginState != .validating {
                coordinator.loginState = .loading
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let coordinator = coordinator else { return }
            // After page finishes loading, start monitoring cookies if not already validating
            if case .validating = coordinator.loginState { return }
            if case .success = coordinator.loginState { return }
            coordinator.loginState = .waitingForLogin
            coordinator.startCookieMonitoring()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Ignore cancelled navigations
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }

            coordinator?.loginState = .failed(message: error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let coordinator = coordinator,
                  let url = navigationAction.request.url,
                  let host = url.host?.lowercased() else {
                decisionHandler(.allow)
                return
            }

            // Check if domain is in the allowed list
            let isAllowed = coordinator.allowedDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            if isAllowed {
                decisionHandler(.allow)
            } else {
                // Open disallowed domains in system browser
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}
