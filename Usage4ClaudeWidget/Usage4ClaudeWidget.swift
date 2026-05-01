//
//  Usage4ClaudeWidget.swift
//  Usage4Claude Widget Extension
//
//  Mirrors the menu bar's 5-hour and 7-day rings as a desktop widget.
//  Reads the latest snapshot the main app wrote to the App Group container —
//  no network calls from the widget itself, so the sandboxed extension stays
//  network-disabled and never has to think about Cloudflare or session
//  expiry. Refresh cadence is 15 min between background ticks; the main app
//  also calls WidgetCenter.shared.reloadAllTimelines() on each successful
//  fetch so the widget catches up immediately when the popover is opened.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

// MARK: - Timeline provider

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: Self.demoSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: UsageSnapshotStore.read() ?? Self.demoSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let entry = UsageEntry(date: now, snapshot: UsageSnapshotStore.read())
        // Refresh every 15 min in the absence of a push from the main app.
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private static let demoSnapshot = UsageSnapshot(
        capturedAt: Date(),
        fiveHour: .init(percentage: 42, resetsAt: Date().addingTimeInterval(3600 * 2.5)),
        sevenDay: .init(percentage: 73, resetsAt: Date().addingTimeInterval(3600 * 24 * 4)),
        opus: nil,
        sonnet: nil,
        extraUsage: nil
    )
}

// MARK: - Views

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

// MARK: - Small (single ring + reset countdown)

private struct SmallView: View {
    let entry: UsageEntry

    var body: some View {
        VStack(spacing: 6) {
            Text("Claude Usage")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let limit = entry.snapshot?.fiveHour ?? entry.snapshot?.sevenDay {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(limit.percentage) / 100.0)
                        .stroke(
                            ringColor(for: limit.percentage),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(limit.percentage))%")
                        .font(.system(size: 22, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                if let reset = limit.resetsAt {
                    Text(resetText(for: reset))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Medium (5h + 7d side by side)

private struct MediumView: View {
    let entry: UsageEntry

    var body: some View {
        HStack(spacing: 16) {
            ringTile(label: "5-hour", limit: entry.snapshot?.fiveHour, accent: .green)
            ringTile(label: "7-day", limit: entry.snapshot?.sevenDay, accent: .purple)
        }
        .padding()
        .containerBackground(for: .widget) { Color.clear }
    }

    private func ringTile(label: String, limit: UsageSnapshot.Limit?, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let limit {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(limit.percentage) / 100.0)
                        .stroke(
                            ringColor(for: limit.percentage, fallback: accent),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(limit.percentage))%")
                        .font(.system(size: 16, weight: .bold))
                }
                .aspectRatio(1, contentMode: .fit)

                if let reset = limit.resetsAt {
                    Text(resetText(for: reset))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

/// Match the main app's color palette: green low, yellow/orange middle, red high.
private func ringColor(for percentage: Double, fallback: Color = .green) -> Color {
    switch percentage {
    case ..<50: return .green
    case ..<70: return .yellow
    case ..<90: return .orange
    default: return .red
    }
}

private func resetText(for resetsAt: Date) -> String {
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

// MARK: - Widget definition

struct Usage4ClaudeWidget: Widget {
    let kind: String = "com.arcanii.Usage4Claude.Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Live 5-hour and 7-day usage rings, mirrored from the menu bar.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
