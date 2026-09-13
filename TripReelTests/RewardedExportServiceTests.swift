import XCTest
@testable import TripReel

@MainActor
final class RewardedExportServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RewardedExportServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstFreeExportIsComplimentaryAndSameEditStaysUnlocked() {
        let service = RewardedExportService(bundle: .main, defaults: defaults)

        XCTAssertTrue(service.authorizeWithoutAdIfEligible(versionID: "edit-a"))
        XCTAssertTrue(service.authorizeWithoutAdIfEligible(versionID: "edit-a"))
    }

    func testAChangedEditRequiresRewardAfterComplimentaryExport() {
        let service = RewardedExportService(bundle: .main, defaults: defaults)

        XCTAssertTrue(service.authorizeWithoutAdIfEligible(versionID: "edit-a"))
        XCTAssertFalse(service.authorizeWithoutAdIfEligible(versionID: "edit-b"))
    }

    func testComplimentaryAndVersionUnlockPersistAcrossLaunches() {
        XCTAssertTrue(
            RewardedExportService(bundle: .main, defaults: defaults)
                .authorizeWithoutAdIfEligible(versionID: "edit-a")
        )

        let relaunched = RewardedExportService(bundle: .main, defaults: defaults)
        XCTAssertTrue(relaunched.authorizeWithoutAdIfEligible(versionID: "edit-a"))
        XCTAssertFalse(relaunched.authorizeWithoutAdIfEligible(versionID: "edit-b"))
    }
}
