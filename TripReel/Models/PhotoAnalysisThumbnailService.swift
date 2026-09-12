import AVFoundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

struct PreparedPhotoThumbnail: @unchecked Sendable {
    let id: String
    let cgImage: CGImage
    let jpegData: Data
}

protocol PhotoAnalysisThumbnailServing: Sendable {
    func prepare(asset: TripAsset) async throws -> PreparedPhotoThumbnail
    func prepareVideoFrame(asset: TripAsset) async throws -> PreparedPhotoThumbnail
}

extension PhotoAnalysisThumbnailServing {
    func prepareVideoFrame(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        try await prepare(asset: asset)
    }
}

enum PhotoAnalysisThumbnailError: LocalizedError {
    case unavailable
    case inaccessible
    case decodeFailed
    case encodeFailed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: "The photo is not available right now."
        case .inaccessible: "The photo is no longer available to Memories."
        case .decodeFailed: "Memories couldn't read the photo."
        case .encodeFailed: "Memories couldn't prepare a private thumbnail."
        case .tooLarge: "The reduced thumbnail exceeded Memories' upload limit."
        }
    }
}

/// Produces a small, orientation-normalized JPEG without EXIF or location
/// metadata. The same in-memory thumbnail is used for local Vision analysis and,
/// only after explicit consent, the optional cloud review.
final class PhotoAnalysisThumbnailService: PhotoAnalysisThumbnailServing, @unchecked Sendable {
    static let maximumPixelSize = 512
    static let maximumJPEGBytes = CloudPhotoAnalysisClient.maximumThumbnailBytes
    static let maximumVideoPixelSize = 1_024
    static let maximumVideoJPEGBytes = 384 * 1_024

    private let imageManager: PHImageManager

    init(imageManager: PHImageManager = PHCachingImageManager()) {
        self.imageManager = imageManager
    }

    func prepare(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        try await prepare(
            asset: asset,
            maximumPixelSize: Self.maximumPixelSize,
            maximumJPEGBytes: Self.maximumJPEGBytes
        )
    }

    func prepareVideoFrame(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        try await prepare(
            asset: asset,
            maximumPixelSize: Self.maximumVideoPixelSize,
            maximumJPEGBytes: Self.maximumVideoJPEGBytes
        )
    }

    private func prepare(
        asset: TripAsset,
        maximumPixelSize: Int,
        maximumJPEGBytes: Int
    ) async throws -> PreparedPhotoThumbnail {
        try Task.checkCancellation()

        let cgImage: CGImage
        switch asset.source {
        case let .library(localIdentifier):
            let image = try await requestLibraryImage(
                localIdentifier: localIdentifier,
                maximumPixelSize: maximumPixelSize
            )
            cgImage = try Self.normalizedCGImage(from: image, maximumPixelSize: maximumPixelSize)
        case let .imported(path):
            cgImage = try await Self.fileThumbnail(path: path, maximumPixelSize: maximumPixelSize)
        case let .bundled(name):
            guard let image = UIImage(named: name) else {
                throw PhotoAnalysisThumbnailError.unavailable
            }
            cgImage = try Self.normalizedCGImage(from: image, maximumPixelSize: maximumPixelSize)
        }

        try Task.checkCancellation()
        let jpegData = try [0.78, 0.66, 0.54, 0.42]
            .lazy
            .map { try Self.encodeMetadataStrippedJPEG(cgImage, quality: $0) }
            .first(where: { $0.count <= maximumJPEGBytes })
        guard let jpegData else { throw PhotoAnalysisThumbnailError.tooLarge }
        return PreparedPhotoThumbnail(id: asset.id, cgImage: cgImage, jpegData: jpegData)
    }

    private func requestLibraryImage(
        localIdentifier: String,
        maximumPixelSize: Int
    ) async throws -> UIImage {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw PhotoAnalysisThumbnailError.inaccessible
        }

