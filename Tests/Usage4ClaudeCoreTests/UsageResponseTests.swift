import XCTest
@testable import Usage4ClaudeCore

/// Tests for `UsageResponse.toUsageData()` — the JSON → in-memory transform
/// that backs the main /api/organizations/<id>/usage fetch.
///
/// Specs the production code intends to honor:
/// - 5-hour data is always parsed (utilization + resets_at).
/// - 7-day always emits a placeholder. Every Claude account has a 7-day limit
///   even before usage starts; when `seven_day` is missing OR returns
///   (utilization=0, resets_at=null), the transform yields a 0% placeholder
///   so the UI can still display the row from day one.
/// - Opus and Sonnet are nil when the field is missing OR when
///   utilization=0 AND resets_at=nil (the API's "no data" sentinel).
/// - resets_at strings are rounded to the nearest whole second so the UI
///   countdown doesn't jitter across `.645` / `.159` fractional boundaries.
final class UsageResponseTests: XCTestCase {

    // MARK: - Decode helpers

    private func decode(_ json: String) throws -> UsageResponse {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    // MARK: - 5-hour limit (always parsed)

    func testFiveHourParsesWithIntegerUtilization() throws {
        let json = """
        {
            "five_hour": { "utilization": 42, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()

        XCTAssertNotNil(usage.fiveHour)
        XCTAssertEqual(usage.fiveHour?.percentage, 42)
        XCTAssertNotNil(usage.fiveHour?.resetsAt)
    }

    func testFiveHourParsesFloatingPointUtilization() throws {
        let json = """
        {
            "five_hour": { "utilization": 73.5, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.fiveHour?.percentage, 73.5)
    }

    func testFiveHourMissingResetsAtParsesPercentage() throws {
        // resets_at can be nil when usage hasn't started — percentage still parses.
        let json = """
        {
            "five_hour": { "utilization": 0, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.fiveHour?.percentage, 0)
        XCTAssertNil(usage.fiveHour?.resetsAt)
    }

    // MARK: - 7-day limit (always emits a placeholder)

    func testSevenDayMissingFieldReturnsZeroPlaceholder() throws {
        // Every Claude account has a 7-day limit; when the API doesn't include
        // a `seven_day` field at all (e.g. brand-new accounts), production
        // code emits a 0% placeholder so the UI can still display the row.
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNotNil(usage.sevenDay)
        XCTAssertEqual(usage.sevenDay?.percentage, 0)
        XCTAssertNil(usage.sevenDay?.resetsAt)
    }

    func testSevenDayWithZeroUtilizationAndNoResetReturnsZeroPlaceholder() throws {
        // Same intent as the missing-field case: when the API returns
        // (utilization=0, resets_at=null) the row is shown with 0%, not hidden.
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": { "utilization": 0, "resets_at": null },
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNotNil(usage.sevenDay)
        XCTAssertEqual(usage.sevenDay?.percentage, 0)
        XCTAssertNil(usage.sevenDay?.resetsAt)
    }

    func testSevenDayWithRealDataIsParsed() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": { "utilization": 55, "resets_at": "2026-05-08T15:00:00.000Z" },
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.sevenDay?.percentage, 55)
        XCTAssertNotNil(usage.sevenDay?.resetsAt)
    }

    func testOpusAndSonnetMissingFieldsAreNil() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNil(usage.opus)
        XCTAssertNil(usage.sonnet)
    }

    func testOpusZeroSentinelIsNil() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": { "utilization": 0, "resets_at": null },
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNil(usage.opus)
    }

    func testSonnetZeroSentinelIsNil() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": { "utilization": 0, "resets_at": null }
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNil(usage.sonnet)
    }

    func testOpusAndSonnetWithRealDataAreParsed() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus":   { "utilization": 25, "resets_at": "2026-05-08T15:00:00.000Z" },
            "seven_day_sonnet": { "utilization": 67, "resets_at": "2026-05-08T15:00:00.000Z" }
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.opus?.percentage, 25)
        XCTAssertEqual(usage.sonnet?.percentage, 67)
    }

    // MARK: - resets_at fractional-second rounding

    func testResetTimeRoundsFractionalSecondsUp() throws {
        // .645 → next whole second
        let json = """
        {
            "five_hour": { "utilization": 50, "resets_at": "2026-05-01T05:59:59.645Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        guard let resetsAt = usage.fiveHour?.resetsAt else {
            XCTFail("expected resetsAt")
            return
        }
        // Rounded interval should land exactly on a whole-second boundary.
        let interval = resetsAt.timeIntervalSinceReferenceDate
        XCTAssertEqual(interval, interval.rounded(), accuracy: 0.0001,
                       "resets_at should be rounded to the nearest whole second")
    }

    func testResetTimeRoundsFractionalSecondsDown() throws {
        // .159 → previous whole second
        let json = """
        {
            "five_hour": { "utilization": 50, "resets_at": "2026-05-01T06:00:00.159Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        guard let resetsAt = usage.fiveHour?.resetsAt else {
            XCTFail("expected resetsAt")
            return
        }
        let interval = resetsAt.timeIntervalSinceReferenceDate
        XCTAssertEqual(interval, interval.rounded(), accuracy: 0.0001)
    }

    // MARK: - Extra Usage is always nil from this transform

    func testToUsageDataLeavesExtraUsageNil() throws {
        // Extra Usage flows through a separate fetcher; UsageResponse must
        // never invent it.
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNil(usage.extraUsage)
    }

    // MARK: - Weekly slot positions must never shift

    /// REGRESSION GUARD. An account can have a Sonnet weekly limit with no Opus one.
    /// The two legacy fields are position-fixed: slot 1 may be filled while slot 0 is
    /// empty. Folding them into a plain array (as upstream `59f4efd` does) collapses
    /// Sonnet into the Opus slot — silent corruption, since `UsageHistorySampleBridge`
    /// writes `opusPct: data.opus?.percentage` into the append-only NDJSON history.
    func testLegacySonnetWithoutOpusKeepsItsOwnSlot() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": { "utilization": 67, "resets_at": "2026-05-01T15:00:00.000Z" }
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNil(usage.opus, "a Sonnet-only week must NOT promote Sonnet into the Opus slot")
        XCTAssertEqual(usage.sonnet?.percentage, 67)
    }

    /// Same guard for the API's "no data" sentinel (utilization 0 + resets_at null),
    /// which `toUsageData` already treats as an absent Opus.
    func testZeroSentinelOpusWithRealSonnetKeepsSlots() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": { "utilization": 0, "resets_at": null },
            "seven_day_sonnet": { "utilization": 92, "resets_at": "2026-05-01T15:00:00.000Z" }
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNil(usage.opus)
        XCTAssertEqual(usage.sonnet?.percentage, 92)
    }

    // MARK: - limits[] forward-compat backfill (Claude 5 era)

    /// Captured from the live `/api/organizations/<id>/usage` response on 2026-08-26.
    /// The API has already moved: `seven_day_opus` / `seven_day_sonnet` are null and the
    /// per-model weekly limit arrives as a `weekly_scoped` entry in `limits[]` carrying
    /// only `scope.model.display_name` (note `model.id` is null). Session and weekly_all
    /// duplicate the legacy `five_hour` / `seven_day` values. Unknown sibling keys
    /// (codenamed future models) must be ignored without breaking the decode.
    func testLiveResponseShapeBackfillsScopedWeeklyModel() throws {
        let json = """
        {
            "five_hour": { "utilization": 71.0, "resets_at": "2026-08-26T14:20:00.027310+00:00" },
            "seven_day": { "utilization": 76.0, "resets_at": "2026-08-27T23:00:00.027333+00:00" },
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "seven_day_cowork": null,
            "nimbus_quill": { "utilization": 0.0, "resets_at": null },
            "limits": [
                { "kind": "session", "group": "session", "percent": 71, "severity": "normal",
                  "resets_at": "2026-08-26T14:20:00.027310+00:00", "scope": null, "is_active": false },
                { "kind": "weekly_all", "group": "weekly", "percent": 76, "severity": "warning",
                  "resets_at": "2026-08-27T23:00:00.027333+00:00", "scope": null, "is_active": true },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 13, "severity": "normal",
                  "resets_at": "2026-08-27T23:00:00.027631+00:00",
                  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
                  "is_active": false }
            ]
        }
        """
        let usage = try decode(json).toUsageData()

        // Legacy rows still come from the dedicated fields.
        XCTAssertEqual(usage.fiveHour?.percentage, 71)
        XCTAssertEqual(usage.sevenDay?.percentage, 76)

        // The scoped per-model weekly limit backfills the first free slot — without this
        // the weekly model row would silently disappear on a live account.
        XCTAssertEqual(usage.opus?.percentage, 13)
        // ...and carries the real model name so the row reads "Fable", not "Opus Weekly".
        XCTAssertEqual(usage.opusModelName, "Fable")
        // session / weekly_all carry scope == nil and must never be treated as per-model.
        XCTAssertNil(usage.sonnet)
        XCTAssertNil(usage.sonnetModelName)
        // Only one scoped model, and it filled slot 0 — nothing overflows.
        XCTAssertTrue(usage.overflowWeeklyModels.isEmpty)
    }

    func testThirdScopedModelOverflowsPastBothSlots() throws {
        // Legacy Opus + legacy Sonnet occupy both slots, so a scoped model arriving
        // alongside them has nowhere to go and must surface as an overflow row.
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": { "utilization": 40, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day_sonnet": { "utilization": 50, "resets_at": "2026-05-01T15:00:00.000Z" },
            "limits": [
                { "kind": "weekly_scoped", "percent": 13, "resets_at": null,
                  "scope": { "model": { "id": null, "display_name": "Fable" } } }
            ]
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.opus?.percentage, 40)
        XCTAssertEqual(usage.sonnet?.percentage, 50)
        // Legacy slots carry no model name — the UI falls back to the localized label.
        XCTAssertNil(usage.opusModelName)
        XCTAssertNil(usage.sonnetModelName)
        XCTAssertEqual(usage.overflowWeeklyModels.count, 1)
        XCTAssertEqual(usage.overflowWeeklyModels.first?.modelName, "Fable")
        XCTAssertEqual(usage.overflowWeeklyModels.first?.limit.percentage, 13)
    }

    func testTwoScopedModelsFillBothSlotsInWireOrder() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "limits": [
                { "kind": "weekly_scoped", "percent": 11, "resets_at": null,
                  "scope": { "model": { "id": null, "display_name": "Fable" } } },
                { "kind": "weekly_scoped", "percent": 22, "resets_at": null,
                  "scope": { "model": { "id": null, "display_name": "Opus" } } },
                { "kind": "weekly_scoped", "percent": 33, "resets_at": null,
                  "scope": { "model": { "id": null, "display_name": "Sonnet" } } }
            ]
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.opusModelName, "Fable")
        XCTAssertEqual(usage.opus?.percentage, 11)
        XCTAssertEqual(usage.sonnetModelName, "Opus")
        XCTAssertEqual(usage.sonnet?.percentage, 22)
        // The third model overflows into its own row rather than being dropped.
        XCTAssertEqual(usage.overflowWeeklyModels.map(\.modelName), ["Sonnet"])
    }

    func testLimitsArrayBackfillsOpusSonnetWhenLegacyFieldsAbsent() throws {
        // If the API stops populating seven_day_opus/seven_day_sonnet and instead
        // reports per-model weekly limits in `limits[]`, the opus/sonnet display
        // slots are backfilled (in order) so the weekly rows don't silently vanish.
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "limits": [
                { "kind": "weekly_scoped", "percent": 33, "resets_at": null,
                  "scope": { "model": { "id": "fable", "display_name": "Fable" } } },
                { "kind": "weekly_scoped", "percent": 66, "resets_at": null,
                  "scope": { "model": { "id": "sonnet", "display_name": "Sonnet" } } }
            ]
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.opus?.percentage, 33)
        XCTAssertEqual(usage.sonnet?.percentage, 66)
    }

    func testLegacyWeeklyFieldsTakePrecedenceOverLimitsArray() throws {
        // When both the legacy fields and limits[] are present, the legacy fields win
        // (backfill is inert for filled slots), keeping current behavior unchanged.
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": { "utilization": 80, "resets_at": "2026-05-01T15:00:00.000Z" },
            "seven_day_sonnet": null,
            "limits": [
                { "kind": "weekly_scoped", "percent": 12, "resets_at": null,
                  "scope": { "model": { "id": "fable", "display_name": "Fable" } } }
            ]
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertEqual(usage.opus?.percentage, 80, "legacy seven_day_opus must win over limits[]")
        // The still-empty sonnet slot is backfilled from the unused scoped entry.
        XCTAssertEqual(usage.sonnet?.percentage, 12)
    }

    func testLimitsArrayEntriesWithoutModelNameAreIgnored() throws {
        // Entries lacking a model display_name (e.g. session / weekly_all scopes) are
        // not per-model weekly limits and must not be backfilled into opus/sonnet.
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": null },
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "limits": [
                { "kind": "weekly_all", "percent": 50, "resets_at": null, "scope": { "surface": "web" } }
            ]
        }
        """
        let usage = try decode(json).toUsageData()
        XCTAssertNil(usage.opus)
        XCTAssertNil(usage.sonnet)
    }

    // MARK: - Plans without a usage dashboard (upstream issues #83 / #74)

    /// Free Tier accounts, and Team/Enterprise orgs that haven't enabled the member
    /// usage dashboard, answer HTTP 200 with every limit window null. `five_hour` used
    /// to be non-optional, so the whole payload failed to decode and surfaced as
    /// "check if your credentials are correct" — the wrong advice for valid credentials.
    func testAllLimitsNullStillDecodes() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "extra_usage": { "is_enabled": true, "monthly_limit": 2000000, "used_credits": 1309.0 }
        }
        """
        let response = try decode(json)
        XCTAssertNil(response.five_hour)
        XCTAssertTrue(response.hasNoLimitData)
        XCTAssertTrue(response.isUsageDashboardUnavailable)
    }

    /// The field being absent entirely must behave exactly like an explicit null.
    func testFiveHourAbsentEntirelyStillDecodes() throws {
        let json = """
        {
            "seven_day": null
        }
        """
        let response = try decode(json)
        XCTAssertNil(response.five_hour)
        XCTAssertTrue(response.isUsageDashboardUnavailable)
        XCTAssertNil(response.toUsageData().fiveHour)
    }

    /// Real data wins over the flag. `member_dashboard_available` is decoded for
    /// logging and the diagnostic report, but the verdict deliberately ignores it: if
    /// personal Pro/Max accounts also report false (meaning "not part of an org
    /// dashboard" rather than "no usage data"), trusting it would mark every healthy
    /// account unavailable.
    func testDashboardFlagFalseWithRealDataStaysUsable() throws {
        let json = """
        {
            "member_dashboard_available": false,
            "five_hour": { "utilization": 20, "resets_at": "2026-07-03T18:19:59.000Z" },
            "seven_day": null
        }
        """
        let response = try decode(json)
        XCTAssertFalse(response.hasNoLimitData)
        XCTAssertFalse(response.isUsageDashboardUnavailable)
        XCTAssertEqual(response.toUsageData().fiveHour?.percentage, 20)
    }

    func testDashboardFlagIsDecodedForDiagnostics() throws {
        let json = """
        {
            "member_dashboard_available": false,
            "five_hour": null,
            "seven_day": null
        }
        """
        XCTAssertEqual(try decode(json).member_dashboard_available, false)
        // Absent from the payload entirely: nil, never defaulted either way.
        XCTAssertNil(try decode(#"{ "five_hour": null }"#).member_dashboard_available)
    }

    /// An empty `limits` array carries no more information than a missing one.
    func testEmptyLimitsArrayWithAllNullWindowsIsUnavailable() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": null,
            "limits": []
        }
        """
        XCTAssertTrue(try decode(json).isUsageDashboardUnavailable)
    }

