//
//  ClaudeOAuthCoordinator.swift
//  Usage4Claude
//
//  Coordinates the "Sign in with Claude" system-browser OAuth flow.
//

import AppKit
import Combine
import Foundation
import OSLog

/// Claude OAuth login coordinator.
///
/// Orchestrates the "Sign in with Claude" flow: system-browser authorization →
/// localhost callback → authorization-code exchange → profile fetch → store the
/// refresh_token on the account. Sidesteps the embedded WKWebView's limits on
/// Google / passkey / enterprise-SSO logins (upstream Issue #49).
///
/// Credential convention: the refresh_token (sk-ant-ort01-…) is stored in
/// `Account.sessionKey`, and `organizationId` holds the organization uuid (the
/// same dedup key as legacy cookie accounts, for a smooth migration).
@MainActor
final class ClaudeOAuthCoordinator: ObservableObject {

    enum LoginState: Equatable {
        case starting
        case waitingForBrowser
        case exchanging
        case success(accountName: String)
        case failed(message: String)
    }

    @Published private(set) var loginState: LoginState = .starting

    private let server = OAuthCallbackServer()
    private var pkce: PKCECodes?
    private var redirectURI = ""
    private var authorizeURL: URL?
    private var onAccountCreated: ((Account) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    private let loginTimeout: TimeInterval = 5 * 60

    // MARK: - Public

    func start(onAccountCreated: ((Account) -> Void)? = nil) {
        self.onAccountCreated = onAccountCreated
        finished = false
        loginState = .starting

        let pkce = PKCECodes()
        self.pkce = pkce

        let ports = [ClaudeOAuthConfig.primaryPort, ClaudeOAuthConfig.fallbackPort]
        guard let port = server.start(ports: ports, onCallback: { [weak self] query in
            Task { @MainActor in self?.handleCallback(query) }
        }) else {
            fail(L.WebLogin.claudeOAuthPortBusy)
            return
        }
        redirectURI = ClaudeOAuthConfig.redirectURI(port: port)

        guard let url = buildAuthorizeURL(pkce: pkce, redirectURI: redirectURI) else {
            fail(L.WebLogin.claudeOAuthFailed)
            return
        }
        authorizeURL = url
        NSWorkspace.shared.open(url)
        loginState = .waitingForBrowser
        Logger.settings.notice("ClaudeOAuth: opened system browser, waiting for authorization (callback port \(port))")

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.loginTimeout ?? 300) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.failIfPending(L.WebLogin.claudeOAuthTimeout)
        }
    }

    func reopenBrowser() {
        guard let url = authorizeURL, !finished else { return }
        NSWorkspace.shared.open(url)
    }

    /// Manual fallback (Issue #68): accept a callback link the user pastes back from
    /// the system browser's address bar, parse out code / state, and run the exact
    /// same path as the automatic loopback callback — including the state check, and
    /// exchanging the token with the same loopback redirect_uri (no browser reopen).
    /// For environments where the browser reached the localhost callback page but the
    /// local server never received the request (e.g. some Chromium variants).
    /// - Returns: whether a usable code was parsed and the flow continued; false means
    ///   the pasted content had no usable code.
    @discardableResult
    func submitManualCallback(_ pasted: String) -> Bool {
        guard !finished else { return false }
        let query = Self.parseManualCallback(pasted)
        // Require at least code or error before handing off: the error case lets
        // handleCallback report an accurate failure; neither present (invalid paste)
        // returns false so the UI can inline-prompt for the full link.
        guard query["code"] != nil || query["error"] != nil else {
            Logger.settings.error("ClaudeOAuth: manual paste contained no parseable code")
            return false
        }
        Logger.settings.notice("ClaudeOAuth: completing login via manually-pasted callback link")
        handleCallback(query)
        return true
    }

    func cancel() {
        cleanup()
    }

    // MARK: - Private

    private func buildAuthorizeURL(pkce: PKCECodes, redirectURI: String) -> URL? {
        var comps = URLComponents(string: ClaudeOAuthConfig.authorizeURL)
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: ClaudeOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: ClaudeOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state)
        ]
        return comps?.url
    }

    /// Parse OAuth callback parameters (code / state) from content the user pasted.
    /// Handles three shapes: a full callback URL (with ?code=...&state=...),
    /// `code#state`, and a bare code.
    static func parseManualCallback(_ raw: String) -> [String: String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [:] }

        // 1) URL with a query: parse via the query (code / state / error; queryItems
        //    are already percent-decoded), so a whole URL isn't mistaken for the code
        //    (e.g. a denied authorization returns only `error`, no code).
        if let items = URLComponents(string: text)?.queryItems, !items.isEmpty {
            var result: [String: String] = [:]
            for key in ["code", "state", "error"] {
                if let value = items.first(where: { $0.name == key })?.value, !value.isEmpty {
                    result[key] = value
                }
            }
            return result
        }

        // 2) `code#state` shape
        if text.contains("#"), !text.contains("?"), !text.contains("/") {
            let parts = text.split(separator: "#", maxSplits: 1).map(String.init)
            var result = ["code": parts[0]]
            if parts.count > 1, !parts[1].isEmpty { result["state"] = parts[1] }
            return result
        }

        // 3) bare code (no state; handleCallback's state check catches it and prompts
        //    the user to paste the full link).
        return ["code": text]
    }

    private func handleCallback(_ query: [String: String]) {
        guard !finished else { return }

        guard let returnedState = query["state"], returnedState == pkce?.state else {
            Logger.settings.error("ClaudeOAuth: state validation failed")
            fail(L.WebLogin.claudeOAuthFailed)
            return
        }
        if let error = query["error"] {
            Logger.settings.error("ClaudeOAuth: authorization endpoint returned error \(error)")
            fail(L.WebLogin.claudeOAuthFailed)
            return
        }
        guard let code = query["code"], let pkce = pkce else {
            fail(L.WebLogin.claudeOAuthFailed)
            return
        }

        loginState = .exchanging
        ClaudeOAuthService.exchangeCode(
            code: code,
            state: returnedState,
            codeVerifier: pkce.codeVerifier,
            redirectURI: redirectURI
        ) { [weak self] result in
            Task { @MainActor in self?.handleTokens(result) }
        }
    }

    private func handleTokens(_ result: Result<ClaudeOAuthTokens, Error>) {
        guard !finished else { return }

        switch result {
        case .failure(let error):
            Logger.settings.error("ClaudeOAuth: token exchange failed \(error.localizedDescription)")
            fail(L.WebLogin.claudeOAuthFailed)

        case .success(let tokens):
            guard !tokens.refreshToken.isEmpty else {
                Logger.settings.error("ClaudeOAuth: response missing refresh_token")
                fail(L.WebLogin.claudeOAuthFailed)
                return
            }
            // Fetch the profile to complete the account (email / org uuid);
            // a failure here doesn't block login.
            ClaudeOAuthService.fetchProfile(accessToken: tokens.accessToken) { [weak self] profile in
                Task { @MainActor in self?.createAccount(tokens: tokens, profile: profile) }
            }
        }
    }

    private func createAccount(tokens: ClaudeOAuthTokens, profile: Result<(email: String, orgId: String, orgName: String), Error>) {
        guard !finished else { return }

        var email = ""
        var orgId = ""
        if case .success(let p) = profile {
            email = p.email
            orgId = p.orgId
        }
        let displayName = email.isEmpty ? "Claude" : email
        // Use the organization uuid as organizationId (falling back to email);
        // matches the dedup key of legacy cookie accounts.
        let stableOrgId = orgId.isEmpty ? email : orgId

        // addAccount refreshes an existing same-organizationId account in place
        // (overwriting its sessionKey with the new refresh_token) and returns the
        // canonical entry, so no manual remove-then-add migration is needed.
        let account = Account(
            sessionKey: tokens.refreshToken,
            organizationId: stableOrgId,
            organizationName: displayName,
            alias: nil
        )
        let stored = UserSettings.shared.addAccount(account)
        UserSettings.shared.switchToAccount(stored)

        loginState = .success(accountName: stored.displayName)
        onAccountCreated?(stored)
        Logger.settings.notice("ClaudeOAuth: account created - \(stored.displayName)")
        finishCleanup()
    }

    private func fail(_ message: String) {
        loginState = .failed(message: message)
        finishCleanup()
    }

    private func failIfPending(_ message: String) {
        guard !finished else { return }
        fail(message)
    }

    private func finishCleanup() {
        finished = true
        cleanup()
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        server.stop()
    }
}
