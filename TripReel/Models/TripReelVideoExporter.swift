import AVFoundation
import CoreGraphics
import CryptoKit
import CoreVideo
import ImageIO
import OSLog
import Network
import Photos
import QuartzCore
import UIKit
import UniformTypeIdentifiers
import VideoToolbox

struct TripReelVideoExportRequest: Sendable {
    let photos: [ReelPhoto]
    let titleCards: [MontageTitleCard]
    let textOverlays: [MontageTextOverlay]
    let secondsPerPhoto: Double
    let look: MontageLook
    let motionIntensity: MontageMotionIntensity
    let quality: ExportQuality
    let soundtrackURL: URL?
    let atmosphereURL: URL?
}

enum TripReelVideoExportPhase: Equatable, Sendable {
    case preparingPhotos(
        ready: Int,
        total: Int,
        currentLabel: String?,
        downloadProgress: Double?
    )
    case rendering
    case addingSoundtrack
    case finalizing
}

struct TripReelVideoExportProgress: Equatable, Sendable {
    let fraction: Double
    let phase: TripReelVideoExportPhase

    init(fraction: Double, phase: TripReelVideoExportPhase) {
        self.fraction = min(1, max(0, fraction))
        self.phase = phase
    }
}

protocol TripReelVideoExporting: Sendable {
    func export(
        _ request: TripReelVideoExportRequest,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws -> URL
    func finishGeneratedClip(_ url: URL, title: String) async throws -> URL
    func saveToPhotoLibrary(_ url: URL) async throws
    /// Starts fetching full-quality originals for a likely HD export while the
    /// user is still watching or deciding. Safe to call repeatedly.
    func prefetchOriginals(for photos: [ReelPhoto])
    /// Cancels any prefetch and deletes what it downloaded.
    func discardPrefetchedOriginals()
    /// Deletes the saved pieces of an interrupted render. Called when the person
    /// cancels on purpose; an interruption keeps them so the export can resume.
    func discardRenderCheckpoints()
}

extension TripReelVideoExporting {
    func finishGeneratedClip(_ url: URL, title: String) async throws -> URL { url }
    func prefetchOriginals(for photos: [ReelPhoto]) {}
    func discardPrefetchedOriginals() {}
    func discardRenderCheckpoints() {}
}

enum TripReelVideoExportError: LocalizedError, Sendable {
    case noPhotos
    case photoUnavailable(String)
    case cannotCreateWriter
    case cannotCreateFrame
    case stalled
    case encodingFailed(String)
    case soundtrackFailed
    case generatedClipFinishingFailed
    case photosPermissionDenied
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPhotos:
            "Keep at least one photo or video before exporting."
        case let .photoUnavailable(label):
            "\(label) needs a little longer in Photos. Memories tried again automatically and kept every edit safe. Check your connection, then retry the download."
        case .cannotCreateWriter:
            "Memories couldn't start the video encoder on this device."
        case .cannotCreateFrame:
            "Memories ran out of room while drawing a video frame."
        case .stalled:
            "Export stopped making progress. Your originals and edits are safe. Keep Memories open and try exporting again."
        case let .encodingFailed(message):
            "The video encoder stopped: \(message)"
        case .soundtrackFailed:
            "The film was rendered, but the selected soundtrack couldn't be added. Pick another track or No music and try again."
        case .generatedClipFinishingFailed:
            "The AI motion was created, but Memories couldn't add the title. Please try again."
        case .photosPermissionDenied:
            "Allow Memories to add videos in Settings to save this film to Photos."
        case let .saveFailed(message):
            "Photos couldn't save this film: \(message)"
        }
    }
}

/// A separate queue requests AVFoundation cancellation without blocking the UI.
/// Resource access serializes teardown with in-flight reads and frame appends.
/// The deadline measures inactivity, not film length.
final class ExportProgressWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private let timeout: TimeInterval
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var interruption: TripReelVideoExportError?
    private var cancelled = false
    private var abort: (@Sendable () -> Void)?
    private var stage = "starting"
    private var timer: DispatchSourceTimer?
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Memories", category: "VideoExport")

    init(timeout: TimeInterval = 45, startTimer: Bool = true) {
        self.timeout = timeout
        if startTimer {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "memories.export-watchdog"))
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.checkDeadline() }
            self.timer = timer
            timer.resume()
        }
    }

    deinit { timer?.cancel() }

    func checkpoint(_ stage: String, abort: @escaping @Sendable () -> Void) throws {
        lock.lock()
        let shouldAbort = cancelled || interruption != nil
        if !shouldAbort {
            self.stage = stage
            self.abort = abort
            lastProgress = ProcessInfo.processInfo.systemUptime
        }
        lock.unlock()
        if shouldAbort { abort() }
        try check()
    }

    func check() throws {
        lock.lock()
        let error = interruption
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if let error { throw error }
        try Task.checkCancellation()
    }

    func checkDeadline(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        guard !cancelled, interruption == nil, let abort, now - lastProgress >= timeout else {
            lock.unlock()
            return
        }
        interruption = .stalled
        let stalledStage = stage
        lock.unlock()
        Self.logger.error("Export stalled: \(stalledStage, privacy: .public)")
        abort()
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let abort = abort
        lock.unlock()
        // Task cancellation can be requested from the UI. Never make that
        // thread wait for AVFoundation to tear down a decoder or encoder.
        if let abort { DispatchQueue.global(qos: .userInitiated).async(execute: abort) }
    }

    func stop() {
        timer?.cancel()
        lock.lock()
        abort = nil
        lock.unlock()
    }
}

/// Lets the monitor and cancellation handler touch a session from other
/// threads. `progress` and `cancelExport()` are documented as thread-safe.
private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    var progress: Float { session.progress }
    func cancel() { session.cancelExport() }
}

/// `AVAssetExportSession` has no built-in stall detection. This polls its
/// progress and tells the watchdog every time it moves, so a silent hang in the
/// soundtrack mix or the final mux times out like the render does, while a slow
/// but advancing export never does.
final class ExportSessionProgressMonitor: @unchecked Sendable {
    private let watchdog: ExportProgressWatchdog
    private let stage: String
    private let interval: UInt64
    private let progress: @Sendable () -> Float
    private let abort: @Sendable () -> Void
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(
        watchdog: ExportProgressWatchdog,
        stage: String,
        interval: TimeInterval = 0.5,
        progress: @escaping @Sendable () -> Float,
        abort: @escaping @Sendable () -> Void
    ) {
        self.watchdog = watchdog
        self.stage = stage
        self.interval = UInt64(max(0.01, interval) * 1_000_000_000)
        self.progress = progress
        self.abort = abort
    }

    func start() throws {
        try watchdog.checkpoint(stage, abort: abort)
        let watchdog = watchdog, stage = stage, progress = progress, abort = abort, interval = interval
        let task = Task.detached {
            var last = progress()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                let value = progress()
                if value != last {
                    last = value
                    try? watchdog.checkpoint(stage, abort: abort)
                }
            }
        }
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let task = task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}

/// Fails a PhotoKit request that stops reporting progress, for example an
/// iCloud download that never calls back, instead of waiting for it forever.
final class RequestInactivityGuard: @unchecked Sendable {
    static let defaultTimeout: TimeInterval = 60
    private let lock = NSLock()
    private let timeout: TimeInterval
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var fired = false
    private var timer: DispatchSourceTimer?
    private let onStall: @Sendable () -> Void

    init(
        timeout: TimeInterval = RequestInactivityGuard.defaultTimeout,
        tick: TimeInterval = 1,
        onStall: @escaping @Sendable () -> Void
    ) {
        self.timeout = timeout
        self.onStall = onStall
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "memories.request-guard"))
        timer.schedule(deadline: .now() + tick, repeating: tick)
        timer.setEventHandler { [weak self] in self?.check() }
        self.timer = timer
        timer.resume()
    }

    deinit { timer?.cancel() }

    func touch() {
        lock.lock()
        lastActivity = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    func stop() {
        lock.lock()
        timer?.cancel()
        timer = nil
        lock.unlock()
    }

    private func check() {
        lock.lock()
        let stalled = !fired && ProcessInfo.processInfo.systemUptime - lastActivity >= timeout
        if stalled { fired = true }
        lock.unlock()
        if stalled {
            ExportProgressWatchdog.logger.error("PhotoKit request stalled with no progress")
            onStall()
        }
    }
}

/// Holds originals fetched ahead of an HD export so paying does not start
/// from zero. Items are keyed by photo ID; a different photo set restarts it.
final class MediaPrefetchCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var completed: [String: PreparedReelMedia] = [:]
    private var signature: String?
    private var directory: URL?
    private var expected = 0
    private var progressTicks = 0

    var completedCount: Int { lock.lock(); defer { lock.unlock() }; return completed.count }
    var stagingDirectory: URL? { lock.lock(); defer { lock.unlock() }; return directory }
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return task != nil }

    /// Starts (or keeps) a prefetch for `signature`. `run` fills the store one
    /// item at a time; failed items are simply left for the export to fetch.
    func begin(
        signature: String,
        expected: Int,
        directory: URL,
        run: @escaping @Sendable (_ store: @escaping @Sendable (String, PreparedReelMedia) -> Void) async -> Void
    ) {
        lock.lock()
        if self.signature == signature, task != nil || !completed.isEmpty {
            lock.unlock()
            return
        }
        let oldTask = task
        let oldDirectory = self.directory
        self.signature = signature
        self.directory = directory
        self.expected = expected
        completed = [:]
        progressTicks = 0
        let newTask = Task.detached(priority: .utility) { [weak self] in
            await run { id, media in self?.store(id: id, media: media, from: signature) }
            self?.finished(signature: signature)
        }
        task = newTask
        lock.unlock()
        oldTask?.cancel()
        if let oldDirectory { try? FileManager.default.removeItem(at: oldDirectory) }
    }

    private func store(id: String, media: PreparedReelMedia, from signature: String) {
        lock.lock()
        defer { lock.unlock() }
        guard self.signature == signature else { return }
        completed[id] = media
        progressTicks += 1
    }

    private func finished(signature: String) {
        lock.lock()
        if self.signature == signature { task = nil }
        lock.unlock()
    }

    /// Items ready for reuse. Stills whose file has gone (for example after the
    /// system cleared temporary files) are dropped so the export refetches them.
    func cachedMedia(for photos: [ReelPhoto]) -> [String: PreparedReelMedia] {
        lock.lock()
        let snapshot = completed
        lock.unlock()
        var result: [String: PreparedReelMedia] = [:]
        for photo in photos {
            guard let media = snapshot[photo.id] else { continue }
            if let url = media.stillImageURL, !FileManager.default.fileExists(atPath: url.path) { continue }
            result[photo.id] = media
        }
        return result
    }

    /// Waits for a running prefetch instead of downloading the same originals
    /// twice. Gives up, and stops the prefetch, if nothing finishes for
    /// `inactivityTimeout`, so a stuck download cannot hold the export back.
    func waitForCompletion(
        inactivityTimeout: TimeInterval = 60,
        poll: TimeInterval = 0.25,
        onProgress: @Sendable (_ ready: Int, _ expected: Int) -> Void = { _, _ in }
    ) async throws {
        var lastTicks = -1
        var lastChange = ProcessInfo.processInfo.systemUptime
        while true {
            lock.lock()
            let running = task != nil
            let ticks = progressTicks
            let expected = expected
            lock.unlock()
            guard running else { return }
            if ticks != lastTicks {
                lastTicks = ticks
                lastChange = ProcessInfo.processInfo.systemUptime
                onProgress(ticks, expected)
            } else if ProcessInfo.processInfo.systemUptime - lastChange >= inactivityTimeout {
                ExportProgressWatchdog.logger.error("Prefetch made no progress; exporting without it")
                lock.lock()
                let stuck = task
                task = nil
                lock.unlock()
                stuck?.cancel()
                return
            }
            try await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
        }
    }

    func discard() {
        lock.lock()
        let oldTask = task
        let oldDirectory = directory
        task = nil
        completed = [:]
        signature = nil
        directory = nil
        expected = 0
        progressTicks = 0
        lock.unlock()
        oldTask?.cancel()
        if let oldDirectory { try? FileManager.default.removeItem(at: oldDirectory) }
    }
}

