import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Photos
import UIKit
import Vision

/// Metadata known before image analysis. Passing PhotoKit's screenshot subtype is
/// more reliable than attempting to infer a screenshot from its pixels.
struct NativePhotoIntelligenceMetadata: Hashable, Sendable {
    let sourceIdentifier: String?
    let isScreenshot: Bool

    init(sourceIdentifier: String? = nil, isScreenshot: Bool = false) {
        self.sourceIdentifier = sourceIdentifier
        self.isScreenshot = isScreenshot
    }
}

struct NativePhotoIntelligenceConfiguration: Hashable, Sendable {
    let maximumImageDimension: Int
    let maximumClassifications: Int
    let maximumTextObservations: Int
    let minimumClassificationConfidence: Float
    let minimumTextConfidence: Float
    let allowsICloudAssetDownload: Bool

    init(
        maximumImageDimension: Int = 1_024,
        maximumClassifications: Int = 12,
        maximumTextObservations: Int = 128,
        minimumClassificationConfidence: Float = 0.08,
        minimumTextConfidence: Float = 0.20,
        allowsICloudAssetDownload: Bool = false
    ) {
        self.maximumImageDimension = min(max(maximumImageDimension, 256), 2_048)
        self.maximumClassifications = min(max(maximumClassifications, 1), 24)
        self.maximumTextObservations = min(max(maximumTextObservations, 1), 256)
        self.minimumClassificationConfidence = min(max(minimumClassificationConfidence, 0), 1)
        self.minimumTextConfidence = min(max(minimumTextConfidence, 0), 1)
        self.allowsICloudAssetDownload = allowsICloudAssetDownload
    }
}

struct NativePhotoClassification: Codable, Hashable, Sendable {
    let identifier: String
    let confidence: Float
}

struct NativePhotoTextSignal: Codable, Hashable, Sendable {
    let lineCount: Int
    let characterCount: Int
    /// Approximate fraction of the image occupied by recognized text, in 0...1.
    let coverage: Double
    let averageConfidence: Float?

    init(
        lineCount: Int = 0,
        characterCount: Int = 0,
        coverage: Double = 0,
        averageConfidence: Float? = nil
    ) {
        self.lineCount = lineCount
        self.characterCount = characterCount
        self.coverage = coverage
        self.averageConfidence = averageConfidence
    }
}

struct NativePhotoFaceSignal: Codable, Hashable, Sendable {
    let count: Int
    let averageCaptureQuality: Float?
    let bestCaptureQuality: Float?

    init(
        count: Int = 0,
        averageCaptureQuality: Float? = nil,
        bestCaptureQuality: Float? = nil
    ) {
        self.count = count
        self.averageCaptureQuality = averageCaptureQuality
        self.bestCaptureQuality = bestCaptureQuality
    }
}

struct NativePhotoHumanSignal: Codable, Hashable, Sendable {
    let count: Int

    init(count: Int = 0) {
        self.count = max(0, count)
    }
}

enum NativePhotoFocalSource: String, Codable, Hashable, Sendable {
    case faces
    case people
    case saliency
}

/// A normalized point of interest in Vision coordinates (origin at the lower
/// left). It is used only to suggest a reversible starting crop on device.
struct NativePhotoFocalPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let coverage: Double
    let source: NativePhotoFocalSource

    init(
        x: Double,
        y: Double,
        coverage: Double,
        source: NativePhotoFocalSource
    ) {
        self.x = Self.clamp(x, fallback: 0.5)
        self.y = Self.clamp(y, fallback: 0.5)
        self.coverage = Self.clamp(coverage, fallback: 0)
        self.source = source
    }

    private static func clamp(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, 0), 1)
    }
}

/// Keeps Vision geometry out of the montage planner and makes the preference
/// for human subjects over generic saliency deterministic and testable.
enum NativePhotoFocalPointResolver {
    static func resolve(
        faceBoxes: [CGRect],
        salientBoxes: [CGRect],
        humanBoxes: [CGRect] = []
    ) -> NativePhotoFocalPoint? {
        let faces = faceBoxes.compactMap(sanitizedUnitRect)
        let humans = humanBoxes.compactMap(sanitizedUnitRect)
        // Person rectangles protect compositions that face-only framing can
        // miss. Include face rectangles too, because either detector can find
        // a partially occluded subject that the other does not.
        if !humans.isEmpty, let union = union(of: humans + faces) {
            return NativePhotoFocalPoint(
                x: union.midX,
                y: union.midY,
                coverage: union.width * union.height,
                source: .people
            )
        }
        if let union = union(of: faces) {
            return NativePhotoFocalPoint(
                x: union.midX,
                y: union.midY,
                coverage: union.width * union.height,
                source: .faces
            )
        }

        guard let salient = salientBoxes
            .compactMap(sanitizedUnitRect)
            .max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) else {
            return nil
        }
        return NativePhotoFocalPoint(
            x: salient.midX,
            y: salient.midY,
            coverage: salient.width * salient.height,
            source: .saliency
        )
    }

    private static func sanitizedUnitRect(_ rect: CGRect) -> CGRect? {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0 else { return nil }
        let clipped = rect.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    private static func union(of rects: [CGRect]) -> CGRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() { result = result.union(rect) }
        return result
    }
}

