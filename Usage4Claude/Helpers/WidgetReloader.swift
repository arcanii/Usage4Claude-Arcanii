//
//  WidgetReloader.swift
//  Usage4Claude
//
//  Recovery actions for widget rendering glitches that survive a normal
//  refresh cycle.
//
//  Background: macOS's `chronod` daemon caches widget extension state and
//  occasionally gets stuck after an app update — symptoms are stale data,
//  missing widget kinds in Edit Widgets…, or all-black widget tiles. The
//  Terminal recipe is `killall chronod`; this helper exposes that from
//  inside the app so users don't need to drop to a shell.
//
//  Two tiers exposed via the popover's "Reset Widgets" menu item:
//   - Default click → `mediumReset(currentData:)` — write a fresh App Group
//     snapshot, reload all timelines, invalidate the configuration cache.
//     No subprocess, no permission prompts, fixes most issues.
//   - ⌥-click (Option-click) → `hardReset(currentData:)` — medium + spawn
//     `killall chronod`. Triggers a TCC "control other processes" prompt on
//     macOS Sequoia+ the first time, but always works.
//

import Foundation
import WidgetKit
import AppKit
import OSLog

enum WidgetReloader {

    // MARK: - Soft (data-only)

    /// Just nudge each widget's timeline to fetch fresh data. Cheap, no
    /// side effects. Won't fix chronod-cache rendering issues — for that
    /// use `mediumReset` or `hardReset`.
    static func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
        Logger.menuBar.notice("WidgetReloader: reloaded all timelines (soft)")
    }

    // MARK: - Medium (snapshot rewrite + timeline reload + config invalidation)

    /// Write a fresh snapshot to the App Group container so widgets read
    /// known-good data, ask WidgetKit to invalidate its configuration cache
    /// (forces re-read of the extension's kind list), and reload all
    /// timelines. Fixes most rendering glitches without spawning a
    /// subprocess.
    /// - Parameter currentData: latest fetched data — written to the snapshot
    ///   file so widgets render this immediately. If nil, the existing
    ///   on-disk snapshot is left alone (still useful: invalidate + reload
    ///   alone may unstick the gallery).
    static func mediumReset(currentData: UsageData?) {
        if let data = currentData {
            UsageSnapshotStore.write(UsageSnapshot(from: data))
        }
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        WidgetCenter.shared.reloadAllTimelines()
        Logger.menuBar.notice("WidgetReloader: medium reset (snapshot + invalidate + reload)")
    }

    // MARK: - Hard (medium + chronod restart)

    /// Medium reset followed by `killall chronod`. Use when the medium
    /// tier doesn't recover the widgets — chronod state can wedge in ways
    /// that only a process restart fixes. Triggers a TCC prompt on first
    /// run.
    static func hardReset(currentData: UsageData?) {
        mediumReset(currentData: currentData)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["chronod"]
        do {
            try process.run()
            process.waitUntilExit()
            Logger.menuBar.notice("WidgetReloader: hard reset — killall chronod exit \(process.terminationStatus)")
        } catch {
            Logger.menuBar.error("WidgetReloader: killall chronod failed: \(error.localizedDescription)")
        }
    }
}
