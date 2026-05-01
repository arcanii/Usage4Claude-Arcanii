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

// Timeline entry + provider live in `SharedWidgetTypes.swift`. This file's
// kind uses `SnapshotOnlyProvider` (no history needed for the rings view).

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

// `ringColor` and `resetText` helpers live in `SharedWidgetTypes.swift`.

// MARK: - Widget definition

struct Usage4ClaudeWidget: Widget {
    let kind: String = "com.arcanii.Usage4Claude.Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotOnlyProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Live 5-hour and 7-day usage rings, mirrored from the menu bar.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
