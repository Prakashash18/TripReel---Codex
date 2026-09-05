import XCTest
@testable import TripReel

@MainActor
final class TripReelModelTests: XCTestCase {
    private func makeModel() -> TripReelModel {
        TripReelModel(arguments: [], useDemoData: true)
    }

    func testPaceMapsToExpectedDurations() {
        let model = makeModel()

        model.pace = 0
        XCTAssertEqual(model.secondsPerPhoto, 1.85, accuracy: 0.001)
        XCTAssertEqual(model.durationText, "2:35")

        model.pace = 1
        XCTAssertEqual(model.secondsPerPhoto, 0.60, accuracy: 0.001)
        XCTAssertEqual(model.durationText, "0:50")
    }

    func testCutAndUndoRestorePhotoState() {
        let model = makeModel()
        let firstPhotoID = model.currentPhoto.id

        model.decideCurrentPhoto(cut: true)

        XCTAssertTrue(model.cutPhotoIDs.contains(firstPhotoID))
        XCTAssertEqual(model.currentPhotoIndex, 1)
        XCTAssertEqual(model.history.count, 1)

        model.undoLastDecision()

        XCTAssertFalse(model.cutPhotoIDs.contains(firstPhotoID))
        XCTAssertEqual(model.currentPhotoIndex, 0)
        XCTAssertTrue(model.history.isEmpty)
    }

    func testKeepingAPhotoDoesNotAddItToCuts() {
        let model = makeModel()

        model.decideCurrentPhoto(cut: false)

        XCTAssertTrue(model.cutPhotoIDs.isEmpty)
        XCTAssertEqual(model.currentPhotoIndex, 1)
        XCTAssertEqual(model.history.count, 1)
    }

    func testNoMusicDisablesBeatCutting() throws {
        let model = makeModel()
        let noMusic = try XCTUnwrap(model.tracks.first { $0.id == "none" })

        model.selectTrack(noMusic)

        XCTAssertNil(model.selectedTrackID)
        XCTAssertFalse(model.cutToBeat)
        XCTAssertNil(model.selectedTrack)
    }

    func testRestartReturnsToTripsAndClearsCleanupState() {
        let model = makeModel()
        model.cleanupShowsGrid = true
        model.cleanupSelection = ["one", "three", "five"]

        model.restart()

        XCTAssertEqual(model.screen, .trips)
        XCTAssertFalse(model.cleanupShowsGrid)
        XCTAssertTrue(model.cleanupSelection.isEmpty)
        XCTAssertTrue(model.showCutHint)
    }

    func testChangingDecisionAndUndoRestoresPreviousCutState() {
        let model = makeModel()
        model.currentPhotoIndex = model.photos.count - 1
        let lastPhotoID = model.currentPhoto.id

        model.decideCurrentPhoto(cut: true)
        XCTAssertTrue(model.cutPhotoIDs.contains(lastPhotoID))

        model.go(.cut)
        model.decideCurrentPhoto(cut: false)
        XCTAssertFalse(model.cutPhotoIDs.contains(lastPhotoID))

        model.undoLastDecision()
        XCTAssertTrue(model.cutPhotoIDs.contains(lastPhotoID))
        XCTAssertEqual(model.currentPhotoIndex, 83)
    }

    func testExportQualityControlsWatermark() {
        let model = makeModel()

        model.startRender(hd: false)
        XCTAssertEqual(model.exportQuality, .standard)
        XCTAssertTrue(model.exportQuality.includesWatermark)

        model.startRender(hd: true)
        XCTAssertEqual(model.exportQuality, .hd)
        XCTAssertFalse(model.exportQuality.includesWatermark)
    }

    func testPhotoFixtureIsDeterministic() {
        let model = makeModel()

        XCTAssertEqual(model.photos.count, 84)
        XCTAssertEqual(model.photos.first?.source, .bundled("my-khe-beach"))
        XCTAssertEqual(model.photos.first?.label, "IMG_2140")
        XCTAssertEqual(model.photos.last?.label, "IMG_2223")
    }

    func testProductionModelDoesNotSilentlyLoadDemoTrips() {
        let model = TripReelModel(arguments: [], useDemoData: false)

        XCTAssertTrue(model.trips.isEmpty)
        XCTAssertTrue(model.photos.isEmpty)
        XCTAssertFalse(model.usesDemoData)
    }

    func testLibraryScanGroupsAssetsAndBuildUsesTheirIdentifiers() async throws {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 60 * 60)
        let metadata = (0..<16).map { index in
            PhotoMetadata(
                id: "library-\(index)",
                creationDate: start.addingTimeInterval(Double(index) * 20 * 60 * 60 / 14),
                coordinate: nil,
                filename: "IMG_\(index).HEIC",
                pixelWidth: 4_032,
                pixelHeight: 3_024,
                isScreenshot: index == 4
            )
        }
        let service = StubPhotoLibrary(photos: metadata)
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: service
        )

        await model.scanPhotoLibrary(navigateToResults: true)

        XCTAssertEqual(model.libraryPhotoCount, 16)
        XCTAssertEqual(model.selectedPhotoCount, 16)
        XCTAssertEqual(model.trips.count, 1)
        XCTAssertEqual(model.screen, .trips)
        XCTAssertEqual(model.libraryPreviewPhotos.count, 6)

        let trip = try XCTUnwrap(model.trips.first)
        model.startBuild(trip: trip)

        XCTAssertEqual(model.photos.map(\.id), metadata.map(\.id))
        XCTAssertEqual(model.photos.first?.source, .library("library-0"))
        XCTAssertEqual(model.selectedTrip?.id, trip.id)
        model.go(.trips)
    }
}

private final class StubPhotoLibrary: PhotoLibraryServing, @unchecked Sendable {
    var onLibraryChange: (@Sendable () -> Void)?
    let photos: [PhotoMetadata]

    init(photos: [PhotoMetadata]) {
        self.photos = photos
    }

    func fetchAllPhotos() async -> [PhotoMetadata] {
        photos
    }

    func fetchPhotos(withLocalIdentifiers identifiers: [String]) async -> [PhotoMetadata] {
        let requested = Set(identifiers)
        return photos.filter { requested.contains($0.id) }
    }
}
