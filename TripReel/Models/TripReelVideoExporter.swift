import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

struct TripReelVideoExportRequest: Sendable {
    let photos: [ReelPhoto]
    let titleCards: [MontageTitleCard]
    let secondsPerPhoto: Double
    let look: MontageLook
    let motionIntensity: MontageMotionIntensity
    let quality: ExportQuality
    let soundtrackURL: URL?
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
    func saveToPhotoLibrary(_ url: URL) async throws
}

enum TripReelVideoExportError: LocalizedError, Sendable {
    case noPhotos
    case photoUnavailable(String)
    case cannotCreateWriter
    case cannotCreateFrame
    case encodingFailed(String)
    case soundtrackFailed
    case photosPermissionDenied
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPhotos:
            "Keep at least one photo before exporting."
        case let .photoUnavailable(label):
            "\(label) needs a little longer in Photos. TripReel tried again automatically and kept every edit safe. Check your connection, then retry the download."
        case .cannotCreateWriter:
            "TripReel couldn't start the video encoder on this device."
        case .cannotCreateFrame:
            "TripReel ran out of room while drawing a video frame."
        case let .encodingFailed(message):
            "The video encoder stopped: \(message)"
        case .soundtrackFailed:
            "The film was rendered, but the selected soundtrack couldn't be added. Pick another track or No music and try again."
        case .photosPermissionDenied:
            "Allow TripReel to add videos in Settings to save this film to Photos."
        case let .saveFailed(message):
            "Photos couldn't save this film: \(message)"
        }
    }
}

/// Renders the same photo/title timeline used by the SwiftUI preview into a
/// vertical H.264 movie. Images are decoded one at a time, so a large trip does
/// not retain a full-resolution copy of the whole library in memory.
final class TripReelVideoExporter: TripReelVideoExporting, @unchecked Sendable {
    private static let preparationProgressWeight = 0.28
    private static let renderingProgressWeight = 0.62
    private let imageManager: PHImageManager
    private let frameRate: Int32

