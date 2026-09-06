import XCTest
@testable import TripReel

@MainActor
final class TripReelModelTests: XCTestCase {
    private func makeModel() -> TripReelModel {
        TripReelModel(arguments: [], useDemoData: true)
    }

    func testNearbyPlaceLabelPrefersLandmarkAndNeighborhood() {
        let placemark = TripPlacemarkComponents(
            areasOfInterest: ["Gardens by the Bay"],
            name: "18 Marina Gardens Drive",
            thoroughfare: "Marina Gardens Drive",
            subLocality: "Marina South",
            locality: "Singapore",
            country: "Singapore",
            isoCountryCode: "SG"
        )

        XCTAssertEqual(
            TripPlaceLabelFormatter.displayName(for: placemark, style: .nearby),
            "Gardens by the Bay, Marina South"
        )
        XCTAssertEqual(
            TripPlaceLabelFormatter.displayName(for: placemark, style: .destination),
            "Singapore"
        )
    }

    func testNearbyPlaceLabelUsesNeighborhoodWithCityContext() {
        let placemark = TripPlacemarkComponents(
            subLocality: "Tiong Bahru",
            locality: "Singapore",
            country: "Singapore",
            isoCountryCode: "SG"
        )

        XCTAssertEqual(
            TripPlaceLabelFormatter.displayName(for: placemark, style: .nearby),
            "Tiong Bahru, Singapore"
        )
    }

    func testFullScreenFillRequestsEnoughPixelsForLandscapeCrop() {
        let target = PhotoDisplaySizing.targetSize(
            sourcePixelWidth: 4_032,
            sourcePixelHeight: 3_024,
            destinationPixelWidth: 1_206,
            destinationPixelHeight: 2_622,
            contentMode: .fill
        )

        XCTAssertGreaterThan(target.width, 3_900)
        XCTAssertGreaterThan(target.height, 2_900)

        let fitted = PhotoDisplaySizing.targetSize(
            sourcePixelWidth: 4_032,
            sourcePixelHeight: 3_024,
            destinationPixelWidth: 1_206,
            destinationPixelHeight: 2_622,
            contentMode: .fit
        )
        XCTAssertLessThan(fitted.width, 1_300)
        XCTAssertLessThan(fitted.height, 1_000)
    }

