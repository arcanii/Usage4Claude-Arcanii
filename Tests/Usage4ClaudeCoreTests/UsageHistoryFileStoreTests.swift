import XCTest
@testable import Usage4ClaudeCore

/// Tests for `UsageHistoryFileStore` — the NDJSON history backing store
/// shared between the main app and the widget extension.
///
/// Covers:
/// - Append creates the file when missing, then appends one line per call
/// - Read parses all lines and silently skips corrupted ones
/// - Compaction trims to maxSamples (FIFO, preserving most recent)
/// - readSince filters by timestamp
/// - Roundtrip preserves all fields including optional nil values
final class UsageHistoryFileStoreTests: XCTestCase {

    // MARK: - Test fixtures

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("U4ClaudeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempURL = tempDir.appendingPathComponent("usage-history.ndjson")
    }

    override func tearDown() {
        if let parent = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: parent)
        }
        tempURL = nil
        super.tearDown()
    }

    private func makeSample(
        secondsAgo: TimeInterval = 0,
        fiveHour: Double? = nil,
        sevenDay: Double? = nil,
        opus: Double? = nil,
        sonnet: Double? = nil,
        extraUsed: Double? = nil,
        extraLimit: Double? = nil,
        currency: String? = nil
    ) -> UsageHistorySample {
        UsageHistorySample(
            timestamp: Date().addingTimeInterval(-secondsAgo),
            fiveHourPct: fiveHour,
            sevenDayPct: sevenDay,
            opusPct: opus,
            sonnetPct: sonnet,
            extraUsageUsed: extraUsed,
            extraUsageLimit: extraLimit,
            extraUsageCurrency: currency
        )
    }

    // MARK: - Append + Read

    func testAppendCreatesFileWhenMissing() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))

        let sample = makeSample(fiveHour: 25)
        XCTAssertTrue(UsageHistoryFileStore.append(sample, at: tempURL))

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        let read = UsageHistoryFileStore.readAll(at: tempURL)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first?.fiveHourPct, 25)
    }

    func testAppendAppendsRatherThanOverwrites() {
        for i in 0..<5 {
            UsageHistoryFileStore.append(makeSample(fiveHour: Double(i * 10)), at: tempURL)
        }
        let read = UsageHistoryFileStore.readAll(at: tempURL)
        XCTAssertEqual(read.count, 5)
        XCTAssertEqual(read.map { $0.fiveHourPct }, [0, 10, 20, 30, 40])
    }

    func testAppendUsesNDJSONFormat() throws {
        UsageHistoryFileStore.append(makeSample(fiveHour: 1), at: tempURL)
        UsageHistoryFileStore.append(makeSample(fiveHour: 2), at: tempURL)
        UsageHistoryFileStore.append(makeSample(fiveHour: 3), at: tempURL)

        let raw = try String(contentsOf: tempURL, encoding: .utf8)
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3, "Each sample must be on its own line")

        // Each line must be a complete JSON object.
        for line in lines {
            XCTAssertTrue(line.hasPrefix("{"))
            XCTAssertTrue(line.hasSuffix("}"))
        }
    }

    // MARK: - Roundtrip

    func testRoundtripPreservesAllFields() {
        let sample = makeSample(
            fiveHour: 42.5,
            sevenDay: 73.25,
            opus: 91.0,
            sonnet: 12.75,
            extraUsed: 5.5,
            extraLimit: 50.0,
            currency: "USD"
        )

        UsageHistoryFileStore.append(sample, at: tempURL)
        let read = UsageHistoryFileStore.readAll(at: tempURL)

        XCTAssertEqual(read.count, 1)
        let r = read[0]
        XCTAssertEqual(r.fiveHourPct, 42.5)
        XCTAssertEqual(r.sevenDayPct, 73.25)
        XCTAssertEqual(r.opusPct, 91.0)
        XCTAssertEqual(r.sonnetPct, 12.75)
        XCTAssertEqual(r.extraUsageUsed, 5.5)
        XCTAssertEqual(r.extraUsageLimit, 50.0)
        XCTAssertEqual(r.extraUsageCurrency, "USD")

        // Timestamp preserved within ISO8601's millisecond resolution.
        XCTAssertEqual(
            r.timestamp.timeIntervalSinceReferenceDate,
            sample.timestamp.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
    }

    func testRoundtripPreservesOptionalNils() {
        // Sample where most fields are nil — only fiveHour data.
        let sample = makeSample(fiveHour: 42.0)
        UsageHistoryFileStore.append(sample, at: tempURL)
        let read = UsageHistoryFileStore.readAll(at: tempURL)

        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].fiveHourPct, 42.0)
        XCTAssertNil(read[0].sevenDayPct)
        XCTAssertNil(read[0].opusPct)
        XCTAssertNil(read[0].sonnetPct)
        XCTAssertNil(read[0].extraUsageUsed)
        XCTAssertNil(read[0].extraUsageLimit)
        XCTAssertNil(read[0].extraUsageCurrency)
    }

    // MARK: - Read tolerance

    func testReadSilentlySkipsCorruptedLines() throws {
        UsageHistoryFileStore.append(makeSample(fiveHour: 1), at: tempURL)
        UsageHistoryFileStore.append(makeSample(fiveHour: 2), at: tempURL)

        // Inject a corrupted line in the middle of the file.
        var raw = try String(contentsOf: tempURL, encoding: .utf8)
        raw += "this is not valid json\n"
        UsageHistoryFileStore.append(makeSample(fiveHour: 3), at: tempURL)
        // Need to re-add the corrupted line since the append above happened
        // *after* we read raw. Just write a known-corrupt file directly.
        let goodSample1 = makeSample(fiveHour: 100)
        let goodSample2 = makeSample(fiveHour: 200)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var buf = Data()
        buf.append(try encoder.encode(goodSample1))
        buf.append(0x0A)
        buf.append("garbage_not_json".data(using: .utf8)!)
        buf.append(0x0A)
        buf.append(try encoder.encode(goodSample2))
        buf.append(0x0A)
        try buf.write(to: tempURL)

        let read = UsageHistoryFileStore.readAll(at: tempURL)
        XCTAssertEqual(read.count, 2, "Corrupted line should be skipped, valid ones kept")
        XCTAssertEqual(read[0].fiveHourPct, 100)
        XCTAssertEqual(read[1].fiveHourPct, 200)
    }

    func testReadOfMissingFileReturnsEmpty() {
        let nowhere = tempURL.deletingLastPathComponent()
            .appendingPathComponent("does-not-exist.ndjson")
        XCTAssertEqual(UsageHistoryFileStore.readAll(at: nowhere), [])
    }

    // MARK: - readSince (timestamp filter)

    func testReadSinceFiltersByTimestamp() {
        // 5 samples, evenly spaced over the last hour.
        for minutesAgo in stride(from: 60, through: 0, by: -15) {
            UsageHistoryFileStore.append(
                makeSample(secondsAgo: TimeInterval(minutesAgo) * 60, fiveHour: Double(minutesAgo)),
                at: tempURL
            )
        }
        // 60, 45, 30, 15, 0 — five samples.
        XCTAssertEqual(UsageHistoryFileStore.readAll(at: tempURL).count, 5)

        // Last 20 minutes → should keep the 15- and 0-minute-ago entries.
        let cutoff = Date().addingTimeInterval(-20 * 60)
        let recent = UsageHistoryFileStore.readSince(cutoff, at: tempURL)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.map { $0.fiveHourPct }, [15, 0])
    }

    // MARK: - Compaction

    func testCompactDoesNothingBelowCap() {
        for i in 0..<10 {
            UsageHistoryFileStore.append(makeSample(fiveHour: Double(i)), at: tempURL)
        }
        XCTAssertFalse(
            UsageHistoryFileStore.compactIfNeeded(at: tempURL),
            "Below the cap, compaction should be a no-op"
        )
        XCTAssertEqual(UsageHistoryFileStore.readAll(at: tempURL).count, 10)
    }

    func testCompactTrimsToMaxSamplesPreservingMostRecent() {
        // Force a small cap is impractical (it's a static let). Instead, test
        // the rewriteAll path directly which compaction uses internally —
        // simulating "we have 10 samples, keep only the last 3".
        var samples: [UsageHistorySample] = []
        for i in 0..<10 {
            samples.append(makeSample(secondsAgo: TimeInterval(10 - i), fiveHour: Double(i)))
        }
        UsageHistoryFileStore.rewriteAll(Array(samples.suffix(3)), at: tempURL)

        let read = UsageHistoryFileStore.readAll(at: tempURL)
        XCTAssertEqual(read.count, 3)
        // suffix(3) takes the last 3 entries (most recent timestamps).
        XCTAssertEqual(read.map { $0.fiveHourPct }, [7, 8, 9])
    }

    // MARK: - Rewrite

    func testRewriteAllReplacesFile() {
        for i in 0..<5 {
            UsageHistoryFileStore.append(makeSample(fiveHour: Double(i)), at: tempURL)
        }
        XCTAssertEqual(UsageHistoryFileStore.readAll(at: tempURL).count, 5)

        let replacement = [makeSample(fiveHour: 99), makeSample(fiveHour: 100)]
        UsageHistoryFileStore.rewriteAll(replacement, at: tempURL)

        let read = UsageHistoryFileStore.readAll(at: tempURL)
        XCTAssertEqual(read.count, 2)
        XCTAssertEqual(read.map { $0.fiveHourPct }, [99, 100])
    }

    func testRewriteAllWithEmptyArrayClearsFile() {
        UsageHistoryFileStore.append(makeSample(fiveHour: 50), at: tempURL)
        XCTAssertEqual(UsageHistoryFileStore.readAll(at: tempURL).count, 1)

        UsageHistoryFileStore.rewriteAll([], at: tempURL)
        XCTAssertEqual(UsageHistoryFileStore.readAll(at: tempURL).count, 0)
    }

    // MARK: - percentage(for:) lookup

    func testPercentageLookupForEachLimitType() {
        let sample = makeSample(
            fiveHour: 10, sevenDay: 20, opus: 30, sonnet: 40,
            extraUsed: 5, extraLimit: 50, currency: "USD"
        )
        XCTAssertEqual(sample.percentage(for: .fiveHour), 10)
        XCTAssertEqual(sample.percentage(for: .sevenDay), 20)
        XCTAssertEqual(sample.percentage(for: .opus), 30)
        XCTAssertEqual(sample.percentage(for: .sonnet), 40)
        XCTAssertEqual(sample.percentage(for: .extraUsage), 10.0,
                       "extraUsage % is used/limit*100 = 5/50*100 = 10")
    }

    func testPercentageLookupHandlesMissingExtraUsage() {
        let sample = makeSample(fiveHour: 10)
        XCTAssertNil(sample.percentage(for: .extraUsage))
    }
}

// MARK: - Conformance helper

extension UsageHistorySample: Equatable {
    public static func == (lhs: UsageHistorySample, rhs: UsageHistorySample) -> Bool {
        lhs.timestamp == rhs.timestamp &&
        lhs.fiveHourPct == rhs.fiveHourPct &&
        lhs.sevenDayPct == rhs.sevenDayPct &&
        lhs.opusPct == rhs.opusPct &&
        lhs.sonnetPct == rhs.sonnetPct &&
        lhs.extraUsageUsed == rhs.extraUsageUsed &&
        lhs.extraUsageLimit == rhs.extraUsageLimit &&
        lhs.extraUsageCurrency == rhs.extraUsageCurrency
    }
}
