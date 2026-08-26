import XCTest
@testable import Usage4ClaudeCore

/// `UsageSnapshot` is the Codable DTO the main app writes to the App Group container
/// and the widget extension reads on every timeline refresh. The two targets can be
/// running different builds mid-update, so decoding must tolerate a snapshot written
/// by an older app: any field added later has to be Optional and absent-safe.
final class UsageSnapshotTests: XCTestCase {

    private func decode(_ json: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
    }

    /// A snapshot written before the weekly model names existed must still decode,
    /// with the names simply nil so the widget falls back to its own tile labels.
    func testDecodesLegacySnapshotWithoutModelNames() throws {
        let json = """
        {
            "capturedAt": "2026-08-26T12:00:00Z",
            "fiveHour": { "percentage": 71, "resetsAt": "2026-08-26T14:20:00Z" },
            "sevenDay": { "percentage": 76, "resetsAt": "2026-08-27T23:00:00Z" },
            "opus": { "percentage": 13, "resetsAt": "2026-08-27T23:00:00Z" },
            "sonnet": null,
            "extraUsage": null
        }
        """
        let snapshot = try decode(json)
        XCTAssertEqual(snapshot.fiveHour?.percentage, 71)
        XCTAssertEqual(snapshot.opus?.percentage, 13)
        XCTAssertNil(snapshot.opusModelName, "absent key must decode as nil, not throw")
        XCTAssertNil(snapshot.sonnetModelName)
    }

    /// A snapshot from a current build carries the real model name through to the widget.
    func testRoundTripsModelNames() throws {
        let original = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_772_000_000),
            fiveHour: .init(percentage: 71, resetsAt: nil),
            sevenDay: .init(percentage: 76, resetsAt: nil),
            opus: .init(percentage: 13, resetsAt: nil),
            sonnet: nil,
            extraUsage: nil,
            opusModelName: "Fable",
            sonnetModelName: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageSnapshot.self, from: encoder.encode(original))

        XCTAssertEqual(decoded.opusModelName, "Fable")
        XCTAssertEqual(decoded.opus?.percentage, 13)
        XCTAssertNil(decoded.sonnetModelName)
    }
}
