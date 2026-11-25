import XCTest
@testable import Usage4ClaudeCore

/// Tests for `LimitDisplayLayout`: which limits are listed, and how the popover's
/// ring area is laid out.
///
/// Specs the production code intends to honor:
/// - Smart mode lists a limit only when the account has it. A plan with no 5-hour
///   window (Anthropic's top subscription, from 2026-11) lists no 5-hour row.
/// - Custom mode lists the user's selection in canonical order, data or not.
/// - The primary ring prefers 5-hour, then 7-day. In custom mode a selected limit with
///   no data keeps the ring as a 0% placeholder.
/// - The outer 7-day ring, and the two stacked center percentages, appear only around
///   a 5-hour primary ring. The 7-day limit is never drawn as both rings.
final class LimitDisplayLayoutTests: XCTestCase {

    // MARK: - Fixtures

    private func limit(_ percentage: Double) -> UsageData.LimitData {
        UsageData.LimitData(percentage: percentage, resetsAt: nil)
    }

    private func usage(
        fiveHour: UsageData.LimitData? = nil,
        sevenDay: UsageData.LimitData? = nil,
        legacyOpus: UsageData.LimitData? = nil,
        legacySonnet: UsageData.LimitData? = nil,
        extraUsageEnabled: Bool? = nil
    ) -> UsageData {
        UsageData(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            legacyOpus: legacyOpus,
            legacySonnet: legacySonnet,
            scopedWeeklyModels: [],
            extraUsage: extraUsageEnabled.map {
                ExtraUsageData(enabled: $0, used: nil, limit: nil, currency: "USD")
            }
        )
    }

    /// An account that still has a 5-hour window.
    private var withFiveHour: UsageData { usage(fiveHour: limit(40), sevenDay: limit(20)) }

    /// An account whose plan has no 5-hour window: the API returns only 7-day.
    private var withoutFiveHour: UsageData { usage(sevenDay: limit(20)) }

    // MARK: - Smart mode listing

    func testSmartListsBothCircularLimitsWhenPresent() {
        XCTAssertEqual(LimitDisplayLayout.smartTypes(for: withFiveHour), [.fiveHour, .sevenDay])
    }

    func testSmartOmitsFiveHourWhenThePlanHasNone() {
        XCTAssertEqual(LimitDisplayLayout.smartTypes(for: withoutFiveHour), [.sevenDay])
    }

    func testSmartListsEverythingInCanonicalOrder() {
        let data = usage(
            fiveHour: limit(1),
            sevenDay: limit(2),
            legacyOpus: limit(3),
            legacySonnet: limit(4),
            extraUsageEnabled: true
        )
        XCTAssertEqual(LimitDisplayLayout.smartTypes(for: data), LimitDisplayLayout.canonicalOrder)
    }

    func testSmartListsExtraUsageOnlyWhenEnabled() {
        XCTAssertFalse(LimitDisplayLayout.smartTypes(for: usage(sevenDay: limit(0), extraUsageEnabled: false))
            .contains(.extraUsage))
        XCTAssertTrue(LimitDisplayLayout.smartTypes(for: usage(sevenDay: limit(0), extraUsageEnabled: true))
            .contains(.extraUsage))
    }

