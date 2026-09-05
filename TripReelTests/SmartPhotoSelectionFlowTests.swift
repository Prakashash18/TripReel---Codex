import CoreGraphics
import Photos
import XCTest
@testable import TripReel

@MainActor
final class SmartPhotoSelectionFlowTests: XCTestCase {
    func testBuildPausesForConsentAndOnDeviceChoiceNeverCallsCloud() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy(results: [])
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )
        let trip = makeTrip(count: 2)

        model.requestBuild(trip: trip)

        XCTAssertTrue(model.isCloudAnalysisConsentPresented)
        let callsBeforeChoice = await cloud.observedCallCount()
        XCTAssertEqual(callsBeforeChoice, 0)

        model.keepAnalysisOnDevice()
        try await waitUntil { model.screen == .building }

        XCTAssertEqual(model.cloudAnalysisPreference, .onDeviceOnly)
        let callsAfterChoice = await cloud.observedCallCount()
        XCTAssertEqual(callsAfterChoice, 0)
        XCTAssertEqual(model.photos.count, 2)
        model.go(.trips)
    }

    func testExplicitCloudChoiceReviewsOnlyAfterConsentAndLeavesExcludedPhotoRecoverable() async throws {
        let preferences = makePreferences()
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let result = CloudPhotoAnalysisResult(
            id: "p0",
            scenic: 0.02,
            people: 0,
            group: 0,
            food: 0,
            document: 0.99,
            screenshot: 0,
            lowQuality: 0.1,
            confidence: 0.98,
            action: .discard,
            reason: "Order confirmation screen"
        )
        let cloud = CloudAnalysisSpy(results: [result])
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: cloud,
            photoAnalysisThumbnails: ThumbnailStub(),
            nativePhotoIntelligence: NativeIntelligenceStub(),
            preferenceStore: preferences
        )
        let trip = makeTrip(count: 2)

        model.requestBuild(trip: trip)
        let callsBeforeChoice = await cloud.observedCallCount()
        XCTAssertEqual(callsBeforeChoice, 0)
        model.useCloudEnhancement()
        try await waitUntil { model.screen == .building }

        let callsAfterChoice = await cloud.observedCallCount()
        XCTAssertEqual(callsAfterChoice, 1)
        XCTAssertEqual(model.cloudAnalysisPreference, .enabled)
        XCTAssertEqual(model.excludedPhotos.map(\.id), ["asset-0"])
        XCTAssertEqual(model.photos.map(\.id), ["asset-1"])

        model.includeExcludedPhoto(id: "asset-0")

        XCTAssertTrue(model.excludedPhotos.isEmpty)
        XCTAssertEqual(model.photos.map(\.id), ["asset-0", "asset-1"])
        model.go(.trips)
    }

    func testMetadataScreenshotIsExcludedWithoutPreparingOrUploadingIt() async throws {
        let preferences = makePreferences()
        preferences.set("enabled", forKey: "tripreel.cloud-photo-analysis-preference.v1")
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let cloud = CloudAnalysisSpy(results: [])
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
        XCTAssertEqual(cloudCalls, 1)
        model.go(.trips)
    }

    func testAuthorizationLossCancelsAnalysisAndClearsPendingFilm() async throws {
        let preferences = makePreferences()
        preferences.set("onDeviceOnly", forKey: "tripreel.cloud-photo-analysis-preference.v1")
        defer { preferences.removePersistentDomain(forName: preferencesSuiteName) }
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            photoLibrary: StubPhotoLibraryForSelection(),
            cloudPhotoAnalysis: CloudAnalysisSpy(results: []),
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
    nonisolated let isConfigured = true
    private(set) var callCount = 0
    let results: [CloudPhotoAnalysisResult]

    init(results: [CloudPhotoAnalysisResult]) {
        self.results = results
    }

    func analyze(_ photos: [CloudPhotoAnalysisInput]) async throws -> [CloudPhotoAnalysisResult] {
        callCount += 1
        let requested = Set(photos.map(\.id))
        return results.filter { requested.contains($0.id) }
    }

    func observedCallCount() -> Int { callCount }
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

private actor NativeIntelligenceStub: NativePhotoIntelligenceServing {
    func analyze(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        metadata: NativePhotoIntelligenceMetadata
    ) async throws -> NativePhotoIntelligenceResult {
        let signals = NativePhotoIntelligenceSignals(
            availability: NativePhotoSignalAvailability(
                classification: false,
                textRecognition: false,
                faceQuality: false,
                documentDetection: false,
                featurePrint: false,
                aesthetics: false
            )
        )
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