        // PhotoKit can transiently finish a thumbnail request without a final
        // image while an optimized library hands the asset off from iCloud.
        // Retry once, then fall back to source-data delivery and decode only a
        // 512 px thumbnail. The original is never retained by TripReel.
        for delay in [UInt64(0), 500_000_000] {
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            do {
                return try await requestLibraryThumbnail(
                    asset: asset,
                    maximumPixelSize: maximumPixelSize
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        try await Task.sleep(nanoseconds: 800_000_000)
        do {
            return try await requestLibraryImageData(
                asset: asset,
                maximumPixelSize: maximumPixelSize
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PhotoAnalysisThumbnailError.unavailable
        }
    }

    private func requestLibraryThumbnail(
        asset: PHAsset,
        maximumPixelSize: Int
    ) async throws -> UIImage {
        let requestState = PhotoKitImageRequestState(manager: imageManager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requestState.install(continuation: continuation)

                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.version = .current
                options.isNetworkAccessAllowed = true

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: maximumPixelSize, height: maximumPixelSize),
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        requestState.finish(with: .failure(CancellationError()))
                        return
                    }
                    if let error = info?[PHImageErrorKey] as? Error {
                        requestState.finish(with: .failure(error))
                        return
                    }
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true {
                        return
                    }
                    guard let image else {
                        requestState.finish(with: .failure(PhotoAnalysisThumbnailError.unavailable))
                        return
                    }
                    requestState.finish(with: .success(image))
                }
                requestState.install(requestID: requestID)
            }
        } onCancel: {
            requestState.cancel()
        }
    }

    private func requestLibraryImageData(
        asset: PHAsset,
        maximumPixelSize: Int
    ) async throws -> UIImage {
        let requestState = PhotoKitImageRequestState(manager: imageManager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requestState.install(continuation: continuation)

                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.version = .current
                options.isNetworkAccessAllowed = true

                let requestID = imageManager.requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        requestState.finish(with: .failure(CancellationError()))
                        return
                    }
                    if let error = info?[PHImageErrorKey] as? Error {
                        requestState.finish(with: .failure(error))
                        return
                    }
                    guard let data,
                          let source = CGImageSourceCreateWithData(
                            data as CFData,
                            [kCGImageSourceShouldCache: false] as CFDictionary
                          ),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                            source,
                            0,
                            [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                                kCGImageSourceShouldCacheImmediately: true
                            ] as CFDictionary
                          ) else {
                        requestState.finish(with: .failure(PhotoAnalysisThumbnailError.decodeFailed))
                        return
                    }
                    requestState.finish(with: .success(UIImage(cgImage: thumbnail)))
                }
                requestState.install(requestID: requestID)
            }
        } onCancel: {
            requestState.cancel()
        }
    }

    private static func fileThumbnail(
        path: String,
        maximumPixelSize: Int
    ) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw PhotoAnalysisThumbnailError.decodeFailed
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw PhotoAnalysisThumbnailError.decodeFailed
            }
            return image
        }.value
    }

    private static func normalizedCGImage(
        from image: UIImage,
        maximumPixelSize: Int
    ) throws -> CGImage {
        let pixelSize = CGSize(
            width: max(1, image.size.width * image.scale),
            height: max(1, image.size.height * image.scale)
        )
        let scale = min(1, CGFloat(maximumPixelSize) / max(pixelSize.width, pixelSize.height))
        let outputSize = CGSize(
            width: max(1, (pixelSize.width * scale).rounded()),
            height: max(1, (pixelSize.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: CGRect(origin: .zero, size: outputSize))
        }
        guard let cgImage = normalized.cgImage else {
            throw PhotoAnalysisThumbnailError.decodeFailed
        }
        return cgImage
    }

    static func encodeMetadataStrippedJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoAnalysisThumbnailError.encodeFailed
        }

        // Supplying only an encoding quality deliberately omits source EXIF,
        // filename, timestamps, camera data, and GPS metadata.
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoAnalysisThumbnailError.encodeFailed
        }
        return try strippingMetadataSegments(from: mutableData as Data)
    }

    /// ImageIO adds empty EXIF and Photoshop application segments even when the
    /// source is a metadata-free CGImage. Remove those marker blocks so neither
    /// accidental source metadata nor encoder boilerplate crosses the network.
    /// The proxy independently rejects any forbidden marker that remains.
    static func strippingMetadataSegments(from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 4,
              bytes[0] == 0xFF,
              bytes[1] == 0xD8,
              bytes[bytes.count - 2] == 0xFF,
              bytes[bytes.count - 1] == 0xD9 else {
            throw PhotoAnalysisThumbnailError.encodeFailed
        }

        var output: [UInt8] = [0xFF, 0xD8]
        output.reserveCapacity(bytes.count)
        var offset = 2

        while offset < bytes.count {
            let markerStart = offset
            guard bytes[offset] == 0xFF else {
                throw PhotoAnalysisThumbnailError.encodeFailed
            }
            while offset < bytes.count, bytes[offset] == 0xFF {
                offset += 1
            }
            guard offset < bytes.count else {
                throw PhotoAnalysisThumbnailError.encodeFailed
            }

            let marker = bytes[offset]
            offset += 1

            // Once scan data begins, preserve its byte-stuffed entropy stream
            // verbatim. ImageIO writes all application metadata before SOS.
            if marker == 0xDA {
                guard offset + 1 < bytes.count else {
                    throw PhotoAnalysisThumbnailError.encodeFailed
                }
                let length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
                guard length >= 2, offset + length <= bytes.count else {
                    throw PhotoAnalysisThumbnailError.encodeFailed
                }
                output.append(contentsOf: bytes[markerStart...])
                return Data(output)
            }

            guard marker != 0x00,
                  marker != 0xD8,
                  marker != 0xD9,
                  marker != 0x01,
                  !(0xD0...0xD7).contains(marker),
                  offset + 1 < bytes.count else {
                throw PhotoAnalysisThumbnailError.encodeFailed
            }

            let length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            guard length >= 2, offset + length <= bytes.count else {
                throw PhotoAnalysisThumbnailError.encodeFailed
            }
            let segmentEnd = offset + length

            // APP1 contains EXIF/XMP, APP13 contains IPTC/Photoshop data, and
            // COM is an arbitrary comment. None is needed for classification.
            if marker != 0xE1, marker != 0xED, marker != 0xFE {
                output.append(contentsOf: bytes[markerStart..<segmentEnd])
            }
            offset = segmentEnd
        }

        throw PhotoAnalysisThumbnailError.encodeFailed
    }
}

