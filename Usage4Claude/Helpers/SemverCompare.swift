//
//  SemverCompare.swift
//  Usage4Claude
//
//  Pure-function version comparison helpers, extracted from UpdateChecker so they
//  can be exercised by unit tests in the standalone SwiftPM package under Tests/.
//

import Foundation

/// Semantic-version comparison utilities (major.minor.patch).
///
/// Handles the format returned by GitHub Releases (e.g. "v1.2.3" with optional "v"
/// prefix) by stripping the "v" and padding to three components. Anything beyond
/// the third component is ignored.
public enum SemverCompare {
    /// Strip a leading "v" / "V" and lowercase. Returns an empty string for nil-ish input.
    public static func parseVersion(_ string: String) -> String {
        return string.lowercased().replacingOccurrences(of: "v", with: "")
    }

    /// True if `latest` is a strictly newer semantic version than `current`.
    /// Equal versions and any malformed pair return false.
    public static func isNewerVersion(latest: String, current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        let latestPadded = (latestComponents + [0, 0, 0]).prefix(3)
        let currentPadded = (currentComponents + [0, 0, 0]).prefix(3)

        for (l, c) in zip(latestPadded, currentPadded) {
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}