/// Prefetching originals can mean large iCloud downloads. Skip it on cellular
/// or in Low Data Mode; the export still fetches what it needs when it runs.
enum PrefetchNetworkPolicy {
    static func allowsPrefetch() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let once = OnceFlag()
            let finish: @Sendable (Bool) -> Void = { value in
                guard once.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: value)
            }
            monitor.pathUpdateHandler = { path in
                finish(path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            let queue = DispatchQueue(label: "memories.prefetch-network")
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1) { finish(false) }
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Combines per-item download progress into one bar while several items are
/// fetched at the same time.
private final class MediaPreparationTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var itemProgress: [Double]
    private var completed = 0

    init(total: Int) { itemProgress = Array(repeating: 0, count: max(0, total)) }

    func update(index: Int, progress: Double) {
        lock.lock()
        if itemProgress.indices.contains(index) {
            itemProgress[index] = max(itemProgress[index], min(1, max(0, progress)))
        }
        lock.unlock()
    }

    func complete(index: Int) {
        lock.lock()
        if itemProgress.indices.contains(index) {
            itemProgress[index] = 1
            completed += 1
        }
        lock.unlock()
    }

    func snapshot() -> (fraction: Double, completed: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !itemProgress.isEmpty else { return (1, completed) }
        return (itemProgress.reduce(0, +) / Double(itemProgress.count), completed)
    }
}

/// Saves each finished piece of a long render so an interrupted export can resume
/// where it stopped. iOS may end a background render at any moment; without this
/// every interruption threw away all the work done so far.
final class RenderCheckpointStore: @unchecked Sendable {
    struct DoneSegment: Codable, Equatable {
        let index: Int
        let fileName: String
        let frameCount: Int
        let carryImageName: String?
    }
    struct Manifest: Codable {
        var fingerprint: String
        var segments: [DoneSegment]
        var updatedAt: Date
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RenderCheckpoints", isDirectory: true)
    }

    let baseDirectory: URL

    init(baseDirectory: URL = RenderCheckpointStore.defaultDirectory) {
        self.baseDirectory = baseDirectory
    }

    func directory(for fingerprint: String) -> URL {
        baseDirectory.appendingPathComponent(String(fingerprint.prefix(40)), isDirectory: true)
    }

    func url(for fingerprint: String, name: String) -> URL {
        directory(for: fingerprint).appendingPathComponent(name)
    }

    func segmentName(_ index: Int) -> String { String(format: "segment-%03d.mp4", index) }
    func carryName(_ index: Int) -> String { String(format: "carry-%03d.png", index) }

    func prepare(_ fingerprint: String) throws {
        let directory = directory(for: fingerprint)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var base = baseDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
    }

    /// The longest unbroken run of finished pieces that still exist on disk.
    func manifest(for fingerprint: String) -> Manifest {
        let empty = Manifest(fingerprint: fingerprint, segments: [], updatedAt: Date())
        let manifestURL = url(for: fingerprint, name: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let saved = try? JSONDecoder().decode(Manifest.self, from: data),
              saved.fingerprint == fingerprint else { return empty }
        var valid: [DoneSegment] = []
        for (position, segment) in saved.segments.enumerated() {
            guard segment.index == position,
                  FileManager.default.fileExists(atPath: url(for: fingerprint, name: segment.fileName).path),
                  segment.carryImageName.map({
                      FileManager.default.fileExists(atPath: url(for: fingerprint, name: $0).path)
                  }) ?? true else { break }
            valid.append(segment)
        }
        return Manifest(fingerprint: fingerprint, segments: valid, updatedAt: saved.updatedAt)
    }

    func save(_ manifest: Manifest) throws {
        var manifest = manifest
        manifest.updatedAt = Date()
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url(for: manifest.fingerprint, name: "manifest.json"), options: .atomic)
    }

    func discard(_ fingerprint: String) {
        try? FileManager.default.removeItem(at: directory(for: fingerprint))
    }

    func discardAll() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    /// Interrupted renders nobody came back to must not fill the phone.
    func purgeStale(olderThan age: TimeInterval = 48 * 60 * 60, now: Date = Date()) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for item in items {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > age { try? FileManager.default.removeItem(at: item) }
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw TripReelVideoExportError.cannotCreateFrame }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TripReelVideoExportError.cannotCreateFrame }
    }

    static func readImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// What one timeline item hands to the next: the previous item (for the cross
/// fade) and the last picture shown (also the background of title cards).
private struct RenderCarry {
    var previousItem: MontageTimelineItem?
    /// The previous item's final picture, used for the cross fade into this item.
    var previousImage: CGImage?
    /// The most recent picture shown (also the background of title cards).
    var lastImage: CGImage?
    var previousPhotoIndex = 0
}

struct PreparedReelMedia: @unchecked Sendable {
    let stillImageURL: URL?
    let videoAsset: AVAsset?
}

/// AVFoundation forbids cancelling a reader during copyNextSampleBuffer, or a
/// writer during append. Keep teardown exclusive and wait for it before cleanup
/// returns, so a retry cannot race the previous attempt's resource destruction.
final class ExportResourceAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func perform<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        return try operation()
    }

    func cancel(_ operation: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true
        operation()
    }
}

/// Only cancellation crosses the rendering task boundary. All writer setup,
/// frame appends and finalization remain owned by the single rendering task.
private final class VideoWriterCancellation: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let access = ExportResourceAccess()
    init(_ writer: AVAssetWriter) { self.writer = writer }
    func perform<T>(_ operation: () throws -> T) throws -> T {
        try access.perform(operation)
    }
    func cancel() { access.cancel { writer.cancelWriting() } }
}

/// Reads a clip in presentation order. `AVAssetImageGenerator` is excellent
/// for occasional thumbnails, but seeking it once per output frame makes even
/// short stories disproportionately slow. Video composition output keeps the
/// decoder moving forward and applies the source track's orientation once.
private final class SequentialVideoFrameReader: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderVideoCompositionOutput
    private let access = ExportResourceAccess()

    init(
        asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        maximumSize: CGSize,
        frameRate: Int32
    ) throws {
        reader = try AVAssetReader(asset: asset)

        let geometry = TripReelVideoExporter.sourceVideoGeometry(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            maximumSize: maximumSize
        )

        let composition = AVMutableVideoComposition()
        composition.renderSize = geometry.renderSize
        composition.frameDuration = CMTime(value: 1, timescale: frameRate)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(geometry.transform, at: timeRange.start)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.alwaysCopiesSampleData = false
        output.videoComposition = composition
        guard reader.canAdd(output) else {
            throw TripReelVideoExportError.cannotCreateFrame
        }
        reader.add(output)
        reader.timeRange = timeRange
        guard reader.startReading() else {
            throw TripReelVideoExportError.encodingFailed(
                reader.error?.localizedDescription ?? "A source clip could not be decoded"
            )
        }
    }

    func nextImage() throws -> CGImage? {
        try access.perform {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed {
                    throw TripReelVideoExportError.encodingFailed(
                        reader.error?.localizedDescription ?? "A source clip stopped decoding"
                    )
                }
                return nil
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                throw TripReelVideoExportError.cannotCreateFrame
            }
            var image: CGImage?
            let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
            guard status == noErr, let image else {
                throw TripReelVideoExportError.cannotCreateFrame
            }
            return image
        }
    }

    func cancel() { access.cancel { reader.cancelReading() } }
    deinit { cancel() }
}

/// Renders the same mixed photo, video, and title timeline used by the SwiftUI
/// preview into a vertical H.264 movie. Full-resolution sources are prepared
/// one at a time so a large memory does not stay resident in memory.
final class TripReelVideoExporter: TripReelVideoExporting, @unchecked Sendable {
    static let defaultFrameRate: Int32 = 30
    private static let preparationProgressWeight = 0.28
    private static let renderingProgressWeight = 0.62
    private let imageManager: PHImageManager
    private let frameRate: Int32
    private let prefetchNetworkPolicy: @Sendable () async -> Bool
    private let checkpoints: RenderCheckpointStore
    private let segmentCounter = NSLock()
    private var segmentsRendered = 0
    /// Test hook: how many pieces this exporter has actually rendered (not resumed).
    var renderedSegmentCount: Int { segmentCounter.lock(); defer { segmentCounter.unlock() }; return segmentsRendered }
    private func countRenderedSegment() { segmentCounter.lock(); segmentsRendered += 1; segmentCounter.unlock() }

