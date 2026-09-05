import CoreGraphics
import Foundation
import ImageIO

protocol NativePhotoIntelligenceServing: Sendable {
    func analyze(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        metadata: NativePhotoIntelligenceMetadata
    ) async throws -> NativePhotoIntelligenceResult
}

extension NativePhotoIntelligenceService: NativePhotoIntelligenceServing {}

enum CloudAnalysisPreference: String, Sendable {
    case undecided
    case enabled
    case onDeviceOnly
}

enum SmartPhotoExclusionReason: String, CaseIterable, Sendable {
    case screenshot
    case document
    case lowQuality
    case utilityImage

    var title: String {
        switch self {
        case .screenshot: "Screenshot"
        case .document: "Order or document"
        case .lowQuality: "Low quality"
        case .utilityImage: "Utility image"
        }
    }

    var symbol: String {
        switch self {
        case .screenshot: "iphone"
        case .document: "doc.text.viewfinder"
        case .lowQuality: "camera.filters"
        case .utilityImage: "shippingbox"
        }
    }
}

enum SmartPhotoAnalysisOrigin: String, Sendable {
    case metadata
    case onDevice
    case cloud

    var title: String {
        switch self {
        case .metadata: "Photo metadata"
        case .onDevice: "On-device analysis"
        case .cloud: "GPT-5.6 Luna"
        }
    }
}

struct SmartExcludedPhoto: Identifiable, Hashable, Sendable {
    let asset: TripAsset
    let reason: SmartPhotoExclusionReason
    let detail: String
    let confidence: Double
    let origin: SmartPhotoAnalysisOrigin

    var id: String { asset.id }
}

struct SmartPhotoSelectionOutcome: Sendable {
    let includedAssets: [TripAsset]
    let excludedPhotos: [SmartExcludedPhoto]
    let analyzedCount: Int
    let cloudReviewedCount: Int
    let unavailableCount: Int
}

enum SmartPhotoSelectionPolicy {
    /// Metadata screenshots are Apple's own high-confidence subtype and never
    /// need to leave the device for identification.
    static func metadataDecision(for asset: TripAsset) -> SmartExcludedPhoto? {
        guard asset.isScreenshot else { return nil }
        return SmartExcludedPhoto(
            asset: asset,
            reason: .screenshot,
            detail: "Apple Photos identifies this image as a screenshot.",
            confidence: 1,
            origin: .metadata
        )
    }

    static func nativeDecision(
        for asset: TripAsset,
        result: NativePhotoIntelligenceResult
    ) -> SmartExcludedPhoto? {
        let scores = result.scores
        let hasMemoryProtection = scores.peopleScore >= 0.42
            || result.tags.contains(.groupPhoto)
            || result.tags.contains(.scenery)
            || result.tags.contains(.food)
            || result.tags.contains(.strongMemory)
            || result.tags.contains(.visuallyAppealing)

        if result.signals.isScreenshot {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .screenshot,
                detail: "On-device analysis identifies this as a screenshot.",
                confidence: scores.nativeConfidence,
                origin: .onDevice
            )
        }

        // Require corroborating document geometry or substantial OCR coverage.
        // Text alone is not enough because landmarks, signs, and menus can be
        // valuable travel memories.
        let strongDocumentEvidence = scores.documentProbability >= 0.94
            && (result.signals.document.detected && result.signals.document.coverage >= 0.48
                || result.signals.text.coverage >= 0.30)
        if strongDocumentEvidence,
           scores.nativeConfidence >= 0.86,
           !hasMemoryProtection,
           scores.memoryScore < 0.42 {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .document,
                detail: "Looks like an order, receipt, ticket, or document.",
                confidence: scores.nativeConfidence,
                origin: .onDevice
            )
        }

        if scores.utilityProbability >= 0.96,
           scores.nativeConfidence >= 0.90,
           !hasMemoryProtection,
           scores.memoryScore < 0.34 {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .utilityImage,
                detail: "Looks useful for reference, but not like a film moment.",
                confidence: scores.nativeConfidence,
                origin: .onDevice
            )
        }

        return nil
    }

    /// Cloud output is intentionally used as a conservative utility filter, not
    /// as an authority on which memories are beautiful. People, group, food,
    /// scenic, and uncertain photos stay eligible for the user's film.
    static func cloudDecision(
        for asset: TripAsset,
        result: CloudPhotoAnalysisResult
    ) -> SmartExcludedPhoto? {
        guard result.scoresAreValid else { return nil }

        let memoryScore = max(result.scenic, result.people, result.group, result.food)
        let protectsMemory = result.group >= 0.72
            || result.people >= 0.82
            || result.scenic >= 0.82
            || result.food >= 0.86

        // Multi-label results can call a valuable group photo "document-like"
        // because of a menu, sign, or ticket in frame. Strong people/scenic/
        // food evidence always wins; uncertain memories stay in the film.
        if protectsMemory { return nil }

        if result.screenshot >= 0.94, result.confidence >= 0.82 {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .screenshot,
                detail: safeDetail(result.reason, fallback: "Looks like a screenshot rather than a camera photo."),
                confidence: result.confidence,
                origin: .cloud
            )
        }

        if result.document >= 0.94, result.confidence >= 0.84 {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .document,
                detail: safeDetail(result.reason, fallback: "Looks like an order, receipt, ticket, or document."),
                confidence: result.confidence,
                origin: .cloud
            )
        }

        if result.lowQuality >= 0.98,
           result.confidence >= 0.92,
           memoryScore < 0.30 {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .lowQuality,
                detail: safeDetail(result.reason, fallback: "Too unclear to add automatically."),
                confidence: result.confidence,
                origin: .cloud
            )
        }

        return nil
    }

    private static func safeDetail(_ detail: String, fallback: String) -> String {
        let singleLine = detail
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return fallback }
        return String(singleLine.prefix(120))
    }
}