private final class PhotoKitImageRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private let manager: PHImageManager
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var requestID = PHInvalidImageRequestID
    private var completed = false

    init(manager: PHImageManager) {
        self.manager = manager
    }

    func install(continuation: CheckedContinuation<UIImage, Error>) {
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

    func finish(with result: Result<UIImage, Error>) {
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

    func cancel() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        let requestID = requestID
        lock.unlock()

        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
        continuation?.resume(throwing: CancellationError())
    }
}

struct VideoClipDescriptor: Hashable, Sendable {
    let startSeconds: Double
    let durationSeconds: Double
    let sourceDurationSeconds: Double
    let hasOriginalAudio: Bool
    let motionScore: Double

    init(
        startSeconds: Double,
        durationSeconds: Double,
        sourceDurationSeconds: Double,
        hasOriginalAudio: Bool,
        motionScore: Double
    ) {
        let sourceDuration = max(0, sourceDurationSeconds.isFinite ? sourceDurationSeconds : 0)
        let duration = min(max(0.8, durationSeconds), min(4, max(0.8, sourceDuration)))
        self.sourceDurationSeconds = sourceDuration
        self.durationSeconds = duration
        self.startSeconds = min(
            max(0, startSeconds.isFinite ? startSeconds : 0),
            max(0, sourceDuration - duration)
        )
        self.hasOriginalAudio = hasOriginalAudio
        self.motionScore = min(1, max(0, motionScore.isFinite ? motionScore : 0))
    }
}

