//
//  ExtraLargeWidget.swift
//  Usage4Claude Widget Extension
//
//  systemExtraLarge — the "everything" widget. All 5 limits as rings across
//  the top, a 24h sparkline strip below, and the Extra Usage band at the
//  bottom. For users who want their full Claude usage state pinned to their
//  desk.
//

import WidgetKit
import SwiftUI

struct ExtraLargeWidget: Widget {
    let kind: String = "com.arcanii.Usage4Claude.ExtraLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HistoryProvider()) { entry in
            ExtraLargeView(entry: entry)
        }
        .configurationDisplayName("Claude Usage — Full Dashboard")
        .description("All 5 limits + sparklines + Extra Usage. The kitchen-sink widget.")
        .supportedFamilies([.systemExtraLarge])
    }
}

private struct ExtraLargeView: View {
    let entry: UsageEntry

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                if let captured = entry.snapshot?.capturedAt {
                    Text(captured, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Top: 5 ring tiles in one row
            HStack(spacing: 12) {
                ringTile(
                    label: "5-hour",
                    limit: entry.snapshot?.fiveHour,
                    historyType: .fiveHour
                )
                ringTile(
                    label: "7-day",
                    limit: entry.snapshot?.sevenDay,
                    historyType: .sevenDay
                )
                ringTile(label: "Opus", limit: entry.snapshot?.opus, historyType: .opus)
                ringTile(label: "Sonnet", limit: entry.snapshot?.sonnet, historyType: .sonnet)
                extraTile(entry.snapshot?.extraUsage)
            }
            .frame(maxHeight: .infinity)

            // Bottom: 24h sparkline strip combining 5h and 7d
            VStack(alignment: .leading, spacing: 4) {
                Text("Last 24 hours")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ZStack {
                    SparklineView(
                        values: entry.history.compactMap { $0.percentage(for: .sevenDay) },
                        color: sevenDayColor(for: entry.snapshot?.sevenDay?.percentage ?? 0),
                        lineWidth: 1.5,
                        showFill: false,
                        showCurrentDot: false
                    )
                    SparklineView(
                        values: entry.history.compactMap { $0.percentage(for: .fiveHour) },
                        color: ringColor(for: entry.snapshot?.fiveHour?.percentage ?? 0),
                        lineWidth: 2.0,
                        showFill: false,
                        showCurrentDot: true
                    )
                }
                .frame(height: 50)
            }
        }
        .padding(16)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func ringTile(
        label: String,
        limit: UsageSnapshot.Limit?,
        historyType: HistoryLimitType
    ) -> some View {
        let color: Color = limit.map { limitColor(for: historyType, percentage: $0.percentage) } ?? .gray
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.18), lineWidth: 6)
                if let limit {
                    Circle()
                        .trim(from: 0, to: CGFloat(limit.percentage) / 100.0)
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(limit.percentage))%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(color)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            if let limit, let reset = limit.resetsAt {
                Text(resetText(for: reset))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(" ").font(.caption2)  // reserve space so tiles align
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func extraTile(_ extra: UsageSnapshot.Extra?) -> some View {
        VStack(spacing: 4) {
            Text("Extra")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 2)
                    .aspectRatio(1, contentMode: .fit)

                if let extra, let used = extra.used, let limit = extra.limit, limit > 0 {
                    VStack(spacing: 2) {
                        Text(String(format: "$%.2f", used))
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(.pink)
                        Text(String(format: "of $%.0f", limit))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }

            Text(" ").font(.caption2)  // reserve space for alignment
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