    func testDisplaySizingNeverUpscalesBeyondOriginalPixels() {
        let target = PhotoDisplaySizing.targetSize(
            sourcePixelWidth: 1_200,
            sourcePixelHeight: 900,
            destinationPixelWidth: 1_206,
            destinationPixelHeight: 2_622,
            contentMode: .fill
        )

        XCTAssertLessThanOrEqual(target.width, 1_200)
        XCTAssertLessThanOrEqual(target.height, 900)
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

    func testSoundtracksHaveBundledAttributedAudio() {
        let model = makeModel()
        let musicTracks = model.tracks.filter { $0.id != "none" }

        XCTAssertFalse(musicTracks.isEmpty)
        XCTAssertTrue(musicTracks.allSatisfy { $0.resourceName != nil && $0.sourceURL != nil })
        XCTAssertNil(model.tracks.first { $0.id == "none" }?.resourceName)
        XCTAssertEqual(model.selectedTrackID, "wanderlust")
    }

    func testBundledSoundtrackStartsRealAudioPlayback() throws {
        let model = makeModel()
        let track = try XCTUnwrap(model.selectedTrack)
        let player = LocalSoundtrackPlayer()

        player.play(track: track)

        XCTAssertTrue(player.isPlaying)
        XCTAssertNil(player.errorMessage)
        player.stop()
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

    func testCleanupDeletesOnlyExplicitlySelectedCutLibraryPhotos() async throws {
        let service = DeletionPhotoLibrary()
        let model = TripReelModel(arguments: [], useDemoData: false, photoLibrary: service)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<3).map { index in
            TripAsset(
                id: "delete-\(index)",
                source: .library("delete-\(index)"),
                creationDate: start.addingTimeInterval(Double(index)),
                filename: "IMG_\(index).HEIC"
            )
        }
        let trip = Trip(
            id: "delete-trip",
            place: "Test",
            dates: "Today",
            startDate: start,
            endDate: start.addingTimeInterval(2),
            assets: assets,
            coverID: assets[0].id
        )
        model.startBuild(trip: trip)
        model.cutPhotoIDs = ["delete-0", "delete-2"]
        model.cleanupSelection = ["delete-2"]

        let count = await model.deleteCleanupSelection()

        XCTAssertEqual(count, 1)
        XCTAssertEqual(service.deletedIdentifiers, ["delete-2"])
        XCTAssertEqual(model.photos.map(\.id), ["delete-0", "delete-1"])
        XCTAssertEqual(model.cutPhotoIDs, ["delete-0"])
        XCTAssertTrue(model.cleanupSelection.isEmpty)
        XCTAssertEqual(model.selectedTrip?.assets.map(\.id), ["delete-0", "delete-1"])
        model.go(.trips)
    }

    func testCleanupFailureKeepsPhotosAndSelection() async {
        let service = DeletionPhotoLibrary(shouldFail: true)
        let model = TripReelModel(arguments: [], useDemoData: false, photoLibrary: service)
        let asset = TripAsset(
            id: "keep-me",
            source: .library("keep-me"),
            creationDate: Date(),
            filename: "IMG_1.HEIC"
        )
        let trip = Trip(
            id: "failure-trip",
            place: "Test",
            dates: "Today",
            startDate: Date(),
            endDate: Date(),
            assets: [asset],
            coverID: asset.id
        )
        model.startBuild(trip: trip)
        model.cutPhotoIDs = [asset.id]
        model.cleanupSelection = [asset.id]

        let count = await model.deleteCleanupSelection()

        XCTAssertNil(count)
        XCTAssertEqual(model.photos.map(\.id), [asset.id])
        XCTAssertEqual(model.cleanupSelection, [asset.id])
        XCTAssertNotNil(model.cleanupDeletionErrorMessage)
        model.go(.trips)
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

    func testMontagePlannerUsesAScenicHeroThenAddsVariety() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = [
            makeAsset("food", start: start, minutes: 5, width: 3_024, height: 4_032),
            makeAsset("people-a", start: start, minutes: 10, width: 4_032, height: 3_024),
            makeAsset("scenic", start: start, minutes: 15, width: 4_032, height: 2_268),
            makeAsset("people-b", start: start, minutes: 20, width: 4_032, height: 3_024)
        ]
        let insights: [String: MontagePhotoInsight] = [
            "food": .init(memoryScore: 0.70, aestheticScore: 0.72, contentKind: .food),
            "people-a": .init(memoryScore: 0.82, aestheticScore: 0.76, contentKind: .people),
            "scenic": .init(memoryScore: 0.94, aestheticScore: 0.91, contentKind: .scenery),
            "people-b": .init(memoryScore: 0.79, aestheticScore: 0.73, contentKind: .people)
        ]

        let plan = MontageSequencePlanner.plan(assets: assets, insights: insights)

        XCTAssertEqual(plan.first?.asset.id, "scenic")
        XCTAssertNotEqual(plan[1].asset.id, "people-b")
        XCTAssertEqual(plan.first?.frameStyle, .cinematic)
        XCTAssertEqual(plan.first(where: { $0.asset.id == "food" })?.frameStyle, .portraitMatte)
    }

    func testMontagePlannerKeepsDaysInStoryOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOne = Date(timeIntervalSince1970: 1_800_000_000)
        let dayTwo = dayOne.addingTimeInterval(24 * 60 * 60)
        let assets = [
            makeAsset("day-two-hero", start: dayTwo, minutes: 5),
            makeAsset("day-one-quiet", start: dayOne, minutes: 5),
            makeAsset("day-one-hero", start: dayOne, minutes: 10)
        ]
        let insights: [String: MontagePhotoInsight] = [
            "day-two-hero": .init(memoryScore: 1, aestheticScore: 1, contentKind: .scenery),
            "day-one-quiet": .init(memoryScore: 0.3, aestheticScore: 0.3, contentKind: .moment),
            "day-one-hero": .init(memoryScore: 0.8, aestheticScore: 0.8, contentKind: .people)
        ]

        let plan = MontageSequencePlanner.plan(assets: assets, insights: insights, calendar: calendar)

        XCTAssertEqual(Set(plan.prefix(2).map(\.asset.id)), ["day-one-quiet", "day-one-hero"])
        XCTAssertEqual(plan.last?.asset.id, "day-two-hero")
    }

