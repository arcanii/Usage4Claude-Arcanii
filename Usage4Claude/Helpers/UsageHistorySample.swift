//
//  UsageHistorySample.swift
//  Usage4Claude — Shared between main app and widget extension
//
//  One captured moment of Claude usage, persisted as one line of NDJSON in the
//  App Group container so both targets can read history without duplicating
//  state. Replaces the v1.5.x JSON-array-rewrite-per-tick approach: writes are
//  now O(1) appends instead of O(N) rewrites.
//
//  Reads are cheap enough for the widget's 15-minute timeline tick — at the
//  10k-sample cap (~7 days at 1-min refresh) the file is ~2 MB and parses in
//  under 100 ms. The main-app `UsageHistoryStore` keeps an in-memory mirror
//  for the popover sparkline + CSV export so the UI never blocks on disk.
//

import Foundation

/// One captured moment of usage. Each fetch produces one of these. Stored as
/// a single line of NDJSON in `usage-history.ndjson`.
public struct UsageHistorySample: Codable, Sendable {
    public let timestamp: Date
    public let fiveHourPct: Double?
    public let sevenDayPct: Double?
    public let opusPct: Double?
    public let sonnetPct: Double?
    public let extraUsageUsed: Double?
    public let extraUsageLimit: Double?
    public let extraUsageCurrency: String?

    public init(
        timestamp: Date,
        fiveHourPct: Double?,
        sevenDayPct: Double?,
        opusPct: Double?,
        sonnetPct: Double?,
        extraUsageUsed: Double?,
        extraUsageLimit: Double?,
        extraUsageCurrency: String?
    ) {
        self.timestamp = timestamp
        self.fiveHourPct = fiveHourPct
        self.sevenDayPct = sevenDayPct
        self.opusPct = opusPct
        self.sonnetPct = sonnetPct
        self.extraUsageUsed = extraUsageUsed
        self.extraUsageLimit = extraUsageLimit
        self.extraUsageCurrency = extraUsageCurrency
    }

    /// Get the percentage for a specific limit type, used for sparkline rendering.
    public func percentage(for limit: HistoryLimitType) -> Double? {
        switch limit {
        case .fiveHour: return fiveHourPct
        case .sevenDay: return sevenDayPct
        case .opus: return opusPct
        case .sonnet: return sonnetPct
        case .extraUsage:
            guard let used = extraUsageUsed, let limit = extraUsageLimit, limit > 0 else { return nil }
            return (used / limit) * 100.0
        }
    }
}

/// Limit-type discriminator used by sparkline lookup helpers. Mirrors
/// `LimitType` in the main app but lives in the shared layer so the widget
/// extension doesn't have to compile the full settings graph.
public enum HistoryLimitType: String, Sendable, CaseIterable {
    case fiveHour
    case sevenDay
    case opus
    case sonnet
    case extraUsage
}

// MARK: - File store

/// File-backed storage for `UsageHistorySample` values. NDJSON-formatted: one
/// JSON object per line. Lives in the App Group container so the widget
/// extension can read it.
///
/// Append-only on the hot path; the cap is enforced via `compactIfNeeded()`
/// at app launch (and could be called periodically — the rewrite is the only
/// O(N) operation, the `append` is O(1)).
///
/// All public methods have an "at: URL" overload taking an explicit file path
/// so unit tests can run against a temp directory without an App Group entitlement.
public enum UsageHistoryFileStore {
    public static let appGroupID = "group.com.arcanii.Usage4Claude"
    public static let filename = "usage-history.ndjson"

    /// Cap. ~7 days at 1-minute intervals; smart-mode idle keeps it under
    /// the cap in practice. Compaction trims FIFO when this is exceeded.
    public static let maxSamples = 10_000

    /// Resolve the App Group file URL. Returns nil if the App Group container
    /// isn't reachable (tests that don't have the entitlement, or first-launch
    /// before the system has provisioned the container).
    public static func sharedFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    // MARK: Read

