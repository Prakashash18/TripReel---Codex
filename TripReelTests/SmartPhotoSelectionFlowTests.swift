import CoreGraphics
import Photos
import XCTest
@testable import TripReel

@MainActor
final class SmartPhotoSelectionFlowTests: XCTestCase {
    func testFirstCutBuildsOnDeviceWithoutConsentOrCloud() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy()
        let thumbnails = ThumbnailStub()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: thumbnails,
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )
        let trip = makeTrip(count: 2)

        model.requestBuild(trip: trip)

        try await waitUntil { model.screen == .building }

        XCTAssertFalse(model.isCloudAnalysisConsentPresented)
        let firstCutCloudCalls = await cloud.observedCallCount()
        XCTAssertEqual(firstCutCloudCalls, 0)
        XCTAssertEqual(model.photos.count, 2)
        XCTAssertNotNil(model.firstCutSnapshot)
        XCTAssertNil(model.aiCutSnapshot)
        model.go(.trips)
    }

    func testConsentComesBeforeDirectionAndCreatesSeparateAICut() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy()
        let thumbnails = ThumbnailStub()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: thumbnails,
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )
        let trip = makeTrip(count: 2)

        model.requestBuild(trip: trip)
        try await waitUntil { model.screen == .building }
        let firstIDs = try XCTUnwrap(model.firstCutSnapshot).keptPhotos.map(\.id)
        model.go(.firstCutOptions)

        model.openAICutDirections()
        XCTAssertEqual(model.selectedAICutDirection, .surpriseMe)
        XCTAssertTrue(model.isCloudAnalysisConsentPresented)
        XCTAssertEqual(model.aiCutSelectedPhotoCount, 2)
        XCTAssertFalse(model.aiCutCanCreate)
        model.continueWithAICutDirection()
        let callsBeforeConsent = await cloud.observedCallCount()
        let thumbnailsBeforeConsent = await thumbnails.observedRequestedIDs()
        XCTAssertEqual(callsBeforeConsent, 0)
        XCTAssertEqual(thumbnailsBeforeConsent, ["asset-0", "asset-1"])

        model.useCloudEnhancement()
        XCTAssertEqual(model.screen, .aiDirection)
        XCTAssertFalse(model.isCloudAnalysisConsentPresented)
        XCTAssertTrue(model.aiCutCanCreate)
        let callsOnConsent = await cloud.observedCallCount()
        let thumbnailsOnConsent = await thumbnails.observedRequestedIDs()
        XCTAssertEqual(callsOnConsent, 0)
        XCTAssertEqual(thumbnailsOnConsent, thumbnailsBeforeConsent)

        model.selectAICutDirection(.dynamic)
        model.continueWithAICutDirection()
        try await waitUntil { model.screen == .aiComparison }

        let callsAfterConsent = await cloud.observedCallCount()
        let thumbnailsAfterConsent = await thumbnails.observedRequestedIDs()
        let baselines = await cloud.observedBaselines()
        let contexts = await cloud.observedEditorialContexts()
        XCTAssertEqual(callsAfterConsent, 1)
        XCTAssertEqual(thumbnailsAfterConsent, ["asset-0", "asset-1", "asset-0", "asset-1"])
        XCTAssertEqual(model.firstCutSnapshot?.keptPhotos.map(\.id), firstIDs)
        XCTAssertEqual(model.aiCutSnapshot?.keptPhotos.map(\.id), Array(firstIDs.reversed()))
        XCTAssertEqual(model.aiCutSnapshot?.selectedTrackID, "simplicity")
        XCTAssertEqual(model.aiCutSnapshot?.montageLook, .journal)
        XCTAssertEqual(model.aiCutSnapshot?.motionIntensity, .expressive)
        XCTAssertEqual(model.aiCutSnapshot?.titleDrafts[.opening]?.title, "A different angle")
        XCTAssertTrue(model.aiCutSnapshot?.titleCards.contains(.ending) == true)
        XCTAssertEqual(model.aiCutRecommendations.count, 4)
        XCTAssertEqual(baselines.count, 1)
        XCTAssertEqual(baselines[0]?.photoCount, 2)
        XCTAssertEqual(baselines[0]?.sequence.map(\.photoID), ["p0", "p1"])
        XCTAssertEqual(contexts.first?.compactMap { $0 }.count, 2)
        XCTAssertEqual(contexts.first?.compactMap { $0 }.first?.captureIndex, 0)
        XCTAssertEqual(model.aiCutDiagnosis?.issues.first?.kind, .flatPacing)
        XCTAssertEqual(model.aiCutComparison?.materiallyDifferent, true)

        model.useAICut()
        XCTAssertEqual(model.selectedCutSource, .aiCut)
        XCTAssertEqual(model.photos.map(\.id), Array(firstIDs.reversed()))
        XCTAssertEqual(model.screen, .secondWatch)

        model.editCut(.aiCut)
        XCTAssertEqual(model.selectedCutSource, .working)
        XCTAssertEqual(model.photos.map(\.id), Array(firstIDs.reversed()))
        XCTAssertEqual(model.screen, .secondWatch)

        model.keepFirstCut()
        XCTAssertEqual(model.selectedCutSource, .firstCut)
        XCTAssertEqual(model.photos.map(\.id), firstIDs)
        XCTAssertEqual(model.firstCutSnapshot?.keptPhotos.map(\.id), firstIDs)

        model.tryAnotherAICut()
        XCTAssertEqual(model.screen, .aiDirection)
        XCTAssertEqual(model.firstCutSnapshot?.keptPhotos.map(\.id), firstIDs)
    }

    func testDecliningConsentReturnsToFirstCutWithoutCloud() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 2))
        try await waitUntil { model.screen == .building }
        model.go(.firstCutOptions)
        model.openAICutDirections()
        XCTAssertTrue(model.isCloudAnalysisConsentPresented)
        model.keepAnalysisOnDevice()

        XCTAssertEqual(model.screen, .firstCutOptions)
        XCTAssertFalse(model.isCloudAnalysisConsentPresented)
        let declinedCalls = await cloud.observedCallCount()
        XCTAssertEqual(declinedCalls, 0)
        XCTAssertNotNil(model.firstCutSnapshot)
        XCTAssertNil(model.aiCutSnapshot)
    }

    func testUnavailableCloudFailsClosedAndLeavesFirstCutIntact() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy(isConfigured: false)
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 3))
        try await waitUntil { model.screen == .building }
        let first = try XCTUnwrap(model.firstCutSnapshot)
        model.go(.firstCutOptions)
        model.openAICutDirections()
        XCTAssertTrue(model.isCloudAnalysisConsentPresented)
        model.useCloudEnhancement()

        XCTAssertEqual(model.screen, .firstCutOptions)
        XCTAssertTrue(model.isCloudAnalysisConsentPresented)
        XCTAssertNil(model.aiCutFailureMessage)
        XCTAssertEqual(model.firstCutSnapshot, first)
        XCTAssertNil(model.aiCutSnapshot)
        let unavailableCalls = await cloud.observedCallCount()
        XCTAssertEqual(unavailableCalls, 0)
    }

    func testCloudFailureAfterConsentLeavesFirstCutReadyAndUnchanged() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy(fails: true)
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 3))
        try await waitUntil { model.screen == .building }
        let first = try XCTUnwrap(model.firstCutSnapshot)
        model.go(.firstCutOptions)
        model.openAICutDirections()
        model.useCloudEnhancement()
        model.selectAICutDirection(.surpriseMe)
        model.continueWithAICutDirection()

        try await waitUntil { model.aiCutFailureMessage != nil }

        let callCount = await cloud.observedCallCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.screen, .aiProcessing)
        XCTAssertEqual(model.firstCutSnapshot, first)
        XCTAssertNil(model.aiCutSnapshot)
        XCTAssertEqual(model.photos, first.photos)
    }

    func testMetadataScreenshotIsExcludedWithoutPreparingOrUploadingIt() async throws {
        let preferences = makePreferences()
        preferences.set("enabled", forKey: "tripreel.cloud-photo-analysis-preference.v1")
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy()
        let thumbnails = ThumbnailStub()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: thumbnails,
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )
        let screenshot = TripAsset(
            id: "screen",
            source: .library("screen"),
            creationDate: Date(),
            filename: "",
            isScreenshot: true
        )
        let camera = TripAsset(
            id: "camera",
            source: .library("camera"),
            creationDate: Date().addingTimeInterval(1),
            filename: "IMG_1.HEIC"
        )
        let trip = Trip(
            id: "trip",
            place: "Test",
            dates: "Today",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1),
            assets: [screenshot, camera],
            coverID: camera.id
        )

        model.requestBuild(trip: trip)
        try await waitUntil { model.screen == .building }

        XCTAssertEqual(model.excludedPhotos.first?.reason, .screenshot)
        XCTAssertEqual(model.excludedPhotos.first?.origin, .metadata)
        let requestedIDs = await thumbnails.observedRequestedIDs()
        let cloudCalls = await cloud.observedCallCount()
        XCTAssertEqual(requestedIDs, ["camera"])
        XCTAssertEqual(cloudCalls, 0)

        model.includeExcludedPhoto(id: screenshot.id)
        XCTAssertEqual(model.selectedCutSource, .working)
        XCTAssertEqual(Set(model.photos.map(\.id)), ["screen", "camera"])
        model.editCut(.working)
        XCTAssertEqual(model.screen, .secondWatch)
        XCTAssertEqual(Set(model.photos.map(\.id)), ["screen", "camera"])

        model.openAICutDirections()
        model.useCloudEnhancement()
        model.selectAICutDirection(.people)
        model.continueWithAICutDirection()
        try await waitUntil { model.screen == .aiComparison }

        let remixCalls = await cloud.observedCallCount()
        let wireIDs = await cloud.observedWireIDs()
        let allRequestedIDs = await thumbnails.observedRequestedIDs()
        XCTAssertEqual(remixCalls, 1)
        XCTAssertEqual(wireIDs, ["p0"])
        XCTAssertEqual(allRequestedIDs, ["camera", "camera"])
    }

    func testTextHeavyMemoryCanStayInFirstCutButIsBlockedFromAIPayload() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy()
        let thumbnails = ThumbnailStub()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: thumbnails,
            nativePhotoIntelligence: NativeIntelligenceStub(protectedDocumentID: "asset-0"),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 2))
        try await waitUntil { model.screen == .building }

        XCTAssertEqual(Set(try XCTUnwrap(model.firstCutSnapshot).keptPhotos.map(\.id)), ["asset-0", "asset-1"])

        model.openAICutDirections()
        model.useCloudEnhancement()
        model.selectAICutDirection(.betterStory)
        model.continueWithAICutDirection()
        try await waitUntil { model.screen == .aiComparison }

        let wireIDs = await cloud.observedWireIDs()
        let requestedIDs = await thumbnails.observedRequestedIDs()
        XCTAssertEqual(wireIDs, ["p0"])
        XCTAssertEqual(requestedIDs, ["asset-0", "asset-1", "asset-1"])
        XCTAssertEqual(model.firstCutSnapshot?.keptPhotos.count, 2)
    }

    func testLargeOnDeviceTripBecomesAConciseRecoverableFirstCut() async throws {
        let preferences = makePreferences()
        preferences.set("onDeviceOnly", forKey: "tripreel.cloud-photo-analysis-preference.v1")
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: CloudAnalysisSpy(),
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 40))
        try await waitUntil { model.screen == .building }

        XCTAssertEqual(model.photos.count, 30)
        XCTAssertEqual(model.excludedPhotos.count, 10)
        XCTAssertTrue(model.excludedPhotos.allSatisfy { $0.reason == .notAHighlight })
        XCTAssertEqual(model.photoAnalysisProcessedCount, 40)
        XCTAssertEqual(model.photoAnalysisRecentAssets.count, 6)
        model.go(.trips)
    }

    func testSmallEventKeepsEverySafeMomentLocally() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: CloudAnalysisSpy(),
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 26))
        try await waitUntil { model.screen == .building }

        XCTAssertEqual(model.photos.count, 26)
        XCTAssertTrue(model.excludedPhotos.isEmpty)
        model.go(.trips)
    }

    func testCloudRemixBalancesFirstCutWithSafeMorePhotosAndCanRestoreThem() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 40))
        try await waitUntil { model.screen == .building }
        let morePhotoIDs = Set(model.excludedPhotos.map(\.id))
        XCTAssertEqual(morePhotoIDs.count, 10)

        model.openAICutDirections()
        model.useCloudEnhancement()
        model.selectAICutDirection(.people)
        model.aiCutStoryContext = "Our students’ competition day"
        model.continueWithAICutDirection()
        try await waitUntil { model.screen == .aiComparison }

        let localSelections = await cloud.observedLocalSelections()
        let storyContexts = await cloud.observedStoryContexts()
        XCTAssertEqual(localSelections.filter { $0 == .firstCut }.count, 26)
        XCTAssertEqual(localSelections.filter { $0 == .morePhotos }.count, 10)
        XCTAssertEqual(storyContexts, ["Our students’ competition day"])
        let aiIDs = Set(try XCTUnwrap(model.aiCutSnapshot).keptPhotos.map(\.id))
        XCTAssertEqual(aiIDs.intersection(morePhotoIDs), morePhotoIDs)
        XCTAssertEqual(aiIDs.count, CloudPhotoAnalysisClient.maximumBatchSize)
        XCTAssertTrue(try XCTUnwrap(model.aiCutSnapshot).titleCards.contains(.place))
        XCTAssertEqual(model.aiCutSnapshot?.titleDrafts[.place]?.title, "People make the moment")

        model.openAIVideoIntro(from: .aiCut)
        XCTAssertEqual(model.screen, .aiVideoIntro)
        XCTAssertEqual(model.aiVideoSelectedPhotos.count, 2)
        XCTAssertEqual(Set(model.aiVideoSelectedPhotoIDs).count, 2)
        XCTAssertTrue(model.aiVideoRecommendationIsVisionBased)
        XCTAssertTrue(
            model.aiCutSnapshot?.keptPhotos.contains(where: { $0.id == model.aiVideoSelectedPhoto?.id }) == true
        )
        model.navigateBack()
        XCTAssertEqual(model.screen, .aiComparison)

        model.useAICut()
        XCTAssertEqual(model.screen, .export)
        XCTAssertNil(model.smartSelectionSummary)
        XCTAssertTrue(model.visibleExcludedPhotos.isEmpty)
    }

    func testUserChoosesExactPhotosSentToAIDirector() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy()
        let thumbnails = ThumbnailStub()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: thumbnails,
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 6))
        try await waitUntil { model.screen == .building }
        model.go(.firstCutOptions)
        model.openAICutDirections()
        model.useCloudEnhancement()

        XCTAssertEqual(model.screen, .aiDirection)
        XCTAssertEqual(model.aiCutPhotoOptions.count, 6)
        XCTAssertEqual(model.aiCutSelectedPhotoCount, 6)

        model.clearAICutPhotoSelection()
        model.toggleAICutPhotoSelection("asset-1")
        model.toggleAICutPhotoSelection("asset-4")
        XCTAssertEqual(model.selectedAICutPhotoIDs, ["asset-1", "asset-4"])

        model.selectAICutDirection(.betterStory)
        model.continueWithAICutDirection()
        try await waitUntil { model.screen == .aiComparison }

        let allRequests = await thumbnails.observedRequestedIDs()
        let cloudCalls = await cloud.observedCallCount()
        XCTAssertEqual(cloudCalls, 1)
        XCTAssertEqual(Array(allRequests.suffix(2)), ["asset-1", "asset-4"])
        XCTAssertEqual(model.aiCutSnapshot?.keptPhotos.map(\.id), ["asset-4", "asset-1"])
    }

    func testDeferredPhotosUsePositiveFollowUpAndCanBeCheckedAgain() async throws {
        let preferences = makePreferences()
        preferences.set("onDeviceOnly", forKey: "tripreel.cloud-photo-analysis-preference.v1")
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let thumbnails = RetryableThumbnailStub()
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: CloudAnalysisSpy(),
            photoAnalysisThumbnails: thumbnails,
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 4))
        try await waitUntil {
            !model.isAnalyzingPhotos && model.photoAnalysisFollowUp != nil
        }

        XCTAssertNil(model.libraryErrorMessage)
        XCTAssertEqual(model.photos.map(\.id), ["asset-3"])
        XCTAssertEqual(model.excludedPhotos.count, 3)
        XCTAssertTrue(model.excludedPhotos.allSatisfy { $0.reason == .waitingForPhotos })
        XCTAssertEqual(model.photoAnalysisFollowUp?.syncingFromPhotosCount, 1)
        XCTAssertEqual(model.photoAnalysisFollowUp?.anotherLookCount, 1)
        XCTAssertEqual(model.photoAnalysisFollowUp?.accessNeededCount, 1)
        XCTAssertEqual(
            model.photoAnalysisFollowUp?.previewMessage,
            "3 more moments can be checked later"
        )

        model.retryPhotoAnalysisFollowUp()
        try await waitUntil {
            !model.isAnalyzingPhotos && model.photoAnalysisFollowUp == nil
        }

        let requestCount = await thumbnails.observedRequestCount()
        XCTAssertEqual(requestCount, 8)
        XCTAssertEqual(model.photos.count, 4)
        model.go(.trips)
    }

    func testEntirelyUnavailableTripDoesNotCreateABlankPreview() async throws {
        let preferences = makePreferences()
        preferences.set("onDeviceOnly", forKey: "tripreel.cloud-photo-analysis-preference.v1")
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: CloudAnalysisSpy(),
            photoAnalysisThumbnails: UnavailableThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.requestBuild(trip: makeTrip(count: 2))
        try await waitUntil { !model.isAnalyzingPhotos && model.libraryErrorMessage != nil }

        XCTAssertTrue(model.photos.isEmpty)
        XCTAssertNotEqual(model.screen, .building)
        XCTAssertEqual(model.excludedPhotos.count, 2)
        XCTAssertTrue(model.excludedPhotos.allSatisfy { $0.reason == .waitingForPhotos })
        XCTAssertTrue(model.libraryErrorMessage?.contains("instead of showing empty frames") == true)
    }

    func testAuthorizationLossCancelsAnalysisAndClearsPendingFilm() async throws {
        let preferences = makePreferences()
        preferences.set("onDeviceOnly", forKey: "tripreel.cloud-photo-analysis-preference.v1")
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: CloudAnalysisSpy(),
            photoAnalysisThumbnails: SlowThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )

        model.go(.trips)
        model.requestBuild(trip: makeTrip(count: 2))
        try await waitUntil { model.isAnalyzingPhotos }

        model.clearLibraryState(afterAuthorizationChangedTo: .denied)
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertFalse(model.isAnalyzingPhotos)
        XCTAssertEqual(model.screen, .access)
        XCTAssertTrue(model.photos.isEmpty)
        XCTAssertTrue(model.excludedPhotos.isEmpty)
        XCTAssertFalse(model.isCloudAnalysisConsentPresented)
    }

    private var preferencesSuiteName: String {
        "TripReelTests.SmartPhotoSelectionFlow"
    }

    private func makePreferences() -> UserDefaults {
        let defaults = UserDefaults(suiteName: preferencesSuiteName)!
        defaults.removePersistentDomain(forName: preferencesSuiteName)
        return defaults
    }

    private func makeTrip(count: Int) -> Trip {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<count).map { index in
            TripAsset(
                id: "asset-\(index)",
                source: .library("asset-\(index)"),
                creationDate: start.addingTimeInterval(Double(index)),
                filename: "IMG_\(index).HEIC"
            )
        }
        return Trip(
            id: "test-trip",
            place: "Test trip",
            dates: "Today",
            startDate: start,
            endDate: start.addingTimeInterval(Double(max(1, count - 1))),
            assets: assets,
            coverID: assets[0].id
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { throw WaitError.timedOut }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private enum WaitError: Error { case timedOut }
}