struct VideoFrameEditorialScore: Hashable, Sendable {
    let timeSeconds: Double
    let memoryScore: Double
    let aestheticScore: Double
    let peopleCount: Int
    let utilityProbability: Double
    let documentProbability: Double
    let motionFromPrevious: Double
}

enum VideoClipHeuristics {
    static func choose(
        sourceDurationSeconds: Double,
        frames: [VideoFrameEditorialScore],
        hasOriginalAudio: Bool
    ) -> VideoClipDescriptor? {
        let sourceDuration = max(0, sourceDurationSeconds)
        guard sourceDuration >= 0.8, !frames.isEmpty else { return nil }

        let best = frames.max { editorialScore($0) < editorialScore($1) }!
        let targetDuration: Double
        if best.peopleCount >= 2 {
            targetDuration = 3.8
        } else if best.motionFromPrevious >= 0.22 {
            targetDuration = 2.8
        } else {
            targetDuration = 3.4
        }
        let duration = min(sourceDuration, targetDuration)
        let start = min(
            max(0, best.timeSeconds - (duration * 0.42)),
            max(0, sourceDuration - duration)
        )
        return VideoClipDescriptor(
            startSeconds: start,
            durationSeconds: duration,
            sourceDurationSeconds: sourceDuration,
            hasOriginalAudio: hasOriginalAudio,
            motionScore: best.motionFromPrevious
        )
    }

    private static func editorialScore(_ frame: VideoFrameEditorialScore) -> Double {
        let peopleBonus = min(0.18, Double(max(0, frame.peopleCount)) * 0.055)
        // Some motion makes a clip feel alive; extreme frame-to-frame change is
        // more likely to be a whip, shake, or accidental camera move.
        let motion = min(1, max(0, frame.motionFromPrevious))
        let motionValue = motion <= 0.34 ? motion * 0.34 : max(0, 0.116 - ((motion - 0.34) * 0.30))
        return (0.48 * frame.memoryScore)
            + (0.30 * frame.aestheticScore)
            + peopleBonus
            + motionValue
            - (0.24 * frame.utilityProbability)
            - (0.18 * frame.documentProbability)
    }
}

struct LocalVideoClipAnalysis: @unchecked Sendable {
    let descriptor: VideoClipDescriptor
    let representativeFrame: PreparedPhotoThumbnail
    let cloudContactSheet: PreparedPhotoThumbnail
    let nativeResult: NativePhotoIntelligenceResult
}

protocol VideoClipIntelligenceServing: Sendable {
    func analyze(
        asset: TripAsset,
        allowsNetworkAccess: Bool,
        nativeIntelligence: any NativePhotoIntelligenceServing
    ) async throws -> LocalVideoClipAnalysis
}

