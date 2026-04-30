import XCTest
@testable import Usage4ClaudeCore

final class SemverCompareTests: XCTestCase {
    // MARK: - parseVersion

    func testParseVersionStripsLeadingV() {
        XCTAssertEqual(SemverCompare.parseVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(SemverCompare.parseVersion("V1.2.3"), "1.2.3")
        XCTAssertEqual(SemverCompare.parseVersion("1.2.3"), "1.2.3")
    }

    func testParseVersionLowercases() {
        XCTAssertEqual(SemverCompare.parseVersion("V1.0.0"), "1.0.0")
    }

    // MARK: - isNewerVersion (the v1.0.0 → v1.1.0 case that motivates this fix)

    func testNewerMajor() {
        XCTAssertTrue(SemverCompare.isNewerVersion(latest: "2.0.0", current: "1.9.9"))
    }

    func testNewerMinor() {
        XCTAssertTrue(SemverCompare.isNewerVersion(latest: "1.1.0", current: "1.0.0"))
    }

    func testNewerPatch() {
        XCTAssertTrue(SemverCompare.isNewerVersion(latest: "1.0.1", current: "1.0.0"))
    }

    func testEqualIsNotNewer() {
        XCTAssertFalse(SemverCompare.isNewerVersion(latest: "1.0.0", current: "1.0.0"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(SemverCompare.isNewerVersion(latest: "1.0.0", current: "1.0.1"))
        XCTAssertFalse(SemverCompare.isNewerVersion(latest: "1.0.0", current: "1.1.0"))
        XCTAssertFalse(SemverCompare.isNewerVersion(latest: "1.0.0", current: "2.0.0"))
    }

    // MARK: - Padding edge cases

    func testShortVersionsArePaddedWithZeros() {
        // "2" should be treated as "2.0.0", not malformed
        XCTAssertTrue(SemverCompare.isNewerVersion(latest: "2", current: "1.9.9"))
        XCTAssertFalse(SemverCompare.isNewerVersion(latest: "1", current: "1.0.0"))
    }

    func testFourthComponentIsIgnored() {
        // GitHub's tag format won't include a fourth component, but if it did the
        // comparator should ignore it rather than crash.
        XCTAssertFalse(SemverCompare.isNewerVersion(latest: "1.0.0.5", current: "1.0.0"))
    }

    // MARK: - Real-world cases from this project

    func testV1_0_0_to_v1_1_0() {
        // What v1.0.0 users running an outdated app should see.
        let current = SemverCompare.parseVersion("1.0.0")  // from Bundle
        let latest = SemverCompare.parseVersion("v1.1.0")  // from GitHub tag
        XCTAssertTrue(SemverCompare.isNewerVersion(latest: latest, current: current))
    }

    func testV1_1_0_is_uptodate_against_v1_1_0() {
        let current = SemverCompare.parseVersion("1.1.0")
        let latest = SemverCompare.parseVersion("v1.1.0")
        XCTAssertFalse(SemverCompare.isNewerVersion(latest: latest, current: current))
    }
}