    init(
        imageManager: PHImageManager = PHCachingImageManager(),
        frameRate: Int32 = TripReelVideoExporter.defaultFrameRate,
        prefetchNetworkPolicy: @escaping @Sendable () async -> Bool = { await PrefetchNetworkPolicy.allowsPrefetch() },
        checkpoints: RenderCheckpointStore = RenderCheckpointStore()
    ) {
        self.imageManager = imageManager
        self.frameRate = max(8, frameRate)
        self.prefetchNetworkPolicy = prefetchNetworkPolicy
        self.checkpoints = checkpoints
        checkpoints.purgeStale()
    }

    func export(
        _ request: TripReelVideoExportRequest,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws -> URL {
        guard !request.photos.isEmpty else { throw TripReelVideoExportError.noPhotos }
        try Task.checkCancellation()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripReel-Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let silentURL = directory.appendingPathComponent("silent-\(UUID().uuidString).mp4")
        let finalURL = directory.appendingPathComponent("Memories-\(UUID().uuidString).mp4")
        let stagingDirectory = directory.appendingPathComponent(
            "staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        do {
            var preparedMedia: [String: PreparedReelMedia] = [:]
            if request.quality == .hd {
                // A prefetch that is still running is waited for, not duplicated.
                try await prefetch.waitForCompletion { ready, expected in
                    progress(
                        TripReelVideoExportProgress(
                            fraction: Double(ready) / Double(max(1, expected)) * Self.preparationProgressWeight,
                            phase: .preparingPhotos(
                                ready: ready, total: expected,
                                currentLabel: nil, downloadProgress: nil
                            )
                        )
                    )
                }
                preparedMedia = prefetch.cachedMedia(for: request.photos)
            }
            let missing = request.photos.filter { preparedMedia[$0.id] == nil }
            let fresh = try await prepareMedia(
                missing,
                outputSize: Self.outputSize(for: request.quality),
                in: stagingDirectory,
                alreadyPrepared: preparedMedia.count,
                overallTotal: request.photos.count,
                progress: progress
            )
            preparedMedia.merge(fresh) { _, new in new }
            let watchdog = ExportProgressWatchdog()
            let fingerprint = Self.renderFingerprint(request, frameRate: frameRate)
            do {
                defer { watchdog.stop() }
                try await withTaskCancellationHandler {
                    do {
                        try await renderSilentVideo(
                            request, preparedMedia: preparedMedia, to: silentURL,
                            fingerprint: fingerprint, watchdog: watchdog, progress: progress
                        )
                    } catch {
                        // Prefer the actionable timeout/cancellation over the
                        // downstream encoder error caused by cancelWriting.
                        try watchdog.check()
                        throw error
                    }
                } onCancel: { watchdog.cancel() }
            }
            try Task.checkCancellation()
            let containsSourceAudio = request.photos.contains {
                $0.isVideo && $0.hasOriginalAudio
            }
            if request.soundtrackURL != nil || request.atmosphereURL != nil || containsSourceAudio {
                progress(
                    TripReelVideoExportProgress(
                        fraction: 0.91,
                        phase: .addingSoundtrack
                    )
                )
                let audioWatchdog = ExportProgressWatchdog()
                defer { audioWatchdog.stop() }
                try await addAudio(
                    soundtrackURL: request.soundtrackURL,
                    toVideoAt: silentURL,
                    outputURL: finalURL,
                    request: request,
                    preparedMedia: preparedMedia,
                    watchdog: audioWatchdog
                )
                try? FileManager.default.removeItem(at: silentURL)
            } else {
                try FileManager.default.moveItem(at: silentURL, to: finalURL)
            }
            progress(
                TripReelVideoExportProgress(
                    fraction: 1,
                    phase: .finalizing
                )
            )
            // Only a finished film clears the saved pieces; any failure keeps them.
            checkpoints.discard(fingerprint)
            return finalURL
        } catch {
            try? FileManager.default.removeItem(at: silentURL)
            try? FileManager.default.removeItem(at: finalURL)
            throw error
        }
    }

    func saveToPhotoLibrary(_ url: URL) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            throw TripReelVideoExportError.photosPermissionDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: TripReelVideoExportError.saveFailed(
                            error?.localizedDescription ?? "The system declined the save request."
                        )
                    )
                }
            }
        }
    }

    func finishGeneratedClip(_ url: URL, title: String) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first, duration > .zero else {
            throw TripReelVideoExportError.generatedClipFinishingFailed
        }
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let preferredTransform = try await sourceVideo.load(.preferredTransform)
        let transformedBounds = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let renderSize = CGSize(
            width: max(1, abs(transformedBounds.width)),
            height: max(1, abs(transformedBounds.height))
        )

        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TripReelVideoExportError.generatedClipFinishingFailed
        }
        try compositionVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideo,
            at: .zero
        )
        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceAudio,
                at: .zero
            )
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideo)
        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -transformedBounds.minX,
                y: -transformedBounds.minY
            )
        )
        layerInstruction.setTransform(normalizedTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = false
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let titleValue = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titleValue.isEmpty {
            let shade = CAGradientLayer()
            shade.frame = parentLayer.bounds
            shade.colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.10).cgColor,
                UIColor.black.withAlphaComponent(0.72).cgColor
            ]
            shade.locations = [0.48, 0.68, 1]
            parentLayer.addSublayer(shade)

            let titleLayer = CATextLayer()
            titleLayer.contentsScale = 2
            titleLayer.alignmentMode = .left
            titleLayer.isWrapped = true
            let inset = max(42, renderSize.width * 0.075)
            titleLayer.frame = CGRect(
                x: inset,
                y: max(58, renderSize.height * 0.075),
                width: renderSize.width - (inset * 2),
                height: min(230, renderSize.height * 0.18)
            )
            let fontSize = min(72, max(38, renderSize.width * 0.072))
            let font = UIFont(name: "InstrumentSerif-Regular", size: fontSize)
                ?? UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = -2
            titleLayer.string = NSAttributedString(
                string: titleValue,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1),
                    .paragraphStyle: paragraph,
                    .kern: -0.6
                ]
            )
            titleLayer.shadowColor = UIColor.black.cgColor
            titleLayer.shadowOpacity = 0.62
            titleLayer.shadowRadius = 10
            titleLayer.shadowOffset = CGSize(width: 0, height: 3)

            let reveal = CAKeyframeAnimation(keyPath: "opacity")
            reveal.values = [0, 1, 1, 0]
            reveal.keyTimes = [0, 0.10, 0.78, 1]
            reveal.beginTime = AVCoreAnimationBeginTimeAtZero
            reveal.duration = max(0.1, duration.seconds)
            reveal.isRemovedOnCompletion = false
            reveal.fillMode = .both
            titleLayer.add(reveal, forKey: "memories-title-reveal")
            parentLayer.addSublayer(titleLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Memories-AI-Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("Memory-Titled-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TripReelVideoExportError.generatedClipFinishingFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            if session.status == .cancelled || Task.isCancelled { throw CancellationError() }
            throw TripReelVideoExportError.generatedClipFinishingFailed
        }
        return outputURL
    }

    /// Whole timeline items grouped into runs of about ten seconds. Each run is
    /// rendered to its own file so an interrupted export resumes at the last
    /// finished run.
    static func segmentPlan(frameCounts: [Int], frameRate: Int32, targetSeconds: Double = 10) -> [Range<Int>] {
        let target = max(1, Int(targetSeconds * Double(frameRate)))
        var ranges: [Range<Int>] = []
        var start = 0
        var frames = 0
        for (index, count) in frameCounts.enumerated() {
            frames += count
            if frames >= target {
                ranges.append(start..<(index + 1))
                start = index + 1
                frames = 0
            }
        }
        if start < frameCounts.count { ranges.append(start..<frameCounts.count) }
        return ranges
    }

    /// Identifies everything that changes the pictures. A different fingerprint
    /// means saved pieces are never reused for an edited film.
    static func renderFingerprint(_ request: TripReelVideoExportRequest, frameRate: Int32) -> String {
        let parts = [
            "render-v1", "\(frameRate)", "\(request.quality)", "\(request.secondsPerPhoto)",
            "\(request.look)", "\(request.motionIntensity)",
            String(reflecting: request.photos), String(reflecting: request.titleCards),
            String(reflecting: request.textOverlays)
        ]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func renderSilentVideo(
        _ request: TripReelVideoExportRequest,
        preparedMedia: [String: PreparedReelMedia],
        to outputURL: URL,
        fingerprint: String,
        watchdog: ExportProgressWatchdog,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws {
        let outputSize = Self.outputSize(for: request.quality)
        let timeline = MontageTimelineBuilder.make(
            photos: request.photos,
            titleCards: request.titleCards
        )
        let frameCounts = timeline.map {
            max(1, Int(ceil($0.duration(defaultPhotoDuration: request.secondsPerPhoto) * Double(frameRate))))
        }
        let totalFrames = frameCounts.reduce(0, +)
        let segments = Self.segmentPlan(frameCounts: frameCounts, frameRate: frameRate)
        try checkpoints.prepare(fingerprint)
        var manifest = checkpoints.manifest(for: fingerprint)

        var completedFrames = manifest.segments.reduce(0) { $0 + $1.frameCount }
        let reportFrames: @Sendable (Int) -> Void = { frames in
            progress(
                TripReelVideoExportProgress(
                    fraction: min(
                        0.90,
                        Self.preparationProgressWeight
                            + (Double(frames) / Double(max(1, totalFrames))) * Self.renderingProgressWeight
                    ),
                    phase: .rendering
                )
            )
        }
        reportFrames(completedFrames)
        if !manifest.segments.isEmpty {
            ExportProgressWatchdog.logger.info("Resuming render: \(manifest.segments.count) of \(segments.count) pieces already finished")
        }

        // Pick up the carried picture from the last finished piece.
        var carry = RenderCarry()
        if let last = manifest.segments.last, segments.indices.contains(last.index) {
            let lastItem = segments[last.index].upperBound - 1
            carry.previousItem = timeline[lastItem]
            carry.lastImage = last.carryImageName.flatMap {
                RenderCheckpointStore.readImage(at: checkpoints.url(for: fingerprint, name: $0))
            }
            carry.previousImage = carry.lastImage
            if case let .photo(photo) = timeline[lastItem] {
                carry.previousPhotoIndex = request.photos.firstIndex { $0.id == photo.id } ?? 0
            }
        }

        let photoIndices = Dictionary(
            uniqueKeysWithValues: request.photos.enumerated().map { ($0.element.id, $0.offset) }
        )
        for (segmentIndex, items) in segments.enumerated() where segmentIndex >= manifest.segments.count {
            try Task.checkCancellation()
            let segmentURL = checkpoints.url(for: fingerprint, name: checkpoints.segmentName(segmentIndex))
            // Every attempt writes to its own file and renames it into place only once complete. A
            // cancelled attempt's writer deletes its output asynchronously, and that late cleanup
            // must never remove the file a resumed attempt is writing.
            let attemptURL = checkpoints.url(
                for: fingerprint, name: "attempt-\(segmentIndex)-\(UUID().uuidString).mp4"
            )
            let baseFrames = completedFrames
            do {
                try await renderSegment(
                    items: items, timeline: timeline, request: request, preparedMedia: preparedMedia,
                    photoIndices: photoIndices, carry: &carry, outputURL: attemptURL,
                    outputSize: outputSize, watchdog: watchdog,
                    onFrame: { done in reportFrames(baseFrames + done) }
                )
            } catch {
                try? FileManager.default.removeItem(at: attemptURL)
                throw error
            }
            try? FileManager.default.removeItem(at: segmentURL)
            try FileManager.default.moveItem(at: attemptURL, to: segmentURL)
            countRenderedSegment()
            var carryName: String?
            if let image = carry.lastImage {
                let name = checkpoints.carryName(segmentIndex)
                try RenderCheckpointStore.writePNG(image, to: checkpoints.url(for: fingerprint, name: name))
                carryName = name
            }
            let pieceFrames = items.reduce(0) { $0 + frameCounts[$1] }
            completedFrames += pieceFrames
            manifest.segments.append(
                .init(index: segmentIndex, fileName: checkpoints.segmentName(segmentIndex),
                      frameCount: pieceFrames, carryImageName: carryName)
            )
            try checkpoints.save(manifest)
            reportFrames(completedFrames)
        }

        try await concatenateSegments(
            manifest.segments.map { checkpoints.url(for: fingerprint, name: $0.fileName) },
            to: outputURL,
            watchdog: watchdog
        )
    }

    /// Renders one run of whole timeline items into its own H.264 file.
    private func renderSegment(
        items: Range<Int>,
        timeline: [MontageTimelineItem],
        request: TripReelVideoExportRequest,
        preparedMedia: [String: PreparedReelMedia],
        photoIndices: [String: Int],
        carry: inout RenderCarry,
        outputURL: URL,
        outputSize: CGSize,
        watchdog: ExportProgressWatchdog,
        onFrame: @escaping @Sendable (Int) -> Void
    ) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let writerCancellation = VideoWriterCancellation(writer)
        var writerCompleted = false
        defer {
            if !writerCompleted { writerCancellation.cancel() }
        }
        let bitRate = request.quality == .hd ? 9_000_000 : 4_000_000
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                // Pieces are joined end to end. Frame reordering (B-frames) shifts each
                // piece's timestamps and made the joins overlap, so keep decode order.
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )
        guard writer.canAdd(input) else { throw TripReelVideoExportError.cannotCreateWriter }
        writer.add(input)
        guard writer.startWriting() else {
            throw TripReelVideoExportError.encodingFailed(
                writer.error?.localizedDescription ?? "Unknown writer error"
            )
        }
        writer.startSession(atSourceTime: .zero)

        var segmentFrames = 0
        for itemIndex in items {
            let item = timeline[itemIndex]
            try Task.checkCancellation()
            let itemStarted = ProcessInfo.processInfo.systemUptime
            try watchdog.checkpoint("prepare item \(itemIndex + 1)") { writerCancellation.cancel() }
            let duration = item.duration(defaultPhotoDuration: request.secondsPerPhoto)
            let frameCount = max(1, Int(ceil(duration * Double(frameRate))))
            var photoImage: CGImage?
            var videoReader: SequentialVideoFrameReader?
            var videoPhoto: ReelPhoto?
            let itemPhotoIndex: Int
            switch item {
            case let .photo(photo):
                if photo.isVideo {
                    guard let videoAsset = preparedMedia[photo.id]?.videoAsset else {
                        throw TripReelVideoExportError.photoUnavailable(photo.label)
                    }
                    videoReader = try await makeVideoFrameReader(
                        asset: videoAsset,
                        sourceStartSeconds: photo.videoStartSeconds,
                        durationSeconds: duration,
                        maximumSize: outputSize
                    )
                    videoPhoto = photo
                } else {
                    photoImage = try await loadImage(
                        for: photo,
                        preparedMedia: preparedMedia,
                        targetSize: outputSize
                    )
                }
                carry.lastImage = photoImage
                itemPhotoIndex = photoIndices[photo.id] ?? 0
            case .title:
                photoImage = carry.lastImage
                itemPhotoIndex = 0
            }

            let activeReader = videoReader
            defer { activeReader?.cancel() }
            for localFrame in 0..<frameCount {
                try watchdog.checkpoint("item \(itemIndex + 1), frame \(localFrame), encoder") {
                    activeReader?.cancel()
                    writerCancellation.cancel()
                }
                while !input.isReadyForMoreMediaData {
                    try watchdog.check()
                    guard writer.status == .writing else {
                        throw TripReelVideoExportError.encodingFailed(
                            writer.error?.localizedDescription ?? "The encoder stopped accepting frames"
                        )
                    }
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                try watchdog.checkpoint("item \(itemIndex + 1), frame \(localFrame), decode/draw") {
                    activeReader?.cancel()
                    writerCancellation.cancel()
                }
                // Include decoding, image conversion and append, not just drawing:
                // otherwise autoreleased video objects can accumulate for a whole clip.
                try autoreleasepool {
                    guard let pool = adaptor.pixelBufferPool else {
                        throw TripReelVideoExportError.cannotCreateFrame
                    }
                    let pixelBuffer = try Self.makePixelBuffer(from: pool)

                    let phase = frameCount <= 1 ? 1 : Double(localFrame) / Double(frameCount - 1)
                    if let videoReader, let videoPhoto {
                        if let decodedFrame = try videoReader.nextImage() {
                            photoImage = decodedFrame
                        }
                        guard photoImage != nil else {
                            throw TripReelVideoExportError.photoUnavailable(videoPhoto.label)
                        }
                        carry.lastImage = photoImage
                    }
                    let transitionFrames = carry.previousItem == nil
                        ? 0
                        : min(frameCount - 1, max(2, Int((0.24 * Double(frameRate)).rounded())))
                    let transitionProgress = Self.transitionProgress(
                        frame: localFrame,
                        transitionFrames: transitionFrames
                    )
                    try Self.draw(
                        item: item,
                        photoImage: photoImage,
                        previousItem: carry.previousItem,
                        previousPhotoImage: carry.previousImage,
                        into: pixelBuffer,
                        outputSize: outputSize,
                        phase: phase,
                        photoIndex: itemPhotoIndex,
                        previousPhotoIndex: carry.previousPhotoIndex,
                        transitionProgress: transitionProgress,
                        request: request
                    )
                    let presentationTime = CMTime(value: CMTimeValue(segmentFrames), timescale: frameRate)
                    try watchdog.check()
                    let appended = try writerCancellation.perform {
                        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    }
                    guard appended else {
                        throw TripReelVideoExportError.encodingFailed(
                            writer.error?.localizedDescription ?? "A frame could not be written"
                        )
                    }
                }
                segmentFrames += 1
                if segmentFrames.isMultiple(of: 6) { onFrame(segmentFrames) }
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - itemStarted
            ExportProgressWatchdog.logger.info("Rendered item \(itemIndex + 1): \(frameCount) frames in \(elapsed) seconds; video=\(videoReader != nil)")

            carry.previousItem = item
            carry.previousImage = carry.lastImage
            carry.previousPhotoIndex = itemPhotoIndex
        }
        onFrame(segmentFrames)

        try watchdog.checkpoint("finalize video piece") { writerCancellation.cancel() }
        try writerCancellation.perform {
            input.markAsFinished()
            writer.finishWriting { }
        }
        while writer.status == .writing {
            try watchdog.check()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try watchdog.check()
        guard writer.status == .completed else {
            throw TripReelVideoExportError.encodingFailed(
                writer.error?.localizedDescription ?? "The file could not be finalized"
            )
        }
        writerCompleted = true
    }

    /// Joins the finished pieces without re-encoding them.
    private func concatenateSegments(
        _ urls: [URL],
        to outputURL: URL,
        watchdog: ExportProgressWatchdog
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        if urls.count == 1 {
            try FileManager.default.copyItem(at: urls[0], to: outputURL)
            return
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw TripReelVideoExportError.cannotCreateWriter }
        var cursor = CMTime.zero
        for url in urls {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw TripReelVideoExportError.encodingFailed("A saved piece of the film could not be read.")
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough
        ) else { throw TripReelVideoExportError.cannotCreateWriter }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        try await runExportSession(
            session, stage: "join film pieces", watchdog: watchdog,
            failure: .encodingFailed("The film pieces could not be joined.")
        )
    }

    /// How many originals are fetched at once. Serial fetching made a long
    /// story wait for every iCloud download one after another before the first
    /// frame could be drawn; more than a few at once just competes for bandwidth
    /// and memory on an older iPhone.
    static let maxConcurrentPreparations = 3

    private func prepareMedia(
        _ photos: [ReelPhoto],
        outputSize: CGSize,
        in directory: URL,
        alreadyPrepared: Int = 0,
        overallTotal: Int? = nil,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws -> [String: PreparedReelMedia] {
        let count = photos.count
        let total = overallTotal ?? count
        let weight = Self.preparationProgressWeight
        let tracker = MediaPreparationTracker(total: count)
        let report: @Sendable (String?, Double?) -> Void = { label, downloadProgress in
            let snapshot = tracker.snapshot()
            let fraction = total == 0
                ? 1
                : (Double(alreadyPrepared) + snapshot.fraction * Double(count)) / Double(total)
            progress(
                TripReelVideoExportProgress(
                    fraction: fraction * weight,
                    phase: .preparingPhotos(
                        ready: alreadyPrepared + snapshot.completed,
                        total: total,
                        currentLabel: label,
                        downloadProgress: downloadProgress
                    )
                )
            )
        }
        report(photos.first?.label, nil)
        guard count > 0 else { return [:] }

        var prepared: [String: PreparedReelMedia] = [:]
        prepared.reserveCapacity(count)
        try await withThrowingTaskGroup(of: (String, PreparedReelMedia).self) { group in
            var nextIndex = 0
            func launchNext() {
                guard nextIndex < count else { return }
                let index = nextIndex
                nextIndex += 1
                let photo = photos[index]
                group.addTask { [self] in
                    try Task.checkCancellation()
                    let itemProgress: @Sendable (Double?) -> Void = { downloadProgress in
                        tracker.update(index: index, progress: downloadProgress ?? 0)
                        report(photo.label, downloadProgress)
                    }
                    itemProgress(nil)
                    let media = try await prepareItem(
                        photo,
                        index: index,
                        outputSize: outputSize,
                        directory: directory,
                        progress: itemProgress
                    )
                    tracker.complete(index: index)
                    report(index + 1 < count ? photos[index + 1].label : nil, nil)
                    return (photo.id, media)
                }
            }
            for _ in 0..<min(Self.maxConcurrentPreparations, count) { launchNext() }
            while let (id, media) = try await group.next() {
                prepared[id] = media
                launchNext()
            }
        }
        return prepared
    }

    /// Fetches one photo or clip at the quality the export needs.
    private func prepareItem(
        _ photo: ReelPhoto,
        index: Int,
        outputSize: CGSize,
        directory: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> PreparedReelMedia {
        if photo.isVideo {
            let asset = try await prepareVideoAsset(for: photo, progress: progress)
            return PreparedReelMedia(stillImageURL: nil, videoAsset: asset)
        }
        let requestSize = Self.photoRequestSize(for: photo, outputSize: outputSize)
        let image = try await prepareImage(for: photo, targetSize: requestSize, progress: progress)
        let fileURL = directory.appendingPathComponent(String(format: "photo-%04d.jpg", index))
        try Self.writePreparedImage(image, to: fileURL)
        return PreparedReelMedia(stillImageURL: fileURL, videoAsset: nil)
    }

    // MARK: Prefetch

    private let prefetch = MediaPrefetchCoordinator()

    func prefetchOriginals(for photos: [ReelPhoto]) {
        guard !photos.isEmpty else { return }
        let outputSize = Self.outputSize(for: .hd)
        let signature = photos.map(\.id).joined(separator: "|")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripReel-Exports", isDirectory: true)
            .appendingPathComponent("prefetch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        prefetch.begin(signature: signature, expected: photos.count, directory: directory) { [self] store in
            guard await prefetchNetworkPolicy() else { return }
            // Gentler than the export itself: playback and editing keep priority.
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                func launch() {
                    guard next < photos.count, !Task.isCancelled else { return }
                    let index = next
                    next += 1
                    let photo = photos[index]
                    group.addTask { [self] in
                        guard let media = try? await prepareItem(
                            photo, index: index, outputSize: outputSize,
                            directory: directory, progress: { _ in }
                        ) else { return }
                        store(photo.id, media)
                    }
                }
                for _ in 0..<min(2, photos.count) { launch() }
                while await group.next() != nil { launch() }
            }
        }
    }

    func discardPrefetchedOriginals() {
        prefetch.discard()
    }

    func discardRenderCheckpoints() {
        checkpoints.discardAll()
    }

    /// Test hooks.
    var prefetchedItemCount: Int { prefetch.completedCount }
    var prefetchDirectory: URL? { prefetch.stagingDirectory }

    private func prepareImage(
        for photo: ReelPhoto,
        targetSize: CGSize,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> CGImage {
        switch photo.source {
        case let .bundled(name):
            guard let source = UIImage(named: name),
                  let image = Self.normalizedCGImage(source) else {
                throw TripReelVideoExportError.photoUnavailable(photo.label)
            }
            return image
        case let .imported(path):
            guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ), let image = Self.thumbnail(
                from: source,
                maximumPixelSize: Int(max(targetSize.width, targetSize.height).rounded(.up))
            ) else {
                throw TripReelVideoExportError.photoUnavailable(photo.label)
            }
            return image
        case let .library(identifier):
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let asset = result.firstObject else {
                throw TripReelVideoExportError.photoUnavailable(photo.label)
            }

            // A final PhotoKit callback can fail transiently while iCloud is
            // handing the asset off. Retry a bounded number of times, then use
            // the original-data API as a slower but more reliable fallback.
            for delay in [UInt64(0), 800_000_000] {
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
                do {
                    return try await requestLibraryImage(
                        asset: asset,
                        targetSize: targetSize,
                        progress: progress
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch VideoPhotoPreparationError.stalled {
                    // Already waited a full inactivity window; do not wait again.
                    throw TripReelVideoExportError.photoUnavailable(photo.label)
                } catch {
                    continue
                }
            }

            try await Task.sleep(nanoseconds: 1_600_000_000)
            do {
                return try await requestLibraryImageData(
                    asset: asset,
                    targetSize: targetSize,
                    progress: progress
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw TripReelVideoExportError.photoUnavailable(photo.label)
            }
        }
    }

    private func prepareVideoAsset(
        for photo: ReelPhoto,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> AVAsset {
        switch photo.source {
        case let .imported(path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw TripReelVideoExportError.photoUnavailable(photo.label)
            }
            progress(1)
            return AVURLAsset(url: url)
        case .bundled:
            throw TripReelVideoExportError.photoUnavailable(photo.label)
        case let .library(identifier):
            do {
                return try await prepareLibraryVideoAsset(
                    identifier: identifier,
                    label: photo.label,
                    progress: progress
                )
            } catch VideoPhotoPreparationError.stalled {
                throw TripReelVideoExportError.photoUnavailable(photo.label)
            }
        }
    }

    private func prepareLibraryVideoAsset(
        identifier: String,
        label: String,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> AVAsset {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject, asset.mediaType == .video else {
            throw TripReelVideoExportError.photoUnavailable(label)
        }

        let state = VideoAssetPreparationState(manager: imageManager)
        let inactivity = RequestInactivityGuard { state.fail(VideoPhotoPreparationError.stalled) }
        defer { inactivity.stop() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let options = PHVideoRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.version = .current
                options.isNetworkAccessAllowed = true
                options.progressHandler = { value, _, _, _ in
                    inactivity.touch()
                    progress(min(0.99, max(0, value)))
                }
                let requestID = imageManager.requestAVAsset(
                    forVideo: asset,
                    options: options
                ) { videoAsset, _, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        state.finish(.failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if let videoAsset {
                        progress(1)
                        state.finish(.success(videoAsset))
                    } else {
                        state.finish(.failure(TripReelVideoExportError.photoUnavailable(label)))
                    }
                }
                state.install(requestID: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func requestLibraryImage(
        asset: PHAsset,
        targetSize: CGSize,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> CGImage {
        let state = VideoImageRequestState(manager: imageManager)
        let inactivity = RequestInactivityGuard { state.fail(VideoPhotoPreparationError.stalled) }
        defer { inactivity.stop() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.version = .current
                options.isNetworkAccessAllowed = true
                options.progressHandler = { value, _, _, _ in
                    inactivity.touch()
                    progress(min(0.99, max(0, value)))
                }
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        state.finish(.failure(CancellationError()))
                        return
                    }
                    if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                        return
                    }
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    guard let source = image,
                          let image = Self.normalizedCGImage(source) else {
                        state.finish(.failure(VideoPhotoPreparationError.noFinalImage))
                        return
                    }
                    progress(1)
                    state.finish(.success(image))
                }
                state.install(requestID: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func requestLibraryImageData(
        asset: PHAsset,
        targetSize: CGSize,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> CGImage {
        let state = VideoImageRequestState(manager: imageManager)
        let inactivity = RequestInactivityGuard { state.fail(VideoPhotoPreparationError.stalled) }
        defer { inactivity.stop() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.version = .current
                options.isNetworkAccessAllowed = true
                options.progressHandler = { value, _, _, _ in
                    inactivity.touch()
                    progress(min(0.99, max(0, value)))
                }
                let requestID = imageManager.requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        state.finish(.failure(CancellationError()))
                        return
                    }
                    if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                        return
                    }
                    guard let data,
                          let source = CGImageSourceCreateWithData(
                            data as CFData,
                            [kCGImageSourceShouldCache: false] as CFDictionary
                          ),
                          let image = Self.thumbnail(
                            from: source,
                            maximumPixelSize: Int(
                                max(targetSize.width, targetSize.height).rounded(.up)
                            )
                          ) else {
                        state.finish(.failure(VideoPhotoPreparationError.cannotDecodeData))
                        return
                    }
                    progress(1)
                    state.finish(.success(image))
                }
                state.install(requestID: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func photoRequestSize(for photo: ReelPhoto, outputSize: CGSize) -> CGSize {
        PhotoDisplaySizing.targetSize(
            sourcePixelWidth: photo.pixelWidth,
            sourcePixelHeight: photo.pixelHeight,
            destinationPixelWidth: Int(outputSize.width),
            destinationPixelHeight: Int(outputSize.height),
            contentMode: .fill,
            maximumPixelDimension: 4_096
        )
    }

    private static func thumbnail(
        from source: CGImageSource,
        maximumPixelSize: Int
    ) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize)
            ] as CFDictionary
        )
    }

    private static func writePreparedImage(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw TripReelVideoExportError.cannotCreateFrame
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.96] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw TripReelVideoExportError.cannotCreateFrame
        }
    }

    private func loadImage(
        for photo: ReelPhoto,
        preparedMedia: [String: PreparedReelMedia],
        targetSize _: CGSize
    ) async throws -> CGImage {
        guard let url = preparedMedia[photo.id]?.stillImageURL,
              let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            throw TripReelVideoExportError.photoUnavailable(photo.label)
        }
        return image
    }

    private func makeVideoFrameReader(
        asset: AVAsset,
        sourceStartSeconds: Double,
        durationSeconds: Double,
        maximumSize: CGSize
    ) async throws -> SequentialVideoFrameReader {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TripReelVideoExportError.cannotCreateFrame
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let trackRange = try await track.load(.timeRange)
        let requestedStart = CMTime(
            seconds: max(0, sourceStartSeconds),
            preferredTimescale: 600
        )
        let start = CMTimeMaximum(trackRange.start, requestedStart)
        let availableDuration = CMTimeSubtract(CMTimeRangeGetEnd(trackRange), start)
        let requestedDuration = CMTime(
            seconds: max(1 / Double(frameRate), durationSeconds),
            preferredTimescale: 600
        )
        let duration = CMTimeMinimum(availableDuration, requestedDuration)
        guard duration > .zero else {
            throw TripReelVideoExportError.cannotCreateFrame
        }
        return try SequentialVideoFrameReader(
            asset: asset,
            track: track,
            timeRange: CMTimeRange(start: start, duration: duration),
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            maximumSize: maximumSize,
            frameRate: frameRate
        )
    }

    private static func outputSize(for quality: ExportQuality) -> CGSize {
        quality == .hd
            ? CGSize(width: 1_080, height: 1_920)
            : CGSize(width: 720, height: 1_280)
    }

    private static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }
        let size = CGSize(
            width: max(1, image.size.width * image.scale),
            height: max(1, image.size.height * image.scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    private func addAudio(
        soundtrackURL: URL?,
        toVideoAt videoURL: URL,
        outputURL: URL,
        request: TripReelVideoExportRequest,
        preparedMedia: [String: PreparedReelMedia],
        watchdog: ExportProgressWatchdog
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let videoDuration = try await videoAsset.load(.duration)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw TripReelVideoExportError.soundtrackFailed
        }

        let audioComposition = AVMutableComposition()

        var mixParameters: [AVAudioMixInputParameters] = []
        var hasMixedAudio = false
        var soundtrackParameters: AVMutableAudioMixInputParameters?
        if let soundtrackURL {
            let audioAsset = AVURLAsset(url: soundtrackURL)
            let audioDuration = try await audioAsset.load(.duration)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            guard let sourceAudioTrack = audioTracks.first,
                  audioDuration > .zero,
                  let audioTrack = audioComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                throw TripReelVideoExportError.soundtrackFailed
            }
            var cursor = CMTime.zero
            while cursor < videoDuration {
                try Task.checkCancellation()
                let remaining = CMTimeSubtract(videoDuration, cursor)
                let segmentDuration = CMTimeMinimum(audioDuration, remaining)
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: sourceAudioTrack,
                    at: cursor
                )
                cursor = CMTimeAdd(cursor, segmentDuration)
            }
            let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
            parameters.setVolume(0.68, at: .zero)
            soundtrackParameters = parameters
            mixParameters.append(parameters)
            hasMixedAudio = true
        }

        var atmosphereParameters: AVMutableAudioMixInputParameters?
        if let atmosphereURL = request.atmosphereURL {
            let atmosphereAsset = AVURLAsset(url: atmosphereURL)
            let atmosphereDuration = try await atmosphereAsset.load(.duration)
            let atmosphereTracks = try await atmosphereAsset.loadTracks(withMediaType: .audio)
            guard let sourceAtmosphereTrack = atmosphereTracks.first,
                  atmosphereDuration > .zero,
                  let atmosphereTrack = audioComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                throw TripReelVideoExportError.soundtrackFailed
            }
            var cursor = CMTime.zero
            while cursor < videoDuration {
                try Task.checkCancellation()
                let remaining = CMTimeSubtract(videoDuration, cursor)
                let segmentDuration = CMTimeMinimum(atmosphereDuration, remaining)
                try atmosphereTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: sourceAtmosphereTrack,
                    at: cursor
                )
                cursor = CMTimeAdd(cursor, segmentDuration)
            }
            let parameters = AVMutableAudioMixInputParameters(track: atmosphereTrack)
            parameters.setVolume(0.12, at: .zero)
            atmosphereParameters = parameters
            mixParameters.append(parameters)
            hasMixedAudio = true
        }

        if let sourceTrack = audioComposition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) {
            let sourceParameters = AVMutableAudioMixInputParameters(track: sourceTrack)
            sourceParameters.setVolume(0, at: .zero)
            var hasSourceAudio = false
            var cursor = CMTime.zero
            for item in MontageTimelineBuilder.make(
                photos: request.photos,
                titleCards: request.titleCards
            ) {
                try Task.checkCancellation()
                let itemDurationSeconds = item.duration(
                    defaultPhotoDuration: request.secondsPerPhoto
                )
                let itemDuration = CMTime(seconds: itemDurationSeconds, preferredTimescale: 600)
                defer { cursor = CMTimeAdd(cursor, itemDuration) }
                guard case let .photo(photo) = item,
                      photo.isVideo,
                      photo.hasOriginalAudio,
                      let sourceAsset = preparedMedia[photo.id]?.videoAsset,
                      let sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio).first
                else { continue }

                let trackRange = try await sourceAudio.load(.timeRange)
                let requestedStart = CMTime(
                    seconds: photo.videoStartSeconds,
                    preferredTimescale: 600
                )
                let sourceStart = CMTimeMaximum(trackRange.start, requestedStart)
                let sourceRemaining = CMTimeSubtract(CMTimeRangeGetEnd(trackRange), sourceStart)
                let clipDuration = CMTimeMinimum(itemDuration, sourceRemaining)
                guard clipDuration > .zero else { continue }
                do {
                    try sourceTrack.insertTimeRange(
                        CMTimeRange(start: sourceStart, duration: clipDuration),
                        of: sourceAudio,
                        at: cursor
                    )
                } catch {
                    continue
                }
                hasSourceAudio = true

                let fadeDuration = CMTimeMinimum(
                    CMTime(seconds: 0.12, preferredTimescale: 600),
                    CMTimeMultiplyByFloat64(clipDuration, multiplier: 0.25)
                )
                sourceParameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: 0.92,
                    timeRange: CMTimeRange(start: cursor, duration: fadeDuration)
                )
                let fadeOutStart = CMTimeSubtract(CMTimeAdd(cursor, clipDuration), fadeDuration)
                sourceParameters.setVolumeRamp(
                    fromStartVolume: 0.92,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeOutStart, duration: fadeDuration)
                )
                if let soundtrackParameters {
                    soundtrackParameters.setVolume(0.24, at: cursor)
                    soundtrackParameters.setVolume(0.68, at: CMTimeAdd(cursor, clipDuration))
                }
                if let atmosphereParameters {
                    atmosphereParameters.setVolume(0.04, at: cursor)
                    atmosphereParameters.setVolume(0.12, at: CMTimeAdd(cursor, clipDuration))
                }
            }
            if hasSourceAudio {
                mixParameters.append(sourceParameters)
                hasMixedAudio = true
            }
        }

        if let soundtrackParameters {
            let fadeDuration = CMTimeMinimum(
                CMTime(seconds: 1.1, preferredTimescale: 600),
                CMTimeMultiplyByFloat64(videoDuration, multiplier: 0.18)
            )
            if fadeDuration > .zero {
                let fadeStart = CMTimeSubtract(videoDuration, fadeDuration)
                soundtrackParameters.setVolumeRamp(
                    fromStartVolume: 0.68,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeStart, duration: fadeDuration)
                )
            }
        }

        if let atmosphereParameters {
            let fadeDuration = CMTimeMinimum(
                CMTime(seconds: 1.1, preferredTimescale: 600),
                CMTimeMultiplyByFloat64(videoDuration, multiplier: 0.18)
            )
            if fadeDuration > .zero {
                let fadeStart = CMTimeSubtract(videoDuration, fadeDuration)
                atmosphereParameters.setVolumeRamp(
                    fromStartVolume: 0.12,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeStart, duration: fadeDuration)
                )
            }
        }

        guard hasMixedAudio else {
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }

        let mixedAudioURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent("mixed-audio-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: mixedAudioURL) }
        guard let audioExportSession = AVAssetExportSession(
            asset: audioComposition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TripReelVideoExportError.soundtrackFailed
        }
        audioExportSession.outputURL = mixedAudioURL
        audioExportSession.outputFileType = .m4a
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters
        audioExportSession.audioMix = audioMix
        try await runExportSession(audioExportSession, stage: "mix soundtrack", watchdog: watchdog)

        try Task.checkCancellation()
        let mixedAudioAsset = AVURLAsset(url: mixedAudioURL)
        guard let mixedAudioTrack = try await mixedAudioAsset
            .loadTracks(withMediaType: .audio)
            .first
        else {
            throw TripReelVideoExportError.soundtrackFailed
        }
        let finalComposition = AVMutableComposition()
        guard let finalVideoTrack = finalComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let finalAudioTrack = finalComposition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TripReelVideoExportError.soundtrackFailed
        }
        try finalVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        let mixedAudioDuration = try await mixedAudioAsset.load(.duration)
        try finalAudioTrack.insertTimeRange(
            CMTimeRange(
                start: .zero,
                duration: CMTimeMinimum(videoDuration, mixedAudioDuration)
            ),
            of: mixedAudioTrack,
            at: .zero
        )

        guard let muxSession = AVAssetExportSession(
            asset: finalComposition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw TripReelVideoExportError.soundtrackFailed
        }
        muxSession.outputURL = outputURL
        muxSession.outputFileType = .mp4
        muxSession.shouldOptimizeForNetworkUse = true
        try await runExportSession(muxSession, stage: "combine video and audio", watchdog: watchdog)
    }

    /// Runs one `AVAssetExportSession` under the inactivity watchdog. A stall
    /// cancels the session and surfaces as `.stalled` (which offers a retry);
    /// task cancellation cancels the session too, instead of leaving it running.
    private func runExportSession(
        _ session: AVAssetExportSession,
        stage: String,
        watchdog: ExportProgressWatchdog,
        failure: TripReelVideoExportError = .soundtrackFailed
    ) async throws {
        let box = ExportSessionBox(session)
        let monitor = ExportSessionProgressMonitor(
            watchdog: watchdog,
            stage: stage,
            progress: { box.progress },
            abort: { box.cancel() }
        )
        try monitor.start()
        defer { monitor.stop() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.session.exportAsynchronously { continuation.resume() }
            }
        } onCancel: {
            watchdog.cancel()
            box.cancel()
        }
        // Prefer the actionable timeout/cancellation over the generic
        // "cancelled" status the aborted session reports.
        try watchdog.check()
        guard box.session.status == .completed else {
            throw failure
        }
    }

    private static func draw(
        item: MontageTimelineItem,
        photoImage: CGImage?,
        previousItem: MontageTimelineItem?,
        previousPhotoImage: CGImage?,
        into pixelBuffer: CVPixelBuffer,
        outputSize: CGSize,
        phase: Double,
        photoIndex: Int,
        previousPhotoIndex: Int,
        transitionProgress: Double,
        request: TripReelVideoExportRequest
    ) throws {
        try drawDirectly(into: pixelBuffer, outputSize: outputSize) { bounds in
            UIColor(red: 0.035, green: 0.025, blue: 0.020, alpha: 1).setFill()
            UIRectFill(bounds)

            if let previousItem, transitionProgress < 1 {
                drawContent(
                    previousItem,
                    photoImage: previousPhotoImage,
                    bounds: bounds,
                    phase: 1,
                    photoIndex: previousPhotoIndex,
                    alpha: 1 - transitionProgress,
                    request: request
                )
            }

            drawContent(
                item,
                photoImage: photoImage,
                bounds: bounds,
                phase: phase,
                photoIndex: photoIndex,
                alpha: transitionProgress,
                request: request
            )

            if request.quality.includesWatermark {
                drawWatermark(in: bounds)
            }
        }
    }

    /// Draws UIKit artwork straight into a top-to-bottom video frame without
    /// allocating a second full-resolution image.
    static func drawDirectly(
        into pixelBuffer: CVPixelBuffer,
        outputSize: CGSize,
        drawing: (CGRect) -> Void
    ) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: Int(outputSize.width),
                height: Int(outputSize.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            throw TripReelVideoExportError.cannotCreateFrame
        }

        // Draw directly into AVAssetWriter's buffer. The previous path first
        // created a second 1080p UIKit image for every frame and then copied it,
        // briefly doubling frame memory. That spike was enough for iOS to deny
        // a new pixel buffer when an HD export continued in the background.
        context.translateBy(x: 0, y: outputSize.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        autoreleasepool {
            let bounds = CGRect(origin: .zero, size: outputSize)
            drawing(bounds)
        }
    }

    /// AVAssetWriter can still own the most recently appended buffers after
    /// its input reports ready. Give that short-lived pressure time to clear
    /// instead of failing an otherwise healthy export on the first allocation.
    private static func makePixelBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var lastStatus = kCVReturnError
        for attempt in 0..<8 {
            var optionalBuffer: CVPixelBuffer?
            lastStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
            if lastStatus == kCVReturnSuccess, let optionalBuffer {
                return optionalBuffer
            }

            guard lastStatus == kCVReturnAllocationFailed
                    || lastStatus == kCVReturnWouldExceedAllocationThreshold else {
                break
            }
            CVPixelBufferPoolFlush(pool, .excessBuffers)
            Thread.sleep(forTimeInterval: 0.004 * Double(attempt + 1))
        }
        throw TripReelVideoExportError.cannotCreateFrame
    }

    private static func drawContent(
        _ item: MontageTimelineItem,
        photoImage: CGImage?,
        bounds: CGRect,
        phase: Double,
        photoIndex: Int,
        alpha: Double,
        request: TripReelVideoExportRequest
    ) {
        guard alpha > 0 else { return }
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setAlpha(CGFloat(min(1, max(0, alpha))))
        defer { context?.restoreGState() }

        switch item {
        case let .photo(photo):
            if let photoImage {
                drawPhoto(
                    photo,
                    image: photoImage,
                    bounds: bounds,
                    phase: easedMotionPhase(phase),
                    index: photoIndex,
                    look: request.look,
                    intensity: photo.isVideo ? .still : request.motionIntensity
                )
            }
            if let overlay = request.textOverlays.first(where: { $0.photoID == photo.id }) {
                drawTextOverlay(overlay, bounds: bounds, phase: phase)
            }
        case let .title(card):
            drawTitle(
                card,
                background: photoImage,
                bounds: bounds,
                phase: easedMotionPhase(phase)
            )
        }
    }

    static func easedMotionPhase(_ phase: Double) -> Double {
        let progress = min(1, max(0, phase))
        return progress * progress * (3 - (2 * progress))
    }

    static func transitionProgress(frame: Int, transitionFrames: Int) -> Double {
        guard transitionFrames > 0 else { return 1 }
        return easedMotionPhase(Double(max(0, frame)) / Double(transitionFrames))
    }

    static func sourceVideoGeometry(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        maximumSize: CGSize
    ) -> (transform: CGAffineTransform, renderSize: CGSize) {
        let transformedBounds = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let orientedSize = CGSize(
            width: abs(transformedBounds.width),
            height: abs(transformedBounds.height)
        )
        let scale = min(
            1,
            min(
                maximumSize.width / max(1, orientedSize.width),
                maximumSize.height / max(1, orientedSize.height)
            )
        )
        let renderSize = CGSize(
            width: evenDimension(orientedSize.width * scale),
            height: evenDimension(orientedSize.height * scale)
        )
        var transform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -transformedBounds.minX,
                y: -transformedBounds.minY
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(scaleX: scale, y: scale)
        )
        return (transform, renderSize)
    }

    private static func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded - 1)
    }

    /// Copies an already top-to-bottom UIKit image into the equally oriented
    /// video buffer. Applying an additional Quartz Y-axis flip here turns the
    /// final encoded movie upside down.
    static func copyRenderedFrame(
        _ image: CGImage,
        into pixelBuffer: CVPixelBuffer,
        outputSize: CGSize
    ) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: Int(outputSize.width),
                height: Int(outputSize.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw TripReelVideoExportError.cannotCreateFrame
        }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(origin: .zero, size: outputSize))
    }

    private static func drawPhoto(
        _ photo: ReelPhoto,
        image: CGImage,
        bounds: CGRect,
        phase: Double,
        index: Int,
        look: MontageLook,
        intensity: MontageMotionIntensity
    ) {
        let style = MontageFrameResolver.resolve(
            planned: photo.frameStyle,
            aspectRatio: photo.aspectRatio,
            index: index,
            isCustomized: photo.hasCustomFrameStyle,
            look: look,
            protectsPeople: photo.protectsPeople
        )
        let motion = motionTransform(
            for: photo.motionStyle,
            phase: phase,
            intensity: intensity,
            bounds: bounds
        )
        switch style {
        case .fullBleed:
            drawImage(
                image,
                in: bounds,
                fill: true,
                scale: photo.cropScale * motion.scale,
                offsetX: photo.cropOffsetX + motion.offsetX,
                offsetY: photo.cropOffsetY + motion.offsetY
            )
        case .portraitMatte:
            drawImage(image, in: bounds, fill: true, scale: 1.12, alpha: 0.42)
            UIColor.black.withAlphaComponent(0.35).setFill()
            UIRectFill(bounds)
            let frame = aspectFitRect(
                imageSize: CGSize(width: image.width, height: image.height),
                inside: bounds.insetBy(
                    dx: bounds.width * 0.03,
                    dy: bounds.height * 0.06
                )
            )
            drawImage(
                image,
                in: frame,
                fill: false,
                scale: photo.usesAutomaticPeopleFraming
                    ? 1
                    : photo.cropScale * motion.scale,
                offsetX: photo.usesAutomaticPeopleFraming
                    ? 0
                    : photo.cropOffsetX + motion.offsetX,
                offsetY: photo.usesAutomaticPeopleFraming
                    ? 0
                    : photo.cropOffsetY + motion.offsetY,
                clips: true
            )
            UIColor.white.withAlphaComponent(0.22).setStroke()
            UIBezierPath(roundedRect: frame, cornerRadius: 4).stroke()
        case .cinematic:
            let frame = CGRect(
                x: 0,
                y: bounds.height * 0.19,
                width: bounds.width,
                height: bounds.height * 0.62
            )
            drawImage(
                image,
                in: frame,
                fill: false,
                scale: photo.usesAutomaticPeopleFraming
                    ? 1
                    : photo.cropScale * motion.scale,
                offsetX: photo.usesAutomaticPeopleFraming
                    ? 0
                    : photo.cropOffsetX + motion.offsetX,
                offsetY: photo.usesAutomaticPeopleFraming
                    ? 0
                    : photo.cropOffsetY + motion.offsetY,
                clips: true
            )
            drawFilmEdges(in: bounds)
        case .postcard:
            drawImage(image, in: bounds, fill: true, scale: 1.08, alpha: 0.30)
            UIColor.black.withAlphaComponent(0.42).setFill()
            UIRectFill(bounds)
            let card = bounds.insetBy(dx: bounds.width * 0.085, dy: bounds.height * 0.15)
            UIColor(red: 0.992, green: 0.980, blue: 0.956, alpha: 1).setFill()
            UIBezierPath(roundedRect: card, cornerRadius: 7).fill()
            let imageFrame = CGRect(
                x: card.minX + 15,
                y: card.minY + 15,
                width: card.width - 30,
                height: card.height - 90
            )
            drawImage(
                image,
                in: imageFrame,
                fill: false,
                scale: photo.cropScale * motion.scale,
                offsetX: photo.cropOffsetX + motion.offsetX,
                offsetY: photo.cropOffsetY + motion.offsetY,
                clips: true
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                .foregroundColor: UIColor.black.withAlphaComponent(0.60)
            ]
            NSString(string: photo.label).draw(
                in: CGRect(x: card.minX + 22, y: card.maxY - 58, width: card.width - 44, height: 26),
                withAttributes: attributes
            )
        }
    }

    private static func drawTitle(
        _ card: MontageTitleCard,
        background: CGImage?,
        bounds: CGRect,
        phase: Double
    ) {
        if let background {
            drawImage(background, in: bounds, fill: true, scale: 1.06, alpha: 0.24)
        }
        let context = UIGraphicsGetCurrentContext()
        let colors = [
            UIColor(red: 0.13, green: 0.065, blue: 0.028, alpha: 0.96).cgColor,
            UIColor(red: 0.025, green: 0.019, blue: 0.016, alpha: 0.97).cgColor
        ] as CFArray
        if let context,
           let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
           ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bounds.minX, y: bounds.minY),
                end: CGPoint(x: bounds.maxX, y: bounds.maxY),
                options: []
            )
        }

        let baseTitleSize: CGFloat = card.kind == .opening ? 70 : 59
        let titleFont: UIFont
        let displayTitle: String
        let titleTracking: CGFloat
        switch card.style {
        case .editorial:
            titleFont = UIFont(name: "InstrumentSerif-Regular", size: baseTitleSize)
                ?? UIFont.systemFont(ofSize: baseTitleSize, weight: .regular)
            displayTitle = card.title
            titleTracking = -0.6
        case .clean:
            titleFont = UIFont.systemFont(ofSize: baseTitleSize * 0.74, weight: .semibold)
            displayTitle = card.title
            titleTracking = 0
        case .bold:
            titleFont = UIFont.systemFont(ofSize: baseTitleSize * 0.78, weight: .black)
            displayTitle = card.title.uppercased()
            titleTracking = 0
        }
        let titleReveal = staggeredReveal(phase, start: 0.05, duration: 0.34)
        drawCenteredText(
            displayTitle,
            in: CGRect(x: 54, y: bounds.midY - 88 + CGFloat(phase * -8), width: bounds.width - 108, height: 180),
            font: titleFont,
            color: UIColor(red: 0.992, green: 0.980, blue: 0.956, alpha: titleReveal),
            tracking: titleTracking
        )
        let subtitleFont: UIFont
        switch card.style {
        case .editorial:
            subtitleFont = UIFont.systemFont(ofSize: 20, weight: .medium)
        case .clean:
            subtitleFont = UIFont.systemFont(ofSize: 18, weight: .regular)
        case .bold:
            subtitleFont = UIFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
        }
        drawCenteredText(
            card.subtitle,
            in: CGRect(x: 58, y: bounds.midY + 102 + CGFloat(phase * -8), width: bounds.width - 116, height: 55),
            font: subtitleFont,
            color: UIColor.white.withAlphaComponent(
                0.58 * staggeredReveal(phase, start: 0.18, duration: 0.34)
            ),
            tracking: 0
        )
    }

    private static func drawTextOverlay(
        _ overlay: MontageTextOverlay,
        bounds: CGRect,
        phase: Double
    ) {
        let reveal = staggeredReveal(phase, start: 0.06, duration: 0.28)
        guard reveal > 0 else { return }
        let baseSize: CGFloat = bounds.width * 0.060
        let font: UIFont
        let text: String
        switch overlay.style {
        case .editorial:
            font = UIFont(name: "InstrumentSerif-Regular", size: baseSize * 1.22)
                ?? UIFont.systemFont(ofSize: baseSize * 1.22, weight: .regular)
            text = overlay.text
        case .clean:
            font = UIFont.systemFont(ofSize: baseSize, weight: .semibold)
            text = overlay.text
        case .bold:
            font = UIFont.systemFont(ofSize: baseSize, weight: .black)
            text = overlay.text.uppercased()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.992, green: 0.980, blue: 0.956, alpha: reveal),
            .paragraphStyle: paragraph,
            .kern: overlay.style == .editorial ? -0.4 : 0
        ]
        let horizontalMargin = bounds.width * 0.085
        let textWidth = bounds.width - (horizontalMargin * 2) - 40
        let measured = NSString(string: text).boundingRect(
            with: CGSize(width: textWidth, height: bounds.height * 0.30),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let textHeight = min(bounds.height * 0.24, ceil(measured.height))
        let baseY: CGFloat
        switch overlay.placement {
        case .top: baseY = bounds.height * 0.105
        case .center: baseY = bounds.midY - (textHeight / 2)
        case .bottom: baseY = bounds.height * 0.73 - textHeight
        }
        let rise = overlay.animation == .rise ? (1 - reveal) * 34 : 0
        let textRect = CGRect(
            x: horizontalMargin + 20,
            y: baseY + rise,
            width: textWidth,
            height: textHeight + 4
        )
        let backgroundRect = textRect.insetBy(dx: -20, dy: -14)
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        defer { context?.restoreGState() }
        if overlay.animation == .pop {
            let scale = 0.88 + (0.12 * reveal)
            context?.translateBy(x: backgroundRect.midX, y: backgroundRect.midY)
            context?.scaleBy(x: scale, y: scale)
            context?.translateBy(x: -backgroundRect.midX, y: -backgroundRect.midY)
        }
        UIColor.black.withAlphaComponent(0.58 * reveal).setFill()
        UIBezierPath(
            roundedRect: backgroundRect,
            cornerRadius: max(14, backgroundRect.height * 0.16)
        ).fill()
        UIColor.white.withAlphaComponent(0.16 * reveal).setStroke()
        let border = UIBezierPath(
            roundedRect: backgroundRect.insetBy(dx: 1, dy: 1),
            cornerRadius: max(13, backgroundRect.height * 0.16)
        )
        border.lineWidth = 1.5
        border.stroke()
        NSString(string: text).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
    }

    private static func staggeredReveal(
        _ phase: Double,
        start: Double,
        duration: Double
    ) -> CGFloat {
        let local = min(1, max(0, (phase - start) / max(0.001, duration)))
        return CGFloat(local * local * (3 - (2 * local)))
    }

    private static func drawCenteredText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        tracking: CGFloat
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        NSString(string: text).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style,
                .kern: tracking
            ],
            context: nil
        )
    }

    private static func drawWatermark(in bounds: CGRect) {
        let text = "Made with Memories"
        let fontSize = max(24, bounds.width * 0.038)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor(red: 0.992, green: 0.980, blue: 0.956, alpha: 1)
        ]
        let size = NSString(string: text).size(withAttributes: attributes)
        let horizontalPadding = fontSize * 0.62
        let verticalPadding = fontSize * 0.42
        let margin = bounds.width * 0.045
        let capsule = CGRect(
            x: bounds.maxX - size.width - (horizontalPadding * 2) - margin,
            y: margin,
            width: size.width + (horizontalPadding * 2),
            height: size.height + (verticalPadding * 2)
        )
        UIColor.black.withAlphaComponent(0.76).setFill()
        UIBezierPath(
            roundedRect: capsule,
            cornerRadius: capsule.height / 2
        ).fill()
        UIColor(red: 0.94, green: 0.71, blue: 0.37, alpha: 0.92).setStroke()
        let border = UIBezierPath(
            roundedRect: capsule.insetBy(dx: 1.5, dy: 1.5),
            cornerRadius: (capsule.height - 3) / 2
        )
        border.lineWidth = 3
        border.stroke()
        NSString(string: text).draw(
            at: CGPoint(
                x: capsule.minX + horizontalPadding,
                y: capsule.minY + verticalPadding
            ),
            withAttributes: attributes
        )
    }

    private static func drawFilmEdges(in bounds: CGRect) {
        UIColor.white.withAlphaComponent(0.16).setFill()
        let width = bounds.width / 13
        for index in 0..<12 {
            let x = CGFloat(index) * width + 6
            UIRectFill(CGRect(x: x, y: 22, width: width * 0.65, height: 8))
            UIRectFill(CGRect(x: x, y: bounds.maxY - 30, width: width * 0.65, height: 8))
        }
    }

    private static func drawImage(
        _ image: CGImage,
        in frame: CGRect,
        fill: Bool,
        scale extraScale: Double,
        offsetX: Double = 0,
        offsetY: Double = 0,
        alpha: CGFloat = 1,
        clips: Bool = false
    ) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let baseScale = fill
            ? max(frame.width / imageSize.width, frame.height / imageSize.height)
            : min(frame.width / imageSize.width, frame.height / imageSize.height)
        let scale = baseScale * CGFloat(max(1, extraScale))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: frame.midX - size.width / 2 + CGFloat(offsetX) * frame.width * 0.24,
            y: frame.midY - size.height / 2 + CGFloat(offsetY) * frame.height * 0.24
        )
        let drawRect = CGRect(origin: origin, size: size)
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        if clips { UIBezierPath(rect: frame).addClip() }
        context?.setAlpha(alpha)
        UIImage(cgImage: image).draw(in: drawRect)
        context?.restoreGState()
    }

    private static func aspectFitRect(imageSize: CGSize, inside bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func motionTransform(
        for style: MontageMotionStyle,
        phase: Double,
        intensity: MontageMotionIntensity,
        bounds: CGRect
    ) -> (scale: Double, offsetX: Double, offsetY: Double) {
        let amplitude = intensity.amplitude
        let centered = (phase * 2) - 1
        switch style {
        case .zoomIn:
            return (1 + phase * 0.085 * amplitude, -0.025 * phase * amplitude, 0)
        case .zoomOut:
            return (1 + (1 - phase) * 0.085 * amplitude, 0.022 * centered * amplitude, 0)
        case .panLeft:
            return (1 + 0.075 * amplitude, -0.15 * centered * amplitude, 0)
        case .panRight:
            return (1 + 0.075 * amplitude, 0.15 * centered * amplitude, 0)
        case .rise:
            return (1 + phase * 0.055 * amplitude, 0, -0.12 * centered * amplitude)
        case .settle:
            return (1 + (1 - phase) * 0.06 * amplitude, 0, 0.04 * (1 - phase) * amplitude)
        }
    }
}