    /// A null 5-hour window alongside a real 7-day window is not a dead account: keep
    /// the 7-day row, leave the 5-hour slot empty, and don't fake a 0% placeholder.
    func testNullFiveHourWithRealSevenDayKeepsSevenDay() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": { "utilization": 37.5, "resets_at": "2026-07-08T00:00:00.000Z" }
        }
        """
        let response = try decode(json)
        XCTAssertFalse(response.isUsageDashboardUnavailable)

        let usage = response.toUsageData()
        XCTAssertNil(usage.fiveHour)
        XCTAssertEqual(usage.sevenDay?.percentage, 37.5)
        // primaryLimit falls back to the 7-day window when 5-hour is absent.
        XCTAssertEqual(usage.primaryLimit?.percentage, 37.5)
    }

    /// Fork-only regression. The worst case isn't the all-null payload — it's a null
    /// `five_hour` arriving with real `limits[]` data, a fully usable response that the
    /// old non-optional field threw away. This also proves a null 5-hour window does
    /// not disturb the fork's position-fixed weekly slot resolution, which upstream's
    /// single-array model does not have.
    func testNullFiveHourWithScopedWeeklyModelsKeepsSlotResolution() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": { "utilization": 12, "resets_at": "2026-07-08T00:00:00.000Z" },
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "limits": [
                { "kind": "weekly_scoped", "percent": 64, "resets_at": null, "scope": { "model": { "display_name": "Fable" } } },
                { "kind": "weekly_scoped", "percent": 21, "resets_at": null, "scope": { "model": { "display_name": "Sonnet" } } }
            ]
        }
        """
        let response = try decode(json)
        XCTAssertFalse(response.isUsageDashboardUnavailable, "limits[] data alone is live data, not an empty dashboard")

        let usage = response.toUsageData()
        XCTAssertNil(usage.fiveHour)
        XCTAssertEqual(usage.opus?.percentage, 64)
        XCTAssertEqual(usage.opusModelName, "Fable")
        XCTAssertEqual(usage.sonnet?.percentage, 21)
        XCTAssertEqual(usage.sonnetModelName, "Sonnet")
    }
}
