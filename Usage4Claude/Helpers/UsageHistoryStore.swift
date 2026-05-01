//
//  UsageHistoryStore.swift
//  Usage4Claude
//
//  Main-app facade over the shared `UsageHistoryFileStore`. Provides:
//   - O(1) append on each successful fetch (no per-tick full-file rewrite)
//   - In-memory mirror published as `@Published samples` so SwiftUI views
//     (popover sparkline) reactively update on each fetch
//   - One-time migration from the v1.5.x JSON-array format in Application
//     Support to the v1.6.0 NDJSON file in the App Group container
//   - CSV export for the diagnostics view (unchanged interface)
//
//  All disk I/O runs on a serial queue so append/load/export can't race.
//

import Foundation
import Combine
import OSLog

@MainActor
final class UsageHistoryStore: ObservableObject {
    static let shared = UsageHistoryStore()

    /// In-memory mirror of what's in the NDJSON file. Source of truth for the
    /// popover sparkline + CSV export. Published so SwiftUI views observing
    /// this store get redraws on each successful fetch.
    @Published private(set) var samples: [UsageHistorySample] = []

    /// Cap, mirrored from the file store for convenience.
    private let maxSamples = UsageHistoryFileStore.maxSamples

    /// Serial queue for file I/O. Append/load/export can't race over the
    /// same file handle here.
    private let queue = DispatchQueue(label: "com.arcanii.Usage4Claude.UsageHistoryStore")

    private init() {
        bootstrap()
    }

    // MARK: - Append

    /// Add the latest fetch to the history. Called from `DataRefreshManager`
    /// on each successful fetch. Cheap on the caller — actual file I/O happens
    /// on the serial queue.
    func append(_ data: UsageData) {
        let sample = UsageHistorySample(from: data)
        queue.async { [weak self] in
            UsageHistoryFileStore.append(sample)
            Task { @MainActor in
                guard let self = self else { return }
                self.samples.append(sample)
                if self.samples.count > self.maxSamples {
                    self.samples.removeFirst(self.samples.count - self.maxSamples)
                }
            }
        }
    }

    /// Wipe history. Exposed for the rare case a user wants to reset (e.g.
    /// before sharing an export, or when switching accounts and the historical
    /// context is no longer meaningful).
    func clear() {
        queue.async { [weak self] in
            UsageHistoryFileStore.rewriteAll([])
            Task { @MainActor in
                self?.samples = []
            }
        }
    }

    // MARK: - History queries (for the popover sparkline)

    /// Recent percentage values for one limit type, for sparkline rendering.
    /// Filters by `maxAge` (e.g. last 24 h) and drops samples where this
    /// limit had no data at the time. Returned in chronological order.
    func recentValues(for limit: HistoryLimitType, maxAge: TimeInterval) -> [Double] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return samples
            .lazy
            .filter { $0.timestamp >= cutoff }
            .compactMap { $0.percentage(for: limit) }
    }

    // MARK: - Export

    /// Generate CSV text from the current in-memory history. Header line
    /// included. Synchronous — but called from the export button, and the
    /// dataset is bounded by `maxSamples`.
    func exportCSV() -> String {
        var lines: [String] = [
            "timestamp,five_hour_pct,seven_day_pct,opus_pct,sonnet_pct,extra_used,extra_limit,extra_currency"
        ]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for sample in samples {
            let cols: [String] = [
                formatter.string(from: sample.timestamp),
                sample.fiveHourPct.map { String(format: "%.2f", $0) } ?? "",
                sample.sevenDayPct.map { String(format: "%.2f", $0) } ?? "",
                sample.opusPct.map { String(format: "%.2f", $0) } ?? "",
                sample.sonnetPct.map { String(format: "%.2f", $0) } ?? "",
                sample.extraUsageUsed.map { String(format: "%.2f", $0) } ?? "",
                sample.extraUsageLimit.map { String(format: "%.2f", $0) } ?? "",
                sample.extraUsageCurrency ?? ""
            ]
            lines.append(cols.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Number of samples currently stored. Useful for UI ("Export 1,234 samples").
    var count: Int {
        samples.count
    }

    // MARK: - Bootstrap (migration + load + compact)

    private func bootstrap() {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 1. Migrate v1.5.x legacy JSON if present.
            self.migrateLegacyJSONIfPresent()

            // 2. Trim to maxSamples in case the file outgrew the cap (e.g.
            //    upgrading from older builds with a different cap).
            UsageHistoryFileStore.compactIfNeeded()

            // 3. Load the in-memory mirror.
            let loaded = UsageHistoryFileStore.readAll()
            Task { @MainActor in
                self.samples = loaded
                Logger.menuBar.debug("UsageHistory: loaded \(loaded.count) samples")
            }
        }
    }

    /// One-time migration from the v1.5.x format (single JSON array file in
    /// `~/Library/Application Support/<bundle-id>/usage-history.json`) to the
    /// v1.6.0 NDJSON file in the App Group container. Idempotent: deletes the
    /// legacy file once successfully drained, so subsequent launches no-op.
    private func migrateLegacyJSONIfPresent() {
        guard let legacyURL = legacyJSONURL() else { return }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        guard let data = try? Data(contentsOf: legacyURL) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacySamples = try? decoder.decode([UsageHistorySample].self, from: data) else {
            // Couldn't parse — keep the file in place so we don't lose data;
            // the user can investigate manually.
            Logger.menuBar.error("UsageHistory: legacy file present but failed to decode; leaving in place")
            return
        }

        Logger.menuBar.notice("UsageHistory: migrating \(legacySamples.count) legacy samples to NDJSON")

        // If the new file already has entries, merge by timestamp + dedupe.
        // Realistic case: first launch of v1.6.0 — new file is empty and we
        // just write everything. Defensive case: a partial earlier migration.
        let existing = UsageHistoryFileStore.readAll()
        let merged = (existing + legacySamples)
            .sorted { $0.timestamp < $1.timestamp }
            .deduplicatedByTimestamp()
            .suffix(UsageHistoryFileStore.maxSamples)

        UsageHistoryFileStore.rewriteAll(Array(merged))

        // Drop the legacy file. Errors are non-fatal — the migration won't
        // re-run because the merged file now contains the data, but if the
        // legacy file isn't deletable it'll just sit there harmless.
        try? FileManager.default.removeItem(at: legacyURL)
    }

    /// Path to the legacy v1.5.x JSON file. Returns nil if Application Support
    /// can't be resolved.
    private func legacyJSONURL() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.arcanii.Usage4Claude"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("usage-history.json")
    }
}

// MARK: - Helpers

private extension Sequence where Element == UsageHistorySample {
    /// Drop entries whose timestamp matches a previous entry exactly. Used
    /// during legacy migration where the merge step might double-count.
    func deduplicatedByTimestamp() -> [UsageHistorySample] {
        var seen = Set<Date>()
        var out: [UsageHistorySample] = []
        for sample in self {
            if seen.insert(sample.timestamp).inserted {
                out.append(sample)
            }
        }
        return out
    }
}
