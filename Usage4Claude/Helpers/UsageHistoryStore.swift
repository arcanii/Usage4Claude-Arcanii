//
//  UsageHistoryStore.swift
//  Usage4Claude
//
//  Rolling-window persistence for usage samples, plus CSV export. Each
//  successful fetch appends one sample; the store caps the history at
//  `maxSamples` (~7 days at 1-minute refresh intervals) and flushes to disk
//  atomically. Lookups and export run on a serial queue so disk I/O can't
//  race with appends.
//

import Foundation
import OSLog

/// One row in the history. Stored as JSON; exported as CSV.
struct UsageHistorySample: Codable {
    let timestamp: Date
    let fiveHourPct: Double?
    let sevenDayPct: Double?
    let opusPct: Double?
    let sonnetPct: Double?
    let extraUsageUsed: Double?
    let extraUsageLimit: Double?
    let extraUsageCurrency: String?

    init(from data: UsageData, at date: Date = Date()) {
        self.timestamp = date
        self.fiveHourPct = data.fiveHour?.percentage
        self.sevenDayPct = data.sevenDay?.percentage
        self.opusPct = data.opus?.percentage
        self.sonnetPct = data.sonnet?.percentage
        self.extraUsageUsed = data.extraUsage?.used
        self.extraUsageLimit = data.extraUsage?.limit
        self.extraUsageCurrency = data.extraUsage?.enabled == true ? data.extraUsage?.currency : nil
    }
}

final class UsageHistoryStore {
    static let shared = UsageHistoryStore()

    /// Cap. ~7 days at 1-minute intervals; smart-mode idle keeps it under in practice.
    /// Older samples are dropped FIFO when the cap is reached.
    private let maxSamples = 10_000

    /// Serial queue so append/load/export don't race over the same file handle.
    private let queue = DispatchQueue(label: "com.arcanii.Usage4Claude.UsageHistoryStore")

    /// In-memory mirror of what's on disk; the source of truth for export.
    private var samples: [UsageHistorySample] = []

    private init() {
        load()
    }

    // MARK: - Append

    /// Add the latest fetch to the history. Called from DataRefreshManager on
    /// successful fetch. Cheap on the caller — actual file I/O happens on the
    /// serial queue.
    func append(_ data: UsageData) {
        let sample = UsageHistorySample(from: data)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.samples.append(sample)
            if self.samples.count > self.maxSamples {
                self.samples.removeFirst(self.samples.count - self.maxSamples)
            }
            self.persist()
        }
    }

    /// Wipe history. Exposed for the rare case a user wants to reset (e.g. before
    /// sharing an export, or when switching accounts and the historical context
    /// is no longer meaningful).
    func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.samples.removeAll()
            self.persist()
        }
    }

    // MARK: - Export

    /// Generate CSV text from the current in-memory history. Header line included.
    /// Synchronous — but called from the export button (UI thread is fine because
    /// the dataset is bounded by `maxSamples` and the formatting is trivial).
    func exportCSV() -> String {
        var lines: [String] = [
            "timestamp,five_hour_pct,seven_day_pct,opus_pct,sonnet_pct,extra_used,extra_limit,extra_currency"
        ]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Snapshot under the queue so an in-flight append doesn't tear the read.
        let snapshot = queue.sync { samples }

        for sample in snapshot {
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
        queue.sync { samples.count }
    }

    // MARK: - Persistence

    /// Path to the JSON file in Application Support. Created on first persist.
    private var storeURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.arcanii.Usage4Claude"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-history.json")
    }

    private func load() {
        queue.async { [weak self] in
            guard let self = self, let url = self.storeURL else { return }
            guard let data = try? Data(contentsOf: url) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([UsageHistorySample].self, from: data) {
                self.samples = decoded
                Logger.menuBar.debug("UsageHistory: loaded \(decoded.count) samples")
            }
        }
    }

    /// Caller must already be on `queue`.
    private func persist() {
        guard let url = storeURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(samples) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.menuBar.error("UsageHistory: persist failed: \(error.localizedDescription)")
        }
    }
}