    /// The real payload for a plan without a 5-hour window, decoded end to end:
    /// `five_hour` null must reach the display layer as "no 5-hour row".
    func testSmartListingFromDecodedPayloadWithNullFiveHour() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": { "utilization": 20, "resets_at": "2026-11-30T15:00:00.000Z" },
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let data = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8)).toUsageData()
        let types = LimitDisplayLayout.smartTypes(for: data)

        XCTAssertEqual(types, [.sevenDay])
        XCTAssertEqual(LimitDisplayLayout.primaryRingType(data: data, activeTypes: types, showPlaceholder: false), .sevenDay)
        XCTAssertFalse(LimitDisplayLayout.showsSevenDayOuterRing(data: data, activeTypes: types, showPlaceholder: false))
    }

    // MARK: - Custom mode listing

    func testCustomListsSelectionInCanonicalOrderRegardlessOfData() {
        XCTAssertEqual(
            LimitDisplayLayout.customTypes(selected: [.sonnetWeekly, .fiveHour, .extraUsage]),
            [.fiveHour, .extraUsage, .sonnetWeekly]
        )
    }

    func testCustomListsNothingForAnEmptySelection() {
        XCTAssertEqual(LimitDisplayLayout.customTypes(selected: []), [])
    }

    // MARK: - Ring layout, smart mode (no placeholder)

    func testSmartWithFiveHourDrawsFiveHourInsideSevenDay() {
        let types = LimitDisplayLayout.smartTypes(for: withFiveHour)
        XCTAssertEqual(LimitDisplayLayout.primaryRingType(data: withFiveHour, activeTypes: types, showPlaceholder: false), .fiveHour)
        XCTAssertTrue(LimitDisplayLayout.showsSevenDayOuterRing(data: withFiveHour, activeTypes: types, showPlaceholder: false))
    }

    /// v1.9.5's fix: the ring had vanished entirely for plans without a 5-hour window.
    func testSmartWithoutFiveHourPromotesSevenDayToTheOnlyRing() {
        let types = LimitDisplayLayout.smartTypes(for: withoutFiveHour)
        XCTAssertEqual(LimitDisplayLayout.primaryRingType(data: withoutFiveHour, activeTypes: types, showPlaceholder: false), .sevenDay)
        XCTAssertFalse(LimitDisplayLayout.showsSevenDayOuterRing(data: withoutFiveHour, activeTypes: types, showPlaceholder: false))
    }

    /// Upstream's smart mode still lists 5-hour unconditionally. Even given that list,
    /// the ring falls back to 7-day without drawing it twice (upstream PR #97's case).
    func testFiveHourListedWithoutDataFallsBackWithoutPlaceholder() {
        let types: [LimitType] = [.fiveHour, .sevenDay]
        XCTAssertEqual(LimitDisplayLayout.primaryRingType(data: withoutFiveHour, activeTypes: types, showPlaceholder: false), .sevenDay)
        XCTAssertFalse(LimitDisplayLayout.showsSevenDayOuterRing(data: withoutFiveHour, activeTypes: types, showPlaceholder: false))
    }

    func testNoActiveTypesDrawsNoRing() {
        XCTAssertNil(LimitDisplayLayout.primaryRingType(data: withFiveHour, activeTypes: [], showPlaceholder: false))
        XCTAssertFalse(LimitDisplayLayout.showsSevenDayOuterRing(data: withFiveHour, activeTypes: [], showPlaceholder: false))
    }

    // MARK: - Ring layout, custom mode (placeholder allowed)

    /// The v1.9.5 regression. Custom mode with the default selection, on a plan with no
    /// 5-hour window: v1.9.5 made 7-day the primary ring while the outer-ring check
    /// still saw both types selected, so 7-day was drawn as both rings under a "0%"
    /// 5-hour center. The ticked 5-hour limit must keep the ring as a placeholder.
    func testCustomDefaultSelectionWithoutFiveHourKeepsFiveHourPlaceholder() {
        let types = LimitDisplayLayout.customTypes(selected: [.fiveHour, .sevenDay])
        XCTAssertEqual(LimitDisplayLayout.primaryRingType(data: withoutFiveHour, activeTypes: types, showPlaceholder: true), .fiveHour)
        XCTAssertTrue(LimitDisplayLayout.showsSevenDayOuterRing(data: withoutFiveHour, activeTypes: types, showPlaceholder: true))
    }

    func testCustomSevenDayOnlyDrawsSevenDayAlone() {
        let types = LimitDisplayLayout.customTypes(selected: [.sevenDay])
        XCTAssertEqual(LimitDisplayLayout.primaryRingType(data: withFiveHour, activeTypes: types, showPlaceholder: true), .sevenDay)
        XCTAssertFalse(LimitDisplayLayout.showsSevenDayOuterRing(data: withFiveHour, activeTypes: types, showPlaceholder: true))
    }

    func testCustomFiveHourOnlyWithoutDataKeepsPlaceholderAlone() {
        let types = LimitDisplayLayout.customTypes(selected: [.fiveHour])
        XCTAssertEqual(LimitDisplayLayout.primaryRingType(data: withoutFiveHour, activeTypes: types, showPlaceholder: true), .fiveHour)
        XCTAssertFalse(LimitDisplayLayout.showsSevenDayOuterRing(data: withoutFiveHour, activeTypes: types, showPlaceholder: true))
    }

    func testCustomWithNoCircularSelectionDrawsNoRing() {
        let types = LimitDisplayLayout.customTypes(selected: [.opusWeekly, .sonnetWeekly, .extraUsage])
        XCTAssertNil(LimitDisplayLayout.primaryRingType(data: withFiveHour, activeTypes: types, showPlaceholder: true))
        XCTAssertFalse(LimitDisplayLayout.showsSevenDayOuterRing(data: withFiveHour, activeTypes: types, showPlaceholder: true))
    }

    // MARK: - Invariants over every configuration

    /// Every subset of limit types, against accounts with and without each circular
    /// window, with and without the placeholder. The ring area must stay coherent:
    /// the primary ring is a selected circular type, the outer ring only ever wraps a
    /// 5-hour primary, and 7-day is never drawn twice.
    func testRingLayoutIsCoherentForEveryConfiguration() {
        let all = LimitDisplayLayout.canonicalOrder
        let accounts: [UsageData] = [
            withFiveHour,
            withoutFiveHour,
            usage(fiveHour: limit(10)),
            usage()
        ]

        for mask in 0..<(1 << all.count) {
            let selected = Set(all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] })
            let types = LimitDisplayLayout.customTypes(selected: selected)

            for data in accounts {
                for showPlaceholder in [false, true] {
                    let primary = LimitDisplayLayout.primaryRingType(data: data, activeTypes: types, showPlaceholder: showPlaceholder)
                    let outer = LimitDisplayLayout.showsSevenDayOuterRing(data: data, activeTypes: types, showPlaceholder: showPlaceholder)
                    let context = "selected=\(types.map(\.rawValue)) fiveHour=\(data.fiveHour != nil) sevenDay=\(data.sevenDay != nil) placeholder=\(showPlaceholder)"

                    if let primary {
                        XCTAssertTrue(primary.isCircular, context)
                        XCTAssertTrue(types.contains(primary), context)
                    }
                    if outer {
                        XCTAssertEqual(primary, .fiveHour, "outer 7-day ring around a non-5-hour primary: \(context)")
                        XCTAssertTrue(types.contains(.sevenDay), context)
                    }
                    // Without a placeholder, a ring is only ever drawn from real data.
                    if !showPlaceholder {
                        if primary == .fiveHour { XCTAssertNotNil(data.fiveHour, context) }
                        if primary == .sevenDay { XCTAssertNotNil(data.sevenDay, context) }
                        if outer { XCTAssertNotNil(data.sevenDay, context) }
                    }
                }
            }
        }
    }
}
