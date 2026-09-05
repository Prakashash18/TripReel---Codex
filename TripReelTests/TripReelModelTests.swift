import XCTest
@testable import TripReel

@MainActor
final class TripReelModelTests: XCTestCase {
    func testPaceMapsToExpectedDurations() {
        let model = TripReelModel(arguments: [])

        model.pace = 0
        XCTAssertEqual(model.secondsPerPhoto, 1.85, accuracy: 0.001)
        XCTAssertEqual(model.durationText, "2:35")

        model.pace = 1
        XCTAssertEqual(model.secondsPerPhoto, 0.60, accuracy: 0.001)
        XCTAssertEqual(model.durationText, "0:50")
    }

    func testCutAndUndoRestorePhotoState() {
        let model = TripReelModel(arguments: [])
        let firstPhotoID = model.currentPhoto.id

        model.decideCurrentPhoto(cut: true)

        XCTAssertTrue(model.cutPhotoIDs.contains(firstPhotoID))
        XCTAssertEqual(model.currentPhotoIndex, 1)
        XCTAssertEqual(model.history.count, 1)

        model.undoLastDecision()

        XCTAssertFalse(model.cutPhotoIDs.contains(firstPhotoID))
        XCTAssertEqual(model.currentPhotoIndex, firstPhotoID)
        XCTAssertTrue(model.history.isEmpty)
    }

    func testKeepingAPhotoDoesNotAddItToCuts() {
        let model = TripReelModel(arguments: [])

        model.decideCurrentPhoto(cut: false)

        XCTAssertTrue(model.cutPhotoIDs.isEmpty)
        XCTAssertEqual(model.currentPhotoIndex, 1)
        XCTAssertEqual(model.history.count, 1)
    }

    func testNoMusicDisablesBeatCutting() throws {
        let model = TripReelModel(arguments: [])
        let noMusic = try XCTUnwrap(model.tracks.first { $0.id == "none" })

        model.selectTrack(noMusic)

        XCTAssertNil(model.selectedTrackID)
        XCTAssertFalse(model.cutToBeat)
        XCTAssertNil(model.selectedTrack)
    }

    func testRestartReturnsToTripsAndClearsCleanupState() {
        let model = TripReelModel(arguments: [])
        model.cleanupShowsGrid = true
        model.cleanupSelection = [1, 3, 5]

        model.restart()

        XCTAssertEqual(model.screen, .trips)
        XCTAssertFalse(model.cleanupShowsGrid)
        XCTAssertTrue(model.cleanupSelection.isEmpty)
        XCTAssertTrue(model.showCutHint)
    }

    func testChangingDecisionAndUndoRestoresPreviousCutState() {
        let model = TripReelModel(arguments: [])
        model.currentPhotoIndex = model.photos.count - 1

        model.decideCurrentPhoto(cut: true)
        XCTAssertTrue(model.cutPhotoIDs.contains(83))

        model.go(.cut)
        model.decideCurrentPhoto(cut: false)
        XCTAssertFalse(model.cutPhotoIDs.contains(83))

        model.undoLastDecision()
        XCTAssertTrue(model.cutPhotoIDs.contains(83))
        XCTAssertEqual(model.currentPhotoIndex, 83)
    }

    func testExportQualityControlsWatermark() {
        let model = TripReelModel(arguments: [])

        model.startRender(hd: false)
        XCTAssertEqual(model.exportQuality, .standard)
        XCTAssertTrue(model.exportQuality.includesWatermark)

        model.startRender(hd: true)
        XCTAssertEqual(model.exportQuality, .hd)
        XCTAssertFalse(model.exportQuality.includesWatermark)
    }

    func testPhotoFixtureIsDeterministic() {
        let model = TripReelModel(arguments: [])

        XCTAssertEqual(model.photos.count, 84)
        XCTAssertEqual(model.photos.first?.imageName, "my-khe-beach")
        XCTAssertEqual(model.photos.first?.label, "IMG_2140")
        XCTAssertEqual(model.photos.first?.time, "07:00")
        XCTAssertEqual(model.photos.last?.label, "IMG_2223")
        XCTAssertEqual(model.photos.last?.time, "16:31")
    }
}
