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
    case similarMoment
    case notAHighlight

    var title: String {
        switch self {
        case .screenshot: "Screenshot"
        case .document: "Order or document"
        case .lowQuality: "Low quality"
        case .utilityImage: "Utility image"
        case .similarMoment: "Similar moment"
        case .notAHighlight: "Not in the first cut"
        }
    }

    var symbol: String {
        switch self {
        case .screenshot: "iphone"
        case .document: "doc.text.viewfinder"
        case .lowQuality: "camera.filters"
        case .utilityImage: "shippingbox"
        case .similarMoment: "square.on.square"
        case .notAHighlight: "photo.stack"
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

/// A gentle, non-blocking summary of photos that can be checked again after a
/// complete first cut is ready. Counts contain no identifiers or image data.
struct PhotoAnalysisFollowUp: Equatable, Sendable {
    var syncingFromPhotosCount = 0
    var anotherLookCount = 0
    var accessNeededCount = 0
    var cloudPassCanBeRetried = false

    var photoCount: Int {
        syncingFromPhotosCount + anotherLookCount + accessNeededCount
    }

    var hasAnythingToCheck: Bool {
        photoCount > 0 || cloudPassCanBeRetried
    }

    var previewMessage: String {
        if photoCount > 0 {
            return "\(photoCount) more moment\(photoCount == 1 ? "" : "s") can be checked later"
        }
        return "A cloud finishing pass can be checked later"
    }
}

enum PhotoAnalysisFollowUpReason: Sendable {
    case syncingFromPhotos
    case anotherLook
    case accessNeeded
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

        if scores.utilityProbability >= 0.91,
           scores.nativeConfidence >= 0.82,
           !hasMemoryProtection,
           scores.memoryScore < 0.38 {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .utilityImage,
                detail: "Looks useful for reference, but not like a film moment.",
                confidence: scores.nativeConfidence,
                origin: .onDevice
            )
        }

        if let aestheticScore = scores.aestheticScore,
           aestheticScore <= 0.18,
           scores.nativeConfidence >= 0.68,
           scores.peopleScore < 0.24,
           !hasMemoryProtection,
           scores.memoryScore < 0.28 {
            return SmartExcludedPhoto(
                asset: asset,
                reason: .lowQuality,
                detail: "A stronger frame from this part of the trip was preferred.",
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

/// Shared, conservative comparison for Vision feature prints. Apple defines
/// smaller distances as more alike, but not a universal duplicate cutoff, so
/// TripReel combines distance with capture time and orientation. Very close
/// bursts may vary more (blink, expression, exposure) and still be one moment.
enum NativePhotoSimilarity {
    static let maximumTimeInterval: TimeInterval = 30 * 60

    static func areSimilar(
        _ first: TripAsset,
        firstPrint: NativePhotoFeaturePrint,
        _ second: TripAsset,
        secondPrint: NativePhotoFeaturePrint
    ) -> Bool {
        guard let firstDate = first.creationDate,
              let secondDate = second.creationDate else { return false }
        let interval = abs(firstDate.timeIntervalSince(secondDate))
        guard interval <= maximumTimeInterval,
              hasComparableComposition(first, second),
              let distance = try? firstPrint.distance(to: secondPrint) else {
            return false
        }

        let threshold: Double
        if interval <= 2 * 60 {
            threshold = 14
        } else if interval <= 10 * 60 {
            threshold = 12
        } else {
            threshold = 10
        }
        return distance <= threshold
    }

    private static func hasComparableComposition(
        _ first: TripAsset,
        _ second: TripAsset
    ) -> Bool {
        guard first.pixelWidth > 0, first.pixelHeight > 0,
              second.pixelWidth > 0, second.pixelHeight > 0 else {
            return true
        }
        let firstRatio = Double(first.pixelWidth) / Double(first.pixelHeight)
        let secondRatio = Double(second.pixelWidth) / Double(second.pixelHeight)
        return abs(log(firstRatio / secondRatio)) <= 0.24
    }
}

/// Turns a large trip into an actual first cut instead of simply replaying the
/// whole camera roll. The selector is deliberately local and reversible: it
/// combines Vision memory/aesthetic scores with day, category, orientation,
/// time, and feature-print diversity, then places every unselected asset in
/// More Photos.
enum SmartHighlightSelector {
    static func decisions(
        for assets: [TripAsset],
        nativeResults: [String: NativePhotoIntelligenceResult],
        excluding existing: [String: SmartExcludedPhoto],
        calendar: Calendar = .current
    ) -> [SmartExcludedPhoto] {
        let candidates = assets.filter { existing[$0.id] == nil }
        let representativeIDs = similarityRepresentativeIDs(
            in: candidates,
            nativeResults: nativeResults
        )
        let uniqueCandidates = candidates.filter { representativeIDs.contains($0.id) }

        let grouped = Dictionary(grouping: uniqueCandidates) { asset -> Date in
            asset.creationDate.map(calendar.startOfDay(for:)) ?? .distantPast
        }
        let target = min(
            uniqueCandidates.count,
            targetCount(total: candidates.count, dayCount: grouped.count)
        )

        var selected: [TripAsset] = []
        var remaining = uniqueCandidates
        let orderedDays = grouped.keys.sorted()
        let coverageRounds = target >= orderedDays.count * 2 ? 2 : 1

        for _ in 0..<coverageRounds {
            for day in orderedDays where selected.count < target {
                let dayCandidates = remaining.filter {
                    ($0.creationDate.map(calendar.startOfDay(for:)) ?? .distantPast) == day
                }
                guard let best = bestCandidate(
                    from: dayCandidates,
                    selected: selected,
                    nativeResults: nativeResults
                ) else { continue }
                selected.append(best)
                remaining.removeAll { $0.id == best.id }
            }
        }

        while selected.count < target,
              let best = bestCandidate(
                from: remaining,
                selected: selected,
                nativeResults: nativeResults
              ) {
            selected.append(best)
            remaining.removeAll { $0.id == best.id }
        }

        let selectedIDs = Set(selected.map(\.id))
        return candidates.compactMap { asset in
            if !representativeIDs.contains(asset.id) {
                return SmartExcludedPhoto(
                    asset: asset,
                    reason: .similarMoment,
                    detail: "A stronger frame from this moment is already in the film.",
                    confidence: 0.93,
                    origin: .onDevice
                )
            }
            guard !selectedIDs.contains(asset.id) else { return nil }
            return SmartExcludedPhoto(
                asset: asset,
                reason: .notAHighlight,
                detail: "Kept nearby for a shorter, more varied first cut.",
                confidence: 0.72,
                origin: .onDevice
            )
        }
    }

    static func targetCount(total: Int, dayCount: Int) -> Int {
        guard total > 24 else { return max(0, total) }
        let editorialScale = Int((sqrt(Double(total)) * 3.1).rounded())
        let dayCoverage = max(1, dayCount) * 4
        return min(total, max(24, min(72, max(editorialScale, dayCoverage))))
    }

    private static func bestCandidate(
        from candidates: [TripAsset],
        selected: [TripAsset],
        nativeResults: [String: NativePhotoIntelligenceResult]
    ) -> TripAsset? {
        candidates.max { left, right in
            score(left, selected: selected, nativeResults: nativeResults)
                < score(right, selected: selected, nativeResults: nativeResults)
        }
    }

    private static func score(
        _ asset: TripAsset,
        selected: [TripAsset],
        nativeResults: [String: NativePhotoIntelligenceResult]
    ) -> Double {
        guard let result = nativeResults[asset.id] else {
            return 0.34 + temporalDiversityBonus(for: asset, selected: selected)
        }

        let kind = contentKind(for: result)
        let aesthetic = result.scores.aestheticScore ?? 0.52
        var value = (0.60 * result.scores.memoryScore) + (0.30 * aesthetic)
        if result.tags.contains(.groupPhoto) { value += 0.12 }
        if result.tags.contains(.scenery) { value += 0.08 }
        if result.tags.contains(.food) { value += 0.04 }
        if !selected.contains(where: { selectedAsset in
            nativeResults[selectedAsset.id].map(contentKind(for:)) == kind
        }) {
            value += 0.08
        }
        value += temporalDiversityBonus(for: asset, selected: selected)
        if selected.contains(where: {
            visuallySimilar(asset, $0, nativeResults: nativeResults)
        }) {
            value -= 0.72
        }
        return value
    }

    private static func temporalDiversityBonus(
        for asset: TripAsset,
        selected: [TripAsset]
    ) -> Double {
        guard let date = asset.creationDate,
              let nearest = selected.compactMap(\.creationDate).map({ abs($0.timeIntervalSince(date)) }).min()
        else { return selected.isEmpty ? 0.12 : 0 }
        return min(0.14, nearest / (8 * 60 * 60) * 0.14)
    }

    private static func visuallySimilar(
        _ first: TripAsset,
        _ second: TripAsset,
        nativeResults: [String: NativePhotoIntelligenceResult]
    ) -> Bool {
        guard let firstPrint = nativeResults[first.id]?.signals.featurePrint,
              let secondPrint = nativeResults[second.id]?.signals.featurePrint else {
            return false
        }
        return NativePhotoSimilarity.areSimilar(
            first,
            firstPrint: firstPrint,
            second,
            secondPrint: secondPrint
        )
    }

    /// Groups neighboring perceptual matches before highlight selection. This
    /// prevents a fixed target count from pulling several versions of the same
    /// burst back into the finished film when there are few unique moments.
    private static func similarityRepresentativeIDs(
        in candidates: [TripAsset],
        nativeResults: [String: NativePhotoIntelligenceResult]
    ) -> Set<String> {
        guard candidates.count > 1 else { return Set(candidates.map(\.id)) }
        let ordered = candidates.sorted(by: chronologicalOrder)
        var parents = Array(ordered.indices)

        for index in ordered.indices {
            guard let date = ordered[index].creationDate, index > 0 else { continue }
            var compared = 0
            for previousIndex in stride(from: index - 1, through: 0, by: -1) {
                guard let previousDate = ordered[previousIndex].creationDate else { continue }
                if date.timeIntervalSince(previousDate) > NativePhotoSimilarity.maximumTimeInterval {
                    break
                }
                compared += 1
                if compared > 32 { break }
                guard visuallySimilar(
                    ordered[index],
                    ordered[previousIndex],
                    nativeResults: nativeResults
                ) else { continue }
                union(index, previousIndex, parents: &parents)
            }
        }

        var groups: [Int: [TripAsset]] = [:]
        for index in ordered.indices {
            let group = root(index, parents: &parents)
            groups[group, default: []].append(ordered[index])
        }

        return Set(groups.values.compactMap { members in
            members.sorted { left, right in
                let leftScore = representativeScore(left, nativeResults: nativeResults)
                let rightScore = representativeScore(right, nativeResults: nativeResults)
                if leftScore != rightScore { return leftScore > rightScore }
                switch (left.creationDate, right.creationDate) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate < rightDate
                default:
                    return left.id < right.id
                }
            }.first?.id
        })
    }

    private static func representativeScore(
        _ asset: TripAsset,
        nativeResults: [String: NativePhotoIntelligenceResult]
    ) -> Double {
        guard let result = nativeResults[asset.id] else { return 0.35 }
        var value = (0.62 * result.scores.memoryScore)
            + (0.32 * (result.scores.aestheticScore ?? 0.52))
        if result.tags.contains(.groupPhoto) { value += 0.14 }
        if result.tags.contains(.people) { value += 0.08 }
        if result.tags.contains(.scenery) { value += 0.05 }
        return value
    }

    private static func root(_ index: Int, parents: inout [Int]) -> Int {
        if parents[index] != index {
            parents[index] = root(parents[index], parents: &parents)
        }
        return parents[index]
    }

    private static func union(_ first: Int, _ second: Int, parents: inout [Int]) {
        let firstRoot = root(first, parents: &parents)
        let secondRoot = root(second, parents: &parents)
        guard firstRoot != secondRoot else { return }
        if firstRoot < secondRoot {
            parents[secondRoot] = firstRoot
        } else {
            parents[firstRoot] = secondRoot
        }
    }

    private static func chronologicalOrder(_ left: TripAsset, _ right: TripAsset) -> Bool {
        switch (left.creationDate, right.creationDate) {
        case let (leftDate?, rightDate?) where leftDate != rightDate:
            return leftDate < rightDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return left.id < right.id
        }
    }

    private static func contentKind(
        for result: NativePhotoIntelligenceResult
    ) -> MontageContentKind {
        if result.tags.contains(.groupPhoto) || result.tags.contains(.people) { return .people }
        if result.tags.contains(.scenery) { return .scenery }
        if result.tags.contains(.food) { return .food }
        return .moment
    }
}
