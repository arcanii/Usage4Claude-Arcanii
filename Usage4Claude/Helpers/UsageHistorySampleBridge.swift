//
//  UsageHistorySampleBridge.swift
//  Usage4Claude
//
//  Bridges the in-memory `UsageData` (private to the main app target) to the
//  Codable `UsageHistorySample` shared with the widget extension via the App
//  Group's NDJSON history file. Same pattern as `UsageSnapshotBridge`.
//

import Foundation

extension UsageHistorySample {
    init(from data: UsageData, at date: Date = Date()) {
        self.init(
            timestamp: date,
            fiveHourPct: data.fiveHour?.percentage,
            sevenDayPct: data.sevenDay?.percentage,
            opusPct: data.opus?.percentage,
            sonnetPct: data.sonnet?.percentage,
            extraUsageUsed: data.extraUsage?.used,
            extraUsageLimit: data.extraUsage?.limit,
            extraUsageCurrency: data.extraUsage?.enabled == true ? data.extraUsage?.currency : nil
        )
    }
}
