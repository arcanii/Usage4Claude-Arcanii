//
//  ClaudeOAuthLoginView.swift
//  Usage4Claude
//
//  Progress window for the Claude system-browser OAuth sign-in.
//

import SwiftUI

/// Claude OAuth login progress window.
///
/// The actual authentication happens in the system default browser; this window
/// only shows progress and the result, fully sidestepping the WKWebView limits
/// on Google / passkey logins (upstream Issue #49).
struct ClaudeOAuthLoginView: View {
    @StateObject private var coordinator = ClaudeOAuthCoordinator()
    var onAccountCreated: ((Account) -> Void)?

    private let purple = Color(red: 122 / 255.0, green: 90 / 255.0, blue: 195 / 255.0)

    var body: some View {
        VStack(spacing: 18) {
            content
        }
        .padding(32)
        .frame(width: 440, height: 300)
        .onAppear { coordinator.start(onAccountCreated: onAccountCreated) }
        .onDisappear { coordinator.cancel() }
        .onChange(of: coordinator.loginState) { state in
            if case .success = state {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    WebLoginWindowManager.shared.closeLoginWindow()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.loginState {
        case .starting:
            spinner(L.WebLogin.claudeOAuthPreparing)

        case .waitingForBrowser:
            VStack(spacing: 14) {
                Image(systemName: "safari")
                    .font(.system(size: 44))
                    .foregroundColor(purple)
                Text(L.WebLogin.claudeOAuthWaitingBrowser)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(L.WebLogin.claudeOAuthWaitingHint)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(L.WebLogin.claudeOAuthReopenBrowser) { coordinator.reopenBrowser() }
                    .buttonStyle(.link)
            }

        case .exchanging:
            spinner(L.WebLogin.claudeOAuthExchanging)

        case .success(let name):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                Text(L.WebLogin.success(name))
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(L.WebLogin.claudeOAuthRetry) {
                    coordinator.start(onAccountCreated: onAccountCreated)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func spinner(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
