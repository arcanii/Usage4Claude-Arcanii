//
//  LimitDisplayLayout.swift
//  Usage4Claude
//
//  Pure display decisions: which limits are listed, and how the popover's ring is
//  laid out. Kept free of UserSettings, localization and SwiftUI so the standalone
//  SwiftPM package under Tests/ can compile and test it.
//

import Foundation

// MARK: - Limit Types

/// Limit type
///
/// Defined here rather than in `UserSettings.swift` so the display decisions below can
/// be unit tested. The localized `displayName` stays in `UserSettings.swift`, because it
/// needs `LocalizationHelper`.
enum LimitType: String, CaseIterable, Codable {
    /// 5-hour limit
    case fiveHour = "five_hour"
    /// 7-day limit
    case sevenDay = "seven_day"
    /// Extra Usage paid overage allowance
    case extraUsage = "extra_usage"
    /// Opus weekly limit
    case opusWeekly = "seven_day_opus"
    /// Sonnet weekly limit
    case sonnetWeekly = "seven_day_sonnet"

    /// Whether this is a circular icon (5-hour and 7-day)
    var isCircular: Bool {
        return self == .fiveHour || self == .sevenDay
    }

    /// Whether this is a rectangular icon (Opus and Sonnet)
    var isRectangular: Bool {
        return self == .opusWeekly || self == .sonnetWeekly
    }

    /// Whether this is a hexagonal icon (Extra Usage)
    var isHexagonal: Bool {
        return self == .extraUsage
    }
}

// MARK: - Display Layout

/// Which limits to show, and which of them the popover draws as rings.
///
/// The popover's ring area makes three decisions: the large primary ring, the thin
/// outer 7-day ring, and whether the center shows one percentage or two stacked. All
/// three come from here so they can't disagree. When they lived in separate view
/// helpers they did: v1.9.5 changed which limit the primary ring picked but not the
/// outer ring's condition, so custom mode drew the 7-day limit as both rings.
enum LimitDisplayLayout {

    /// Canonical display order: fiveHour -> sevenDay -> extraUsage -> opus -> sonnet
    static let canonicalOrder: [LimitType] = [.fiveHour, .sevenDay, .extraUsage, .opusWeekly, .sonnetWeekly]

    // MARK: Listed types

    /// Smart mode: every limit the account actually has, in canonical order.
    ///
    /// 5-hour and 7-day are listed only when the account has them. They used to be
    /// appended unconditionally, on the reasoning that "every Claude account is subject
    /// to both limits" (backported from upstream `fffff55`). That stopped being true
    /// when Anthropic dropped the 5-hour window from the top subscription: the API
    /// returns no 5-hour window at all.
    ///
    /// `sevenDay` is still effectively always present: `toUsageData()` emits a 0%
    /// placeholder for it so brand-new accounts show the row from day one.
    static func smartTypes(for data: UsageData) -> [LimitType] {
        var types: [LimitType] = []
        if data.fiveHour != nil {
            types.append(.fiveHour)
        }
        if data.sevenDay != nil {
            types.append(.sevenDay)
        }
        if data.extraUsage?.enabled == true {
            types.append(.extraUsage)
        }
        if data.opus != nil {
            types.append(.opusWeekly)
        }
        if data.sonnet != nil {
            types.append(.sonnetWeekly)
        }
        return types
    }

    /// Custom mode: the user's selection in canonical order, whether or not it has data.
    static func customTypes(selected: Set<LimitType>) -> [LimitType] {
        return canonicalOrder.filter { selected.contains($0) }
    }

    // MARK: Popover ring

    /// Which limit the popover's large ring shows, or nil for no ring.
    ///
    /// 5-hour first, then 7-day. A type is used when it is active and either has data
    /// or `showPlaceholder` is set. `showPlaceholder` is true only in custom mode with
    /// the selection applied to the popover. There, the user ticked the limit, so it
    /// keeps the ring as a 0% placeholder rather than handing it to 7-day.
    ///
    /// Design from upstream PR #97 (coriff), which has the same function as a view
    /// helper; it is a parameter here so it can be tested.
    static func primaryRingType(data: UsageData, activeTypes: [LimitType], showPlaceholder: Bool) -> LimitType? {
        return [LimitType.fiveHour, .sevenDay].first { type in
            activeTypes.contains(type) && hasRing(type, in: data, showPlaceholder: showPlaceholder)
        }
    }

    /// Whether the popover draws the thin outer 7-day ring around a 5-hour primary
    /// ring, and stacks both percentages in the center.
    ///
    /// Only when the primary ring is 5-hour. If the primary ring already fell back to
    /// 7-day, an outer ring would draw the same limit a second time.
    static func showsSevenDayOuterRing(data: UsageData, activeTypes: [LimitType], showPlaceholder: Bool) -> Bool {
        return primaryRingType(data: data, activeTypes: activeTypes, showPlaceholder: showPlaceholder) == .fiveHour
            && activeTypes.contains(.sevenDay)
            && hasRing(.sevenDay, in: data, showPlaceholder: showPlaceholder)
    }

    /// Whether `type` can be drawn as a ring: it is circular and has data, or a
    /// placeholder is allowed.
    private static func hasRing(_ type: LimitType, in data: UsageData, showPlaceholder: Bool) -> Bool {
        switch type {
        case .fiveHour:
            return data.fiveHour != nil || showPlaceholder
        case .sevenDay:
            return data.sevenDay != nil || showPlaceholder
        case .extraUsage, .opusWeekly, .sonnetWeekly:
            return false
        }
    }
}