/// Samples a bounded set of frames and chooses one short, useful source window.
/// All Vision work and timing decisions stay on-device. The only cloud-ready
/// artifact is a metadata-stripped three-frame contact sheet.
actor VideoClipIntelligenceService: VideoClipIntelligenceServing {
    private let imageManager: PHImageManager

    init(imageManager: PHImageManager = PHCachingImageManager()) {
        self.imageManager = imageManager
    }

    func analyze(
        asset: TripAsset,
        allowsNetworkAccess: Bool,
        nativeIntelligence: any NativePhotoIntelligenceServing
    ) async throws -> LocalVideoClipAnalysis {
        guard asset.isVideo else {
            throw PhotoAnalysisThumbnailError.inaccessible
        }
        let source = try await requestVideoAsset(
            source: asset.source,
            allowsNetworkAccess: allowsNetworkAccess
        )
        let loadedDuration = try await source.load(.duration)
        let sourceDuration = CMTimeGetSeconds(loadedDuration)
        guard sourceDuration.isFinite, sourceDuration >= 0.8 else {
            throw PhotoAnalysisThumbnailError.decodeFailed
        }

        let generator = AVAssetImageGenerator(asset: source)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)

        let sampleCount = sourceDuration < 3 ? 3 : (sourceDuration < 12 ? 7 : 9)
        let sampleTimes = (0..<sampleCount).map { index -> Double in
            let fraction = 0.08 + (0.84 * Double(index) / Double(max(1, sampleCount - 1)))
            return min(max(0, sourceDuration * fraction), max(0, sourceDuration - 0.05))
        }

        var samples: [(time: Double, image: CGImage, result: NativePhotoIntelligenceResult, hash: [UInt8])] = []
        samples.reserveCapacity(sampleTimes.count)
        for time in sampleTimes {
            try Task.checkCancellation()
            let requested = CMTime(seconds: time, preferredTimescale: 600)
            let generated = try await generator.image(at: requested)
            let result = try await nativeIntelligence.analyze(
                cgImage: generated.image,
                orientation: .up,
                metadata: NativePhotoIntelligenceMetadata(
                    sourceIdentifier: asset.id,
                    isScreenshot: false
                )
            )
            samples.append((
                time: CMTimeGetSeconds(generated.actualTime),
                image: generated.image,
                result: result,
                hash: Self.luminanceHash(generated.image)
            ))
        }
        guard !samples.isEmpty else { throw PhotoAnalysisThumbnailError.decodeFailed }

        let hasAudio = !(try await source.loadTracks(withMediaType: .audio)).isEmpty
        let scored = samples.enumerated().map { index, sample in
            let previousHash = index > 0 ? samples[index - 1].hash : sample.hash
            return VideoFrameEditorialScore(
                timeSeconds: sample.time,
                memoryScore: sample.result.scores.memoryScore,
                aestheticScore: sample.result.scores.aestheticScore ?? 0.52,
                peopleCount: max(
                    sample.result.signals.faces.count,
                    sample.result.signals.humans.count
                ),
                utilityProbability: sample.result.scores.utilityProbability,
                documentProbability: sample.result.scores.documentProbability,
                motionFromPrevious: Self.hashDistance(sample.hash, previousHash)
            )
        }
        guard let descriptor = VideoClipHeuristics.choose(
            sourceDurationSeconds: sourceDuration,
            frames: scored,
            hasOriginalAudio: hasAudio
        ) else {
            throw PhotoAnalysisThumbnailError.decodeFailed
        }
        let targetTime = descriptor.startSeconds + (descriptor.durationSeconds * 0.42)
        let bestIndex = scored.indices.min { left, right in
            abs(scored[left].timeSeconds - targetTime)
                < abs(scored[right].timeSeconds - targetTime)
        } ?? 0
        let representative = try Self.preparedThumbnail(
            id: asset.id,
            image: samples[bestIndex].image,
            maximumBytes: PhotoAnalysisThumbnailService.maximumJPEGBytes
        )
        let contactIndices = Self.contactSheetIndices(
            sampleCount: samples.count,
            representativeIndex: bestIndex
        )
        let contactSheetImage = try Self.contactSheet(
            contactIndices.map { samples[$0].image }
        )
        let contactSheet = try Self.preparedThumbnail(
            id: asset.id,
            image: contactSheetImage,
            maximumBytes: PhotoAnalysisThumbnailService.maximumJPEGBytes
        )
        return LocalVideoClipAnalysis(
            descriptor: descriptor,
            representativeFrame: representative,
            cloudContactSheet: contactSheet,
            nativeResult: samples[bestIndex].result
        )
    }

    private func requestVideoAsset(
        source: PhotoSource,
        allowsNetworkAccess: Bool
    ) async throws -> AVAsset {
        switch source {
        case let .imported(path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw PhotoAnalysisThumbnailError.inaccessible
            }
            return AVURLAsset(url: url)
        case .bundled:
            throw PhotoAnalysisThumbnailError.inaccessible
        case let .library(identifier):
            return try await requestLibraryVideoAsset(
                identifier: identifier,
                allowsNetworkAccess: allowsNetworkAccess
            )
        }
    }

    private func requestLibraryVideoAsset(
        identifier: String,
        allowsNetworkAccess: Bool
    ) async throws -> AVAsset {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject, asset.mediaType == .video else {
            throw PhotoAnalysisThumbnailError.inaccessible
        }
        let state = PhotoKitVideoAssetRequestState(manager: imageManager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let options = PHVideoRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.version = .current
                options.isNetworkAccessAllowed = allowsNetworkAccess
                let requestID = imageManager.requestAVAsset(
                    forVideo: asset,
                    options: options
                ) { videoAsset, _, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        state.finish(.failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if let videoAsset {
                        state.finish(.success(videoAsset))
                    } else {
                        state.finish(.failure(PhotoAnalysisThumbnailError.unavailable))
                    }
                }
                state.install(requestID: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func preparedThumbnail(
        id: String,
        image: CGImage,
        maximumBytes: Int
    ) throws -> PreparedPhotoThumbnail {
        let data = try [0.72, 0.60, 0.48, 0.36]
            .lazy
            .map { try PhotoAnalysisThumbnailService.encodeMetadataStrippedJPEG(image, quality: $0) }
            .first { $0.count <= maximumBytes }
        guard let data else { throw PhotoAnalysisThumbnailError.tooLarge }
        return PreparedPhotoThumbnail(id: id, cgImage: image, jpegData: data)
    }

    private static func contactSheetIndices(
        sampleCount: Int,
        representativeIndex: Int
    ) -> [Int] {
        guard sampleCount > 1 else { return [0] }
        let candidates = [max(0, representativeIndex - 1), representativeIndex, min(sampleCount - 1, representativeIndex + 1)]
        var seen = Set<Int>()
        let unique = candidates.filter { seen.insert($0).inserted }
        if unique.count == 3 { return unique }
        return Array(Set(unique + [0, sampleCount - 1])).sorted().prefix(3).map { $0 }
    }

    private static func contactSheet(_ images: [CGImage]) throws -> CGImage {
        guard let first = images.first else { throw PhotoAnalysisThumbnailError.decodeFailed }
        let cellHeight = 256
        let cellWidth = max(120, min(256, Int((Double(first.width) / Double(max(1, first.height))) * Double(cellHeight))))
        let size = CGSize(width: cellWidth * images.count, height: cellHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, image) in images.enumerated() {
                let cell = CGRect(x: index * cellWidth, y: 0, width: cellWidth, height: cellHeight)
                let sourceSize = CGSize(width: image.width, height: image.height)
                let scale = min(
                    cell.width / max(1, sourceSize.width),
                    cell.height / max(1, sourceSize.height)
                )
                let fittedSize = CGSize(
                    width: sourceSize.width * scale,
                    height: sourceSize.height * scale
                )
                UIImage(cgImage: image).draw(
                    in: CGRect(
                        x: cell.midX - (fittedSize.width / 2),
                        y: cell.midY - (fittedSize.height / 2),
                        width: fittedSize.width,
                        height: fittedSize.height
                    )
                )
            }
        }
        guard let image = rendered.cgImage else { throw PhotoAnalysisThumbnailError.decodeFailed }
        return image
    }

    private static func luminanceHash(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 16 * 16)
        guard let context = CGContext(
            data: &pixels,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return pixels }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        return pixels
    }

    private static func hashDistance(_ left: [UInt8], _ right: [UInt8]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return 0 }
        let total = zip(left, right).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return min(1, Double(total) / (Double(left.count) * 255))
    }
}

private final class PhotoKitVideoAssetRequestState: @unchecked Sendable {
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

    func cancel() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = continuation
        self.continuation = nil
        let requestID = requestID
        lock.unlock()
        if requestID != PHInvalidImageRequestID { manager.cancelImageRequest(requestID) }
        continuation?.resume(throwing: CancellationError())
    }
}