struct NativePhotoDocumentSignal: Codable, Hashable, Sendable {
    let detected: Bool
    let confidence: Float
    /// Fraction of the image covered by the best detected document rectangle.
    let coverage: Double

    init(detected: Bool = false, confidence: Float = 0, coverage: Double = 0) {
        self.detected = detected
        self.confidence = confidence
        self.coverage = coverage
    }
}

struct NativePhotoAestheticsSignal: Codable, Hashable, Sendable {
    /// Apple's native score in -1...1.
    let overallScore: Float
    let isUtility: Bool
}

enum NativePhotoFeaturePrintError: Error, Equatable, Sendable {
    case incompatiblePrints
    case malformedData
    case unsupportedElementType
}

/// A value-only representation of Vision's feature print. Keeping only its raw
/// values makes analysis results safe to move across actor boundaries or persist.
struct NativePhotoFeaturePrint: Codable, Hashable, Sendable {
    let revision: Int
    let elementTypeRawValue: UInt
    let elementCount: Int
    let data: Data

    /// Euclidean distance is suitable for duplicate clustering when both prints
    /// were produced by the same Vision request revision. Smaller is more alike.
    func distance(to other: NativePhotoFeaturePrint) throws -> Double {
        guard revision == other.revision,
              elementTypeRawValue == other.elementTypeRawValue,
              elementCount == other.elementCount else {
            throw NativePhotoFeaturePrintError.incompatiblePrints
        }

        switch elementTypeRawValue {
        case 1:
            return try floatDistance(to: other)
        case 2:
            return try doubleDistance(to: other)
        default:
            throw NativePhotoFeaturePrintError.unsupportedElementType
        }
    }

    private func floatDistance(to other: NativePhotoFeaturePrint) throws -> Double {
        let size = elementCount.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
        guard elementCount >= 0,
              !size.overflow,
              data.count == size.partialValue,
              other.data.count == size.partialValue else {
            throw NativePhotoFeaturePrintError.malformedData
        }

        var left = [Float](repeating: 0, count: elementCount)
        var right = [Float](repeating: 0, count: elementCount)
        _ = left.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        _ = right.withUnsafeMutableBytes { other.data.copyBytes(to: $0) }

        return sqrt(zip(left, right).reduce(0.0) { total, pair in
            let difference = Double(pair.0) - Double(pair.1)
            return total + (difference * difference)
        })
    }

    private func doubleDistance(to other: NativePhotoFeaturePrint) throws -> Double {
        let size = elementCount.multipliedReportingOverflow(by: MemoryLayout<Double>.stride)
        guard elementCount >= 0,
              !size.overflow,
              data.count == size.partialValue,
              other.data.count == size.partialValue else {
            throw NativePhotoFeaturePrintError.malformedData
        }

        var left = [Double](repeating: 0, count: elementCount)
        var right = [Double](repeating: 0, count: elementCount)
        _ = left.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        _ = right.withUnsafeMutableBytes { other.data.copyBytes(to: $0) }

        return sqrt(zip(left, right).reduce(0.0) { total, pair in
            let difference = pair.0 - pair.1
            return total + (difference * difference)
        })
    }
}

struct NativePhotoSignalAvailability: Codable, Hashable, Sendable {
    let classification: Bool
    let textRecognition: Bool
    let faceQuality: Bool
    let humanDetection: Bool
    let documentDetection: Bool
    let featurePrint: Bool
    let aesthetics: Bool

    init(
        classification: Bool = true,
        textRecognition: Bool = true,
        faceQuality: Bool = true,
        humanDetection: Bool = false,
        documentDetection: Bool = true,
        featurePrint: Bool = false,
        aesthetics: Bool = false
    ) {
        self.classification = classification
        self.textRecognition = textRecognition
        self.faceQuality = faceQuality
        self.humanDetection = humanDetection
        self.documentDetection = documentDetection
        self.featurePrint = featurePrint
        self.aesthetics = aesthetics
    }
}

