//
//  UsageSnapshot.swift
//  Usage4Claude — Shared between main app and widget extension
//
//  Codable representation of UsageData written by the main app to the App
//  Group container and read by the widget extension on each timeline refresh.
//  Kept separate from `UsageData` so the main type can stay free of Codable
//  obligations and the widget target doesn't need to compile half the
//  ClaudeAPIService graph just to render a percentage.
//

import Foundation

/// One captured moment of usage. Persisted to the App Group container as JSON.
public struct UsageSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let fiveHour: Limit?
    public let sevenDay: Limit?
    public let opus: Limit?
    public let sonnet: Limit?
    public let extraUsage: Extra?
    /// Display name for the weekly slot 0 limit (e.g. "Fable"), or nil when it came
    /// from the legacy `seven_day_opus` field and the widget should use its own label.
    ///
    /// Optional and added after the fact on purpose: snapshots written by older builds
    /// simply decode these as nil, so no migration is needed for a file the widget may
    /// read before the main app rewrites it.
    public let opusModelName: String?
    /// Display name for the weekly slot 1 limit. Same semantics as `opusModelName`.
    public let sonnetModelName: String?

    public struct Limit: Codable, Sendable {
        public let percentage: Double
        public let resetsAt: Date?

        public init(percentage: Double, resetsAt: Date?) {
            self.percentage = percentage
            self.resetsAt = resetsAt
        }
    }

    public struct Extra: Codable, Sendable {
        public let used: Double?
        public let limit: Double?
        public let currency: String?

        public init(used: Double?, limit: Double?, currency: String?) {
            self.used = used
            self.limit = limit
            self.currency = currency
        }
    }

    public init(
        capturedAt: Date = Date(),
        fiveHour: Limit?,
        sevenDay: Limit?,
        opus: Limit?,
        sonnet: Limit?,
        extraUsage: Extra?,
        opusModelName: String? = nil,
        sonnetModelName: String? = nil
    ) {
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.opus = opus
        self.sonnet = sonnet
        self.extraUsage = extraUsage
        self.opusModelName = opusModelName
        self.sonnetModelName = sonnetModelName
    }
}

/// Read/write the current snapshot from the App Group container. Both targets
/// (main app + widget extension) share the same App Group identifier and thus
/// the same `~/Library/Group Containers/<id>/usage-snapshot.json` file.
public enum UsageSnapshotStore {
    public static let appGroupID = "group.com.arcanii.Usage4Claude"
    public static let filename = "usage-snapshot.json"

    @discardableResult
    public static func write(_ snapshot: UsageSnapshot) -> Bool {
        guard let url = sharedFileURL() else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func read() -> UsageSnapshot? {
        guard let url = sharedFileURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public static func sharedFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }
}
