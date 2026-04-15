//
//  Account.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-02-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Account data model
/// Stores Claude account information for the user, including authentication credentials and display name
/// Each account corresponds to a pair of Session Key and Organization ID
struct Account: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: UUID
    /// Claude Session Key
    var sessionKey: String
    /// Organization ID (fetched from API)
    var organizationId: String
    /// Organization name returned by the API (e.g., "xxx's Organization")
    var organizationName: String
    /// User-defined alias (optional)
    var alias: String?
    /// Creation time
    let createdAt: Date

    /// Display name: Prefers alias if set, otherwise uses the API-returned name
    var displayName: String {
        if let alias = alias, !alias.isEmpty {
            return alias
        }
        return organizationName
    }

    // MARK: - Initialization

    /// Create a new account
    /// - Parameters:
    ///   - sessionKey: Claude Session Key
    ///   - organizationId: Organization ID
    ///   - organizationName: Organization name
    ///   - alias: User-defined alias (optional)
    init(
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String? = nil
    ) {
        self.id = UUID()
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = Date()
    }

    /// Full initializer for decoding from storage
    init(
        id: UUID,
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String?,
        createdAt: Date
    ) {
        self.id = id
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = createdAt
    }

    // MARK: - Equatable

    static func == (lhs: Account, rhs: Account) -> Bool {
        return lhs.id == rhs.id
    }
}
