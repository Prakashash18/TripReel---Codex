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

    private let imageManager: PHImageManager

    init(imageManager: PHImageManager = PHCachingImageManager()) {
        self.imageManager = imageManager
    }

    func prepare(asset: TripAsset) async throws -> PreparedPhotoThumbnail {
        try Task.checkCancellation()

        let cgImage: CGImage
        switch asset.source {
        case let .library(localIdentifier):
            let image = try await requestLibraryImage(localIdentifier: localIdentifier)
            cgImage = try Self.normalizedCGImage(from: image)
        case let .imported(path):
            cgImage = try await Self.fileThumbnail(path: path)
        case let .bundled(name):
            guard let image = UIImage(named: name) else {
                throw PhotoAnalysisThumbnailError.unavailable
            }
            cgImage = try Self.normalizedCGImage(from: image)
        }

        try Task.checkCancellation()
        let jpegData = try [0.72, 0.56, 0.42]
            .lazy
            .map { try Self.encodeMetadataStrippedJPEG(cgImage, quality: $0) }
            .first(where: { $0.count <= Self.maximumJPEGBytes })
        guard let jpegData else { throw PhotoAnalysisThumbnailError.tooLarge }
        return PreparedPhotoThumbnail(id: asset.id, cgImage: cgImage, jpegData: jpegData)
    }

    private func requestLibraryImage(localIdentifier: String) async throws -> UIImage {
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
                return try await requestLibraryThumbnail(asset: asset)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        try await Task.sleep(nanoseconds: 800_000_000)
        do {
            return try await requestLibraryImageData(asset: asset)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PhotoAnalysisThumbnailError.unavailable
        }
    }

    private func requestLibraryThumbnail(asset: PHAsset) async throws -> UIImage {
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
                    targetSize: CGSize(width: Self.maximumPixelSize, height: Self.maximumPixelSize),
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

    private func requestLibraryImageData(asset: PHAsset) async throws -> UIImage {
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
                                kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelSize,
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

    private static func fileThumbnail(path: String) async throws -> CGImage {
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

    private static func normalizedCGImage(from image: UIImage) throws -> CGImage {
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