private actor CloudAnalysisSpy: CloudPhotoAnalysisServing {
    nonisolated let isConfigured: Bool
    private(set) var callCount = 0
    private(set) var wireIDs: [String] = []
    private(set) var localSelections: [CloudPhotoLocalSelection] = []
    private(set) var storyContexts: [String?] = []
    private(set) var baselines: [CloudFirstCutInput?] = []
    private(set) var editorialContexts: [[CloudPhotoEditorialContext?]] = []
    private let fails: Bool

    init(isConfigured: Bool = true, fails: Bool = false) {
        self.isConfigured = isConfigured
        self.fails = fails
    }

    func createEditPlan(
        direction: AICutDirection,
        storyContext: String?,
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan {
        try makePlan(
            direction: direction,
            storyContext: storyContext,
            baseline: nil,
            photos: photos
        )
    }

    func createEditPlan(
        direction: AICutDirection,
        storyContext: String?,
        baseline: CloudFirstCutInput?,
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan {
        try makePlan(
            direction: direction,
            storyContext: storyContext,
            baseline: baseline,
            photos: photos
        )
    }

    private func makePlan(
        direction: AICutDirection,
        storyContext: String?,
        baseline: CloudFirstCutInput?,
        photos: [CloudPhotoAnalysisInput]
    ) throws -> AICutEditPlan {
        callCount += 1
        wireIDs = photos.map(\.id)
        localSelections = photos.map(\.localSelection)
        storyContexts.append(storyContext)
        baselines.append(baseline)
        editorialContexts.append(photos.map(\.context))
        if fails { throw CloudPhotoAnalysisError.invalidResponse }
        return AICutEditPlan(
            version: baseline == nil ? 2 : 3,
            direction: direction,
            summary: "A distinct alternative using only the selected previews.",
            story: AICutStory(
                title: "People make the moment",
                arc: "Open with a strong shared moment, vary the details, and resolve on a warm final frame."
            ),
            hook: AICutTitleCardPlan(
                title: "A different angle",
                subtitle: "The moments between the moments",
                style: .bold,
                durationSeconds: 2.2
            ),
            ending: AICutEndingPlan(
                enabled: true,
                title: "Worth another look",
                subtitle: "",
                style: .clean,
                durationSeconds: 2
            ),
            soundtrack: AICutSoundtrackPlan(
                trackID: .simplicity,
                reason: "A bright acoustic pulse supports the people-led edit."
            ),
            treatment: AICutTreatmentPlan(
                look: .journal,
                motionIntensity: .expressive,
                reason: "Tactile frames and varied movement separate similar settings."
            ),
            sequence: photos.reversed().enumerated().map { index, photo in
                AICutPlanItem(
                    photoID: photo.id,
                    order: index,
                    durationSeconds: min(3.8, 1.4 + (Double(index) * 0.2)),
                    role: index == 0 ? .opening : .closing,
                    emphasis: index == 0 ? .highlight : .normal,
                    motion: index.isMultiple(of: 2) ? .zoomIn : .panLeft
                )
            },
            diagnosis: baseline.map { _ in
                AICutDiagnosis(
                    verdict: "The First Cut needs a clearer emotional build.",
                    issues: [AICutDiagnosisIssue(
                        kind: .flatPacing,
                        title: "Vary the rhythm",
                        detail: "Let strong reactions land and move faster through connective frames.",
                        evidencePhotoIDs: photos.prefix(1).map(\.id)
                    )]
                )
            },
            comparison: baseline.map {
                AICutComparison(
                    firstCutPhotoCount: $0.photoCount,
                    aiCutPhotoCount: photos.count,
                    restoredCount: photos.filter { $0.localSelection == .morePhotos }.count,
                    removedCount: 0,
                    reorderedCount: photos.count > 1 ? 1 : 0,
                    retimedCount: photos.count,
                    motionChangedCount: photos.count,
                    titleChangedCount: 2,
                    soundtrackChanged: true,
                    treatmentChanged: true,
                    score: 62,
                    materiallyDifferent: true
                )
            }
        )
    }

    func observedCallCount() -> Int { callCount }
    func observedWireIDs() -> [String] { wireIDs }
    func observedLocalSelections() -> [CloudPhotoLocalSelection] { localSelections }
    func observedStoryContexts() -> [String?] { storyContexts }
    func observedBaselines() -> [CloudFirstCutInput?] { baselines }
    func observedEditorialContexts() -> [[CloudPhotoEditorialContext?]] { editorialContexts }
}

private actor ThumbnailStub: PhotoAnalysisThumbnailServing {
    private(set) var requestedIDs: [String] = []

    func prepare(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        requestedIDs.append(asset.id)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return PreparedPhotoThumbnail(
            id: asset.id,
            cgImage: context.makeImage()!,
            jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )
    }

    func observedRequestedIDs() -> [String] { requestedIDs }
}

private actor SlowThumbnailStub: PhotoAnalysisThumbnailServing {
    func prepare(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw CancellationError()
    }
}

private actor UnavailableThumbnailStub: PhotoAnalysisThumbnailServing {
    func prepare(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        throw PhotoAnalysisThumbnailError.unavailable
    }
}

private actor RetryableThumbnailStub: PhotoAnalysisThumbnailServing {
    private var attempts: [String: Int] = [:]

    func prepare(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        let attempt = (attempts[asset.id] ?? 0) + 1
        attempts[asset.id] = attempt
        if attempt == 1 {
            switch asset.id {
            case "asset-0": throw PhotoAnalysisThumbnailError.unavailable
            case "asset-1": throw PhotoAnalysisThumbnailError.decodeFailed
            case "asset-2": throw PhotoAnalysisThumbnailError.inaccessible
            default: break
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return PreparedPhotoThumbnail(
            id: asset.id,
            cgImage: context.makeImage()!,
            jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )
    }

    func observedRequestCount() -> Int {
        attempts.values.reduce(0, +)
    }
}

private actor NativeIntelligenceStub: NativePhotoIntelligenceServing {
    private let protectedDocumentID: String?

    init(protectedDocumentID: String? = nil) {
        self.protectedDocumentID = protectedDocumentID
    }

    func analyze(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        metadata: NativePhotoIntelligenceMetadata
    ) async throws -> NativePhotoIntelligenceResult {
        let signals: NativePhotoIntelligenceSignals
        if metadata.sourceIdentifier == protectedDocumentID {
            signals = NativePhotoIntelligenceSignals(
                classifications: [
                    NativePhotoClassification(identifier: "landscape", confidence: 0.96)
                ],
                text: NativePhotoTextSignal(
                    lineCount: 20,
                    characterCount: 800,
                    coverage: 0.40,
                    averageConfidence: 0.96
                ),
                document: NativePhotoDocumentSignal(
                    detected: true,
                    confidence: 0.98,
                    coverage: 0.72
                ),
                aesthetics: NativePhotoAestheticsSignal(overallScore: 0.82, isUtility: false),
                availability: NativePhotoSignalAvailability(
                    classification: true,
                    textRecognition: true,
                    faceQuality: false,
                    documentDetection: true,
                    featurePrint: false,
                    aesthetics: true
                )
            )
        } else {
            signals = NativePhotoIntelligenceSignals(
                availability: NativePhotoSignalAvailability(
                    classification: false,
                    textRecognition: false,
                    faceQuality: false,
                    documentDetection: false,
                    featurePrint: false,
                    aesthetics: false
                )
            )
        }
        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)
        return NativePhotoIntelligenceResult(
            sourceIdentifier: metadata.sourceIdentifier,
            analyzedPixelWidth: cgImage.width,
            analyzedPixelHeight: cgImage.height,
            signals: signals,
            scores: assessment.scores,
            tags: assessment.tags,
            cloudReviewGate: assessment.cloudReviewGate
        )
    }
}

private final class StubPhotoLibraryForSelection: PhotoLibraryServing, @unchecked Sendable {
    var onLibraryChange: (@Sendable () -> Void)?
    func fetchAllPhotos() async -> [PhotoMetadata] { [] }
    func fetchPhotos(withLocalIdentifiers identifiers: [String]) async -> [PhotoMetadata] { [] }
}
