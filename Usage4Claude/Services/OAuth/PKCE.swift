//
//  PKCE.swift
//  Usage4Claude
//
//  Provider-neutral PKCE helper shared by the OAuth sign-in flows.
//

import Foundation
import CryptoKit

/// PKCE (RFC 7636) parameters plus an OAuth `state` (CSRF protection).
/// The `code_challenge` uses S256 (SHA-256 + base64url).
struct PKCECodes {
    let codeVerifier: String
    let codeChallenge: String
    let state: String

    init() {
        codeVerifier = Self.randomURLSafe(byteCount: 64)
        state = Self.randomURLSafe(byteCount: 32)
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        codeChallenge = Self.base64URL(Data(digest))
    }

    /// Generate a URL-safe random string (base64url, no padding).
    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    /// base64url encoding (no padding).
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