    func testMontagePlannerVariesMotionInsteadOfRepeatingOneZoom() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<8).map {
            makeAsset("motion-\($0)", start: start, minutes: $0 * 12)
        }

        let plan = MontageSequencePlanner.plan(assets: assets, insights: [:])

        XCTAssertGreaterThanOrEqual(Set(plan.map(\.motionStyle)).count, 5)
        XCTAssertFalse(zip(plan, plan.dropFirst()).contains { pair in
            pair.0.motionStyle == pair.1.motionStyle
        })
    }

    func testHighlightTargetMakesLargeTripsConcise() {
        XCTAssertEqual(SmartHighlightSelector.targetCount(total: 431, dayCount: 5), 64)
        XCTAssertEqual(SmartHighlightSelector.targetCount(total: 84, dayCount: 7), 28)
        XCTAssertEqual(SmartHighlightSelector.targetCount(total: 20, dayCount: 3), 20)
    }

    func testHighlightSelectorProtectsStrongMemoriesAndMovesDuplicateToMorePhotos() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<32).map {
            makeAsset("candidate-\($0)", start: start, minutes: $0 * 5)
        }
        let scenic = assets[10]
        let group = assets[18]
        let duplicate = assets[11]
        let sharedPrint = NativePhotoFeaturePrint(
            revision: 2,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: [Float(0.1), 0.2, 0.3].withUnsafeBytes { Data($0) }
        )
        let nearPrint = NativePhotoFeaturePrint(
            revision: 2,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: [Float(0.11), 0.21, 0.31].withUnsafeBytes { Data($0) }
        )
        let results: [String: NativePhotoIntelligenceResult] = [
            scenic.id: makeNativeResult(
                id: scenic.id,
                memory: 0.96,
                aesthetic: 0.92,
                tags: [.scenery, .strongMemory],
                featurePrint: sharedPrint
            ),
            group.id: makeNativeResult(
                id: group.id,
                memory: 0.94,
                aesthetic: 0.86,
                tags: [.people, .groupPhoto, .strongMemory]
            ),
            duplicate.id: makeNativeResult(
                id: duplicate.id,
                memory: 0.12,
                aesthetic: 0.18,
                tags: [],
                featurePrint: nearPrint
            )
        ]

        let decisions = SmartHighlightSelector.decisions(
            for: assets,
            nativeResults: results,
            excluding: [:]
        )

        XCTAssertFalse(decisions.contains { $0.id == scenic.id })
        XCTAssertFalse(decisions.contains { $0.id == group.id })
        XCTAssertEqual(decisions.first { $0.id == duplicate.id }?.reason, .similarMoment)
        XCTAssertEqual(assets.count - decisions.count, 24)
    }

    private func makeAsset(
        _ id: String,
        start: Date,
        minutes: Int,
        width: Int = 4_032,
        height: Int = 3_024
    ) -> TripAsset {
        TripAsset(
            id: id,
            source: .library(id),
            creationDate: start.addingTimeInterval(Double(minutes) * 60),
            filename: "\(id).HEIC",
            pixelWidth: width,
            pixelHeight: height
        )
    }

    private func makeNativeResult(
        id: String,
        memory: Double,
        aesthetic: Double,
        tags: [NativePhotoIntelligenceTag],
        featurePrint: NativePhotoFeaturePrint? = nil
    ) -> NativePhotoIntelligenceResult {
        NativePhotoIntelligenceResult(
            sourceIdentifier: id,
            analyzedPixelWidth: 512,
            analyzedPixelHeight: 384,
            signals: NativePhotoIntelligenceSignals(
                featurePrint: featurePrint,
                availability: .init(featurePrint: featurePrint != nil, aesthetics: true)
            ),
            scores: NativePhotoIntelligenceScores(
                memoryScore: memory,
                utilityProbability: 0,
                documentProbability: 0,
                peopleScore: tags.contains(.people) ? 0.9 : 0,
                aestheticScore: aesthetic,
                nativeConfidence: 0.92
            ),
            tags: tags,
            cloudReviewGate: NativeCloudReviewGate(
                disposition: .unnecessary,
                reason: .highMemoryConfidence
            )
        )
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

private final class DeletionPhotoLibrary: PhotoLibraryServing, @unchecked Sendable {
    var onLibraryChange: (@Sendable () -> Void)?
    private(set) var deletedIdentifiers: [String] = []
    let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func fetchAllPhotos() async -> [PhotoMetadata] { [] }
    func fetchPhotos(withLocalIdentifiers identifiers: [String]) async -> [PhotoMetadata] { [] }

    func deletePhotos(withLocalIdentifiers identifiers: [String]) async throws -> Int {
        if shouldFail {
            throw PhotoLibraryDeletionError.rejected("Deletion was declined for testing.")
        }
        deletedIdentifiers = identifiers
        return identifiers.count
    }
}