private enum VideoPhotoPreparationError: Error {
    case noFinalImage
    case cannotDecodeData
    case stalled
}

private final class VideoImageRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private let manager: PHImageManager
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var requestID = PHInvalidImageRequestID
    private var completed = false

    init(manager: PHImageManager) {
        self.manager = manager
    }

    func install(continuation: CheckedContinuation<CGImage, Error>) {
        lock.lock()
        if completed {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(requestID: PHImageRequestID) {
        lock.lock()
        if completed {
            lock.unlock()
            manager.cancelImageRequest(requestID)
            return
        }
        self.requestID = requestID
        lock.unlock()
    }

    func finish(_ result: Result<CGImage, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() { fail(CancellationError()) }

    /// Cancels the underlying PhotoKit request and resumes with `error`.
    func fail(_ error: Error) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let requestID = requestID
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
        continuation?.resume(throwing: error)
    }
}

private final class VideoAssetPreparationState: @unchecked Sendable {
    private let lock = NSLock()
    private let manager: PHImageManager
    private var continuation: CheckedContinuation<AVAsset, Error>?
    private var requestID = PHInvalidImageRequestID
    private var completed = false

    init(manager: PHImageManager) {
        self.manager = manager
    }

    func install(continuation: CheckedContinuation<AVAsset, Error>) {
        lock.lock()
        if completed {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(requestID: PHImageRequestID) {
        lock.lock()
        if completed {
            lock.unlock()
            manager.cancelImageRequest(requestID)
            return
        }
        self.requestID = requestID
        lock.unlock()
    }

    func finish(_ result: Result<AVAsset, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() { fail(CancellationError()) }

    /// Cancels the underlying PhotoKit request and resumes with `error`.
    func fail(_ error: Error) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = continuation
        self.continuation = nil
        let requestID = requestID
        lock.unlock()
        if requestID != PHInvalidImageRequestID { manager.cancelImageRequest(requestID) }
        continuation?.resume(throwing: error)
    }
}
