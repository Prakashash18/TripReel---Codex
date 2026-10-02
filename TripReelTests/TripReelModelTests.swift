import AVFoundation
import CoreVideo
import Photos
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import TripReel

@MainActor
final class TripReelModelTests: XCTestCase {
    private var isolatedShelf: URL!

    /// Tests that render films must never write to the app's real "My exports" shelf.
    override func setUp() async throws {
        try await super.setUp()
        isolatedShelf = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-shelf-\(UUID().uuidString)", isDirectory: true)
        LocalCompletedExport.directoryOverride = isolatedShelf
    }

    override func tearDown() async throws {
        LocalCompletedExport.directoryOverride = nil
        try? FileManager.default.removeItem(at: isolatedShelf)
        try await super.tearDown()
    }

    func testResourceCancellationWaitsForTheCurrentFrameAndRunsOnlyOnce() async throws {
        let access = ExportResourceAccess()
        let frameStarted = expectation(description: "Frame is being processed")
        let cancellationRequested = expectation(description: "Cancellation requested on another thread")
        let prematureCancellation = expectation(description: "Must not cancel during a frame")
        prematureCancellation.isInverted = true
        let releaseFrame = DispatchSemaphore(value: 0)
        let framesFinished = Counter()
        let cancellations = Counter()
        let frame = Task.detached {
            try access.perform {
                frameStarted.fulfill()
                releaseFrame.wait()
                framesFinished.next()
            }
        }
        defer { releaseFrame.signal() }
        await fulfillment(of: [frameStarted], timeout: 5)
        let cancellation = Task.detached {
            cancellationRequested.fulfill()
            access.cancel {
                if framesFinished.value == 0 { prematureCancellation.fulfill() }
                cancellations.next()
            }
        }
        await fulfillment(of: [cancellationRequested], timeout: 5)
        await fulfillment(of: [prematureCancellation], timeout: 0.1)
        releaseFrame.signal()
        try await frame.value
        await cancellation.value

        // Deferred cleanup and a late watchdog callback must not tear down twice.
        access.cancel { cancellations.next() }
        XCTAssertEqual(cancellations.value, 1)
        XCTAssertThrowsError(try access.perform { XCTFail("Read or append after cancellation") }) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testConcurrentCancellationWaitsForTeardownBeforeReturning() async {
        let access = ExportResourceAccess()
        let teardownStarted = expectation(description: "AVFoundation teardown started")
        let cleanupRequested = expectation(description: "Deferred cleanup requested")
        let earlyReturn = expectation(description: "Cleanup must wait for teardown")
        earlyReturn.isInverted = true
        let releaseTeardown = DispatchSemaphore(value: 0)
        let finished = Counter()
        let cancellations = Counter()
        let watchdog = Task.detached {
            access.cancel {
                cancellations.next()
                teardownStarted.fulfill()
                releaseTeardown.wait()
                finished.next()
            }
        }
        defer { releaseTeardown.signal() }
        await fulfillment(of: [teardownStarted], timeout: 5)
        let cleanup = Task.detached {
            cleanupRequested.fulfill()
            access.cancel { cancellations.next() }
            if finished.value == 0 { earlyReturn.fulfill() }
        }
        await fulfillment(of: [cleanupRequested], timeout: 5)
        await fulfillment(of: [earlyReturn], timeout: 0.1)
        releaseTeardown.signal()
        await watchdog.value
        await cleanup.value
        XCTAssertEqual(cancellations.value, 1)
    }

    func testExportWatchdogTimerStopsBlockedWork() async throws {
        let aborted = expectation(description: "Independent watchdog queue fires")
        let watchdog = ExportProgressWatchdog(timeout: 0.01)
        defer { watchdog.stop() }
        try watchdog.checkpoint("decoder") { aborted.fulfill() }
        await fulfillment(of: [aborted], timeout: 3)
        XCTAssertThrowsError(try watchdog.check())
    }

    func testExportWatchdogTimesOutWithoutProgress() throws {
        let aborted = expectation(description: "Stops blocked encoder")
        aborted.assertForOverFulfill = true
        let watchdog = ExportProgressWatchdog(startTimer: false)
        defer { watchdog.stop() }
        try watchdog.checkpoint("decoder") { aborted.fulfill() }
        watchdog.checkDeadline(now: .greatestFiniteMagnitude)
        watchdog.checkDeadline(now: .greatestFiniteMagnitude)
        XCTAssertThrowsError(try watchdog.check()) { error in
            guard case TripReelVideoExportError.stalled = error else {
                return XCTFail("Expected a retryable stall, got \(error)")
            }
        }
        wait(for: [aborted], timeout: 1)
    }

    func testExportWatchdogAllowsProgressAndStopsAfterCompletion() throws {
        let watchdog = ExportProgressWatchdog(startTimer: false)
        try watchdog.checkpoint("frame") { XCTFail("Healthy encoder was cancelled") }
        watchdog.checkDeadline()
        XCTAssertNoThrow(try watchdog.check())
        watchdog.stop()
        watchdog.checkDeadline(now: .greatestFiniteMagnitude)
        XCTAssertNoThrow(try watchdog.check())
    }

    func testExportWatchdogCancelsResourcesRegisteredAfterCancellation() {
        let aborted = expectation(description: "Late decoder is stopped")
        let watchdog = ExportProgressWatchdog(startTimer: false)
        defer { watchdog.stop() }
        watchdog.cancel()
        XCTAssertThrowsError(try watchdog.checkpoint("decoder") { aborted.fulfill() }) {
            XCTAssertTrue($0 is CancellationError)
        }
        wait(for: [aborted], timeout: 1)
    }

    /// Exercises actual decoding, transitions, H.264 encoding and finalization.
    /// Unlike the UI demo, this must produce a decodable 2,700-frame 1080p film.
    func testRealExporterNinetySecondMixedStoryAtThirtyFPS() async throws {
        executionTimeAllowance = 300
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("fixture.jpg")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 250, height: 400))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: imageURL)
        func photo(_ id: String) -> ReelPhoto {
            ReelPhoto(id: id, source: .imported(imageURL.path), label: "Fixture", time: "",
                      isSimilar: false, pixelWidth: 600, pixelHeight: 900,
                      frameStyle: .fullBleed, motionStyle: .zoomIn, durationSeconds: 2)
        }
        func request(_ photos: [ReelPhoto]) -> TripReelVideoExportRequest {
            TripReelVideoExportRequest(photos: photos, titleCards: [], textOverlays: [],
                                      secondsPerPhoto: 2, look: .clean, motionIntensity: .gentle,
                                      quality: .hd, soundtrackURL: nil, atmosphereURL: nil)
        }
        let exporter = TripReelVideoExporter(
            checkpoints: RenderCheckpointStore(baseDirectory: directory.appendingPathComponent("checkpoints"))
        )
        let sourceRequest = request([photo("source-1"), photo("source-2")])
        let sourceURL = try await Task.detached {
            try await exporter.export(sourceRequest) { _ in }
        }.value
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        var moments: [ReelPhoto] = []
        for index in 0..<15 {
            moments.append(photo("photo-\(index)"))
            moments.append(ReelPhoto(
                id: "video-\(index)", source: .imported(sourceURL.path), label: "Video fixture", time: "",
                isSimilar: false, pixelWidth: 1080, pixelHeight: 1920,
                frameStyle: .fullBleed, motionStyle: .zoomIn, durationSeconds: 4,
                mediaKind: .video, sourceDurationSeconds: 4
            ))
        }
        let mixedRequest = request(moments)
        let renderingStarted = expectation(description: "Real renderer has produced frames")
        let cancelledExport = Task.detached {
            try await exporter.export(mixedRequest) { progress in
                if abs(progress.fraction - 0.342) < 0.000001 {
                    renderingStarted.fulfill()
                }
            }
        }
        await fulfillment(of: [renderingStarted], timeout: 90)
        cancelledExport.cancel()
        do {
            let unexpectedURL = try await cancelledExport.value
            try? FileManager.default.removeItem(at: unexpectedURL)
            XCTFail("Cancelled renderer unexpectedly completed")
        } catch {
            XCTAssertTrue(error is CancellationError, "Expected cancellation, got \(error)")
        }
        // Retry the identical request with the same exporter after cancellation.
        let started = Date()
        let outputURL: URL
        do {
            outputURL = try await Task.detached {
                try await exporter.export(mixedRequest) { _ in }
            }.value
        } catch {
            XCTFail("Retry failed: \(String(reflecting: error)) / \((error as NSError).domain) \((error as NSError).code) \((error as NSError).userInfo)")
            return
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 90, accuracy: 0.05)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(fps, 30, accuracy: 0.01)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frameCount = 0
        while autoreleasepool(invoking: { output.copyNextSampleBuffer() != nil }) {
            frameCount += 1
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(frameCount, 2700)
        let timing = XCTAttachment(string: "90-second 1080p/30 mixed export plus verification: \(Date().timeIntervalSince(started))s. Simulator timing is not an iPhone 13 benchmark.")
        timing.lifetime = .keepAlways
        add(timing)
    }

    /// Runs the real renderer for both the free (watermarked, 720p) and paid (HD, 1080p) exports.
    func testRealExporterProducesDecodableFreeAndPaidFilms() async throws {
        executionTimeAllowance = 180
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("fixture.jpg")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: imageURL)
        let photos = (0..<3).map { index in
            ReelPhoto(id: "photo-\(index)", source: .imported(imageURL.path), label: "Fixture", time: "",
                      isSimilar: false, pixelWidth: 600, pixelHeight: 900,
                      frameStyle: .fullBleed, motionStyle: .zoomIn, durationSeconds: 2)
        }
        let expectations: [(ExportQuality, CGSize)] = [
            (.standard, CGSize(width: 720, height: 1_280)),
            (.hd, CGSize(width: 1_080, height: 1_920))
        ]
        let exporter = TripReelVideoExporter(
            checkpoints: RenderCheckpointStore(baseDirectory: directory.appendingPathComponent("checkpoints"))
        )
        for (quality, expectedSize) in expectations {
            let request = TripReelVideoExportRequest(
                photos: photos, titleCards: [], textOverlays: [], secondsPerPhoto: 2,
                look: .clean, motionIntensity: .gentle, quality: quality,
                soundtrackURL: nil, atmosphereURL: nil)
            let outputURL = try await Task.detached {
                try await exporter.export(request) { _ in }
            }.value
            defer { try? FileManager.default.removeItem(at: outputURL) }
            let asset = AVURLAsset(url: outputURL)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 6, accuracy: 0.05, "\(quality)")
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let size = try await track.load(.naturalSize)
            XCTAssertEqual(size, expectedSize, "\(quality)")
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
            reader.add(output)
            XCTAssertTrue(reader.startReading())
            var frameCount = 0
            while autoreleasepool(invoking: { output.copyNextSampleBuffer() != nil }) { frameCount += 1 }
            XCTAssertEqual(reader.status, .completed, "\(quality)")
            XCTAssertEqual(frameCount, 180, "\(quality)")
        }
    }

    func testSessionMonitorAbortsAStalledAudioSession() async throws {
        let aborted = expectation(description: "Stalled audio session is cancelled")
        aborted.assertForOverFulfill = true
        let watchdog = ExportProgressWatchdog(startTimer: false)
        defer { watchdog.stop() }
        let monitor = ExportSessionProgressMonitor(
            watchdog: watchdog, stage: "mix soundtrack", interval: 0.02,
            progress: { 0.25 }, abort: { aborted.fulfill() }
        )
        try monitor.start()
        try await Task.sleep(nanoseconds: 120_000_000)
        watchdog.checkDeadline(now: .greatestFiniteMagnitude)
        monitor.stop()
        XCTAssertThrowsError(try watchdog.check()) { error in
            guard case TripReelVideoExportError.stalled = error else {
                return XCTFail("Expected a retryable stall, got \(error)")
            }
        }
        await fulfillment(of: [aborted], timeout: 1)
    }

    func testSessionMonitorKeepsFeedingWatchdogWhileProgressAdvances() async throws {
        let watchdog = ExportProgressWatchdog(timeout: 0.3, startTimer: false)
        defer { watchdog.stop() }
        let ticks = Counter()
        let monitor = ExportSessionProgressMonitor(
            watchdog: watchdog, stage: "mix soundtrack", interval: 0.02,
            progress: { Float(ticks.next()) / 1000 },
            abort: { XCTFail("A slow but advancing export was cancelled") }
        )
        try monitor.start()
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 60_000_000)
            watchdog.checkDeadline()
        }
        monitor.stop()
        XCTAssertNoThrow(try watchdog.check())
    }

    func testRequestGuardFailsARequestThatStopsReportingProgress() async throws {
        let stalled = expectation(description: "Silent PhotoKit request is failed")
        stalled.assertForOverFulfill = true
        let requestGuard = RequestInactivityGuard(timeout: 0.15, tick: 0.03) { stalled.fulfill() }
        defer { requestGuard.stop() }
        await fulfillment(of: [stalled], timeout: 3)
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    func testRequestGuardLeavesAnActiveDownloadAlone() async throws {
        let stalled = expectation(description: "Active download must not be failed")
        stalled.isInverted = true
        let requestGuard = RequestInactivityGuard(timeout: 0.3, tick: 0.03) { stalled.fulfill() }
        defer { requestGuard.stop() }
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 60_000_000)
            requestGuard.touch()
        }
        await fulfillment(of: [stalled], timeout: 0.2)
    }

    /// The reported hang: a two-minute paid (1080p) film with music. Runs the
    /// real renderer, the soundtrack mix and the final mux, then decodes the result.
    func testRealExporterTwoMinuteHDFilmWithSoundtrackAndAtmosphere() async throws {
        executionTimeAllowance = 600
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("fixture.jpg")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            UIColor.white.setFill()
            context.fill(CGRect(x: 150, y: 200, width: 300, height: 400))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: imageURL)
        let photos = (0..<60).map { index in
            ReelPhoto(id: "photo-\(index)", source: .imported(imageURL.path), label: "Fixture", time: "",
                      isSimilar: false, pixelWidth: 600, pixelHeight: 900,
                      frameStyle: .fullBleed, motionStyle: .zoomIn, durationSeconds: 2)
        }
        let soundtrack = try XCTUnwrap(Bundle.main.url(forResource: "wanderlust", withExtension: "m4a"))
        let atmosphere = try XCTUnwrap(
            Bundle.main.url(forResource: "city-day", withExtension: "m4a")
                ?? Bundle.main.url(forResource: "city-day", withExtension: "m4a", subdirectory: "Atmospheres")
        )
        let request = TripReelVideoExportRequest(
            photos: photos, titleCards: [], textOverlays: [], secondsPerPhoto: 2,
            look: .clean, motionIntensity: .gentle, quality: .hd,
            soundtrackURL: soundtrack, atmosphereURL: atmosphere)
        let exporter = TripReelVideoExporter(
            checkpoints: RenderCheckpointStore(baseDirectory: directory.appendingPathComponent("checkpoints"))
        )
        let started = Date()
        let phases = Counter()
        let outputURL = try await Task.detached {
            try await exporter.export(request) { progress in
                if case .addingSoundtrack = progress.phase { _ = phases.next() }
            }
        }.value
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertGreaterThan(phases.value, 0, "The soundtrack stage never ran")

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 120, accuracy: 0.1)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        XCTAssertFalse(audioTracks.isEmpty, "The film has no soundtrack")
        let size = try await videoTrack.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1920))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frameCount = 0
        while autoreleasepool(invoking: { output.copyNextSampleBuffer() != nil }) { frameCount += 1 }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(frameCount, 3600)
        let timing = XCTAttachment(string: "120-second 1080p film with soundtrack and atmosphere, export plus verification: \(Date().timeIntervalSince(started))s. Simulator timing is not an iPhone benchmark.")
        timing.lifetime = .keepAlways
        add(timing)
    }

    func testPrefetchCoordinatorSharesOneRunAndWaitsForItToFinish() async throws {
        let coordinator = MediaPrefetchCoordinator()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prefetch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { coordinator.discard() }
        let runs = Counter()
        let body: @Sendable (@escaping @Sendable (String, PreparedReelMedia) -> Void) async -> Void = { store in
            _ = runs.next()
            for id in ["a", "b", "c"] {
                try? await Task.sleep(nanoseconds: 60_000_000)
                store(id, PreparedReelMedia(stillImageURL: nil, videoAsset: nil))
            }
        }
        coordinator.begin(signature: "a|b|c", expected: 3, directory: directory, run: body)
        // The same photo set must not start a second download run.
        coordinator.begin(signature: "a|b|c", expected: 3, directory: directory, run: body)
        try await coordinator.waitForCompletion(poll: 0.02)
        XCTAssertEqual(runs.value, 1)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.completedCount, 3)
    }

    func testPrefetchCoordinatorStopsWaitingOnAStuckDownloadAndDiscardCleansUp() async throws {
        let coordinator = MediaPrefetchCoordinator()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prefetch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        coordinator.begin(signature: "stuck", expected: 1, directory: directory) { _ in
            try? await Task.sleep(nanoseconds: 60_000_000_000)   // never finishes in time
        }
        let started = Date()
        try await coordinator.waitForCompletion(inactivityTimeout: 0.2, poll: 0.02)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(coordinator.isRunning, "A stuck prefetch must not block the export")
        coordinator.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    /// The point of prefetch: once originals are fetched ahead of time, export
    /// no longer needs the source at all. Deleting the source proves reuse.
    func testExportReusesPrefetchedOriginalsInsteadOfFetchingAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("fixture.jpg")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: imageURL)
        let photos = (0..<6).map { index in
            ReelPhoto(id: "photo-\(index)", source: .imported(imageURL.path), label: "Fixture", time: "",
                      isSimilar: false, pixelWidth: 600, pixelHeight: 900,
                      frameStyle: .fullBleed, motionStyle: .zoomIn, durationSeconds: 2)
        }
        let exporter = TripReelVideoExporter(
            prefetchNetworkPolicy: { true },
            checkpoints: RenderCheckpointStore(baseDirectory: directory.appendingPathComponent("checkpoints"))
        )
        defer { exporter.discardPrefetchedOriginals() }

        exporter.prefetchOriginals(for: photos)
        let deadline = Date().addingTimeInterval(30)
        while exporter.prefetchedItemCount < photos.count, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(exporter.prefetchedItemCount, photos.count)
        let prefetchDirectory = try XCTUnwrap(exporter.prefetchDirectory)

        try FileManager.default.removeItem(at: imageURL)   // the source is gone now

        let request = TripReelVideoExportRequest(
            photos: photos, titleCards: [], textOverlays: [], secondsPerPhoto: 2,
            look: .clean, motionIntensity: .gentle, quality: .hd,
            soundtrackURL: nil, atmosphereURL: nil)
        let outputURL = try await Task.detached { try await exporter.export(request) { _ in } }.value
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 12, accuracy: 0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefetchDirectory.path),
                      "A retry should still find the prefetched originals")

        exporter.discardPrefetchedOriginals()
        XCTAssertFalse(FileManager.default.fileExists(atPath: prefetchDirectory.path))
        XCTAssertEqual(exporter.prefetchedItemCount, 0)
    }

    // MARK: Resumable rendering

    private func makeColoredPhotos(count: Int, in directory: URL) throws -> [ReelPhoto] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return try (0..<count).map { index in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
                UIColor(hue: CGFloat(index) / CGFloat(count), saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
                UIColor.white.setFill()
                context.fill(CGRect(x: 80 + CGFloat(index % 5) * 60, y: 200, width: 160, height: 300))
            }
            let url = directory.appendingPathComponent("photo-\(index).jpg")
            try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: url)
            return ReelPhoto(id: "photo-\(index)", source: .imported(url.path), label: "Fixture", time: "",
                             isSimilar: false, pixelWidth: 600, pixelHeight: 900,
                             frameStyle: .fullBleed, motionStyle: .zoomIn, durationSeconds: 2)
        }
    }

    private func exportRequest(_ photos: [ReelPhoto]) -> TripReelVideoExportRequest {
        TripReelVideoExportRequest(photos: photos, titleCards: [], textOverlays: [], secondsPerPhoto: 2,
                                  look: .clean, motionIntensity: .gentle, quality: .standard,
                                  soundtrackURL: nil, atmosphereURL: nil)
    }

    func testSegmentPlanCoversEveryItemInOrderInRunsOfAboutTenSeconds() {
        let frameCounts = Array(repeating: 60, count: 13)   // thirteen two-second items
        let plan = TripReelVideoExporter.segmentPlan(frameCounts: frameCounts, frameRate: 30)
        XCTAssertEqual(plan, [0..<5, 5..<10, 10..<13])
        XCTAssertEqual(plan.flatMap { Array($0) }, Array(0..<13))
        XCTAssertEqual(TripReelVideoExporter.segmentPlan(frameCounts: [30], frameRate: 30), [0..<1])
        XCTAssertTrue(TripReelVideoExporter.segmentPlan(frameCounts: [], frameRate: 30).isEmpty)
    }

    func testRenderFingerprintChangesOnlyWhenTheFilmChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photos = try makeColoredPhotos(count: 4, in: directory)
        let same = TripReelVideoExporter.renderFingerprint(exportRequest(photos), frameRate: 30)
        XCTAssertEqual(same, TripReelVideoExporter.renderFingerprint(exportRequest(photos), frameRate: 30))
        XCTAssertNotEqual(same, TripReelVideoExporter.renderFingerprint(exportRequest(Array(photos.dropLast())), frameRate: 30))
        XCTAssertNotEqual(same, TripReelVideoExporter.renderFingerprint(exportRequest(photos), frameRate: 24))
        var hd = exportRequest(photos)
        hd = TripReelVideoExportRequest(photos: hd.photos, titleCards: [], textOverlays: [], secondsPerPhoto: 2,
                                       look: .clean, motionIntensity: .gentle, quality: .hd,
                                       soundtrackURL: nil, atmosphereURL: nil)
        XCTAssertNotEqual(same, TripReelVideoExporter.renderFingerprint(hd, frameRate: 30))
    }

    private func meanDifference(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: 48 * 80 * 4)
            let context = CGContext(data: &data, width: 48, height: 80, bitsPerComponent: 8, bytesPerRow: 48 * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 48, height: 80))
            return data
        }
        let a = pixels(lhs), b = pixels(rhs)
        return zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
    }

    /// iOS can end a background render at any time. An interrupted export must resume from the
    /// finished pieces, not start over, and the resumed film must match an uninterrupted one.
    func testInterruptedExportResumesFromFinishedPiecesAndMatchesAnUninterruptedFilm() async throws {
        executionTimeAllowance = 300
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = try makeColoredPhotos(count: 24, in: root)          // 48 s, five pieces
        let request = exportRequest(photos)
        let fingerprint = TripReelVideoExporter.renderFingerprint(request, frameRate: 30)

        // A: render straight through.
        let straight = TripReelVideoExporter(checkpoints: RenderCheckpointStore(baseDirectory: root.appendingPathComponent("cpA")))
        let straightURL = try await Task.detached { try await straight.export(request) { _ in } }.value
        defer { try? FileManager.default.removeItem(at: straightURL) }
        XCTAssertEqual(straight.renderedSegmentCount, 5)

        // B: interrupt once the first piece is saved, then resume with a new exporter.
        let store = RenderCheckpointStore(baseDirectory: root.appendingPathComponent("cpB"))
        let first = TripReelVideoExporter(checkpoints: store)
        let started = Task.detached {
            try await first.export(request) { progress in
                // 0.28 preparation + a quarter of the 0.62 render share
                if progress.fraction >= 0.45 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        _ = try? await started.value
        let saved = store.manifest(for: fingerprint).segments.count
        XCTAssertGreaterThanOrEqual(saved, 1, "No finished piece was kept")
        XCTAssertLessThan(saved, 5, "The interruption came too late to test a resume")

        let second = TripReelVideoExporter(checkpoints: store)
        let resumedURL = try await Task.detached { try await second.export(request) { _ in } }.value
        defer { try? FileManager.default.removeItem(at: resumedURL) }
        XCTAssertEqual(second.renderedSegmentCount, 5 - saved, "Resume re-rendered pieces that were already finished")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: fingerprint).path),
                       "A finished film must clear its saved pieces")

        // Both films are complete and look the same, including across the joins.
        for url in [straightURL, resumedURL] {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 48, accuracy: 0.05)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let rate = try await track.load(.nominalFrameRate)
            XCTAssertEqual(rate, 30, accuracy: 0.01)
        }
        let generatorA = AVAssetImageGenerator(asset: AVURLAsset(url: straightURL))
        let generatorB = AVAssetImageGenerator(asset: AVURLAsset(url: resumedURL))
        for generator in [generatorA, generatorB] {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.appliesPreferredTrackTransform = true
        }
        // Zero-tolerance reads must request actual 30 fps frame timestamps,
        // including the frames immediately before and after a segment join.
        // Await decoding so a loaded simulator does not block the main actor.
        for frame: Int64 in [297, 300, 303, 599, 601, 900, 1200] {
            let time = CMTime(value: frame, timescale: 30)
            let a = try await generatorA.image(at: time)
            let b = try await generatorB.image(at: time)
            XCTAssertEqual(a.actualTime.seconds, time.seconds, accuracy: 0.001)
            XCTAssertEqual(b.actualTime.seconds, time.seconds, accuracy: 0.001)
            XCTAssertLessThan(meanDifference(a.image, b.image), 4.0,
                              "Resumed film differs from the uninterrupted one at frame \(frame)")
        }
    }

    private func makeModel() -> TripReelModel {
        TripReelModel(arguments: [], useDemoData: true)
    }

    func testAIDirectorAllowsEnoughTimeForUploadAndServerAnalysis() {
        XCTAssertEqual(CloudPhotoAnalysisClient.requestTimeout, 75)
        XCTAssertEqual(CloudPhotoAnalysisClient.resourceTimeout, 90)
        XCTAssertGreaterThan(
            CloudPhotoAnalysisClient.resourceTimeout,
            CloudPhotoAnalysisClient.requestTimeout
        )
    }

    func testMonthlyExportReminderUsesFirstDayOfNextMonthAtNine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 22))
        )
        let reset = try XCTUnwrap(
            MonthlyExportResetNotificationScheduler.nextResetDate(
                after: now,
                calendar: calendar
            )
        )

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reset),
            DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 0)
        )
    }

    func testUnsavedMemorySchedulesReminderOneDayBeforeExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let memoryID = UUID(uuidString: "A1111111-1111-1111-1111-111111111111")!
        let expiry = now.addingTimeInterval(7 * 24 * 60 * 60)
        let memory = SharedMemory(
            id: memoryID,
            title: "A day together",
            durationSeconds: 42,
            exportTier: "story_pass",
            shareToken: UUID(),
            createdAt: now,
            expiresAt: expiry,
            savedToPhoneAt: nil
        )

        let reminder = try XCTUnwrap(
            MemoryExpiryNotificationScheduler.reminders(for: [memory], now: now).first
        )

        XCTAssertEqual(reminder.memoryID, memoryID)
        XCTAssertEqual(reminder.title, "A day together")
        XCTAssertEqual(reminder.fireDate, expiry.addingTimeInterval(-24 * 60 * 60))
        XCTAssertEqual(reminder.identifier, "memory-expiry.a1111111-1111-1111-1111-111111111111")
    }

    func testExpiryReminderSkipsSavedExpiredAndAlreadyDueMemories() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func memory(expiresAt: Date, savedAt: Date? = nil) -> SharedMemory {
            SharedMemory(
                id: UUID(),
                title: "Private memory",
                durationSeconds: 20,
                exportTier: "free",
                shareToken: UUID(),
                createdAt: now.addingTimeInterval(-60),
                expiresAt: expiresAt,
                savedToPhoneAt: savedAt
            )
        }

        let reminders = MemoryExpiryNotificationScheduler.reminders(
            for: [
                memory(expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60), savedAt: now),
                memory(expiresAt: now.addingTimeInterval(-60)),
                memory(expiresAt: now.addingTimeInterval(12 * 60 * 60))
            ],
            now: now
        )

        XCTAssertTrue(reminders.isEmpty)
    }

    // MARK: My exports (finished films kept on the phone)

    private func withTemporaryShelf(_ body: () throws -> Void) throws {
        let previous = LocalCompletedExport.directoryOverride
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-test-\(UUID().uuidString)", isDirectory: true)
        LocalCompletedExport.directoryOverride = directory
        defer {
            LocalCompletedExport.directoryOverride = previous
            try? FileManager.default.removeItem(at: directory)
        }
        try body()
    }

    private func renderedFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rendered-\(UUID().uuidString).mp4")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }

    func testAFullFilmStaysForSevenDaysAndAPreviewForOneDay() throws {
        try withTemporaryShelf {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let full = try LocalCompletedExport.keep(try renderedFile(), title: "Full", durationSeconds: 89, isHD: true, now: start)
            let preview = try LocalCompletedExport.keep(try renderedFile(), title: "Preview", durationSeconds: 9, isHD: false, now: start)
            XCTAssertEqual(LocalCompletedExport.all(now: start).count, 2)

            let sixDays = start.addingTimeInterval(6 * 24 * 3600)
            XCTAssertEqual(LocalCompletedExport.all(now: sixDays).map(\.title), ["Full"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: preview.fileURL.path), "An expired film's file must be deleted")
            XCTAssertTrue(FileManager.default.fileExists(atPath: full.fileURL.path))

            let eightDays = start.addingTimeInterval(8 * 24 * 3600)
            XCTAssertTrue(LocalCompletedExport.all(now: eightDays).isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: full.fileURL.path))
        }
    }

    func testTheShelfKeepsOnlyTheNewestFiveFilms() throws {
        try withTemporaryShelf {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            var saved: [LocalCompletedExport] = []
            for index in 0..<7 {
                saved.append(try LocalCompletedExport.keep(
                    try renderedFile(), title: "Film \(index)", durationSeconds: 60, isHD: true,
                    now: start.addingTimeInterval(Double(index) * 60)
                ))
            }
            let shelf = LocalCompletedExport.all(now: start.addingTimeInterval(600))
            XCTAssertEqual(shelf.map(\.title), ["Film 6", "Film 5", "Film 4", "Film 3", "Film 2"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: saved[0].fileURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: saved[1].fileURL.path))
        }
    }

    func testAFilmThatFinishedWhileAwayOpensOnceAndCanBeDeleted() throws {
        try withTemporaryShelf {
            let film = try LocalCompletedExport.keep(try renderedFile(), title: "A day together", durationSeconds: 42, isHD: true)
            XCTAssertEqual(LocalCompletedExport.latestUnseen()?.id, film.id)
            LocalCompletedExport.markSeen(film.id)
            XCTAssertNil(LocalCompletedExport.latestUnseen(), "A film already shown must not reopen on every launch")
            XCTAssertEqual(LocalCompletedExport.all().count, 1, "Seen films stay on the shelf")

            LocalCompletedExport.remove(film.id)
            XCTAssertTrue(LocalCompletedExport.all().isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: film.fileURL.path))
        }
    }

    func testTheOldSingleReceiptMovesOntoTheShelf() throws {
        try withTemporaryShelf {
            let directory = LocalCompletedExport.directory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = "memory-legacy.mp4"
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent(fileName))
            let legacy = """
            {"fileName":"\(fileName)","title":"Old film","durationSeconds":30,"isHD":true,"completedAt":\(Date().timeIntervalSinceReferenceDate)}
            """
            try Data(legacy.utf8).write(to: directory.appendingPathComponent("completed-export.json"))

            let shelf = LocalCompletedExport.all()
            XCTAssertEqual(shelf.map(\.title), ["Old film"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("completed-export.json").path))
            XCTAssertEqual(LocalCompletedExport.all().count, 1, "The migration must run only once")
        }
    }

    func testRemainingTimeIsDescribedInDaysThenHours() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let item = LocalCompletedExport(id: "x", fileName: "x.mp4", title: "T", durationSeconds: 10, isHD: true, completedAt: start, seen: true)
        XCTAssertEqual(item.remainingDescription(now: start), "7 days left")
        XCTAssertEqual(item.remainingDescription(now: start.addingTimeInterval(6 * 24 * 3600)), "1 day left")
        XCTAssertEqual(item.remainingDescription(now: start.addingTimeInterval(6.5 * 24 * 3600)), "12 hours left")
        XCTAssertEqual(item.remainingDescription(now: start.addingTimeInterval(7 * 24 * 3600 - 5 * 3600)), "5 hours left")
        XCTAssertEqual(item.remainingDescription(now: start.addingTimeInterval(8 * 24 * 3600)), "1 hour left")
    }

    func testShareItemSourceHandsOffAFileURLAsAnExplicitMP4Movie() {
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-provider-test.mp4")
        let source = MP4ShareItemSource(
            videoURL: videoURL,
            title: "A memory"
        )
        let controller = UIActivityViewController(
            activityItems: [videoURL],
            applicationActivities: nil
        )

        XCTAssertEqual(
            source.activityViewControllerPlaceholderItem(controller) as? URL,
            videoURL
        )
        XCTAssertEqual(
            source.activityViewController(controller, itemForActivityType: nil) as? URL,
            videoURL
        )
        XCTAssertEqual(
            source.activityViewController(controller, dataTypeIdentifierForActivityType: nil),
            UTType.mpeg4Movie.identifier
        )
    }

    func testAIDirectorSetupAdvancesAndBacktracksOneDecisionAtATime() {
        let model = makeModel()
        model.go(.firstCutOptions)
        model.openAICutDirections()
        model.go(.aiDirection)

        XCTAssertEqual(model.aiCutSetupStep, .moments)
        XCTAssertGreaterThan(model.aiCutSelectedPhotoCount, 0)

        model.advanceAICutSetup()
        XCTAssertEqual(model.aiCutSetupStep, .direction)
        XCTAssertEqual(model.screen, .aiDirection)

        model.navigateBack()
        XCTAssertEqual(model.aiCutSetupStep, .moments)
        XCTAssertEqual(model.screen, .aiDirection)

        model.navigateBack()
        XCTAssertEqual(model.screen, .firstCutOptions)
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

    func testDirectVideoFrameDrawingKeepsUIKitArtworkUpright() throws {
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

        try TripReelVideoExporter.drawDirectly(
            into: buffer,
            outputSize: CGSize(width: 2, height: 2)
        ) { bounds in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: bounds.width, height: 1))
            UIColor.blue.setFill()
            UIRectFill(CGRect(x: 0, y: 1, width: bounds.width, height: 1))
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
            .assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: baseAddress, count: 4)), [0, 0, 255, 255])
        XCTAssertEqual(
            Array(UnsafeBufferPointer(start: baseAddress + bytesPerRow, count: 4)),
            [255, 0, 0, 255]
        )
    }

    func testExportMotionUsesSmoothBoundedProgress() {
        XCTAssertEqual(TripReelVideoExporter.defaultFrameRate, 30)
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

    func testSequentialVideoGeometryKeepsRotatedClipsUprightAndInsideBounds() {
        let sourceSize = CGSize(width: 1920, height: 1080)
        let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        let geometry = TripReelVideoExporter.sourceVideoGeometry(
            naturalSize: sourceSize,
            preferredTransform: rotation,
            maximumSize: CGSize(width: 1080, height: 1920)
        )
        let displayedBounds = CGRect(origin: .zero, size: sourceSize)
            .applying(geometry.transform)

        XCTAssertEqual(geometry.renderSize.width, 1080, accuracy: 0.001)
        XCTAssertEqual(geometry.renderSize.height, 1920, accuracy: 0.001)
        XCTAssertEqual(displayedBounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(displayedBounds.minY, 0, accuracy: 0.001)
        XCTAssertEqual(displayedBounds.width, geometry.renderSize.width, accuracy: 0.001)
        XCTAssertEqual(displayedBounds.height, geometry.renderSize.height, accuracy: 0.001)
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

    func testStoryPassIsRaisedOverFirstWatchAndBackDismissesItFirst() {
        let model = makeModel()

        model.go(.firstWatch)
        XCTAssertFalse(model.isStoryPassPresented)

        model.openStoryPass()
        XCTAssertTrue(model.isStoryPassPresented)
        // The film is never replaced by a purchase screen.
        XCTAssertEqual(model.screen, .firstWatch)
        XCTAssertTrue(model.canNavigateBack)

        model.navigateBack()
        XCTAssertFalse(model.isStoryPassPresented)
        XCTAssertEqual(model.screen, .firstWatch)

        model.navigateBack()
        XCTAssertEqual(model.screen, .trips)
    }

    func testKeepingTheFilmAtFirstWatchRendersTheFullStoryWithNoExportScreen() async throws {
        let exporter = RecordingVideoExporter()
        let model = makeFirstWatchModel(exporter: exporter)
        let freeMomentCount = model.freeExportMomentCount
        model.openStoryPass()

        model.exportFirstCutFullStory()

        XCTAssertFalse(model.isStoryPassPresented)
        XCTAssertNotEqual(model.screen, .paywall)
        XCTAssertNotEqual(model.screen, .export)
        await waitForDone(model)

        XCTAssertEqual(model.screen, .done)
        XCTAssertEqual(model.exportQuality, .hd)
        XCTAssertFalse(model.exportQuality.includesWatermark)
        let recordedRequest = await exporter.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.quality, .hd)
        XCTAssertGreaterThan(request.photos.count, freeMomentCount)
    }

    func testDecliningTheStoryPassStillRendersTheFreeTrailer() async throws {
        let exporter = RecordingVideoExporter()
        let model = makeFirstWatchModel(exporter: exporter)
        model.openStoryPass()

        model.exportFirstCutFreeTrailer()

        XCTAssertFalse(model.isStoryPassPresented)
        XCTAssertNotEqual(model.screen, .paywall)
        await waitForDone(model)

        XCTAssertEqual(model.screen, .done)
        XCTAssertEqual(model.exportQuality, .standard)
        XCTAssertTrue(model.exportQuality.includesWatermark)
        let recordedRequest = await exporter.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.quality, .standard)
    }

    /// Yielding a fixed number of times is not a wait: the render finishes on
    /// its own schedule, and a loaded CI machine will still be on `.rendering`
    /// after any number of yields. This waits on the clock instead.
    private func waitForDone(_ model: TripReelModel, timeout: TimeInterval = 20) async {
        let deadline = Date().addingTimeInterval(timeout)
        while model.screen != .done, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// A built memory parked on First Watch, long enough that the free trailer
    /// genuinely has to leave moments out.
    private func makeFirstWatchModel(exporter: RecordingVideoExporter) -> TripReelModel {
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            videoExporter: exporter
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let assets = (0..<36).map { index in
            TripAsset(
                id: "first-watch-\(index)",
                source: .bundled("my-khe-beach"),
                creationDate: date.addingTimeInterval(Double(index) * 60),
                filename: "IMG_\(index).JPG",
                pixelWidth: 1_024,
                pixelHeight: 1_536
            )
        }
        model.startBuild(trip: Trip(
            id: "first-watch-trip",
            place: "Da Nang",
            dates: "Today",
            startDate: date,
            endDate: date.addingTimeInterval(35 * 60),
            assets: assets,
            coverID: assets[18].id
        ))
        model.go(.firstWatch)
        return model
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
            "Chiang Mai"
        )
        XCTAssertEqual(
            LocalStoryIntelligence.collectionTitle(
                for: nearby,
                isNearby: true,
                calendar: calendar
            ),
            "Gardens by the Bay"
        )
        XCTAssertEqual(
            LocalStoryIntelligence.locationContext(for: trip),
            "Mueang Chiang Mai District, Thailand"
        )

        let undeterminedPlace = Trip(
            id: "undetermined",
            place: "Photo memory",
            dates: "14–16 May 2026",
            startDate: start,
            endDate: start.addingTimeInterval(2 * 24 * 60 * 60),
            assets: tripAssets,
            coverID: tripAssets[0].id
        )
        XCTAssertEqual(
            LocalStoryIntelligence.collectionTitle(
                for: undeterminedPlace,
                isNearby: false,
                calendar: calendar
            ),
            "14–16 May 2026"
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

    func testMemoryAtmospheresHaveBundledAudioAndAuditableSources() {
        XCTAssertEqual(MemoryAtmosphereCatalog.all.count, 8)
        XCTAssertTrue(MemoryAtmosphereCatalog.all.allSatisfy { atmosphere in
            atmosphere.bundledURL != nil
                && atmosphere.sourcePageURL.hasPrefix("https://mixkit.co/")
                && atmosphere.sourceAssetURL.hasPrefix("https://assets.mixkit.co/")
        })
        XCTAssertTrue(MemoryAtmosphereCatalog.licenseURL.hasPrefix("https://mixkit.co/"))
    }

    func testMemoryAtmosphereUsesMemoryLocationForCoast() {
        let result = MemoryAtmosphereCatalog.recommended(
            place: "My Khe Beach, Da Nang",
            insights: [],
            captureDates: []
        )

        XCTAssertEqual(result.id, "coast")
    }

    func testMemoryAtmosphereUsesOnDeviceImageryWhenPlaceIsGeneric() {
        let insight = MontagePhotoInsight(
            contentKind: .scenery,
            classifications: [
                NativePhotoClassification(identifier: "airport terminal", confidence: 0.91)
            ]
        )
        let result = MemoryAtmosphereCatalog.recommended(
            place: "Selected moments",
            insights: [insight],
            captureDates: []
        )

        XCTAssertEqual(result.id, "airport")
    }

    func testMemoryAtmosphereUsesCaptureTimeForUrbanNight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 21))
        )
        let insight = MontagePhotoInsight(
            classifications: [
                NativePhotoClassification(identifier: "urban street", confidence: 0.8)
            ]
        )
        let result = MemoryAtmosphereCatalog.recommended(
            place: "Singapore",
            insights: [insight],
            captureDates: [date],
            calendar: calendar
        )

        XCTAssertEqual(result.id, "city-night")
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

    func testFilmStudioCanRemoveAndRestoreAMomentWithoutDeletingItsSource() throws {
        let model = makeModel()
        let photo = try XCTUnwrap(model.keptPhotos.first)
        let originalCount = model.photos.count

        XCTAssertTrue(model.removeMomentFromFilm(id: photo.id))
        XCTAssertFalse(model.keptPhotos.contains(where: { $0.id == photo.id }))
        XCTAssertTrue(model.cutPhotoIDs.contains(photo.id))
        XCTAssertEqual(model.photos.count, originalCount)

        XCTAssertTrue(model.restoreMomentToFilm(id: photo.id))
        XCTAssertTrue(model.keptPhotos.contains(where: { $0.id == photo.id }))
        XCTAssertFalse(model.cutPhotoIDs.contains(photo.id))
        XCTAssertEqual(model.photos.count, originalCount)
    }

    func testFilmStudioWillNotRemoveTheFinalMoment() throws {
        let model = makeModel()
        let finalMoment = try XCTUnwrap(model.photos.first)
        model.cutPhotoIDs = Set(model.photos.dropFirst().map(\.id))

        XCTAssertEqual(model.keptCount, 1)
        XCTAssertFalse(model.removeMomentFromFilm(id: finalMoment.id))
        XCTAssertEqual(model.keptPhotos.map(\.id), [finalMoment.id])
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
        model.startRender(hd: true)

        await waitForDone(model)

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
        XCTAssertEqual(model.freeExportMomentCount, 5)
        XCTAssertLessThan(model.freeExportMomentCount, model.keptCount)
        XCTAssertEqual(model.fullStoryExclusiveMomentCount, 31)
        XCTAssertFalse(model.fullStoryHighlightPhotos.isEmpty)

        model.requestExport(.standard, isUnlocked: false)
        await waitForDone(model)

        XCTAssertEqual(model.screen, .done)
        let recordedRequest = await exporter.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.quality, .standard)
        XCTAssertEqual(request.photos.first?.id, expectedFirstID)
        XCTAssertEqual(request.photos.count, 5)
        XCTAssertNotEqual(request.photos.map(\.id), Array(model.keptPhotos.prefix(5)).map(\.id))
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

    func testDecliningStoryPassImmediatelyExportsTheFreeVersion() async throws {
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

        model.requestExport(.highDefinition, isUnlocked: false)
        XCTAssertEqual(model.screen, .paywall)

        model.exportFreeVersionInsteadOfUpgrading()
        await waitForDone(model)

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
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(model.screen, .export)
        XCTAssertEqual(model.exportErrorTitle, "A moment needs a little longer")
        XCTAssertTrue(model.exportCanRetryPhotoDownload)
        XCTAssertTrue(model.exportErrorMessage?.contains("kept every edit safe") == true)

        model.retryExportPhotoDownload()
        await waitForDone(model)

        XCTAssertEqual(model.screen, .done)
        let qualities = await exporter.recordedQualities()
        XCTAssertEqual(qualities, [.hd, .hd])
    }

    func testFramePressureOffersOneTapRetryWithoutLosingHD() async throws {
        try await assertRetryableExportFailure(.cannotCreateFrame)
    }

    func testExportStallOffersOneTapRetryWithoutLosingHD() async throws {
        try await assertRetryableExportFailure(.stalled)
    }

    private func assertRetryableExportFailure(_ firstError: TripReelVideoExportError) async throws {
        let exporter = FailOnceVideoExporter(firstError: firstError)
        let model = TripReelModel(
            arguments: [],
            useDemoData: false,
            videoExporter: exporter
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let asset = TripAsset(
            id: "frame-pressure-video",
            source: .bundled("my-khe-beach"),
            creationDate: date,
            filename: "VIDEO_0007.MOV",
            pixelWidth: 1_024,
            pixelHeight: 1_536
        )
        model.startBuild(trip: Trip(
            id: "frame-pressure-trip",
            place: "Test trip",
            dates: "Today",
            startDate: date,
            endDate: date,
            assets: [asset],
            coverID: asset.id
        ))
        model.startRender(hd: true)

        for _ in 0..<100 where model.exportErrorMessage == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(model.screen, .export)
        XCTAssertEqual(model.exportErrorTitle, "Export paused")
        XCTAssertTrue(model.exportCanRetryRender)
        XCTAssertFalse(model.exportCanRetryPhotoDownload)

        model.retryExportAfterFrameFailure()
        await waitForDone(model)

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

    func testMemoryPreviewSelectsStrongMomentsAcrossTheWholeStory() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let photos = (0..<12).map {
            makeReelPhoto(from: makeAsset("trailer-\($0)", start: start, minutes: $0))
        }
        let strongIndices = [1, 5, 9]
        let insights = Dictionary(uniqueKeysWithValues: photos.enumerated().map { index, photo in
            (
                photo.id,
                MontagePhotoInsight(
                    memoryScore: strongIndices.contains(index) ? 0.98 : 0.12,
                    aestheticScore: strongIndices.contains(index) ? 0.94 : 0.18,
                    contentKind: strongIndices.contains(index) ? .people : .moment,
                    peopleCount: strongIndices.contains(index) ? 3 : 0
                )
            )
        })

        let preview = FreeExportStoryPlanner.previewPhotos(
            from: photos,
            titleCards: [],
            textOverlays: [],
            insights: insights,
            preferredEndPhotoID: nil
        )

        XCTAssertEqual(preview.map(\.id), strongIndices.map { photos[$0].id })
        XCTAssertEqual(preview.count, 3)
        XCTAssertLessThan(preview.last?.durationSeconds ?? 99, 2)
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripReel-test-\(UUID().uuidString).mp4")
        try Data([0, 1, 2, 3]).write(to: url, options: .atomic)
        return url
    }

    func saveToPhotoLibrary(_ url: URL) async throws {
        savedURL = url
    }
}

private actor FailOnceVideoExporter: TripReelVideoExporting {
    private var qualities: [ExportQuality] = []
    private let firstError: TripReelVideoExportError

    init(firstError: TripReelVideoExportError = .photoUnavailable("PHOTO_0006")) {
        self.firstError = firstError
    }

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
            throw firstError
        }
        progress(
            TripReelVideoExportProgress(
                fraction: 1,
                phase: .finalizing
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripReel-retry-test-\(UUID().uuidString).mp4")
        try Data([0, 1, 2, 3]).write(to: url, options: .atomic)
        return url
    }

    func saveToPhotoLibrary(_ url: URL) async throws {}

    func recordedQualities() -> [ExportQuality] { qualities }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    @discardableResult func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}