    init(
        imageManager: PHImageManager = PHCachingImageManager(),
        frameRate: Int32 = 12
    ) {
        self.imageManager = imageManager
        self.frameRate = max(8, frameRate)
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
        let finalURL = directory.appendingPathComponent("TripReel-\(UUID().uuidString).mp4")
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
            let preparedPhotos = try await preparePhotos(
                request.photos,
                outputSize: Self.outputSize(for: request.quality),
                in: stagingDirectory,
                progress: progress
            )
            try await renderSilentVideo(
                request,
                preparedPhotos: preparedPhotos,
                to: silentURL,
                progress: progress
            )
            try Task.checkCancellation()
            if let soundtrackURL = request.soundtrackURL {
                progress(
                    TripReelVideoExportProgress(
                        fraction: 0.91,
                        phase: .addingSoundtrack
                    )
                )
                try await addSoundtrack(
                    soundtrackURL,
                    toVideoAt: silentURL,
                    outputURL: finalURL
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

    private func renderSilentVideo(
        _ request: TripReelVideoExportRequest,
        preparedPhotos: [String: URL],
        to outputURL: URL,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws {
        let outputSize = Self.outputSize(for: request.quality)
        progress(
            TripReelVideoExportProgress(
                fraction: Self.preparationProgressWeight,
                phase: .rendering
            )
        )
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        var writerCompleted = false
        defer {
            if !writerCompleted { writer.cancelWriting() }
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
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2
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

        let timeline = MontageTimelineBuilder.make(
            photos: request.photos,
            titleCards: request.titleCards
        )
        let photoIndices = Dictionary(
            uniqueKeysWithValues: request.photos.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        let totalFrames = timeline.reduce(0) { partial, item in
            partial + max(1, Int(ceil(item.duration(defaultPhotoDuration: request.secondsPerPhoto) * Double(frameRate))))
        }
        var completedFrames = 0
        var lastPhotoImage: CGImage?
        var previousItem: MontageTimelineItem?
        var previousItemImage: CGImage?
        var previousItemPhotoIndex = 0

        for item in timeline {
            try Task.checkCancellation()
            let duration = item.duration(defaultPhotoDuration: request.secondsPerPhoto)
            let frameCount = max(1, Int(ceil(duration * Double(frameRate))))
            let photoImage: CGImage?
            let itemPhotoIndex: Int
            switch item {
            case let .photo(photo):
                photoImage = try await loadImage(
                    for: photo,
                    preparedPhotos: preparedPhotos,
                    targetSize: outputSize
                )
                lastPhotoImage = photoImage
                itemPhotoIndex = photoIndices[photo.id] ?? 0
            case .title:
                photoImage = lastPhotoImage
                itemPhotoIndex = 0
            }

            for localFrame in 0..<frameCount {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                guard let pool = adaptor.pixelBufferPool else {
                    throw TripReelVideoExportError.cannotCreateFrame
                }
                var optionalBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                      let pixelBuffer = optionalBuffer else {
                    throw TripReelVideoExportError.cannotCreateFrame
                }

                let phase = frameCount <= 1 ? 1 : Double(localFrame) / Double(frameCount - 1)
                let transitionFrames = previousItem == nil
                    ? 0
                    : min(frameCount - 1, max(2, Int((0.24 * Double(frameRate)).rounded())))
                let transitionProgress = Self.transitionProgress(
                    frame: localFrame,
                    transitionFrames: transitionFrames
                )
                try autoreleasepool {
                    try Self.draw(
                        item: item,
                        photoImage: photoImage,
                        previousItem: previousItem,
                        previousPhotoImage: previousItemImage,
                        into: pixelBuffer,
                        outputSize: outputSize,
                        phase: phase,
                        photoIndex: itemPhotoIndex,
                        previousPhotoIndex: previousItemPhotoIndex,
                        transitionProgress: transitionProgress,
                        request: request
                    )
                }
                let presentationTime = CMTime(value: CMTimeValue(completedFrames), timescale: frameRate)
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw TripReelVideoExportError.encodingFailed(
                        writer.error?.localizedDescription ?? "A frame could not be written"
                    )
                }
                completedFrames += 1
                if completedFrames.isMultiple(of: 6) || completedFrames == totalFrames {
                    let renderFraction = Double(completedFrames) / Double(max(1, totalFrames))
                    progress(
                        TripReelVideoExportProgress(
                            fraction: min(
                                0.90,
                                Self.preparationProgressWeight
                                    + (renderFraction * Self.renderingProgressWeight)
                            ),
                            phase: .rendering
                        )
                    )
                }
            }

            previousItem = item
            previousItemImage = photoImage
            previousItemPhotoIndex = itemPhotoIndex
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw TripReelVideoExportError.encodingFailed(
                writer.error?.localizedDescription ?? "The file could not be finalized"
            )
        }
        writerCompleted = true
    }

    private func preparePhotos(
        _ photos: [ReelPhoto],
        outputSize: CGSize,
        in directory: URL,
        progress: @escaping @Sendable (TripReelVideoExportProgress) -> Void
    ) async throws -> [String: URL] {
        let total = photos.count
        var prepared: [String: URL] = [:]
        prepared.reserveCapacity(total)
        progress(
            TripReelVideoExportProgress(
                fraction: 0,
                phase: .preparingPhotos(
                    ready: 0,
                    total: total,
                    currentLabel: photos.first?.label,
                    downloadProgress: nil
                )
            )
        )

        for (index, photo) in photos.enumerated() {
            try Task.checkCancellation()
            let preparationProgress: @Sendable (Double?) -> Void = { downloadProgress in
                let itemProgress = downloadProgress ?? 0
                let fraction = total == 0
                    ? Self.preparationProgressWeight
                    : ((Double(index) + itemProgress) / Double(total))
                        * Self.preparationProgressWeight
                progress(
                    TripReelVideoExportProgress(
                        fraction: fraction,
                        phase: .preparingPhotos(
                            ready: index,
                            total: total,
                            currentLabel: photo.label,
                            downloadProgress: downloadProgress
                        )
                    )
                )
            }
            preparationProgress(nil)
            let requestSize = Self.photoRequestSize(for: photo, outputSize: outputSize)
            let image = try await prepareImage(
                for: photo,
                targetSize: requestSize,
                progress: preparationProgress
            )
            let fileURL = directory.appendingPathComponent(
                String(format: "photo-%04d.jpg", index)
            )
            try Self.writePreparedImage(image, to: fileURL)
            prepared[photo.id] = fileURL
            progress(
                TripReelVideoExportProgress(
                    fraction: (Double(index + 1) / Double(max(1, total)))
                        * Self.preparationProgressWeight,
                    phase: .preparingPhotos(
                        ready: index + 1,
                        total: total,
                        currentLabel: index + 1 < total ? photos[index + 1].label : nil,
                        downloadProgress: nil
                    )
                )
            )
        }
        return prepared
    }

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

    private func requestLibraryImage(
        asset: PHAsset,
        targetSize: CGSize,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> CGImage {
        let state = VideoImageRequestState(manager: imageManager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.version = .current
                options.isNetworkAccessAllowed = true
                options.progressHandler = { value, _, _, _ in
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
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.version = .current
                options.isNetworkAccessAllowed = true
                options.progressHandler = { value, _, _, _ in
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
        preparedPhotos: [String: URL],
        targetSize _: CGSize
    ) async throws -> CGImage {
        guard let url = preparedPhotos[photo.id],
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

    private func addSoundtrack(
        _ soundtrackURL: URL,
        toVideoAt videoURL: URL,
        outputURL: URL
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: soundtrackURL)
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceVideoTrack = videoTracks.first,
              let sourceAudioTrack = audioTracks.first,
              audioDuration > .zero else {
            throw TripReelVideoExportError.soundtrackFailed
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TripReelVideoExportError.soundtrackFailed
        }
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )

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

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw TripReelVideoExportError.soundtrackFailed
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously { continuation.resume() }
        }
        guard exportSession.status == .completed else {
            if exportSession.status == .cancelled || Task.isCancelled {
                throw CancellationError()
            }
            throw TripReelVideoExportError.soundtrackFailed
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
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: rendererFormat)
        let rendered = renderer.image { rendererContext in
            let bounds = CGRect(origin: .zero, size: outputSize)
            UIColor(red: 0.035, green: 0.025, blue: 0.020, alpha: 1).setFill()
            rendererContext.fill(bounds)

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
        guard let cgImage = rendered.cgImage else {
            throw TripReelVideoExportError.cannotCreateFrame
        }

        try copyRenderedFrame(cgImage, into: pixelBuffer, outputSize: outputSize)
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
                    intensity: request.motionIntensity
                )
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

        let eyebrow = card.kind.name.uppercased()
        let eyebrowReveal = staggeredReveal(phase, start: 0, duration: 0.24)
        drawCenteredText(
            eyebrow,
            in: CGRect(x: 50, y: bounds.midY - 142 + CGFloat(phase * 6), width: bounds.width - 100, height: 30),
            font: UIFont.monospacedSystemFont(ofSize: 16, weight: .medium),
            color: UIColor(red: 0.94, green: 0.71, blue: 0.37, alpha: 0.86 * eyebrowReveal),
            tracking: 2.4
        )
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
        let text = "Made with TripReel"
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

    func cancel() {
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
        continuation?.resume(throwing: CancellationError())
    }
}
