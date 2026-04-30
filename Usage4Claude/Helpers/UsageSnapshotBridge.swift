//
//  UsageSnapshotBridge.swift
//  Usage4Claude
//
//  Bridges the in-memory `UsageData` (private to the main app target) to the
//  Codable `UsageSnapshot` shared with the widget extension via the App Group.
//

import Foundation

extension UsageSnapshot {
    init(from data: UsageData, at date: Date = Date()) {
        self.init(
            capturedAt: date,
            fiveHour: data.fiveHour.map { Limit(percentage: $0.percentage, resetsAt: $0.resetsAt) },
            sevenDay: data.sevenDay.map { Limit(percentage: $0.percentage, resetsAt: $0.resetsAt) },
            opus: data.opus.map { Limit(percentage: $0.percentage, resetsAt: $0.resetsAt) },
            sonnet: data.sonnet.map { Limit(percentage: $0.percentage, resetsAt: $0.resetsAt) },
            extraUsage: data.extraUsage.flatMap { extra in
                extra.enabled
                    ? Extra(used: extra.used, limit: extra.limit, currency: extra.currency)
                    : nil
            }
        )
    }
}
