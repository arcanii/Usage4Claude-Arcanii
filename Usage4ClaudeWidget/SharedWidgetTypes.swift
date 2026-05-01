//
//  SharedWidgetTypes.swift
//  Usage4Claude Widget Extension
//
//  Common timeline entry + timeline providers used by all widget kinds in
//  this bundle. Splits providers by data needs:
//   - SnapshotOnlyProvider: reads only `usage-snapshot.json` (fast)
//   - HistoryProvider: reads snapshot + last 24h of NDJSON history (sparklines)
//
//  Both produce the same `UsageEntry`; `history` is nil for snapshot-only
//  widgets so they don't pay the cost of parsing a multi-thousand-line NDJSON
//  file on every timeline tick.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline entry

/// One captured moment of state delivered to a widget. Some kinds use only
/// the snapshot; sparkline kinds read `history` as well.
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let history: [UsageHistorySample]
}

// MARK: - Demo data (for placeholder + Edit-Widgets gallery preview)

enum WidgetDemoData {
    static let snapshot = UsageSnapshot(
        capturedAt: Date(),
        fiveHour: .init(percentage: 42, resetsAt: Date().addingTimeInterval(3600 * 2.5)),
        sevenDay: .init(percentage: 73, resetsAt: Date().addingTimeInterval(3600 * 24 * 4)),
        opus: .init(percentage: 18, resetsAt: Date().addingTimeInterval(3600 * 24 * 4)),
        sonnet: .init(percentage: 55, resetsAt: Date().addingTimeInterval(3600 * 24 * 4)),
        extraUsage: .init(used: 12.50, limit: 50.00, currency: "USD")
    )

    /// Synthetic 24h sparkline curve — used so the gallery preview shows a
    /// reasonable trend instead of a flat line.
    static let history: [UsageHistorySample] = {
        let now = Date()
        let count = 60
        return (0..<count).map { i in
            // Even spacing across last 24h, with a sine-ish curve.
            let secondsAgo = TimeInterval(count - i) * (24 * 3600 / TimeInterval(count))
            let timestamp = now.addingTimeInterval(-secondsAgo)
            let progress = Double(i) / Double(count - 1)  // 0...1
            let sine = sin(progress * .pi * 1.5) * 0.5 + 0.5  // 0...1
            return UsageHistorySample(
                timestamp: timestamp,
                fiveHourPct: 10 + sine * 35,
                sevenDayPct: 30 + progress * 45,
                opusPct: 8 + sine * 14,
                sonnetPct: 25 + progress * 35,
                extraUsageUsed: 2 + progress * 11,
                extraUsageLimit: 50,
                extraUsageCurrency: "USD"
            )
        }
    }()
}

// MARK: - Provider: snapshot only

struct SnapshotOnlyProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: WidgetDemoData.snapshot, history: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snap = context.isPreview
            ? WidgetDemoData.snapshot
            : (UsageSnapshotStore.read() ?? WidgetDemoData.snapshot)
        completion(UsageEntry(date: Date(), snapshot: snap, history: []))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let entry = UsageEntry(date: now, snapshot: UsageSnapshotStore.read(), history: [])
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Provider: snapshot + history (last 24h)

struct HistoryProvider: TimelineProvider {
    /// 24 h of history for sparkline rendering. At 1-min refresh that's ~1440
    /// samples max; smart-mode idle keeps it well below.
    private let historyWindow: TimeInterval = 24 * 3600

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: WidgetDemoData.snapshot, history: WidgetDemoData.history)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: Date(), snapshot: WidgetDemoData.snapshot, history: WidgetDemoData.history))
            return
        }
        let snap = UsageSnapshotStore.read() ?? WidgetDemoData.snapshot
        let history = UsageHistoryFileStore.readSince(Date().addingTimeInterval(-historyWindow))
        completion(UsageEntry(
            date: Date(),
            snapshot: snap,
            history: history.isEmpty ? WidgetDemoData.history : history
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-historyWindow)
        let entry = UsageEntry(
            date: now,
            snapshot: UsageSnapshotStore.read(),
            history: UsageHistoryFileStore.readSince(cutoff)
        )
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Shared color helpers (mirrors main app)

func ringColor(for percentage: Double, fallback: Color = .green) -> Color {
    switch percentage {
    case ..<50: return .green
    case ..<70: return .yellow
    case ..<90: return .orange
    default: return .red
    }
}

func sevenDayColor(for percentage: Double) -> Color {
    switch percentage {
    case ..<50: return Color(red: 0.75, green: 0.52, blue: 0.99)  // light purple
    case ..<70: return Color(red: 0.71, green: 0.31, blue: 0.94)  // mid purple
    case ..<90: return Color(red: 0.71, green: 0.12, blue: 0.63)  // deep purple
    default: return Color(red: 0.71, green: 0.12, blue: 0.63)
    }
}

func limitColor(for type: HistoryLimitType, percentage: Double) -> Color {
    switch type {
    case .fiveHour:   return ringColor(for: percentage)
    case .sevenDay:   return sevenDayColor(for: percentage)
    case .opus:       return .orange
    case .sonnet:     return .blue
    case .extraUsage: return .pink
    }
}

// MARK: - Reset countdown text

func resetText(for resetsAt: Date) -> String {
    let interval = resetsAt.timeIntervalSinceNow
    guard interval > 0 else { return "Resetting" }

    let totalMinutes = Int(ceil(interval / 60))
    if totalMinutes < 60 { return "\(totalMinutes)m left" }

    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours < 24 {
        return minutes == 0 ? "\(hours)h left" : "\(hours)h \(minutes)m left"
    }
    let days = hours / 24
    let h = hours % 24
    return h == 0 ? "\(days)d left" : "\(days)d \(h)h left"
}