struct NativePhotoIntelligenceSignals: Codable, Hashable, Sendable {
    let isScreenshot: Bool
    let classifications: [NativePhotoClassification]
    let text: NativePhotoTextSignal
    let faces: NativePhotoFaceSignal
    let humans: NativePhotoHumanSignal
    let document: NativePhotoDocumentSignal
    let aesthetics: NativePhotoAestheticsSignal?
    let featurePrint: NativePhotoFeaturePrint?
    let focalPoint: NativePhotoFocalPoint?
    let availability: NativePhotoSignalAvailability

    init(
        isScreenshot: Bool = false,
        classifications: [NativePhotoClassification] = [],
        text: NativePhotoTextSignal = .init(),
        faces: NativePhotoFaceSignal = .init(),
        humans: NativePhotoHumanSignal = .init(),
        document: NativePhotoDocumentSignal = .init(),
        aesthetics: NativePhotoAestheticsSignal? = nil,
        featurePrint: NativePhotoFeaturePrint? = nil,
        focalPoint: NativePhotoFocalPoint? = nil,
        availability: NativePhotoSignalAvailability = .init()
    ) {
        self.isScreenshot = isScreenshot
        self.classifications = classifications
        self.text = text
        self.faces = faces
        self.humans = humans
        self.document = document
        self.aesthetics = aesthetics
        self.featurePrint = featurePrint
        self.focalPoint = focalPoint
        self.availability = availability
    }
}

struct NativePhotoIntelligenceScores: Codable, Hashable, Sendable {
    let memoryScore: Double
    let utilityProbability: Double
    let documentProbability: Double
    let peopleScore: Double
    let aestheticScore: Double?
    let nativeConfidence: Double
}

enum NativePhotoIntelligenceTag: String, Codable, CaseIterable, Hashable, Sendable {
    case screenshot
    case likelyDocument
    case textHeavy
    case people
    case groupPhoto
    case scenery
    case food
    case utility
    case strongMemory
    case visuallyAppealing
    case lowAesthetic
    case cloudReviewCandidate
}

enum NativeCloudReviewDisposition: String, Codable, Hashable, Sendable {
    /// Native signals are decisive enough that no image should leave the device.
    case unnecessary
    /// The caller may offer cloud analysis, but only after explicit user consent.
    case eligibleAfterExplicitConsent
    /// Screenshots/documents are intentionally withheld because they may be sensitive.
    case blockedSensitiveContent
}

enum NativeCloudReviewReason: String, Codable, Hashable, Sendable {
    case screenshot
    case documentOrTextHeavy
    case highUtilityConfidence
    case highMemoryConfidence
    case ambiguousNativeResult
    case insufficientNativeSignals
}

struct NativeCloudReviewGate: Codable, Hashable, Sendable {
    let disposition: NativeCloudReviewDisposition
    let reason: NativeCloudReviewReason
}

struct NativePhotoIntelligenceAssessment: Codable, Hashable, Sendable {
    let scores: NativePhotoIntelligenceScores
    let tags: [NativePhotoIntelligenceTag]
    let cloudReviewGate: NativeCloudReviewGate
}

struct NativePhotoIntelligenceResult: Codable, Hashable, Sendable {
    let sourceIdentifier: String?
    let analyzedPixelWidth: Int
    let analyzedPixelHeight: Int
    let signals: NativePhotoIntelligenceSignals
    let scores: NativePhotoIntelligenceScores
    let tags: [NativePhotoIntelligenceTag]
    let cloudReviewGate: NativeCloudReviewGate
}

