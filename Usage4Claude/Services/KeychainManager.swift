//
//  KeychainManager.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-19.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Security
import OSLog

/// Class that manages Keychain storage
/// Used for securely storing sensitive information (e.g., Organization ID and Session Key)
/// Debug mode: Uses UserDefaults (convenient for development, no prompts)
/// Release mode: Uses Keychain (secure storage)
class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {
        #if !DEBUG
        // Dynamically get Bundle ID, use default if retrieval fails
        if let bundleID = Bundle.main.bundleIdentifier {
            service = bundleID
        }
        #endif
    }
    
    // MARK: - Keychain Configuration
    
    #if DEBUG
    /// Debug mode: UserDefaults key prefix
    private let debugKeyPrefix = "DEBUG_"
    #else
    /// Keychain service identifier (automatically obtained from Bundle)
    private var service: String = "com.arcanii.Usage4Claude"  // Default value, updated in init
    #endif
    
    // MARK: - Save Methods
    
    #if DEBUG
    /// Save Organization ID to UserDefaults (Debug mode)
    /// - Parameter value: Organization ID value
    /// - Returns: Whether the save was successful
    @discardableResult
    func saveOrganizationId(_ value: String) -> Bool {
        UserDefaults.standard.set(value, forKey: debugKeyPrefix + "organizationId")
        Logger.keychain.debug("[Debug] Saved Organization ID to UserDefaults")
        return true
    }

    /// Save Session Key to UserDefaults (Debug mode)
    /// - Parameter value: Session Key value
    /// - Returns: Whether the save was successful
    @discardableResult
    func saveSessionKey(_ value: String) -> Bool {
        UserDefaults.standard.set(value, forKey: debugKeyPrefix + "sessionKey")
        Logger.keychain.debug("[Debug] Saved Session Key to UserDefaults")
        return true
    }
    #else
    /// Save Organization ID to Keychain (Release mode)
    /// - Parameter value: Organization ID value
    /// - Returns: Whether the save was successful
    @discardableResult
    func saveOrganizationId(_ value: String) -> Bool {
        return save(key: "organizationId", value: value)
    }
    
    /// Save Session Key to Keychain (Release mode)
    /// - Parameter value: Session Key value
    /// - Returns: Whether the save was successful
    @discardableResult
    func saveSessionKey(_ value: String) -> Bool {
        return save(key: "sessionKey", value: value)
    }
    #endif
    
    // MARK: - Load Methods
    
    #if DEBUG
    /// Load Organization ID from UserDefaults (Debug mode)
    /// - Returns: Organization ID value, returns nil if not found
    func loadOrganizationId() -> String? {
        let value = UserDefaults.standard.string(forKey: debugKeyPrefix + "organizationId")
        Logger.keychain.debug("[Debug] Loaded Organization ID: \(value ?? "nil")")
        return value
    }

    /// Load Session Key from UserDefaults (Debug mode)
    /// - Returns: Session Key value, returns nil if not found
    func loadSessionKey() -> String? {
        let value = UserDefaults.standard.string(forKey: debugKeyPrefix + "sessionKey")
        Logger.keychain.debug("[Debug] Loaded Session Key: \(value != nil ? "present" : "nil")")
        return value
    }
    #else
    /// Load Organization ID from Keychain (Release mode)
    /// - Returns: Organization ID value, returns nil if not found
    func loadOrganizationId() -> String? {
        return load(key: "organizationId")
    }
    
    /// Load Session Key from Keychain (Release mode)
    /// - Returns: Session Key value, returns nil if not found
    func loadSessionKey() -> String? {
        return load(key: "sessionKey")
    }
    #endif
    
    // MARK: - Delete Methods
    
    #if DEBUG
    /// Delete Organization ID from UserDefaults (Debug mode)
    /// - Returns: Whether the deletion was successful
    @discardableResult
    func deleteOrganizationId() -> Bool {
        UserDefaults.standard.removeObject(forKey: debugKeyPrefix + "organizationId")
        Logger.keychain.debug("[Debug] Deleted Organization ID")
        return true
    }

    /// Delete Session Key from UserDefaults (Debug mode)
    /// - Returns: Whether the deletion was successful
    @discardableResult
    func deleteSessionKey() -> Bool {
        UserDefaults.standard.removeObject(forKey: debugKeyPrefix + "sessionKey")
        Logger.keychain.debug("[Debug] Deleted Session Key")
        return true
    }
    #else
    /// Delete Organization ID from Keychain (Release mode)
    /// - Returns: Whether the deletion was successful
    @discardableResult
    func deleteOrganizationId() -> Bool {
        return delete(key: "organizationId")
    }
    
    /// Delete Session Key from Keychain (Release mode)
    /// - Returns: Whether the deletion was successful
    @discardableResult
    func deleteSessionKey() -> Bool {
        return delete(key: "sessionKey")
    }
    #endif
    
    /// Delete all authentication credentials
    /// - Returns: Whether all deletions were successful
    @discardableResult
    func deleteAll() -> Bool {
        let result1 = deleteOrganizationId()
        let result2 = deleteSessionKey()
        return result1 && result2
    }
    
    /// Delete all credential information (alias for deleteAll, better business semantics)
    /// - Returns: Whether all deletions were successful
    @discardableResult
    func deleteCredentials() -> Bool {
        return deleteAll()
    }

    // MARK: - Account List Storage (v2.1.0 multi-account support)

    #if DEBUG
    /// Save account list to UserDefaults (Debug mode)
    /// - Parameter accounts: Account list
    /// - Returns: Whether the save was successful
    @discardableResult
    func saveAccounts(_ accounts: [Account]) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(accounts) else {
            Logger.keychain.error("[Debug] Account list encoding failed")
            return false
        }
        UserDefaults.standard.set(data, forKey: debugKeyPrefix + "accounts")
        Logger.keychain.debug("[Debug] Saved \(accounts.count) accounts to UserDefaults")
        return true
    }

    /// Load account list from UserDefaults (Debug mode)
    /// - Returns: Account list, returns nil if not found
    func loadAccounts() -> [Account]? {
        guard let data = UserDefaults.standard.data(forKey: debugKeyPrefix + "accounts") else {
            Logger.keychain.debug("[Debug] Account list not found")
            return nil
        }
        let decoder = JSONDecoder()
        guard let accounts = try? decoder.decode([Account].self, from: data) else {
            Logger.keychain.error("[Debug] Account list decoding failed")
            return nil
        }
        Logger.keychain.debug("[Debug] Loaded \(accounts.count) accounts")
        return accounts
    }

    /// Delete account list from UserDefaults (Debug mode)
    /// - Returns: Whether the deletion was successful
    @discardableResult
    func deleteAccounts() -> Bool {
        UserDefaults.standard.removeObject(forKey: debugKeyPrefix + "accounts")
        Logger.keychain.debug("[Debug] Deleted account list")
        return true
    }
    #else
    /// Save account list to Keychain (Release mode)
    /// - Parameter accounts: Account list
    /// - Returns: Whether the save was successful
    @discardableResult
    func saveAccounts(_ accounts: [Account]) -> Bool {
        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(accounts),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Logger.keychain.error("Account list encoding failed")
            return false
        }
        let result = save(key: "accounts", value: jsonString)
        if result {
            Logger.keychain.debug("Saved \(accounts.count) accounts to Keychain")
        }
        return result
    }

    /// Load account list from Keychain (Release mode)
    /// - Returns: Account list, returns nil if not found
    func loadAccounts() -> [Account]? {
        guard let jsonString = load(key: "accounts"),
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let accounts = try? decoder.decode([Account].self, from: jsonData) else {
            Logger.keychain.error("Account list decoding failed")
            return nil
        }
        Logger.keychain.debug("Loaded \(accounts.count) accounts")
        return accounts
    }

    /// Delete account list from Keychain (Release mode)
    /// - Returns: Whether the deletion was successful
    @discardableResult
    func deleteAccounts() -> Bool {
        return delete(key: "accounts")
    }
    #endif

    #if !DEBUG
    // MARK: - Generic Keychain Operations (Release mode only)
    
    /// Save data to Keychain
    /// - Parameters:
    ///   - key: Key name
    ///   - value: Value to save
    /// - Returns: Whether the save was successful
    private func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        
        // Build query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // First try to delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            return true
        } else {
            Logger.keychain.error("Keychain save failed: \(key), status: \(status)")
            return false
        }
    }
    
    /// Load data from Keychain
    /// - Parameter key: Key name
    /// - Returns: Loaded value, returns nil if not found
    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        } else if status != errSecItemNotFound {
            Logger.keychain.error("Keychain load failed: \(key), status: \(status)")
        }

        return nil
    }
    
    /// Delete data from Keychain
    /// - Parameter key: Key name
    /// - Returns: Whether the deletion was successful
    private func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        } else {
            Logger.keychain.error("Keychain delete failed: \(key), status: \(status)")
            return false
        }
    }
    #endif
}
