import XCTest
@testable import TripReel

final class MemoriesEngagementTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "MemoriesEngagementTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }
    func testRepeatedSaveDoesNotQualifyForReview() {
        let history = EngagementHistory(defaults: defaults)
        XCTAssertTrue(history.recordSave(id: "export-a"))
        XCTAssertFalse(history.recordSave(id: "export-a"))
        XCTAssertFalse(history.reviewEligible(version: "1", now: Date()))
        XCTAssertTrue(history.recordSave(id: "export-b"))
        XCTAssertTrue(history.reviewEligible(version: "1", now: Date()))
    }
    func testReviewCooldownAndVersionBothApplyAcrossLaunches() {
        let history = EngagementHistory(defaults: defaults)
        _ = history.recordSave(id: "a")
        _ = history.recordSave(id: "b")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        history.markReviewRequested(version: "1", now: now)
        let relaunched = EngagementHistory(defaults: defaults)
        XCTAssertFalse(relaunched.reviewEligible(version: "2", now: now.addingTimeInterval(119 * 86400)))
        XCTAssertFalse(relaunched.reviewEligible(version: "1", now: now.addingTimeInterval(121 * 86400)))
        XCTAssertTrue(relaunched.reviewEligible(version: "2", now: now.addingTimeInterval(121 * 86400)))
    }
    func testTipsAreLimitedToOncePerDayIncludingClockRollback() {
        let history = EngagementHistory(defaults: defaults)
        let now = Date()
        XCTAssertTrue(history.tipEligible(now: now))
        history.markTipShown(now: now)
        XCTAssertFalse(history.tipEligible(now: now.addingTimeInterval(-1)))
        XCTAssertFalse(history.tipEligible(now: now.addingTimeInterval(86399)))
        XCTAssertTrue(history.tipEligible(now: now.addingTimeInterval(86400)))
    }
    func testRemoteValuesCannotInjectArbitraryText() {
        XCTAssertEqual(HelpTipVariant(remoteValue: "music"), .music)
        XCTAssertEqual(HelpTipVariant(remoteValue: "none"), .none)
        XCTAssertEqual(HelpTipVariant(remoteValue: "https://unexpected.example"), .save)
    }
}
