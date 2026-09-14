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

    func testExtendedPreviewStartsLocked() {
        let service = RewardedExportService(bundle: .main, defaults: defaults)

        XCTAssertFalse(service.hasUnlockedExtendedPreview(versionID: "edit-a"))
    }

    func testStoredRewardUnlocksOnlyMatchingEdit() {
        defaults.set(["edit-a"], forKey: "memories.rewarded-export.unlocked-version-ids")
        let service = RewardedExportService(bundle: .main, defaults: defaults)

        XCTAssertTrue(service.hasUnlockedExtendedPreview(versionID: "edit-a"))
        XCTAssertFalse(service.hasUnlockedExtendedPreview(versionID: "edit-b"))
    }

    func testStoredRewardPersistsAcrossLaunches() {
        defaults.set(["edit-a"], forKey: "memories.rewarded-export.unlocked-version-ids")

        let relaunched = RewardedExportService(bundle: .main, defaults: defaults)
        XCTAssertTrue(relaunched.hasUnlockedExtendedPreview(versionID: "edit-a"))
    }
}
