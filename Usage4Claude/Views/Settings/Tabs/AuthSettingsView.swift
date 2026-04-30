//
//  AuthSettingsView.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Authentication settings page
/// Uses card layout for managing multiple accounts
struct AuthSettingsView: View {
    @ObservedObject private var settings = UserSettings.shared
    @State private var isAddingAccount = false
    @State private var newSessionKey = ""
    @State private var newAlias = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var isShowingPassword = false
    @State private var showDeleteConfirmation = false
    @State private var accountToDelete: Account?
    @State private var successMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isAddingAccount {
                    // Add account view
                    addAccountView
                } else {
                    // Multi-organization add success message
                    if let message = successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { successMessage = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // Account list view
                    accountListView

                    // Current account details
                    if let currentAccount = settings.currentAccount {
                        currentAccountDetailView(account: currentAccount)
                    }

                    // How-to card
                    howToCard

                    // Diagnostics card
                    diagnosticsCard
                }
            }
            .padding()
        }
        .alert(L.Account.deleteConfirmTitle, isPresented: $showDeleteConfirmation) {
            Button(L.Account.cancel, role: .cancel) {}
            Button(L.Account.delete, role: .destructive) {
                if let account = accountToDelete {
                    settings.removeAccount(account)
                }
            }
        } message: {
            Text(L.Account.deleteConfirmMessage)
        }
    }

    // MARK: - Account List View

    private var accountListView: some View {
        SettingCard(
            icon: "person.2.fill",
            iconColor: .blue,
            title: L.Account.listTitle,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if settings.accounts.isEmpty {
                    // Prompt when no accounts exist
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(L.Account.noAccounts)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    // Account list
                    ForEach(settings.accounts) { account in
                        accountRow(account: account)
                    }
                }

                // Add account button
                HStack(spacing: 10) {
                    Button(action: {
                        WebLoginWindowManager.shared.showLoginWindow()
                    }) {
                        HStack {
                            Image(systemName: "globe")
                            Text(L.WebLogin.browserLogin)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        withAnimation {
                            isAddingAccount = true
                            newSessionKey = ""
                            newAlias = ""
                            validationError = nil
                        }
                    }) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text(L.WebLogin.manualInput)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Account Row

    private func accountRow(account: Account) -> some View {
        Button(action: {
            settings.switchToAccount(account)
        }) {
            HStack(spacing: 12) {
                // Selection state indicator
                Circle()
                    .fill(account.id == settings.currentAccountId ? Color.blue : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )

                // Account info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(account.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if account.id == settings.currentAccountId {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    // If alias exists, show original name as subtitle
                    if account.alias != nil && !account.alias!.isEmpty {
                        Text(account.organizationName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(account.id == settings.currentAccountId ? Color.blue.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Current Account Detail View

    private func currentAccountDetailView(account: Account) -> some View {
        SettingCard(
            icon: "person.circle.fill",
            iconColor: .green,
            title: L.Account.currentAccount,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Alias editing
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                        Text(L.Account.alias)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    HStack {
                        TextField(account.organizationName, text: Binding(
                            get: { account.alias ?? "" },
                            set: { newValue in
                                settings.updateAccount(account, alias: newValue.isEmpty ? nil : newValue)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        if account.alias != nil && !account.alias!.isEmpty {
                            Button(action: {
                                settings.updateAccount(account, alias: nil)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L.Account.clearAlias)
                        }
                    }
                }

                // Session Key display
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .foregroundColor(.red)
                            .font(.subheadline)
                        Text(L.SettingsAuth.sessionKeyLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    HStack {
                        if isShowingPassword {
                            Text(account.sessionKey)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(String(repeating: "•", count: min(account.sessionKey.count, 30)))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            isShowingPassword.toggle()
                        }) {
                            Image(systemName: isShowingPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isShowingPassword ? L.SettingsAuth.hidePassword : L.SettingsAuth.showPassword)
                    }
                }

                // Organization ID display
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(.purple)
                            .font(.subheadline)
                        Text(L.Account.organizationId)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text(account.organizationId)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(account.organizationId, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L.Account.copyOrgId)
                    }
                }

                // Delete button
                if settings.accounts.count > 0 {
                    Divider()

                    Button(action: {
                        accountToDelete = account
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(L.Account.deleteAccount)
                        }
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Add Account View

    private var addAccountView: some View {
        SettingCard(
            icon: "person.badge.plus",
            iconColor: .blue,
            title: L.Account.addNewAccount,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Session Key input
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .foregroundColor(.red)
                            .font(.subheadline)
                        Text(L.SettingsAuth.sessionKeyLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    SecureField(L.SettingsAuth.sessionKeyPlaceholder, text: $newSessionKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    // Validation status hint
                    if !newSessionKey.isEmpty {
                        if settings.isValidSessionKey(newSessionKey) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text(L.Welcome.validFormat)
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(L.Welcome.invalidFormat)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(L.SettingsAuth.sessionKeyHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Alias input (optional)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                        Text(L.Account.aliasOptional)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    TextField(L.Account.aliasPlaceholder, text: $newAlias)
                        .textFieldStyle(.roundedBorder)
                }

                // Error message
                if let error = validationError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Action buttons
                HStack {
                    Button(action: {
                        withAnimation {
                            isAddingAccount = false
                        }
                    }) {
                        Text(L.Account.cancel)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(action: {
                        validateAndAddAccount()
                    }) {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Text(L.Account.validateAndAdd)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.isValidSessionKey(newSessionKey) || isValidating)
                }
            }
        }
    }

    // MARK: - How To Card

    private var howToCard: some View {
        SettingCard(
            icon: "book.fill",
            iconColor: .blue,
            title: L.SettingsAuth.howToTitle,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.SettingsAuth.step1)
                    .font(.subheadline)
                Text(L.SettingsAuth.step2)
                    .font(.subheadline)
                Text(L.SettingsAuth.step3)
                    .font(.subheadline)
                Text(L.SettingsAuth.step4)
                    .font(.subheadline)
                Text(L.SettingsAuth.step5)
                    .font(.subheadline)
                Text(L.SettingsAuth.step6)
                    .font(.subheadline)

                Button(action: {
                    if let url = URL(string: "https://claude.ai/settings/usage") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "safari")
                        Text(L.SettingsAuth.openBrowser)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Diagnostics Card

    private var diagnosticsCard: some View {
        SettingCard(
            icon: "stethoscope",
            iconColor: .blue,
            title: L.Diagnostic.sectionTitle,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.Diagnostic.sectionDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Diagnostics component
                DiagnosticsView()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Private Methods

    /// Validate and add account
    private func validateAndAddAccount() {
        isValidating = true
        validationError = nil

        let apiService = ClaudeAPIService()
        apiService.fetchOrganizations(sessionKey: newSessionKey) { result in
            DispatchQueue.main.async {
                isValidating = false

                switch result {
                case .success(let organizations):
                    if !organizations.isEmpty {
                        let useAlias = organizations.count == 1
                        for (index, org) in organizations.enumerated() {
                            let candidate = Account(
                                sessionKey: newSessionKey,
                                organizationId: org.uuid,
                                organizationName: org.name,
                                alias: (useAlias && !newAlias.isEmpty) ? newAlias : nil
                            )
                            // addAccount returns the canonical entry (refreshed if same orgId already existed)
                            let stored = settings.addAccount(candidate)
                            // Switch to the first added/refreshed account
                            if index == 0 {
                                settings.switchToAccount(stored)
                            }
                        }
                        // Show hint for multiple organizations
                        if organizations.count > 1 {
                            successMessage = String(format: L.Account.multiOrgAdded, organizations.count)
                        }
                        // Close add account interface
                        withAnimation {
                            isAddingAccount = false
                        }
                    } else {
                        validationError = L.Error.noOrganizationsFound
                    }
                case .failure(let error):
                    if let usageError = error as? UsageError {
                        validationError = usageError.localizedDescription
                    } else {
                        validationError = error.localizedDescription
                    }
                }
            }
        }
    }
}

/// About page
/// Displays app information, version number, and related links
