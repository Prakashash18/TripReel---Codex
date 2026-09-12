import CoreVideo
import Photos
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import TripReel

@MainActor
final class TripReelModelTests: XCTestCase {
    private func makeModel() -> TripReelModel {
        TripReelModel(arguments: [], useDemoData: true)
    }

    func testShareProviderAdvertisesAnExplicitMP4Movie() {
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-provider-test.mp4")
        let provider = MP4ShareProviderFactory.makeProvider(
            for: videoURL,
            suggestedName: "Memories-Reel"
        )

        XCTAssertEqual(provider.suggestedName, "Memories-Reel.mp4")
        XCTAssertEqual(provider.registeredTypeIdentifiers, [UTType.mpeg4Movie.identifier])
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier))
    }

    func testVideoFrameCopyDoesNotTurnUIKitArtworkUpsideDown() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2),
            format: format
        ).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 1, width: 2, height: 1))
        }
        let source = try XCTUnwrap(rendered.cgImage)

        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            2,
            2,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ] as CFDictionary,
            &optionalBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)

        try TripReelVideoExporter.copyRenderedFrame(
            source,
            into: buffer,
            outputSize: CGSize(width: 2, height: 2)
        )

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
            .assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        // BGRA row zero is the top of a video frame.
        XCTAssertEqual(Array(UnsafeBufferPointer(start: baseAddress, count: 4)), [0, 0, 255, 255])
        XCTAssertEqual(
            Array(UnsafeBufferPointer(start: baseAddress + bytesPerRow, count: 4)),
            [255, 0, 0, 255]
        )
    }

    func testExportMotionUsesSmoothBoundedProgress() {
        XCTAssertEqual(TripReelVideoExporter.easedMotionPhase(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(TripReelVideoExporter.easedMotionPhase(0.25), 0.15625, accuracy: 0.0001)
        XCTAssertEqual(TripReelVideoExporter.easedMotionPhase(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TripReelVideoExporter.easedMotionPhase(2), 1, accuracy: 0.0001)
        XCTAssertEqual(
            TripReelVideoExporter.transitionProgress(frame: 1, transitionFrames: 2),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TripReelVideoExporter.transitionProgress(frame: 0, transitionFrames: 0),
            1,
            accuracy: 0.0001
        )
    }

    func testNavigationTracksForwardBackwardAndReplacementMotion() {
        let model = makeModel()

        model.go(.access)
        XCTAssertEqual(model.navigationDirection, .forward)

        model.go(.welcome)
        XCTAssertEqual(model.navigationDirection, .backward)

        model.go(.welcome)
        XCTAssertEqual(model.navigationDirection, .replace)
    }

    func testBrandWelcomeAppearsOnceThenRoutesToPhotoSetup() {
        let suiteName = "MemoriesTests.Welcome.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let photoLibrary = StubPhotoLibrary(photos: [], authorizationStatus: .notDetermined)

        let firstLaunch = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: photoLibrary,
            preferenceStore: preferences
        )
        XCTAssertEqual(firstLaunch.screen, .welcome)

        firstLaunch.continueFromWelcome()
        XCTAssertEqual(firstLaunch.screen, .access)

        photoLibrary.authorizationStatus = .denied
        let returningLaunch = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: photoLibrary,
            preferenceStore: preferences
        )
        XCTAssertEqual(returningLaunch.screen, .access)
    }

    func testReturningUserWithPhotoAccessSkipsOneTimeSetup() {
        let suiteName = "MemoriesTests.Returning.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(true, forKey: "memories.welcome-completed.v1")
        let photoLibrary = StubPhotoLibrary(photos: [], authorizationStatus: .authorized)

        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: photoLibrary,
            preferenceStore: preferences
        )

        XCTAssertEqual(model.screen, .trips)
    }

    func testFirstWelcomeSkipsPhotoPromptWhenIOSAlreadyGrantedAccess() {
        let suiteName = "MemoriesTests.ExistingAccess.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let photoLibrary = StubPhotoLibrary(photos: [], authorizationStatus: .limited)
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: photoLibrary,
            preferenceStore: preferences
        )

        model.continueFromWelcome()

        XCTAssertEqual(model.screen, .trips)
    }

    func testBackNavigationReturnsToTheScreenThatOpenedExport() {
        let model = makeModel()

        model.go(.firstWatch)
        model.openExport()
        XCTAssertEqual(model.screen, .export)
        XCTAssertTrue(model.canNavigateBack)

        model.navigateBack()
        XCTAssertEqual(model.screen, .firstWatch)
        XCTAssertEqual(model.navigationDirection, .backward)

        model.go(.secondWatch)
        model.openExport()
        model.go(.paywall)
        model.navigateBack()
        XCTAssertEqual(model.screen, .export)

        model.navigateBack()
        XCTAssertEqual(model.screen, .secondWatch)
    }

    func testFirstCutPlaybackAndChoiceScreenHavePredictableBackNavigation() {
        let model = makeModel()

        model.go(.firstWatch)
        model.continueFromFirstWatch()
        XCTAssertEqual(model.screen, .firstCutOptions)

        model.openAICutDirections()
        XCTAssertTrue(model.isCloudAnalysisConsentPresented)
        model.keepAnalysisOnDevice()
        XCTAssertEqual(model.screen, .firstCutOptions)

        model.navigateBack()
        XCTAssertEqual(model.screen, .firstWatch)
    }

    func testBackNavigationSkipsTransientProcessingScreens() {
        let model = makeModel()

        model.go(.secondWatch)
        model.go(.pace)
        model.navigateBack()
        XCTAssertEqual(model.screen, .secondWatch)

        model.go(.done)
        model.navigateBack()
        XCTAssertEqual(model.screen, .export)

        model.go(.trips)
        XCTAssertFalse(model.canNavigateBack)
        model.navigateBack()
        XCTAssertEqual(model.screen, .trips)
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

    func testDestinationPlaceLabelUsesRecognizableCityInsteadOfAdministrativeDistrict() {
        let vietnam = TripPlacemarkComponents(
            subLocality: "An Hải",
            locality: "An Hải",
            administrativeArea: "Da Nang",
            country: "Vietnam",
            isoCountryCode: "VN"
        )
        let thailand = TripPlacemarkComponents(
            locality: "Mueang Chiang Mai District",
            administrativeArea: "Chiang Mai",
            country: "Thailand",
            isoCountryCode: "TH"
        )

        XCTAssertEqual(
            TripPlaceLabelFormatter.displayName(for: vietnam, style: .destination),
            "Da Nang, Vietnam"
        )
        XCTAssertEqual(
            TripPlaceLabelFormatter.displayName(for: thailand, style: .destination),
            "Chiang Mai, Thailand"
        )
    }

    func testLocalStoryNamesCollectionsWithTimeAndFriendlyPlaceContext() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 9))
        )
        let tripAssets = (0..<3).map {
            makeAsset("trip-\($0)", start: start, minutes: $0 * 24 * 60)
        }
        let trip = Trip(
            id: "chiang-mai",
            place: "Mueang Chiang Mai District, Thailand",
            dates: "28–30 Aug 2026",
            startDate: start,
            endDate: start.addingTimeInterval(2 * 24 * 60 * 60),
            assets: tripAssets,
            coverID: tripAssets[0].id
        )
        let nearbyAsset = makeAsset("nearby", start: start, minutes: 6 * 60)
        let nearby = Trip(
            id: "gardens",
            place: "Gardens by the Bay, Marina South",
            dates: "28 Aug 2026",
            startDate: nearbyAsset.creationDate ?? start,
            endDate: nearbyAsset.creationDate ?? start,
            assets: [nearbyAsset],
            coverID: nearbyAsset.id
        )

        XCTAssertEqual(
            LocalStoryIntelligence.collectionTitle(
                for: trip,
                isNearby: false,
                calendar: calendar
            ),
            "Three days in Chiang Mai"
        )
        XCTAssertEqual(
            LocalStoryIntelligence.collectionTitle(
                for: nearby,
                isNearby: true,
                calendar: calendar
            ),
            "An afternoon around Gardens by the Bay"
        )
        XCTAssertEqual(
            LocalStoryIntelligence.locationContext(for: trip),
            "Mueang Chiang Mai District, Thailand"
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

    func testBundledSoundtrackCanFadeAndFinishInsteadOfLoopingForever() async throws {
        let model = makeModel()
        let track = try XCTUnwrap(model.selectedTrack)
        let player = LocalSoundtrackPlayer()

        player.play(track: track)
        player.finishNaturally(fadeDuration: 0.15)
        try await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertFalse(player.isPlaying)
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

    func testCleanupBulkSelectionSelectsEveryCutLibraryPhotoAndCanClear() {
        let model = TripReelModel(arguments: [], useDemoData: false)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = [
            TripAsset(
                id: "cut-library-one",
                source: .library("cut-library-one"),
                creationDate: start,
                filename: "IMG_1.HEIC"
            ),
            TripAsset(
                id: "cut-library-two",
                source: .library("cut-library-two"),
                creationDate: start.addingTimeInterval(1),
                filename: "IMG_2.HEIC"
            ),
            TripAsset(
                id: "kept-library",
                source: .library("kept-library"),
                creationDate: start.addingTimeInterval(2),
                filename: "IMG_3.HEIC"
            ),
            TripAsset(
                id: "temporary-import",
                source: .imported("/tmp/temporary-import.jpg"),
                creationDate: start.addingTimeInterval(3),
                filename: "IMG_4.JPG"
            ),
            TripAsset(
                id: "cut-library-video",
                source: .library("cut-library-video"),
                creationDate: start.addingTimeInterval(4),
                filename: "IMG_5.MOV",
                mediaKind: .video,
                sourceDurationSeconds: 5
            )
        ]
        let trip = Trip(
            id: "cleanup-bulk-trip",
            place: "Test",
            dates: "Today",
            startDate: start,
            endDate: start.addingTimeInterval(3),
            assets: assets,
            coverID: assets[0].id
        )
        model.startBuild(trip: trip)
        model.cutPhotoIDs = [
            "cut-library-one",
            "cut-library-two",
            "temporary-import",
            "cut-library-video"
        ]

        XCTAssertEqual(
            Set(model.cleanupCandidatePhotos.map(\.id)),
            ["cut-library-one", "cut-library-two"]
        )
        XCTAssertFalse(model.areAllCleanupCandidatesSelected)

        model.selectAllCleanupPhotos()

        XCTAssertEqual(model.cleanupSelection, ["cut-library-one", "cut-library-two"])
        XCTAssertEqual(model.cleanupSelectedCount, 2)
        XCTAssertTrue(model.areAllCleanupCandidatesSelected)

        model.clearCleanupSelection()

        XCTAssertTrue(model.cleanupSelection.isEmpty)
        XCTAssertEqual(model.cleanupSelectedCount, 0)
        XCTAssertFalse(model.areAllCleanupCandidatesSelected)
        model.go(.trips)
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
        model.currentPhotoIndex = model.photos.count - 2
        let photoID = model.currentPhoto.id

        model.decideCurrentPhoto(cut: true)
        XCTAssertTrue(model.cutPhotoIDs.contains(photoID))

        model.go(.cut)
        model.currentPhotoIndex = model.photos.count - 2
        model.decideCurrentPhoto(cut: false)
        XCTAssertFalse(model.cutPhotoIDs.contains(photoID))

        model.undoLastDecision()
        XCTAssertTrue(model.cutPhotoIDs.contains(photoID))
        XCTAssertEqual(model.currentPhotoIndex, 82)
    }

    func testExportQualityControlsWatermark() {
        let model = makeModel()

        model.startRender(hd: false)
        XCTAssertEqual(model.exportQuality, .standard)
        XCTAssertEqual(model.exportHandoff, .normal)
        XCTAssertTrue(model.exportQuality.includesWatermark)

        model.startCapCutRender()
        XCTAssertEqual(model.exportQuality, .standard)
        XCTAssertEqual(model.exportHandoff, .capCut)

        model.startRender(hd: true)
        XCTAssertEqual(model.exportQuality, .hd)
        XCTAssertEqual(model.exportHandoff, .normal)
        XCTAssertFalse(model.exportQuality.includesWatermark)
    }

    func testStandardExportAlwaysHasAFreePath() {
        XCTAssertNil(ExportAccessPolicy.premiumRequirement(
            photoCount: 24,
            durationSeconds: 30,
            quality: .standard
        ))
    }

    func testHDRequirementUsesTheStorySelectedFreeCut() throws {
        let requirement = try XCTUnwrap(ExportAccessPolicy.premiumRequirement(
            photoCount: 12,
            durationSeconds: 28,
            freePhotoCount: 10,
            freeDurationSeconds: 23.4,
            quality: .hd
        ))

        XCTAssertEqual(requirement.freePhotoLimit, 10)
        XCTAssertEqual(requirement.freeDurationLimit, 23.4, accuracy: 0.001)
        XCTAssertTrue(requirement.exceedsPhotoLimit)
        XCTAssertTrue(requirement.exceedsDurationLimit)
    }

    func testLongerOrLargerStandardExportUsesAutomaticFreeCut() {
        XCTAssertNil(ExportAccessPolicy.premiumRequirement(
            photoCount: 25,
            durationSeconds: 30,
            quality: .standard
        ))
        XCTAssertNil(ExportAccessPolicy.premiumRequirement(
            photoCount: 24,
            durationSeconds: 30.01,
            quality: .standard
        ))
    }

    func testHDAlwaysRequiresPremium() {
        let requirement = ExportAccessPolicy.premiumRequirement(
            photoCount: 1,
            durationSeconds: 2,
            quality: .hd
        )
        XCTAssertNotNil(requirement)
        XCTAssertTrue(requirement?.requiresHighDefinition == true)
    }

    func testTitleCardsBecomeRealTimelineItems() {
        let model = makeModel()
        model.titleCards = [.opening, .place, .ending]
        model.titleText = "A Singapore Day"
        model.setTitleText("Marina after dark", for: .place)
        model.setTitleSubtitle("Bayfront · 9:14 PM", for: .place)
        model.setTitleStyle(.bold, for: .place)
        model.setTitleDuration(3.2, for: .place)
        model.setTitleText("Until next time", for: .ending)

        let timeline = MontageTimelineBuilder.make(
            photos: Array(model.photos.prefix(2)),
            titleCards: model.montageTitleCards
        )

        XCTAssertEqual(timeline.count, 5)
        guard case let .title(opening) = timeline[0],
              case .photo = timeline[1],
              case let .title(place) = timeline[2],
              case .photo = timeline[3],
              case let .title(ending) = timeline[4] else {
            return XCTFail("Expected opening, photo, place, photo, ending")
        }
        XCTAssertEqual(opening.title, "A Singapore Day")
        XCTAssertEqual(place.title, "Marina after dark")
        XCTAssertEqual(place.subtitle, "Bayfront · 9:14 PM")
        XCTAssertEqual(place.style, .bold)
        XCTAssertEqual(place.duration, 3.2, accuracy: 0.001)
        XCTAssertEqual(ending.title, "Until next time")
        XCTAssertEqual(ending.subtitle, "Made with Memories")
    }

    func testLocalTitlePlanUsesVisionThemesAndPlacesStoryBeatAtDayChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 9))
        )
        let assets = (0..<8).map { index in
            makeAsset(
                "moment-\(index)",
                start: start,
                minutes: index < 4 ? index * 30 : (24 * 60) + ((index - 4) * 30)
            )
        }
        let trip = Trip(
            id: "people-trip",
            place: "Mueang Chiang Mai District, Thailand",
            dates: "28–29 Aug 2026",
            startDate: start,
            endDate: start.addingTimeInterval(25.5 * 60 * 60),
            assets: assets,
            coverID: assets[0].id
        )
        let photos = assets.map { makeReelPhoto(from: $0) }
        let insights = Dictionary(uniqueKeysWithValues: assets.enumerated().map { index, asset in
            let isPeopleChapter = index >= 4
            return (
                asset.id,
                MontagePhotoInsight(
                    memoryScore: 0.86,
                    aestheticScore: 0.82,
                    contentKind: isPeopleChapter ? .people : .scenery,
                    peopleCount: isPeopleChapter ? 3 : 0,
                    classifications: [
                        NativePhotoClassification(
                            identifier: isPeopleChapter ? "group portrait" : "outdoor landscape",
                            confidence: 0.86
                        )
                    ]
                )
            )
        })

        let plan = LocalStoryIntelligence.makeTitlePlan(
            for: trip,
            photos: photos,
            insights: insights,
            isNearby: false,
            calendar: calendar
        )

        XCTAssertEqual(plan.drafts[.opening]?.title, "Together in Chiang Mai")
        XCTAssertEqual(plan.drafts[.place]?.title, "The people in the story")
        XCTAssertEqual(plan.drafts[.place]?.subtitle, "Day 2 of 2")
        XCTAssertEqual(plan.drafts[.place]?.afterPhotoID, "moment-3")
        XCTAssertEqual(plan.enabledCards, [.opening, .place])

        let cards = TitleCardKind.allCases.compactMap { kind -> MontageTitleCard? in
            guard plan.enabledCards.contains(kind), let draft = plan.drafts[kind] else { return nil }
            return MontageTitleCard(
                kind: kind,
                title: draft.title,
                subtitle: draft.subtitle,
                style: draft.style,
                duration: draft.duration,
                afterPhotoID: draft.afterPhotoID
            )
        }
        let timeline = MontageTimelineBuilder.make(photos: photos, titleCards: cards)
        guard case let .title(storyBeat) = timeline[5] else {
            return XCTFail("Expected the local story beat after the final photo from day one")
        }
        XCTAssertEqual(storyBeat.kind, .place)
    }

    func testLocalTitlePlanUsesAppleVisionSceneLabelsWithoutInventingALandmark() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<6).map {
            makeAsset("coast-\($0)", start: start, minutes: $0 * 20)
        }
        let trip = Trip(
            id: "coast",
            place: "Da Nang, Vietnam",
            dates: "2 Aug 2026",
            startDate: start,
            endDate: start.addingTimeInterval(100 * 60),
            assets: assets,
            coverID: assets[0].id
        )
        let photos = assets.map(makeReelPhoto)
        let insights = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (
                asset.id,
                MontagePhotoInsight(
                    memoryScore: 0.9,
                    aestheticScore: 0.86,
                    contentKind: .scenery,
                    classifications: [
                        NativePhotoClassification(identifier: "beach sunset", confidence: 0.91)
                    ]
                )
            )
        })

        let plan = LocalStoryIntelligence.makeTitlePlan(
            for: trip,
            photos: photos,
            insights: insights,
            isNearby: false
        )

        XCTAssertEqual(plan.drafts[.opening]?.title, "By the water")
        XCTAssertEqual(plan.drafts[.opening]?.subtitle, "Da Nang, Vietnam · 2 Aug 2026")
        XCTAssertEqual(plan.drafts[.place]?.title, "Toward the water")
        XCTAssertTrue(plan.enabledCards.contains(.place))
        XCTAssertFalse(plan.enabledCards.contains(.ending))
    }

    func testTitleDraftsRemainIndependentAndDurationsAreClamped() {
        let model = makeModel()

        model.setTitleText("Opening", for: .opening)
        model.setTitleText("Place", for: .place)
        model.setTitleText("Ending", for: .ending)
        model.setTitleDuration(0.2, for: .opening)
        model.setTitleDuration(8, for: .ending)
        model.setTitleCardEnabled(true, for: .place)
        model.setTitleCardEnabled(false, for: .opening)

        XCTAssertEqual(model.titleDraft(for: .opening).title, "Opening")
        XCTAssertEqual(model.titleDraft(for: .place).title, "Place")
        XCTAssertEqual(model.titleDraft(for: .ending).title, "Ending")
        XCTAssertEqual(model.titleDraft(for: .opening).duration, 1, accuracy: 0.001)
        XCTAssertEqual(model.titleDraft(for: .ending).duration, 4, accuracy: 0.001)
        XCTAssertFalse(model.titleCards.contains(.opening))
        XCTAssertTrue(model.titleCards.contains(.place))
    }

    func testPerPhotoFramingMotionCropAndTimingCanBeReset() {
        let model = makeModel()
        let photo = model.photos[0]

        model.setFrameStyle(.postcard, forPhotoID: photo.id)
        model.setMotionStyle(.panRight, forPhotoID: photo.id)
        model.setPhotoCrop(scale: 2.2, offsetX: 0.4, offsetY: -0.3, forPhotoID: photo.id)
        model.setPhotoDuration(3.1, forPhotoID: photo.id)

        XCTAssertEqual(model.photos[0].frameStyle, .postcard)
        XCTAssertTrue(model.photos[0].hasCustomFrameStyle)
        XCTAssertEqual(model.photos[0].motionStyle, .panRight)
        XCTAssertEqual(model.photos[0].cropScale, 2.2, accuracy: 0.001)
        XCTAssertEqual(model.photos[0].cropOffsetX, 0.4, accuracy: 0.001)
        XCTAssertEqual(model.photos[0].cropOffsetY, -0.3, accuracy: 0.001)
        XCTAssertEqual(model.duration(for: model.photos[0]), 3.1, accuracy: 0.001)
        XCTAssertEqual(model.customizedPhotoCount, 1)

        model.resetPhotoEdit(id: photo.id)

        XCTAssertEqual(model.photos[0].frameStyle, photo.automaticFrameStyle)
        XCTAssertFalse(model.photos[0].hasCustomFrameStyle)
        XCTAssertEqual(model.photos[0].motionStyle, photo.automaticMotionStyle)
        XCTAssertEqual(model.photos[0].cropScale, photo.automaticCropScale, accuracy: 0.001)
        XCTAssertEqual(model.photos[0].cropOffsetX, photo.automaticCropOffsetX, accuracy: 0.001)
        XCTAssertEqual(model.photos[0].cropOffsetY, photo.automaticCropOffsetY, accuracy: 0.001)
        XCTAssertNil(model.photos[0].durationSeconds)
        XCTAssertEqual(model.customizedPhotoCount, 0)
    }

    func testEditingPhotoSelectionStartsAtTheBeginningWithoutLosingCuts() {
        let model = makeModel()
        let firstID = model.photos[0].id
        model.currentPhotoIndex = min(5, model.photos.count - 1)
        model.cutPhotoIDs = [firstID]
        model.history = [
            PhotoDecision(id: firstID, previousIndex: 0, previousWasCut: false)
        ]
        model.go(.secondWatch)

        model.editPhotoSelection()

        XCTAssertEqual(model.screen, .cut)
        XCTAssertEqual(model.currentPhotoIndex, 0)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(model.cutPhotoIDs.contains(firstID))
    }

    func testFinishingPhotoSelectionReturnsDirectlyToFilmStudio() {
        let model = makeModel()
        model.go(.cut)
        model.history = [
            PhotoDecision(id: model.photos[0].id, previousIndex: 0, previousWasCut: false)
        ]

        model.finishPhotoSelection()

        XCTAssertEqual(model.screen, .secondWatch)
        XCTAssertTrue(model.history.isEmpty)
    }

    func testFilmStudioTimelineReordersOnlyKeptPhotoSlots() throws {
        let model = makeModel()
        let original = model.photos
        let cutID = original[1].id
        model.cutPhotoIDs = [cutID]
        let keptBefore = model.keptPhotos
        let movedID = try XCTUnwrap(keptBefore.last?.id)
        let targetID = try XCTUnwrap(keptBefore.first?.id)

        model.moveKeptPhoto(id: movedID, before: targetID)

        XCTAssertEqual(model.keptPhotos.first?.id, movedID)
        XCTAssertEqual(model.photos[1].id, cutID)
        XCTAssertEqual(model.cutPhotoIDs, [cutID])
        XCTAssertEqual(Set(model.keptPhotos.map(\.id)), Set(keptBefore.map(\.id)))
    }

    func testProductionRenderUsesEditedTimelineAndProducesShareableURL() async throws {
        let exporter = RecordingVideoExporter()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            videoExporter: exporter
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let asset = TripAsset(
            id: "render-photo",
            source: .bundled("my-khe-beach"),
            creationDate: date,
            filename: "IMG_1.JPG",
            pixelWidth: 1_024,
            pixelHeight: 1_536
        )
        let trip = Trip(
            id: "render-trip",
            place: "Marina Bay, Singapore",
            dates: "Today",
            startDate: date,
            endDate: date,
            assets: [asset],
            coverID: asset.id
        )
        model.startBuild(trip: trip)
        model.setFrameStyle(.postcard, forPhotoID: asset.id)
        model.titleCards = [.opening, .ending]
        model.startRender()

        for _ in 0..<50 where model.screen != .done {
            await Task.yield()
        }

        XCTAssertEqual(model.screen, .done)
        XCTAssertNotNil(model.exportedVideoURL)
        let recordedRequest = await exporter.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.photos.first?.frameStyle, .postcard)
        XCTAssertEqual(request.titleCards.map(\.kind), [.opening, .ending])

        let saved = await model.saveExportToPhotos()
        let savedURL = await exporter.savedURL
        XCTAssertTrue(saved)
        XCTAssertEqual(savedURL, model.exportedVideoURL)
    }

    func testStandardExportBuildsACompleteFreeCutWithinLimits() async throws {
        let exporter = RecordingVideoExporter()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            videoExporter: exporter
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<36).map { index in
            TripAsset(
                id: "free-\(index)",
                source: .bundled("my-khe-beach"),
                creationDate: date.addingTimeInterval(Double(index) * 60),
                filename: "IMG_\(index).JPG",
                pixelWidth: 1_024,
                pixelHeight: 1_536
            )
        }
        let trip = Trip(
            id: "free-export-trip",
            place: "Singapore",
            dates: "Today",
            startDate: date,
            endDate: date.addingTimeInterval(35 * 60),
            assets: assets,
            coverID: assets[18].id
        )
        model.startBuild(trip: trip)
        model.titleCards = [.opening, .place, .ending]
        let expectedFirstID = try XCTUnwrap(model.keptPhotos.first?.id)

        XCTAssertLessThan(model.freeExportDurationSeconds, model.filmDurationSeconds)
        XCTAssertGreaterThanOrEqual(model.freeExportMomentCount, 31)
        XCTAssertLessThan(model.freeExportMomentCount, model.keptCount)
        XCTAssertGreaterThanOrEqual(model.fullStoryExclusiveMomentCount, 1)
        XCTAssertLessThanOrEqual(model.fullStoryExclusiveMomentCount, 5)
        XCTAssertFalse(model.fullStoryHighlightPhotos.isEmpty)
        let expectedPhotoIDs = Array(
            model.keptPhotos.prefix(model.freeExportMomentCount)
        ).map(\.id)

        model.requestExport(.standard, isPremium: false)
        for _ in 0..<100 where model.screen != .done {
            await Task.yield()
        }

        XCTAssertEqual(model.screen, .done)
        let recordedRequest = await exporter.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.quality, .standard)
        XCTAssertEqual(request.photos.map(\.id), expectedPhotoIDs)
        XCTAssertEqual(request.photos.first?.id, expectedFirstID)
        XCTAssertFalse(request.titleCards.contains(where: { $0.kind == .ending }))
        let duration = MontageTimelineBuilder.make(
            photos: request.photos,
            titleCards: request.titleCards
        ).reduce(0) { total, item in
            total + item.duration(defaultPhotoDuration: request.secondsPerPhoto)
        }
        XCTAssertEqual(duration, model.freeExportDurationSeconds, accuracy: 0.001)
        XCTAssertEqual(model.activeExportDurationSeconds, duration, accuracy: 0.001)
    }

    func testDecliningProImmediatelyExportsTheFreeVersion() async throws {
        let exporter = RecordingVideoExporter()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            videoExporter: exporter
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let asset = TripAsset(
            id: "free-fallback",
            source: .bundled("my-khe-beach"),
            creationDate: date,
            filename: "IMG_FREE.JPG",
            pixelWidth: 1_024,
            pixelHeight: 1_536
        )
        model.startBuild(trip: Trip(
            id: "paywall-trip",
            place: "Singapore",
            dates: "Today",
            startDate: date,
            endDate: date,
            assets: [asset],
            coverID: asset.id
        ))

        model.requestExport(.highDefinition, isPremium: false)
        XCTAssertEqual(model.screen, .paywall)

        model.exportFreeVersionInsteadOfUpgrading()
        for _ in 0..<100 where model.screen != .done {
            await Task.yield()
        }

        XCTAssertEqual(model.screen, .done)
        XCTAssertNil(model.pendingExportIntent)
        XCTAssertEqual(model.exportQuality, .standard)
        let recordedRequest = await exporter.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.quality, .standard)
    }

    func testUnavailableExportPhotoOffersOneTapRetryWithoutLosingQuality() async throws {
        let exporter = FailOnceVideoExporter()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            videoExporter: exporter
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let asset = TripAsset(
            id: "icloud-photo",
            source: .bundled("my-khe-beach"),
            creationDate: date,
            filename: "PHOTO_0006.JPG",
            pixelWidth: 1_024,
            pixelHeight: 1_536
        )
        let trip = Trip(
            id: "icloud-trip",
            place: "Test trip",
            dates: "Today",
            startDate: date,
            endDate: date,
            assets: [asset],
            coverID: asset.id
        )
        model.startBuild(trip: trip)
        model.startRender(hd: true)

        for _ in 0..<100 where model.exportErrorMessage == nil {
            await Task.yield()
        }

        XCTAssertEqual(model.screen, .export)
        XCTAssertEqual(model.exportErrorTitle, "A moment needs a little longer")
        XCTAssertTrue(model.exportCanRetryPhotoDownload)
        XCTAssertTrue(model.exportErrorMessage?.contains("kept every edit safe") == true)

        model.retryExportPhotoDownload()
        for _ in 0..<100 where model.screen != .done {
            await Task.yield()
        }

        XCTAssertEqual(model.screen, .done)
        let qualities = await exporter.recordedQualities()
        XCTAssertEqual(qualities, [.hd, .hd])
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

    func testFilmLooksResolveToTheSameDistinctTreatmentsForPreviewAndExport() {
        XCTAssertEqual(
            MontageFrameResolver.resolve(
                planned: .fullBleed,
                aspectRatio: 1.5,
                index: 0,
                isCustomized: false,
                look: .story
            ),
            .fullBleed
        )
        XCTAssertEqual(
            MontageFrameResolver.resolve(
                planned: .fullBleed,
                aspectRatio: 1.5,
                index: 0,
                isCustomized: false,
                look: .cinema
            ),
            .cinematic
        )
        XCTAssertEqual(
            MontageFrameResolver.resolve(
                planned: .fullBleed,
                aspectRatio: 1.5,
                index: 0,
                isCustomized: false,
                look: .journal
            ),
            .postcard
        )
        XCTAssertEqual(
            MontageFrameResolver.resolve(
                planned: .cinematic,
                aspectRatio: 1.5,
                index: 1,
                isCustomized: false,
                look: .clean
            ),
            .fullBleed
        )
        XCTAssertEqual(
            MontageFrameResolver.resolve(
                planned: .postcard,
                aspectRatio: 1.5,
                index: 0,
                isCustomized: true,
                look: .cinema
            ),
            .postcard
        )
    }

    func testMontagePlannerUsesLocalFocalPointForPortraitStartingCrop() throws {
        let asset = makeAsset(
            "portrait-subject",
            start: Date(timeIntervalSince1970: 1_800_000_000),
            minutes: 0,
            width: 3_024,
            height: 4_032
        )
        let insight = MontagePhotoInsight(
            memoryScore: 0.91,
            aestheticScore: 0.84,
            contentKind: .people,
            focalPoint: NativePhotoFocalPoint(
                x: 0.80,
                y: 0.74,
                coverage: 0.08,
                source: .faces
            )
        )

        let item = try XCTUnwrap(
            MontageSequencePlanner.plan(
                assets: [asset],
                insights: [asset.id: insight]
            ).first
        )

        XCTAssertEqual(item.frameStyle, .portraitMatte)
        XCTAssertGreaterThan(item.cropScale, 1)
        XCTAssertLessThan(item.cropOffsetX, 0)
        XCTAssertGreaterThan(item.cropOffsetY, 0)
    }

    func testMontagePlannerPreservesCompleteGroupComposition() throws {
        let asset = makeAsset(
            "landscape-group",
            start: Date(timeIntervalSince1970: 1_800_000_000),
            minutes: 0,
            width: 4_032,
            height: 3_024
        )
        let insight = MontagePhotoInsight(
            memoryScore: 0.94,
            aestheticScore: 0.86,
            contentKind: .people,
            peopleCount: 4,
            focalPoint: NativePhotoFocalPoint(
                x: 0.50,
                y: 0.48,
                coverage: 0.62,
                source: .people
            )
        )

        let item = try XCTUnwrap(
            MontageSequencePlanner.plan(
                assets: [asset],
                insights: [asset.id: insight]
            ).first
        )

        XCTAssertTrue(item.protectsPeople)
        XCTAssertEqual(item.frameStyle, .cinematic)
        XCTAssertEqual(item.cropScale, 1)
        XCTAssertEqual(item.cropOffsetX, 0)
        XCTAssertEqual(item.cropOffsetY, 0)
        XCTAssertEqual(
            MontageFrameResolver.resolve(
                planned: item.frameStyle,
                aspectRatio: 4.0 / 3.0,
                index: 0,
                isCustomized: false,
                look: .clean,
                protectsPeople: item.protectsPeople
            ),
            .cinematic
        )
    }

    func testPeopleSafeAutomaticFramingYieldsToAnExplicitMotionEdit() {
        var photo = ReelPhoto(
            id: "people-frame",
            source: .bundled("my-khe-beach"),
            label: "Friends",
            time: "10:00",
            isSimilar: false,
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            protectsPeople: true,
            frameStyle: .cinematic,
            motionStyle: .zoomIn
        )

        XCTAssertTrue(photo.usesAutomaticPeopleFraming)

        photo.motionStyle = .panLeft

        XCTAssertFalse(photo.usesAutomaticPeopleFraming)
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
        XCTAssertEqual(SmartHighlightSelector.targetCount(total: 84, dayCount: 7), 30)
        XCTAssertEqual(SmartHighlightSelector.targetCount(total: 26, dayCount: 1), 26)
        XCTAssertEqual(SmartHighlightSelector.targetCount(total: 20, dayCount: 3), 20)
    }

    func testHighlightSelectorProtectsStrongMemoriesAndMovesDuplicateToMorePhotos() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<40).map {
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
        XCTAssertEqual(assets.count - decisions.count, 30)
    }

    func testSmallEventDoesNotCollapseARepeatedBackdropWithoutPeopleSignals() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<26).map {
            makeAsset("student-\($0)", start: start, minutes: $0)
        }
        let repeatedBackdropPrint = NativePhotoFeaturePrint(
            revision: 2,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: [Float(0.1), 0.2, 0.3].withUnsafeBytes { Data($0) }
        )
        let results = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (
                asset.id,
                makeNativeResult(
                    id: asset.id,
                    memory: 0.52,
                    aesthetic: 0.52,
                    tags: [],
                    featurePrint: repeatedBackdropPrint
                )
            )
        })

        let decisions = SmartHighlightSelector.decisions(
            for: assets,
            nativeResults: results,
            excluding: [:]
        )

        XCTAssertTrue(decisions.isEmpty)
    }

    func testHighlightSelectorDoesNotCollapseDifferentPeopleAgainstTheSameBackdrop() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<20).map {
            makeAsset("burst-candidate-\($0)", start: start, minutes: $0 * 5)
        }
        let firstPrint = NativePhotoFeaturePrint(
            revision: 2,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: [Float(0), 0, 0].withUnsafeBytes { Data($0) }
        )
        let changedExpressionPrint = NativePhotoFeaturePrint(
            revision: 2,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: [Float(11), 0, 0].withUnsafeBytes { Data($0) }
        )
        let weaker = assets[0]
        let stronger = assets[1]
        let results = [
            weaker.id: makeNativeResult(
                id: weaker.id,
                memory: 0.42,
                aesthetic: 0.46,
                tags: [.people],
                featurePrint: firstPrint
            ),
            stronger.id: makeNativeResult(
                id: stronger.id,
                memory: 0.94,
                aesthetic: 0.90,
                tags: [.people, .groupPhoto, .strongMemory],
                featurePrint: changedExpressionPrint
            )
        ]

        let decisions = SmartHighlightSelector.decisions(
            for: assets,
            nativeResults: results,
            excluding: [:]
        )

        XCTAssertTrue(decisions.isEmpty)
        XCTAssertFalse(decisions.contains { $0.id == weaker.id })
        XCTAssertFalse(decisions.contains { $0.id == stronger.id })
    }

    func testMemoryCollectionsOnlyExposeCategoriesThatContainMemories() {
        XCTAssertEqual(
            MemoryCollection.available(overseasCount: 2, localCount: 3),
            [.overseas, .local]
        )
        XCTAssertEqual(
            MemoryCollection.available(overseasCount: 0, localCount: 3),
            [.local]
        )
        XCTAssertEqual(
            MemoryCollection.available(overseasCount: 2, localCount: 0),
            [.overseas]
        )
        XCTAssertTrue(
            MemoryCollection.available(overseasCount: 0, localCount: 0).isEmpty
        )
    }

    func testMemoryCollectionSelectionMovesToTheOnlyAvailableCategory() {
        XCTAssertEqual(
            MemoryCollection.resolvedSelection(.overseas, available: [.local]),
            .local
        )
        XCTAssertEqual(
            MemoryCollection.resolvedSelection(.local, available: [.overseas, .local]),
            .local
        )
        XCTAssertEqual(
            MemoryCollection.resolvedSelection(.local, available: []),
            .overseas
        )
    }

    func testAIVideoMomentRecommendationUsesSceneryForTheBeginningAndPeopleForTheEnding() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = [
            makeAsset("quiet", start: start, minutes: 0),
            makeAsset("place", start: start, minutes: 10),
            makeAsset("detail", start: start, minutes: 20),
            makeAsset("friends", start: start, minutes: 30)
        ]
        let photos = assets.map(makeReelPhoto)
        let insights: [String: MontagePhotoInsight] = [
            "quiet": MontagePhotoInsight(
                memoryScore: 0.45,
                aestheticScore: 0.46,
                contentKind: .moment
            ),
            "place": MontagePhotoInsight(
                memoryScore: 0.87,
                aestheticScore: 0.92,
                contentKind: .scenery
            ),
            "detail": MontagePhotoInsight(
                memoryScore: 0.62,
                aestheticScore: 0.61,
                contentKind: .food
            ),
            "friends": MontagePhotoInsight(
                memoryScore: 0.91,
                aestheticScore: 0.84,
                contentKind: .people,
                peopleCount: 5
            )
        ]

        let recommendation = AIVideoMomentRecommender.recommend(
            photos: photos,
            insights: insights
        )

        XCTAssertEqual(recommendation.photoIDs, ["place", "friends"])
        XCTAssertTrue(recommendation.isVisionBased)
    }

    func testAIVideoMomentRecommendationFallsBackToTheFirstAndLastFrames() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let photos = [
            makeReelPhoto(from: makeAsset("first", start: start, minutes: 0)),
            makeReelPhoto(from: makeAsset("middle", start: start, minutes: 5)),
            makeReelPhoto(from: makeAsset("last", start: start, minutes: 10))
        ]

        let recommendation = AIVideoMomentRecommender.recommend(
            photos: photos,
            insights: [:]
        )

        XCTAssertEqual(recommendation.photoIDs, ["first", "last"])
        XCTAssertFalse(recommendation.isVisionBased)
    }

    func testAICutRecommendationPrefersQualityOverFirstCutMembership() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let weakFirstCut = makeAsset("weak-first", start: start, minutes: 0)
        let strongMoreMoment = makeAsset("strong-more", start: start, minutes: 20)
        let candidates = [
            AICutMomentCandidate(
                photo: makeReelPhoto(from: weakFirstCut),
                asset: weakFirstCut,
                localSelection: .firstCut
            ),
            AICutMomentCandidate(
                photo: makeReelPhoto(from: strongMoreMoment),
                asset: strongMoreMoment,
                localSelection: .morePhotos
            )
        ]
        let insights = [
            weakFirstCut.id: MontagePhotoInsight(
                memoryScore: 0.18,
                aestheticScore: 0.22,
                contentKind: .moment
            ),
            strongMoreMoment.id: MontagePhotoInsight(
                memoryScore: 0.95,
                aestheticScore: 0.94,
                contentKind: .scenery
            )
        ]

        let recommendation = AICutMomentRecommender.recommend(
            candidates: candidates,
            insights: insights,
            direction: .surpriseMe,
            limit: 1
        )

        XCTAssertEqual(recommendation.map { $0.photo.id }, [strongMoreMoment.id])
    }

    func testAICutRecommendationIncludesRelevantPeopleAndVideo() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let scenic = makeAsset("scenic", start: start, minutes: 0)
        let people = makeAsset("people", start: start, minutes: 15)
        let video = makeAsset(
            "video",
            start: start,
            minutes: 30,
            mediaKind: .video,
            sourceDurationSeconds: 12
        )
        let candidates = [scenic, people, video].map {
            AICutMomentCandidate(
                photo: makeReelPhoto(from: $0),
                asset: $0,
                localSelection: .firstCut
            )
        }
        let insights = [
            scenic.id: MontagePhotoInsight(
                memoryScore: 0.94,
                aestheticScore: 0.94,
                contentKind: .scenery
            ),
            people.id: MontagePhotoInsight(
                memoryScore: 0.76,
                aestheticScore: 0.74,
                contentKind: .people,
                peopleCount: 4
            ),
            video.id: MontagePhotoInsight(
                memoryScore: 0.72,
                aestheticScore: 0.70,
                contentKind: .moment
            )
        ]

        let recommendation = AICutMomentRecommender.recommend(
            candidates: candidates,
            insights: insights,
            direction: .people,
            limit: 2
        )
        let selectedIDs = Set(recommendation.map { $0.photo.id })

        XCTAssertEqual(selectedIDs, [people.id, video.id])
    }

    func testFreeExportPlannerHonorsASafeAIDirectedEnding() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let photos = (0..<12).map {
            makeReelPhoto(from: makeAsset("preview-\($0)", start: start, minutes: $0))
        }

        let decision = FreeExportStoryPlanner.decide(
            photos: photos,
            titleCards: [],
            textOverlays: [],
            insights: [:],
            preferredEndPhotoID: photos[9].id,
            preferredReason: "  The first payoff lands here.  "
        )

        XCTAssertEqual(decision.endPhotoID, photos[9].id)
        XCTAssertEqual(decision.reason, "The first payoff lands here.")
        XCTAssertEqual(decision.source, .aiDirector)
    }

    func testFreeExportPlannerRejectsAnAICutThatWouldHideTooMuch() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let photos = (0..<12).map {
            makeReelPhoto(from: makeAsset("guardrail-\($0)", start: start, minutes: $0))
        }

        let decision = FreeExportStoryPlanner.decide(
            photos: photos,
            titleCards: [],
            textOverlays: [],
            insights: [:],
            preferredEndPhotoID: photos[2].id,
            preferredReason: "End very early."
        )

        let selectedIndex = try XCTUnwrap(
            photos.firstIndex { $0.id == decision.endPhotoID }
        )
        XCTAssertEqual(decision.source, .onDevice)
        XCTAssertLessThanOrEqual(
            photos.count - selectedIndex - 1,
            2,
            "Only the bounded final story window may be omitted"
        )
    }

    func testFreeExportPlannerUsesLocalQualityToFindTheStrongerLateBeat() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let photos = (0..<12).map {
            makeReelPhoto(from: makeAsset("quality-\($0)", start: start, minutes: $0))
        }
        let insights = [
            photos[9].id: MontagePhotoInsight(
                memoryScore: 0.18,
                aestheticScore: 0.24,
                contentKind: .moment
            ),
            photos[10].id: MontagePhotoInsight(
                memoryScore: 0.96,
                aestheticScore: 0.92,
                contentKind: .people,
                peopleCount: 4
            )
        ]

        let decision = FreeExportStoryPlanner.decide(
            photos: photos,
            titleCards: [],
            textOverlays: [],
            insights: insights,
            preferredEndPhotoID: nil,
            preferredReason: nil
        )

        XCTAssertEqual(decision.endPhotoID, photos[10].id)
        XCTAssertEqual(decision.reason, "Ends on a strong people moment.")
        XCTAssertEqual(decision.source, .onDevice)
    }

    func testFreeExportPlannerKeepsAShortStoryWhole() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let photos = (0..<5).map {
            makeReelPhoto(from: makeAsset("short-\($0)", start: start, minutes: $0))
        }

        let decision = FreeExportStoryPlanner.decide(
            photos: photos,
            titleCards: [],
            textOverlays: [],
            insights: [:],
            preferredEndPhotoID: photos[1].id,
            preferredReason: "Too early"
        )

        XCTAssertEqual(decision.endPhotoID, photos.last?.id)
        XCTAssertEqual(decision.reason, "This story is strongest kept whole.")
    }

    private func makeAsset(
        _ id: String,
        start: Date,
        minutes: Int,
        width: Int = 4_032,
        height: Int = 3_024,
        mediaKind: LibraryMediaKind = .photo,
        sourceDurationSeconds: Double = 0
    ) -> TripAsset {
        TripAsset(
            id: id,
            source: .library(id),
            creationDate: start.addingTimeInterval(Double(minutes) * 60),
            filename: "\(id).HEIC",
            pixelWidth: width,
            pixelHeight: height,
            mediaKind: mediaKind,
            sourceDurationSeconds: sourceDurationSeconds
        )
    }

    private func makeReelPhoto(from asset: TripAsset) -> ReelPhoto {
        ReelPhoto(
            id: asset.id,
            source: asset.source,
            label: asset.filename,
            time: "12:00",
            isSimilar: false,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            frameStyle: .fullBleed,
            motionStyle: .zoomIn,
            durationSeconds: asset.isVideo ? 2.5 : nil,
            mediaKind: asset.mediaKind,
            sourceDurationSeconds: asset.sourceDurationSeconds
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
    var authorizationStatus: PHAuthorizationStatus

    init(
        photos: [PhotoMetadata],
        authorizationStatus: PHAuthorizationStatus = .authorized
    ) {
        self.photos = photos
        self.authorizationStatus = authorizationStatus
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        authorizationStatus
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

private actor RecordingVideoExporter: TripReelVideoExporting {
    private(set) var lastRequest: TripReelVideoExportRequest?
    private(set) var savedURL: URL?

    func export(
        _ request: TripReelVideoExportRequest,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws -> URL {
        lastRequest = request
        progress(
            TripReelVideoExportProgress(
                fraction: 1,
                phase: .finalizing
            )
        )
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("TripReel-test.mp4")
    }

    func saveToPhotoLibrary(_ url: URL) async throws {
        savedURL = url
    }
}

private actor FailOnceVideoExporter: TripReelVideoExporting {
    private var qualities: [ExportQuality] = []

    func export(
        _ request: TripReelVideoExportRequest,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws -> URL {
        qualities.append(request.quality)
        if qualities.count == 1 {
            progress(
                TripReelVideoExportProgress(
                    fraction: 0.08,
                    phase: .preparingPhotos(
                        ready: 0,
                        total: 1,
                        currentLabel: "PHOTO_0006",
                        downloadProgress: 0.42
                    )
                )
            )
            throw TripReelVideoExportError.photoUnavailable("PHOTO_0006")
        }
        progress(
            TripReelVideoExportProgress(
                fraction: 1,
                phase: .finalizing
            )
        )
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("TripReel-retry-test.mp4")
    }

    func saveToPhotoLibrary(_ url: URL) async throws {}

    func recordedQualities() -> [ExportQuality] { qualities }
}
