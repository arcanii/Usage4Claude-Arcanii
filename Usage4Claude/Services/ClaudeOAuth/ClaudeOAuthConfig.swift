//
//  ClaudeOAuthConfig.swift
//  Usage4Claude
//
//  Claude (claude.ai) OAuth configuration constants.
//

import Foundation

/// Claude (claude.ai) OAuth configuration constants.
///
/// Reuses Anthropic's official Claude Code public OAuth client (PKCE, no client
/// secret). Authentication completes in the user's default system browser,
/// which sidesteps WKWebView's block on Google embedded login and the fact that
/// passkey/WebAuthn don't work inside an embedded WebView (see upstream Issue #49).
enum ClaudeOAuthConfig {
    /// Authorization endpoint (login + consent happen on claude.ai).
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    /// token / refresh endpoint.
    static let tokenURL = "https://console.anthropic.com/v1/oauth/token"

    /// Claude Code official public client id (PKCE, no client secret).
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// OAuth scope: read-only usage only needs user:profile (deliberately not
    /// requesting user:inference, to avoid over-broad permissions).
    static let scope = "user:profile"

    // MARK: - Usage / account endpoints (Bearer access_token)

    /// Subscription usage: returns five_hour / seven_day utilization + reset
    /// times and extra_usage.
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    /// Account info: returns account (email etc.) and organization.
    static let profileURL = "https://api.anthropic.com/api/oauth/profile"
    /// The beta header the OAuth endpoints require.
    static let betaHeader = "oauth-2025-04-20"

    // MARK: - Local callback (preferred) / manual paste (fallback)

    /// Local callback port (loopback auto-callback, tried first).
    ///
    /// Must avoid macOS's ephemeral port range (49152–65535), otherwise the
    /// system may dynamically claim the port for an outbound connection and the
    /// callback server fails to bind (especially after a restart, when system
    /// network activity is heavy). Use a fixed registered-port-range port, and
    /// keep clear of Codex's 1455/1457.
    static let primaryPort: UInt16 = 1456
    static let fallbackPort: UInt16 = 1458
    static let callbackPath = "/callback"

    /// Claude Code's official manual-paste redirect (used if the client rejects
    /// a localhost redirect_uri).
    static let manualRedirectURI = "https://console.anthropic.com/oauth/code/callback"

    /// Build the local redirect_uri.
    static func redirectURI(port: UInt16) -> String {
        "http://localhost:\(port)\(callbackPath)"
    }
}