/// Deterministic policy separated from Vision so it can be tested with value-only
/// fixtures and tuned later using opt-in evaluation data.
enum NativePhotoIntelligenceScorer {
    static func score(signals: NativePhotoIntelligenceSignals) -> NativePhotoIntelligenceAssessment {
        let textCoverage = clamp(signals.text.coverage)
        let characterEvidence = clamp(Double(max(signals.text.characterCount, 0)) / 1_200.0)
        let textEvidence = max(
            clamp((textCoverage - 0.025) / 0.325),
            characterEvidence * 0.72
        )

        let documentCoverage = clamp(signals.document.coverage)
        let documentConfidence = clamp(Double(signals.document.confidence))
        let detectedDocumentEvidence = signals.document.detected
            ? max(documentCoverage, (0.68 * documentConfidence) + (0.32 * documentCoverage))
            : 0
        let documentClassification = classificationConfidence(
            in: signals.classifications,
            matching: documentTerms
        )
        let documentComponents = [
            detectedDocumentEvidence,
            textEvidence * 0.73,
            documentClassification * 0.90
        ]
        // Fuse independent evidence instead of letting a single OCR hit decide.
        // A document rectangle plus dense text is far more reliable than either
        // signal alone, while a text-covered landmark remains below the cutoff.
        var documentProbability = 1 - documentComponents.reduce(1.0) {
            $0 * (1 - clamp($1))
        }
        if signals.isScreenshot, textEvidence >= 0.12 {
            documentProbability = max(documentProbability, 0.82)
        }
        documentProbability = clamp(documentProbability)

        let utilityClassification = classificationConfidence(
            in: signals.classifications,
            matching: utilityTerms
        )
        var utilityProbability = max(
            documentProbability * 0.92,
            textEvidence * 0.76,
            utilityClassification * 0.88,
            signals.aesthetics?.isUtility == true ? 0.90 : 0
        )
        let detectedPeopleCount = max(signals.faces.count, signals.humans.count)
        if signals.isScreenshot {
            utilityProbability = 1
        } else if detectedPeopleCount >= 2, documentProbability < 0.50 {
            utilityProbability *= 0.78
        }
        utilityProbability = clamp(utilityProbability)

        let peopleScore = peopleScore(
            for: signals.faces,
            detectedPeopleCount: detectedPeopleCount
        )
        let sceneryConfidence = classificationConfidence(
            in: signals.classifications,
            matching: sceneryTerms
        )
        let foodConfidence = classificationConfidence(
            in: signals.classifications,
            matching: foodTerms
        )
        let memoryClassification = max(
            sceneryConfidence,
            foodConfidence,
            classificationConfidence(in: signals.classifications, matching: memoryTerms)
        )

        let aestheticScore = signals.aesthetics.map {
            clamp((Double($0.overallScore) + 1) / 2)
        }
        let effectiveAestheticScore = aestheticScore ?? 0.55

        var memoryScore = 0.18
            + (0.34 * effectiveAestheticScore)
            + (0.28 * peopleScore)
            + (0.22 * memoryClassification)
        if detectedPeopleCount > 0 { memoryScore += 0.06 }
        if memoryClassification >= 0.55 { memoryScore += 0.06 }
        memoryScore *= 1 - (0.78 * utilityProbability)
        memoryScore -= 0.08 * documentProbability
        memoryScore = clamp(memoryScore)
        if signals.isScreenshot {
            memoryScore = min(memoryScore, 0.06)
        }

        let performedCount = [
            signals.availability.classification,
            signals.availability.textRecognition,
            signals.availability.faceQuality,
            signals.availability.humanDetection,
            signals.availability.documentDetection,
            signals.availability.featurePrint,
            signals.availability.aesthetics
        ].filter { $0 }.count
        let availabilityStrength = Double(performedCount) / 7.0
        let decisiveEvidence = max(
            utilityProbability,
            peopleScore,
            memoryClassification,
            aestheticScore.map { abs($0 - 0.5) * 2 } ?? 0
        )
        let decisionMargin = abs(memoryScore - 0.5) * 2
        var nativeConfidence = clamp(
            (0.38 * decisionMargin) +
            (0.42 * decisiveEvidence) +
            (0.20 * availabilityStrength)
        )
        if signals.isScreenshot { nativeConfidence = 1 }
        if documentProbability >= 0.78 { nativeConfidence = max(nativeConfidence, 0.90) }
        if memoryScore >= 0.78 { nativeConfidence = max(nativeConfidence, 0.86) }

        let cloudReviewGate: NativeCloudReviewGate
        if signals.isScreenshot {
            cloudReviewGate = .init(
                disposition: .blockedSensitiveContent,
                reason: .screenshot
            )
        } else if documentProbability >= 0.64 || textCoverage >= 0.22 || signals.text.characterCount >= 700 {
            cloudReviewGate = .init(
                disposition: .blockedSensitiveContent,
                reason: .documentOrTextHeavy
            )
        } else if utilityProbability >= 0.72 {
            cloudReviewGate = .init(
                disposition: .unnecessary,
                reason: .highUtilityConfidence
            )
        } else if memoryScore >= 0.68,
                  peopleScore >= 0.48 || memoryClassification >= 0.42 || effectiveAestheticScore >= 0.72 {
            cloudReviewGate = .init(
                disposition: .unnecessary,
                reason: .highMemoryConfidence
            )
        } else {
            cloudReviewGate = .init(
                disposition: .eligibleAfterExplicitConsent,
                reason: performedCount < 3 ? .insufficientNativeSignals : .ambiguousNativeResult
            )
        }

        var tags = Set<NativePhotoIntelligenceTag>()
        if signals.isScreenshot { tags.insert(.screenshot) }
        if documentProbability >= 0.60 { tags.insert(.likelyDocument) }
        if textCoverage >= 0.12 || signals.text.characterCount >= 350 { tags.insert(.textHeavy) }
        if detectedPeopleCount > 0 { tags.insert(.people) }
        if detectedPeopleCount >= 2 { tags.insert(.groupPhoto) }
        if sceneryConfidence >= 0.35 { tags.insert(.scenery) }
        if foodConfidence >= 0.35 { tags.insert(.food) }
        if utilityProbability >= 0.65 { tags.insert(.utility) }
        if memoryScore >= 0.68 { tags.insert(.strongMemory) }
        if let aestheticScore, aestheticScore >= 0.68 { tags.insert(.visuallyAppealing) }
        if let aestheticScore, aestheticScore <= 0.32 { tags.insert(.lowAesthetic) }
        if cloudReviewGate.disposition == .eligibleAfterExplicitConsent {
            tags.insert(.cloudReviewCandidate)
        }

        return NativePhotoIntelligenceAssessment(
            scores: NativePhotoIntelligenceScores(
                memoryScore: memoryScore,
                utilityProbability: utilityProbability,
                documentProbability: documentProbability,
                peopleScore: peopleScore,
                aestheticScore: aestheticScore,
                nativeConfidence: nativeConfidence
            ),
            tags: tags.sorted { $0.rawValue < $1.rawValue },
            cloudReviewGate: cloudReviewGate
        )
    }

