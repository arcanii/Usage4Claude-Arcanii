//
//  UsageRowComponents.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Mini Progress Icon Component

/// Mini progress icon (with percentage number and progress arc, consistent with menu bar icon style)
struct MiniProgressIcon: View {
    let type: LimitType
    let color: Color
    let percentage: Double
    let size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            let lineWidth: CGFloat = 2.2
            let rect = CGRect(origin: .zero, size: canvasSize)
            let fullPath = IconShapePaths.pathForLimitType(type, in: rect)

            // 1. Shape border (colored)
            context.stroke(fullPath, with: .color(color), lineWidth: lineWidth)

            // 2. Percentage number (centered)
            let fontSize = percentage >= 100 ? canvasSize.width * 0.28 : canvasSize.width * 0.38
            let text = Text("\(Int(percentage))")
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
            context.draw(text, at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Unified Limit Row Component

/// Unified limit row component (supports all 5 limit types)
struct UnifiedLimitRow: View {
    let type: LimitType
    let data: UsageData
    let showRemainingMode: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Icon (with percentage number and progress arc)
            MiniProgressIcon(type: type, color: iconColor, percentage: percentageValue ?? 0)

            // Limit type name
            Text(limitName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            // Right side: reset time or remaining quota
            Text(displayValue)
                .font(.system(size: 12))
                .fontWeight(.medium)
                .id(showRemainingMode ? "remaining" : "reset")  // Force recognition as different views
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Computed Properties

    private var limitName: String {
        switch type {
        case .fiveHour:
            return L.Limit.fiveHour
        case .sevenDay:
            return L.Limit.sevenDay
        case .opusWeekly:
            return L.Limit.opusWeekly
        case .sonnetWeekly:
            return L.Limit.sonnetWeekly
        case .extraUsage:
            return L.Limit.extraUsage
        }
    }

    private var iconColor: Color {
        switch type {
        case .fiveHour:
            return .green  // Green for 5-hour
        case .sevenDay:
            return .purple
        case .opusWeekly:
            return .orange
        case .sonnetWeekly:
            return .blue  // Blue for 7-day Sonnet
        case .extraUsage:
            return .pink
        }
    }

    private var percentageValue: Double? {
        switch type {
        case .fiveHour:   return data.fiveHour?.percentage
        case .sevenDay:   return data.sevenDay?.percentage
        case .opusWeekly: return data.opus?.percentage
        case .sonnetWeekly: return data.sonnet?.percentage
        case .extraUsage: return data.extraUsage?.percentage
        }
    }

    private var displayValue: String {
        switch type {
        case .fiveHour:
            guard let fiveHour = data.fiveHour else { return "-" }
            return showRemainingMode ? fiveHour.formattedCompactRemaining : fiveHour.formattedCompactResetTime

        case .sevenDay:
            guard let sevenDay = data.sevenDay else { return "-" }
            return showRemainingMode ? sevenDay.formattedCompactRemaining : sevenDay.formattedCompactResetDate

        case .opusWeekly:
            guard let opus = data.opus else { return "-" }
            return showRemainingMode ? opus.formattedCompactRemaining : opus.formattedCompactResetDate

        case .sonnetWeekly:
            guard let sonnet = data.sonnet else { return "-" }
            return showRemainingMode ? sonnet.formattedCompactRemaining : sonnet.formattedCompactResetDate

        case .extraUsage:
            guard let extra = data.extraUsage else { return "-" }
            return showRemainingMode ? extra.formattedRemainingAmount : extra.formattedCompactAmount
        }
    }
}