    public static func readAll() -> [UsageHistorySample] {
        guard let url = sharedFileURL() else { return [] }
        return readAll(at: url)
    }

    /// Read every sample from the given file. Lines that fail to decode are
    /// silently skipped — better to lose one corrupted entry than to reject
    /// the whole history file.
    public static func readAll(at url: URL) -> [UsageHistorySample] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let decoder = makeDecoder()
        var out: [UsageHistorySample] = []
        out.reserveCapacity(1024)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let sample = try? decoder.decode(UsageHistorySample.self, from: Data(line.utf8)) {
                out.append(sample)
            }
        }
        return out
    }

    /// Read samples newer than `cutoff`. Useful for sparkline reads where we
    /// only care about the last N hours / days.
    public static func readSince(_ cutoff: Date) -> [UsageHistorySample] {
        guard let url = sharedFileURL() else { return [] }
        return readSince(cutoff, at: url)
    }

    public static func readSince(_ cutoff: Date, at url: URL) -> [UsageHistorySample] {
        readAll(at: url).filter { $0.timestamp >= cutoff }
    }

    // MARK: Append

    @discardableResult
    public static func append(_ sample: UsageHistorySample) -> Bool {
        guard let url = sharedFileURL() else { return false }
        return append(sample, at: url)
    }

    /// Append one sample. Creates the file if missing. The cap is *not*
    /// enforced here — call `compactIfNeeded()` periodically (typically once
    /// per app launch) to trim.
    @discardableResult
    public static func append(_ sample: UsageHistorySample, at url: URL) -> Bool {
        let encoder = makeEncoder()
        guard let data = try? encoder.encode(sample) else { return false }

        var line = data
        line.append(0x0A)  // '\n'

        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return false }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                return true
            } catch {
                return false
            }
        } else {
            // First write — create directory if needed, then atomic write.
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            do {
                try line.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: Compact / rewrite

    /// If the file exceeds `maxSamples` lines, rewrite keeping only the most
    /// recent samples. Returns true if compaction happened, false if the file
    /// was already within budget (or the file couldn't be read).
    @discardableResult
    public static func compactIfNeeded() -> Bool {
        guard let url = sharedFileURL() else { return false }
        return compactIfNeeded(at: url)
    }

    @discardableResult
    public static func compactIfNeeded(at url: URL) -> Bool {
        let samples = readAll(at: url)
        guard samples.count > maxSamples else { return false }

        let trimmed = Array(samples.suffix(maxSamples))
        return rewriteAll(trimmed, at: url)
    }

    /// Replace the file with `samples` (one per line). Atomic.
    @discardableResult
    public static func rewriteAll(_ samples: [UsageHistorySample]) -> Bool {
        guard let url = sharedFileURL() else { return false }
        return rewriteAll(samples, at: url)
    }

    @discardableResult
    public static func rewriteAll(_ samples: [UsageHistorySample], at url: URL) -> Bool {
        let encoder = makeEncoder()
        var buffer = Data()
        buffer.reserveCapacity(samples.count * 200)

        for sample in samples {
            guard let data = try? encoder.encode(sample) else { continue }
            buffer.append(data)
            buffer.append(0x0A)
        }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try buffer.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Encoding helpers

    /// ISO8601 with fractional seconds — `.iso8601` defaults to whole-second
    /// precision and would silently drop the sub-second portion of capture
    /// timestamps. Use a custom strategy so roundtrips are exact.
    ///
    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` doesn't declare
    /// Sendable conformance, but it's documented thread-safe (since macOS
    /// 10.12 / iOS 10) so concurrent use from encode/decode closures is fine.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Plain ISO8601 (no fractional seconds) — used as a fallback when
    /// reading legacy entries written by v1.5.x's whole-second strategy
    /// during migration.
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFractional.string(from: date))
        }
        // Compact one-line JSON output for NDJSON safety.
        encoder.outputFormatting = []
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = isoFractional.date(from: str) { return d }
            if let d = isoPlain.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable timestamp: \(str)"
            )
        }
        return decoder
    }
}