    private static let documentTerms = [
        "document", "receipt", "invoice", "paper", "form", "ticket", "menu", "letter"
    ]
    private static let utilityTerms = [
        "screen", "screenshot", "web site", "website", "computer monitor", "document",
        "receipt", "invoice", "diagram", "chart", "menu", "form"
    ]
    private static let sceneryTerms = [
        "landscape", "outdoor", "beach", "coast", "mountain", "waterfall", "forest",
        "garden", "ocean", "sea", "lake", "sky", "sunset", "cityscape", "architecture",
        "landmark", "building"
    ]
    private static let foodTerms = ["food", "dish", "meal", "cuisine", "dessert", "drink"]
    private static let memoryTerms = [
        "animal", "event", "concert", "festival", "sports", "wedding", "vacation", "travel"
    ]

    private static func classificationConfidence(
        in classifications: [NativePhotoClassification],
        matching terms: [String]
    ) -> Double {
        classifications.reduce(0) { current, classification in
            let identifier = " \(normalized(classification.identifier)) "
            guard terms.contains(where: { identifier.contains(" \($0) ") }) else { return current }
            return max(current, clamp(Double(classification.confidence)))
        }
    }

    private static func peopleScore(
        for faces: NativePhotoFaceSignal,
        detectedPeopleCount: Int
    ) -> Double {
        let countScore: Double
        switch max(detectedPeopleCount, 0) {
        case 0: countScore = 0
        case 1: countScore = 0.62
        case 2: countScore = 0.82
        case 3...5: countScore = 0.94
        default: countScore = 1
        }

        guard let quality = faces.averageCaptureQuality else { return countScore }
        return clamp(countScore * (0.72 + (0.28 * clamp(Double(quality)))))
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().map { character in
            character.isLetter || character.isNumber ? character : " "
        }.reduce(into: "") { result, character in
            if character != " " || result.last != " " { result.append(character) }
        }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

enum NativePhotoIntelligenceError: Error, Equatable, Sendable {
    case invalidImage
    case photoLibraryAccessUnavailable
    case assetNotFound
    case assetUnavailableLocally
    case imageRequestFailed(String)
    case visionRequestFailed(String)
}

extension NativePhotoIntelligenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image could not be prepared for analysis."
        case .photoLibraryAccessUnavailable:
            return "Photo library access is not available."
        case .assetNotFound:
            return "The photo is no longer available in the accessible library."
        case .assetUnavailableLocally:
            return "The photo is stored in iCloud and local download is disabled."
        case let .imageRequestFailed(message):
            return "The photo thumbnail request failed: \(message)"
        case let .visionRequestFailed(message):
            return "On-device photo analysis failed: \(message)"
        }
    }
}

