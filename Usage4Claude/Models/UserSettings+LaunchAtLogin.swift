//
//  UserSettings+LaunchAtLogin.swift
//  Usage4Claude
//
//  Launch-at-login plumbing extracted from UserSettings.swift. The @Published
//  toggle (`launchAtLogin`) and status property (`launchAtLoginStatus`) stay on
//  the main type so SwiftUI views observe them in place; this extension just
//  owns the SMAppService side-effects.
//

import Foundation
import ServiceManagement
import OSLog

extension UserSettings {
    /// Enable launch-at-login by registering the main app with SMAppService. On
    /// failure, reverts the toggle (without re-triggering didSet) and posts a
    /// `.launchAtLoginError` notification with the underlying error.
    func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: "launchAtLogin")
            syncLaunchAtLoginStatus()
            Logger.settings.notice("Launch-at-login enabled")
        } catch {
            Logger.settings.error("Enabling launch-at-login failed: \(error.localizedDescription)")
            isSyncingLaunchStatus = true
            DispatchQueue.main.async {
                self.launchAtLogin = false
                self.isSyncingLaunchStatus = false
                self.syncLaunchAtLoginStatus()
            }
            NotificationCenter.default.post(
                name: .launchAtLoginError,
                object: nil,
                userInfo: ["error": error, "operation": "enable"]
            )
        }
    }

    /// Disable launch-at-login. Skips the unregister call when the service is
    /// already in `.notRegistered`/`.notFound` (just updates the persisted
    /// preference). On unregister failure, reverts the toggle and posts the
    /// `.launchAtLoginError` notification.
    func disableLaunchAtLogin() {
        let currentStatus = SMAppService.mainApp.status

        if currentStatus == .notRegistered || currentStatus == .notFound {
            defaults.set(false, forKey: "launchAtLogin")
            syncLaunchAtLoginStatus()
            Logger.settings.notice("Launch-at-login service not registered; preference updated")
            return
        }

        do {
            try SMAppService.mainApp.unregister()
            defaults.set(false, forKey: "launchAtLogin")
            syncLaunchAtLoginStatus()
            Logger.settings.notice("Launch-at-login disabled")
        } catch {
            Logger.settings.error("Disabling launch-at-login failed: \(error.localizedDescription)")
            isSyncingLaunchStatus = true
            DispatchQueue.main.async {
                self.launchAtLogin = true
                self.isSyncingLaunchStatus = false
                self.syncLaunchAtLoginStatus()
            }
            NotificationCenter.default.post(
                name: .launchAtLoginError,
                object: nil,
                userInfo: ["error": error, "operation": "disable"]
            )
        }
    }

    /// Read the system's actual launch-at-login state and reconcile it with the
    /// persisted preference. Called on init, after enable/disable, and any time
    /// the app becomes active (in case the user changed the setting in System
    /// Settings while the app was background).
    func syncLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        DispatchQueue.main.async {
            self.launchAtLoginStatus = status

            let isActuallyEnabled = (status == .enabled)
            if self.launchAtLogin != isActuallyEnabled {
                self.isSyncingLaunchStatus = true
                self.defaults.set(isActuallyEnabled, forKey: "launchAtLogin")
                self.launchAtLogin = isActuallyEnabled
                self.isSyncingLaunchStatus = false
            }
        }

        Logger.settings.debug("Launch-at-login status: \(String(describing: status))")
    }
}
