//
//  UserSettings+SmartMode.swift
//  Usage4Claude
//
//  Smart-mode refresh logic extracted from UserSettings.swift. The state vars
//  (`lastUtilization`, `unchangedCount`, `currentMonitoringMode`) stay on the
//  main type since they're observed and persisted alongside other settings;
//  this extension owns the transition rules.
//
//  Transition table:
//    active     →  idleShort   after 3 consecutive unchanged ticks
//    idleShort  →  idleMedium  after 6 consecutive unchanged ticks
//    idleMedium →  idleLong    after 12 consecutive unchanged ticks
//    idleLong   →  (no further escalation)
//    any        →  active      on any utilization change
//

import Foundation
import OSLog

extension UserSettings {
    /// Adjust the smart-mode monitoring tier based on the latest utilization
    /// value. No-op when refreshMode != .smart. Posts `.refreshIntervalChanged`
    /// when the tier changes so DataRefreshManager can rebuild its timer.
    func updateSmartMonitoringMode(currentUtilization: Double) {
        guard refreshMode == .smart else { return }

        if hasUtilizationChanged(currentUtilization) {
            switchToActiveMode()
        } else {
            handleNoChange()
        }

        lastUtilization = currentUtilization
    }

    /// Reset smart-mode state. Called when switching to fixed mode or on manual refresh.
    func resetSmartMonitoringState() {
        lastUtilization = nil
        unchangedCount = 0
        currentMonitoringMode = .active
    }

    // MARK: - Private helpers

    private func hasUtilizationChanged(_ current: Double) -> Bool {
        guard let last = lastUtilization else { return false }
        return abs(current - last) > 0.01
    }

    private func switchToActiveMode() {
        guard currentMonitoringMode != .active else { return }
        Logger.settings.debug("检测到使用变化，切换到活跃模式 (1分钟)")
        currentMonitoringMode = .active
        unchangedCount = 0
        NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
    }

    private func handleNoChange() {
        unchangedCount += 1
        let previousMode = currentMonitoringMode
        guard let newMode = calculateNewMode() else { return }
        currentMonitoringMode = newMode
        unchangedCount = 0
        logModeTransition(from: previousMode, to: newMode)
        NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
    }

    private func calculateNewMode() -> MonitoringMode? {
        switch currentMonitoringMode {
        case .active:      return unchangedCount >= 3 ? .idleShort : nil
        case .idleShort:   return unchangedCount >= 6 ? .idleMedium : nil
        case .idleMedium:  return unchangedCount >= 12 ? .idleLong : nil
        case .idleLong:    return nil
        }
    }

    private func logModeTransition(from: MonitoringMode, to: MonitoringMode) {
        let modeNames: [MonitoringMode: String] = [
            .active: "活跃 (1分钟)",
            .idleShort: "短期静默 (3分钟)",
            .idleMedium: "中期静默 (5分钟)",
            .idleLong: "长期静默 (10分钟)"
        ]
        Logger.settings.debug("监控模式切换: \(modeNames[from] ?? "") -> \(modeNames[to] ?? "")")
    }
}
