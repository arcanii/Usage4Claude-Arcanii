//
//  LargeDashboardWidget.swift
//  Usage4Claude Widget Extension
//
//  systemLarge widget showing all 5 Claude usage limits at a glance — 5-hour
//  and 7-day across the top, Opus and Sonnet in the middle, Extra Usage as a
//  full-width band at the bottom (it's a dollar amount, not a percentage —
//  rendered differently from the rings).
//
//  Snapshot-only: doesn't read history. Same data path as the existing
//  small/medium widget.
//

import WidgetKit
import SwiftUI

struct LargeDashboardWidget: Widget {
    let kind: String = "com.arcanii.Usage4Claude.LargeDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotOnlyProvider()) { entry in
            LargeDashboardView(entry: entry)
        }
        .configurationDisplayName("Claude Usage — Dashboard")
        .description("All five usage limits (5-hour, 7-day, Opus, Sonnet, Extra) at a glance.")
        .supportedFamilies([.systemLarge])
    }
}

private struct LargeDashboardView: View {
    let entry: UsageEntry

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("Claude Usage")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                if let captured = entry.snapshot?.capturedAt {
                    Text(captured, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Top row: 5h + 7d
            HStack(spacing: 10) {
                ringTile(
                    label: "5-hour",
                    limit: entry.snapshot?.fiveHour,
                    color: ringColor(for: entry.snapshot?.fiveHour?.percentage ?? 0)
                )
                ringTile(
                    label: "7-day",
                    limit: entry.snapshot?.sevenDay,
                    color: sevenDayColor(for: entry.snapshot?.sevenDay?.percentage ?? 0)
                )
            }

            // Middle row: Opus + Sonnet
            HStack(spacing: 10) {
                ringTile(label: "Opus", limit: entry.snapshot?.opus, color: .orange)
                ringTile(label: "Sonnet", limit: entry.snapshot?.sonnet, color: .blue)
            }

            // Bottom: Extra Usage (full width)
            extraUsageBand(entry.snapshot?.extraUsage)
        }
        .padding(12)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func ringTile(
        label: String,
        limit: UsageSnapshot.Limit?,
        color: Color
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let limit {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.18), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(limit.percentage) / 100.0)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(limit.percentage))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                }
                .aspectRatio(1, contentMode: .fit)

                if let resetsAt = limit.resetsAt {
                    Text(resetText(for: resetsAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func extraUsageBand(_ extra: UsageSnapshot.Extra?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "creditcard.fill")
                .font(.caption2)
                .foregroundStyle(.pink)

            Text("Extra Usage")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if let extra, let used = extra.used, let limit = extra.limit, limit > 0 {
                Text(String(format: "$%.2f / $%.0f", used, limit))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)
                    .foregroundStyle(.pink)
            } else {
                Text("Not enabled")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.pink.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
