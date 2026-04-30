//
//  UserSettings+Accounts.swift
//  Usage4Claude
//
//  Multi-account management (v2.1.0) extracted from UserSettings.swift. The
//  `@Published var accounts` and `@Published var currentAccountId` stay on the
//  main type so SwiftUI views observe them in place; this extension owns the
//  mutation API.
//
//  Persistence: account lists are stored in Keychain via KeychainManager.
//  saveAccounts() runs on a background queue because Keychain writes block.
//

import Foundation
import OSLog

extension UserSettings {
    /// Persist the account list to Keychain on a background queue (Keychain
    /// writes are synchronous and would otherwise block the main thread).
    /// Called from didSet observers on `accounts` in the main type.
    func saveAccounts() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.keychain.saveAccounts(self.accounts)
        }
    }

    /// Add a new account, or refresh an existing one with the same organizationId.
    /// A re-login against the same org produces a fresh session cookie that must
    /// overwrite the stale one — that case returns the existing entry with the
    /// session key (and optional alias) updated. Otherwise the new account is
    /// appended and, if it's the first one, set as current.
    /// - Returns: The canonical Account now in the store.
    @discardableResult
    func addAccount(_ account: Account) -> Account {
        if let index = accounts.firstIndex(where: { $0.organizationId == account.organizationId }) {
            accounts[index].sessionKey = account.sessionKey
            accounts[index].organizationName = account.organizationName
            if let alias = account.alias, !alias.isEmpty {
                accounts[index].alias = alias
            }
            let refreshed = accounts[index]
            Logger.settings.notice("刷新账户: \(refreshed.displayName)")
            return refreshed
        }

        accounts.append(account)
        if accounts.count == 1 {
            currentAccountId = account.id
        }
        Logger.settings.notice("添加账户: \(account.displayName)")
        return account
    }

    /// Delete an account. If the removed account was the current one, switches to
    /// the first remaining account (or nil if none) and posts `.accountChanged`.
    func removeAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }

        let wasCurrentAccount = (currentAccountId == account.id)
        accounts.remove(at: index)

        if wasCurrentAccount {
            currentAccountId = accounts.first?.id
            NotificationCenter.default.post(name: .accountChanged, object: nil)
        }

        Logger.settings.notice("删除账户: \(account.displayName)")
    }

    /// Switch to the specified account. No-op if it's already current or not in
    /// the store. Posts `.accountChanged` so observers (DataRefreshManager,
    /// MenuBarManager) trigger a refetch + icon update.
    func switchToAccount(_ account: Account) {
        guard account.id != currentAccountId else { return }
        guard accounts.contains(where: { $0.id == account.id }) else { return }

        currentAccountId = account.id
        Logger.settings.notice("切换到账户: \(account.displayName)")
        NotificationCenter.default.post(name: .accountChanged, object: nil)
    }

    /// Update account metadata (currently just the user-supplied alias).
    func updateAccount(_ account: Account, alias: String?) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].alias = alias
        // Bind to a local before the OSLog autoclosure so the implicit-self capture
        // rule doesn't fire on `accounts[index]`.
        let displayName = accounts[index].displayName
        Logger.settings.notice("更新账户别名: \(displayName)")
    }

    /// Account list for display (returns the published array as-is).
    var displayAccounts: [Account] { accounts }

    /// Display name of the current account, if one is selected.
    var currentAccountName: String? { currentAccount?.displayName }
}