/// Serial actor isolation bounds expensive Vision execution to one downsampled
/// image at a time. It never sends image pixels, labels, or OCR content to a server.
actor NativePhotoIntelligenceService {
    private let configuration: NativePhotoIntelligenceConfiguration
    private let imageManager: PHImageManager
    private let ciContext: CIContext

    init(
        configuration: NativePhotoIntelligenceConfiguration = .init(),
        imageManager: PHImageManager = .default()
    ) {
        self.configuration = configuration
        self.imageManager = imageManager
        self.ciContext = CIContext(options: [.cacheIntermediates: false])
    }

    func analyze(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        metadata: NativePhotoIntelligenceMetadata = .init()
    ) async throws -> NativePhotoIntelligenceResult {
        try Task.checkCancellation()
        let image = try Self.downsample(
            cgImage,
            maximumDimension: configuration.maximumImageDimension
        )
        return try await performAnalysis(image: image, orientation: orientation, metadata: metadata)
    }

    func analyze(
        ciImage: CIImage,
        orientation: CGImagePropertyOrientation = .up,
        metadata: NativePhotoIntelligenceMetadata = .init()
    ) async throws -> NativePhotoIntelligenceResult {
        try Task.checkCancellation()
        let image = try renderDownsampled(ciImage)
        return try await performAnalysis(image: image, orientation: orientation, metadata: metadata)
    }

    /// Resolves exactly one accessible PHAsset and asks PhotoKit for a bounded
    /// thumbnail. iCloud network access remains off unless explicitly configured.
    func analyze(
        localAssetIdentifier: String,
        metadata: NativePhotoIntelligenceMetadata = .init()
    ) async throws -> NativePhotoIntelligenceResult {
        try Task.checkCancellation()
        guard !localAssetIdentifier.isEmpty else {
            throw NativePhotoIntelligenceError.assetNotFound
        }

        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            break
        case .notDetermined, .restricted, .denied:
            throw NativePhotoIntelligenceError.photoLibraryAccessUnavailable
        @unknown default:
            throw NativePhotoIntelligenceError.photoLibraryAccessUnavailable
        }

        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [localAssetIdentifier],
            options: nil
        )
        guard let asset = result.firstObject, asset.mediaType == .image else {
            throw NativePhotoIntelligenceError.assetNotFound
        }

        let loaded = try await Self.requestImage(
            for: asset,
            manager: imageManager,
            maximumDimension: configuration.maximumImageDimension,
            allowsNetworkAccess: configuration.allowsICloudAssetDownload
        )
        try Task.checkCancellation()

        let mergedMetadata = NativePhotoIntelligenceMetadata(
            sourceIdentifier: metadata.sourceIdentifier ?? localAssetIdentifier,
            isScreenshot: metadata.isScreenshot || asset.mediaSubtypes.contains(.photoScreenshot)
        )
        let boundedImage = try Self.downsample(
            loaded.cgImage,
            maximumDimension: configuration.maximumImageDimension
        )
        return try await performAnalysis(
            image: boundedImage,
            orientation: loaded.orientation,
            metadata: mergedMetadata
        )
    }

    private func performAnalysis(
        image: CGImage,
        orientation: CGImagePropertyOrientation,
        metadata: NativePhotoIntelligenceMetadata
    ) async throws -> NativePhotoIntelligenceResult {
        let classificationRequest = VNClassifyImageRequest()
        if VNClassifyImageRequest.supportedRevisions.contains(VNClassifyImageRequestRevision2) {
            classificationRequest.revision = VNClassifyImageRequestRevision2
        }
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        textRequest.minimumTextHeight = 0.012

        let faceRequest = VNDetectFaceCaptureQualityRequest()
        if VNDetectFaceCaptureQualityRequest.supportedRevisions.contains(
            VNDetectFaceCaptureQualityRequestRevision3
        ) {
            faceRequest.revision = VNDetectFaceCaptureQualityRequestRevision3
        }

        let humanRequest = VNDetectHumanRectanglesRequest()

        let documentRequest = VNDetectDocumentSegmentationRequest()

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        if VNGenerateImageFeaturePrintRequest.supportedRevisions.contains(
            VNGenerateImageFeaturePrintRequestRevision2
        ) {
            featureRequest.revision = VNGenerateImageFeaturePrintRequestRevision2
        }
        featureRequest.imageCropAndScaleOption = .scaleFit

        var requests: [VNRequest] = [
            classificationRequest,
            textRequest,
            faceRequest,
            humanRequest,
            documentRequest,
            featureRequest
        ]
        if #available(iOS 18.0, *) {
            requests.append(VNCalculateImageAestheticsScoresRequest())
        }

        let cancellation = NativeVisionRequestCancellation(
            requests: requests + [saliencyRequest]
        )
        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: orientation,
            options: [:]
        )

        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try handler.perform(requests)
                try Task.checkCancellation()
                // Saliency is a best-effort enhancement. Run it only when
                // people detection did not already provide a stronger focus,
                // never discard an otherwise valid analysis if it fails.
                if (faceRequest.results ?? []).isEmpty,
                   (humanRequest.results ?? []).isEmpty {
                    do {
                        try VNImageRequestHandler(
                            cgImage: image,
                            orientation: orientation,
                            options: [:]
                        ).perform([saliencyRequest])
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                    }
                }
                try Task.checkCancellation()
            } onCancel: {
                cancellation.cancel()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw NativePhotoIntelligenceError.visionRequestFailed(error.localizedDescription)
        }

        let classifications = (classificationRequest.results ?? [])
            .filter { $0.confidence >= configuration.minimumClassificationConfidence }
            .sorted {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.identifier < $1.identifier
            }
            .prefix(configuration.maximumClassifications)
            .map {
                NativePhotoClassification(identifier: $0.identifier, confidence: $0.confidence)
            }

        let textSignal = Self.textSignal(
            from: textRequest.results ?? [],
            maximumCount: configuration.maximumTextObservations,
            minimumConfidence: configuration.minimumTextConfidence
        )
        let faceSignal = Self.faceSignal(from: faceRequest.results ?? [])
        let humanSignal = NativePhotoHumanSignal(
            count: (humanRequest.results ?? []).count
        )
        let documentSignal = Self.documentSignal(from: documentRequest.results ?? [])
        let focalPoint = NativePhotoFocalPointResolver.resolve(
            faceBoxes: (faceRequest.results ?? []).map(\.boundingBox),
            salientBoxes: saliencyRequest.results?.first?.salientObjects?.map(\.boundingBox) ?? [],
            humanBoxes: (humanRequest.results ?? []).map(\.boundingBox)
        )

        let featurePrint = featureRequest.results?.first.map {
            NativePhotoFeaturePrint(
                revision: featureRequest.revision,
                elementTypeRawValue: $0.elementType.rawValue,
                elementCount: $0.elementCount,
                data: $0.data
            )
        }

        var aesthetics: NativePhotoAestheticsSignal?
        var aestheticsWasPerformed = false
        if #available(iOS 18.0, *) {
            if let request = requests.first(where: {
                $0 is VNCalculateImageAestheticsScoresRequest
            }) as? VNCalculateImageAestheticsScoresRequest {
                aestheticsWasPerformed = true
                aesthetics = request.results?.first.map {
                    NativePhotoAestheticsSignal(
                        overallScore: $0.overallScore,
                        isUtility: $0.isUtility
                    )
                }
            }
        }

        let signals = NativePhotoIntelligenceSignals(
            isScreenshot: metadata.isScreenshot,
            classifications: classifications,
            text: textSignal,
            faces: faceSignal,
            humans: humanSignal,
            document: documentSignal,
            aesthetics: aesthetics,
            featurePrint: featurePrint,
            focalPoint: focalPoint,
            availability: NativePhotoSignalAvailability(
                classification: true,
                textRecognition: true,
                faceQuality: true,
                humanDetection: true,
                documentDetection: true,
                featurePrint: featurePrint != nil,
                aesthetics: aestheticsWasPerformed
            )
        )
        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)

        return NativePhotoIntelligenceResult(
            sourceIdentifier: metadata.sourceIdentifier,
            analyzedPixelWidth: image.width,
            analyzedPixelHeight: image.height,
            signals: signals,
            scores: assessment.scores,
            tags: assessment.tags,
            cloudReviewGate: assessment.cloudReviewGate
        )
    }

    private func renderDownsampled(_ image: CIImage) throws -> CGImage {
        let extent = image.extent.standardized
        guard !extent.isInfinite,
              !extent.isNull,
              extent.width.isFinite,
              extent.height.isFinite,
              extent.width > 0,
              extent.height > 0 else {
            throw NativePhotoIntelligenceError.invalidImage
        }

        let scale = min(
            1,
            CGFloat(configuration.maximumImageDimension) / max(extent.width, extent.height)
        )
        let normalized = image.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let output = ciContext.createCGImage(scaled, from: scaled.extent.integral) else {
            throw NativePhotoIntelligenceError.invalidImage
        }
        return output
    }

    private static func downsample(_ image: CGImage, maximumDimension: Int) throws -> CGImage {
        let largestDimension = max(image.width, image.height)
        guard largestDimension > 0 else { throw NativePhotoIntelligenceError.invalidImage }
        guard largestDimension > maximumDimension else { return image }

        let scale = CGFloat(maximumDimension) / CGFloat(largestDimension)
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NativePhotoIntelligenceError.invalidImage
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else {
            throw NativePhotoIntelligenceError.invalidImage
        }
        return output
    }

    private static func textSignal(
        from observations: [VNRecognizedTextObservation],
        maximumCount: Int,
        minimumConfidence: Float
    ) -> NativePhotoTextSignal {
        var lineCount = 0
        var characterCount = 0
        var coverage = 0.0
        var confidenceTotal = 0.0

        for observation in observations.prefix(maximumCount) {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else {
                continue
            }
            lineCount += 1
            characterCount += candidate.string.count
            coverage += Double(observation.boundingBox.width * observation.boundingBox.height)
            confidenceTotal += Double(candidate.confidence)
        }

        return NativePhotoTextSignal(
            lineCount: lineCount,
            characterCount: characterCount,
            coverage: min(max(coverage, 0), 1),
            averageConfidence: lineCount > 0 ? Float(confidenceTotal / Double(lineCount)) : nil
        )
    }

    private static func faceSignal(from observations: [VNFaceObservation]) -> NativePhotoFaceSignal {
        let qualities = observations.prefix(128).compactMap(\.faceCaptureQuality)
        return NativePhotoFaceSignal(
            count: observations.count,
            averageCaptureQuality: qualities.isEmpty
                ? nil
                : qualities.reduce(0, +) / Float(qualities.count),
            bestCaptureQuality: qualities.max()
        )
    }

    private static func documentSignal(
        from observations: [VNRectangleObservation]
    ) -> NativePhotoDocumentSignal {
        guard let document = observations.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height) <
                ($1.boundingBox.width * $1.boundingBox.height)
        }) else {
            return NativePhotoDocumentSignal()
        }

        return NativePhotoDocumentSignal(
            detected: true,
            confidence: document.confidence,
            coverage: min(
                max(Double(document.boundingBox.width * document.boundingBox.height), 0),
                1
            )
        )
    }

    private static func requestImage(
        for asset: PHAsset,
        manager: PHImageManager,
        maximumDimension: Int,
        allowsNetworkAccess: Bool
    ) async throws -> NativeAnalysisImage {
        let requestState = NativePhotoAssetRequestState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard requestState.install(continuation) else { return }

                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.version = .current
                options.isNetworkAccessAllowed = allowsNetworkAccess
                options.isSynchronous = false

                let targetSize = Self.targetSize(for: asset, maximumDimension: maximumDimension)
                let requestID = manager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        requestState.finish(.failure(CancellationError()))
                        return
                    }
                    if let error = info?[PHImageErrorKey] as? Error {
                        requestState.finish(.failure(
                            NativePhotoIntelligenceError.imageRequestFailed(error.localizedDescription)
                        ))
                        return
                    }
                    guard let image, let cgImage = image.cgImage else {
                        let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                        requestState.finish(.failure(
                            isInCloud && !allowsNetworkAccess
                                ? NativePhotoIntelligenceError.assetUnavailableLocally
                                : NativePhotoIntelligenceError.invalidImage
                        ))
                        return
                    }

                    requestState.finish(.success(
                        NativeAnalysisImage(
                            cgImage: cgImage,
                            orientation: Self.cgOrientation(from: image.imageOrientation)
                        )
                    ))
                }
                requestState.setRequestID(requestID, manager: manager)
            }
        } onCancel: {
            requestState.cancel(manager: manager)
        }
    }

    private static func targetSize(for asset: PHAsset, maximumDimension: Int) -> CGSize {
        let width = max(asset.pixelWidth, 1)
        let height = max(asset.pixelHeight, 1)
        let scale = min(1, Double(maximumDimension) / Double(max(width, height)))
        return CGSize(
            width: max((Double(width) * scale).rounded(), 1),
            height: max((Double(height) * scale).rounded(), 1)
        )
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

private struct NativeAnalysisImage: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

private final class NativeVisionRequestCancellation: @unchecked Sendable {
    private let requests: [VNRequest]

    init(requests: [VNRequest]) {
        self.requests = requests
    }

    func cancel() {
        requests.forEach { $0.cancel() }
    }
}

private final class NativePhotoAssetRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NativeAnalysisImage, Error>?
    private var requestID = PHInvalidImageRequestID
    private var isFinished = false
    private var isCancelled = false

    func install(_ continuation: CheckedContinuation<NativeAnalysisImage, Error>) -> Bool {
        lock.lock()
        guard !isCancelled, !isFinished else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setRequestID(_ requestID: PHImageRequestID, manager: PHImageManager) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { manager.cancelImageRequest(requestID) }
    }

    func finish(_ result: Result<NativeAnalysisImage, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel(manager: PHImageManager) {
        lock.lock()
        isCancelled = true
        let requestID = self.requestID
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
        continuation?.resume(throwing: CancellationError())
    }
}
