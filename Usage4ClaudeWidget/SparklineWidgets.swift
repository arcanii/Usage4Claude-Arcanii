//
//  SparklineWidgets.swift
//  Usage4Claude Widget Extension
//
//  History-aware widget kinds that render a sparkline of the last 24h
//  alongside the current value:
//   - SparklineWidget (small + medium) — single ring (5h preferred,
//     falls back to 7d) with a sparkline of its history.
//   - DualSparklineWidget (medium) — 5h + 7d sparklines side by side
//     with overlaid percentages.
//
//  Both depend on `HistoryProvider` reading the App Group NDJSON file.
//

import WidgetKit
import SwiftUI

// MARK: - Single sparkline widget (small + medium)

struct SparklineWidget: Widget {
    let kind: String = "com.arcanii.Usage4Claude.SparklineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HistoryProvider()) { entry in
            SparklineWidgetDispatch(entry: entry)
        }
        .configurationDisplayName("Claude Usage — Trend")
        .description("Current usage with a 24-hour sparkline. Small or medium.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SparklineWidgetDispatch: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallSparklineView(entry: entry)
        case .systemMedium: MediumSparklineView(entry: entry)
        default:            SmallSparklineView(entry: entry)
        }
    }
}

private struct SmallSparklineView: View {
    let entry: UsageEntry

    var body: some View {
        let limit = entry.snapshot?.fiveHour ?? entry.snapshot?.sevenDay
        let isFiveHour = entry.snapshot?.fiveHour != nil
        let limitType: HistoryLimitType = isFiveHour ? .fiveHour : .sevenDay

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(isFiveHour ? "5-hour" : "7-day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let limit, let reset = limit.resetsAt {
                    Text(resetText(for: reset))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if let limit {
                Text("\(Int(limit.percentage))%")
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(limitColor(for: limitType, percentage: limit.percentage))
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            SparklineView(
                values: historyValues(for: limitType),
                color: limit.map { limitColor(for: limitType, percentage: $0.percentage) } ?? .gray,
                lineWidth: 1.5,
                showFill: true,
                showCurrentDot: true
            )
            .frame(height: 24)
        }
        .padding(12)
        .containerBackground(for: .widget) { Color.clear }
    }

    private func historyValues(for type: HistoryLimitType) -> [Double] {
        entry.history.compactMap { $0.percentage(for: type) }
    }
}

private struct MediumSparklineView: View {
    let entry: UsageEntry

    var body: some View {
        // Larger version: same single-limit focus, but with room for the
        // bigger sparkline to actually convey shape.
        let limit = entry.snapshot?.fiveHour ?? entry.snapshot?.sevenDay
        let isFiveHour = entry.snapshot?.fiveHour != nil
        let limitType: HistoryLimitType = isFiveHour ? .fiveHour : .sevenDay
        let color: Color = limit.map { limitColor(for: limitType, percentage: $0.percentage) } ?? .gray

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isFiveHour ? "5-hour limit" : "7-day limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let limit {
                    Text("\(Int(limit.percentage))%")
                        .font(.system(size: 42, weight: .bold).monospacedDigit())
                        .foregroundStyle(color)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }

                if let limit, let reset = limit.resetsAt {
                    Text(resetText(for: reset))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SparklineView(
                values: entry.history.compactMap { $0.percentage(for: limitType) },
                color: color,
                lineWidth: 2.0,
                showFill: true,
                showCurrentDot: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Dual sparkline widget (medium)

struct DualSparklineWidget: Widget {
    let kind: String = "com.arcanii.Usage4Claude.DualSparklineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HistoryProvider()) { entry in
            DualSparklineView(entry: entry)
        }
        .configurationDisplayName("Claude Usage — 5h + 7d Trend")
        .description("Side-by-side 24-hour sparklines for both 5-hour and 7-day limits.")
        .supportedFamilies([.systemMedium])
    }
}

private struct DualSparklineView: View {
    let entry: UsageEntry

    var body: some View {
        HStack(spacing: 12) {
            sparklineColumn(
                label: "5-hour",
                limit: entry.snapshot?.fiveHour,
                limitType: .fiveHour
            )
            sparklineColumn(
                label: "7-day",
                limit: entry.snapshot?.sevenDay,
                limitType: .sevenDay
            )
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func sparklineColumn(
        label: String,
        limit: UsageSnapshot.Limit?,
        limitType: HistoryLimitType
    ) -> some View {
        let color: Color = limit.map { limitColor(for: limitType, percentage: $0.percentage) } ?? .gray
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let limit {
                    Text("\(Int(limit.percentage))%")
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(color)
                }
            }

            SparklineView(
                values: entry.history.compactMap { $0.percentage(for: limitType) },
                color: color,
                lineWidth: 1.6,
                showFill: true,
                showCurrentDot: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let limit, let reset = limit.resetsAt {
                Text(resetText(for: reset))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
