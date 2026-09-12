import Foundation
import Photos
import PhotosUI
import SwiftUI

enum AppScreen: String {
    case welcome
    case access
    case limited
    case trips
    case empty
    case building
    case firstWatch
    case firstCutOptions
    case aiDirection
    case aiProcessing
    case aiComparison
    case aiVideoIntro
    case aiVideoGenerating
    case aiVideoReady
    case cut
    case pace
    case secondWatch
    case export
    case paywall
    case rendering
    case done
    case cleanup

    fileprivate var motionOrder: Int {
        switch self {
        case .welcome: 0
        case .access: 1
        case .limited: 2
        case .trips, .empty: 3
        case .building: 4
        case .firstWatch: 5
        case .firstCutOptions: 6
        case .aiDirection: 7
        case .aiProcessing: 8
        case .aiComparison: 9
        case .aiVideoIntro, .aiVideoGenerating, .aiVideoReady: 10
        case .secondWatch: 11
        case .cut, .pace: 12
        case .export: 13
        case .paywall, .rendering: 14
        case .done: 15
        case .cleanup: 16
        }
    }
}

enum PhotoSource: Hashable, Sendable {
    case bundled(String)
    case library(String)
    case imported(String)
}

struct TripAsset: Identifiable, Hashable, Sendable {
    let id: String
    let source: PhotoSource
    let creationDate: Date?
    let filename: String
    let isScreenshot: Bool
    let pixelWidth: Int
    let pixelHeight: Int

    init(
        id: String,
        source: PhotoSource,
        creationDate: Date?,
        filename: String,
        isScreenshot: Bool = false,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.id = id
        self.source = source
        self.creationDate = creationDate
        self.filename = filename
        self.isScreenshot = isScreenshot
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
    }
}

struct Trip: Identifiable, Hashable, Sendable {
    let id: String
    let place: String
    let dates: String
    let startDate: Date
    let endDate: Date
    let assets: [TripAsset]
    let coverID: String

    var photoCount: Int { assets.count }

    var coverSource: PhotoSource {
        assets.first(where: { $0.id == coverID })?.source
            ?? assets.first?.source
            ?? .bundled("my-khe-beach")
    }

    var shortPlace: String {
        place.split(separator: ",", maxSplits: 1).first.map(String.init) ?? place
    }

    func renamed(_ newPlace: String) -> Trip {
        Trip(
            id: id,
            place: newPlace,
            dates: dates,
            startDate: startDate,
            endDate: endDate,
            assets: assets,
            coverID: coverID
        )
    }

    func retainingAssets(withIDs identifiers: Set<String>) -> Trip? {
        let retained = assets.filter { identifiers.contains($0.id) }
        guard !retained.isEmpty else { return nil }
        return Trip(
            id: id,
            place: place,
            dates: dates,
            startDate: startDate,
            endDate: endDate,
            assets: retained,
            coverID: identifiers.contains(coverID) ? coverID : retained[retained.count / 2].id
        )
    }

    func replacingAssets(_ replacement: [TripAsset]) -> Trip? {
        guard !replacement.isEmpty else { return nil }
        let sorted = replacement.sorted {
            switch ($0.creationDate, $1.creationDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return $0.id < $1.id
            }
        }
        return Trip(
            id: id,
            place: place,
            dates: dates,
            startDate: startDate,
            endDate: endDate,
            assets: sorted,
            coverID: sorted.contains(where: { $0.id == coverID })
                ? coverID
                : sorted[sorted.count / 2].id
        )
    }
}

struct ReelPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let source: PhotoSource
    let label: String
    let time: String
    let isSimilar: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let protectsPeople: Bool
    let automaticFrameStyle: MontageFrameStyle
    let automaticMotionStyle: MontageMotionStyle
    let automaticCropScale: Double
    let automaticCropOffsetX: Double
    let automaticCropOffsetY: Double
    var frameStyle: MontageFrameStyle
    var motionStyle: MontageMotionStyle
    var hasCustomFrameStyle: Bool
    var cropScale: Double
    var cropOffsetX: Double
    var cropOffsetY: Double
    var durationSeconds: Double?

    init(
        id: String,
        source: PhotoSource,
        label: String,
        time: String,
        isSimilar: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        protectsPeople: Bool = false,
        frameStyle: MontageFrameStyle,
        motionStyle: MontageMotionStyle,
        cropScale: Double = 1,
        cropOffsetX: Double = 0,
        cropOffsetY: Double = 0,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.source = source
        self.label = label
        self.time = time
        self.isSimilar = isSimilar
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.protectsPeople = protectsPeople
        automaticFrameStyle = frameStyle
        automaticMotionStyle = motionStyle
        automaticCropScale = min(max(cropScale, 1), 3)
        automaticCropOffsetX = min(max(cropOffsetX, -1), 1)
        automaticCropOffsetY = min(max(cropOffsetY, -1), 1)
        self.frameStyle = frameStyle
        self.motionStyle = motionStyle
        hasCustomFrameStyle = false
        self.cropScale = automaticCropScale
        self.cropOffsetX = automaticCropOffsetX
        self.cropOffsetY = automaticCropOffsetY
        self.durationSeconds = durationSeconds.map { min(max($0, 0.6), 4) }
    }

    var aspectRatio: Double {
        guard pixelWidth > 0, pixelHeight > 0 else { return 4.0 / 3.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    var usesAutomaticPeopleFraming: Bool {
        protectsPeople
            && !hasCustomFrameStyle
            && motionStyle == automaticMotionStyle
            && cropScale == automaticCropScale
            && cropOffsetX == automaticCropOffsetX
            && cropOffsetY == automaticCropOffsetY
    }
}

enum MontageFrameStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case fullBleed
    case portraitMatte
    case cinematic
    case postcard

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fullBleed: "Fill"
        case .portraitMatte: "Portrait"
        case .cinematic: "Cinema"
        case .postcard: "Print"
        }
    }

    var symbol: String {
        switch self {
        case .fullBleed: "rectangle.inset.filled"
        case .portraitMatte: "rectangle.portrait"
        case .cinematic: "film"
        case .postcard: "photo.on.rectangle"
        }
    }
}

enum MontageMotionStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case zoomIn
    case zoomOut
    case panLeft
    case panRight
    case rise
    case settle

    var id: String { rawValue }

    var name: String {
        switch self {
        case .zoomIn: "Zoom in"
        case .zoomOut: "Zoom out"
        case .panLeft: "Pan left"
        case .panRight: "Pan right"
        case .rise: "Rise"
        case .settle: "Settle"
        }
    }
}

private struct PhotoEditOverride: Hashable, Sendable {
    var frameStyle: MontageFrameStyle?
    var motionStyle: MontageMotionStyle?
    var cropScale: Double?
    var cropOffsetX: Double?
    var cropOffsetY: Double?
    var durationSeconds: Double?
}

enum MontageLook: String, CaseIterable, Identifiable, Hashable, Sendable {
    case story
    case cinema
    case journal
    case clean

    var id: String { rawValue }

    var name: String {
        switch self {
        case .story: "Story"
        case .cinema: "Cinema"
        case .journal: "Journal"
        case .clean: "Clean"
        }
    }

    var detail: String {
        switch self {
        case .story: "An automatic mix matched to each photo"
        case .cinema: "Wide frames, soft mattes, and quieter cuts"
        case .journal: "Warm prints and tactile postcard moments"
        case .clean: "Simple full-bleed photos with minimal framing"
        }
    }

    var symbol: String {
        switch self {
        case .story: "wand.and.stars"
        case .cinema: "film"
        case .journal: "rectangle.stack"
        case .clean: "rectangle.inset.filled"
        }
    }
}

enum MontageMotionIntensity: String, CaseIterable, Identifiable, Hashable, Sendable {
    case still
    case gentle
    case expressive

    var id: String { rawValue }

    var name: String {
        switch self {
        case .still: "Still"
        case .gentle: "Gentle"
        case .expressive: "Expressive"
        }
    }

    var amplitude: Double {
        switch self {
        case .still: 0
        case .gentle: 0.62
        case .expressive: 1
        }
    }
}

/// One source of truth for the look-to-frame mapping used by both the live
/// SwiftUI preview and the exported video renderer.
enum MontageFrameResolver {
    static func resolve(
        planned: MontageFrameStyle,
        aspectRatio: Double,
        index: Int,
        isCustomized: Bool,
        look: MontageLook,
        protectsPeople: Bool = false
    ) -> MontageFrameStyle {
        if isCustomized { return planned }
        if protectsPeople {
            return aspectRatio >= 1.25 ? .cinematic : .portraitMatte
        }
        switch look {
        case .story:
            return planned
        case .cinema:
            return aspectRatio < 0.88 ? .portraitMatte : .cinematic
        case .journal:
            return index % 3 == 2 && aspectRatio >= 0.88 ? .fullBleed : .postcard
        case .clean:
            return aspectRatio < 0.88 ? .portraitMatte : .fullBleed
        }
    }
}

enum MontageContentKind: String, Hashable, Sendable {
    case scenery
    case people
    case food
    case moment
}

struct MontagePhotoInsight: Hashable, Sendable {
    let memoryScore: Double
    let aestheticScore: Double
    let contentKind: MontageContentKind
    let peopleCount: Int
    let classifications: [NativePhotoClassification]
    let featurePrint: NativePhotoFeaturePrint?
    let focalPoint: NativePhotoFocalPoint?

    init(
        memoryScore: Double = 0.5,
        aestheticScore: Double = 0.5,
        contentKind: MontageContentKind = .moment,
        peopleCount: Int = 0,
        classifications: [NativePhotoClassification] = [],
        featurePrint: NativePhotoFeaturePrint? = nil,
        focalPoint: NativePhotoFocalPoint? = nil
    ) {
        self.memoryScore = min(max(memoryScore, 0), 1)
        self.aestheticScore = min(max(aestheticScore, 0), 1)
        self.contentKind = contentKind
        self.peopleCount = max(0, peopleCount)
        self.classifications = classifications
        self.featurePrint = featurePrint
        self.focalPoint = focalPoint
    }

    init(result: NativePhotoIntelligenceResult) {
        let kind: MontageContentKind
        if result.tags.contains(.groupPhoto) || result.tags.contains(.people) {
            kind = .people
        } else if result.tags.contains(.scenery) {
            kind = .scenery
        } else if result.tags.contains(.food) {
            kind = .food
        } else {
            kind = .moment
        }
        self.init(
            memoryScore: result.scores.memoryScore,
            aestheticScore: result.scores.aestheticScore ?? 0.5,
            contentKind: kind,
            peopleCount: max(result.signals.faces.count, result.signals.humans.count),
            classifications: result.signals.classifications,
            featurePrint: result.signals.featurePrint,
            focalPoint: result.signals.focalPoint
        )
    }
}

enum AIVideoMomentRole: String, CaseIterable, Hashable, Sendable {
    case beginning
    case ending

    var title: String {
        switch self {
        case .beginning: "Beginning"
        case .ending: "Ending"
        }
    }
}

struct AIVideoMomentRecommendation: Equatable, Sendable {
    let photoIDs: [String]
    let isVisionBased: Bool
}

/// Selects two complementary story anchors from the already-computed local
/// Vision results. The first favors a strong sense of place; the second favors
/// people and emotional payoff. Nothing leaves the device during this step.
enum AIVideoMomentRecommender {
    static func recommend(
        photos: [ReelPhoto],
        insights: [String: MontagePhotoInsight]
    ) -> AIVideoMomentRecommendation {
        var seen = Set<String>()
        let candidates = photos.filter { seen.insert($0.id).inserted }
        guard candidates.count > 1 else {
            return AIVideoMomentRecommendation(
                photoIDs: candidates.map(\.id),
                isVisionBased: candidates.first.map { insights[$0.id] != nil } ?? false
            )
        }

        let denominator = Double(max(1, candidates.count - 1))
        var bestPair = (first: 0, second: candidates.count - 1, score: -Double.infinity)

        for firstIndex in 0..<(candidates.count - 1) {
            for secondIndex in (firstIndex + 1)..<candidates.count {
                let first = candidates[firstIndex]
                let second = candidates[secondIndex]
                let firstInsight = insights[first.id] ?? MontagePhotoInsight()
                let secondInsight = insights[second.id] ?? MontagePhotoInsight()
                let firstPosition = Double(firstIndex) / denominator
                let secondPosition = Double(secondIndex) / denominator
                let separation = Double(secondIndex - firstIndex) / denominator

                var score = openingScore(firstInsight, position: firstPosition)
                    + endingScore(secondInsight, position: secondPosition)
                    + min(0.20, separation * 0.20)

                if firstInsight.contentKind != secondInsight.contentKind {
                    score += 0.10
                }
                if orientationBucket(first) == orientationBucket(second) {
                    score += 0.04
                }
                if areNearDuplicates(firstInsight, secondInsight) {
                    score -= 1.4
                }

                if score > bestPair.score {
                    bestPair = (firstIndex, secondIndex, score)
                }
            }
        }

        let selected = [candidates[bestPair.first], candidates[bestPair.second]]
        return AIVideoMomentRecommendation(
            photoIDs: selected.map(\.id),
            isVisionBased: selected.allSatisfy { insights[$0.id] != nil }
        )
    }

    private static func openingScore(
        _ insight: MontagePhotoInsight,
        position: Double
    ) -> Double {
        var score = (0.58 * insight.memoryScore) + (0.34 * insight.aestheticScore)
        if insight.contentKind == .scenery { score += 0.28 }
        if insight.contentKind == .moment { score += 0.08 }
        score += (1 - position) * 0.10
        return score
    }

    private static func endingScore(
        _ insight: MontagePhotoInsight,
        position: Double
    ) -> Double {
        var score = (0.58 * insight.memoryScore) + (0.34 * insight.aestheticScore)
        if insight.contentKind == .people { score += 0.24 }
        if insight.peopleCount > 1 { score += 0.12 }
        if insight.contentKind == .moment { score += 0.08 }
        score += position * 0.10
        return score
    }

    private static func orientationBucket(_ photo: ReelPhoto) -> Int {
        if photo.aspectRatio < 0.88 { return 0 }
        if photo.aspectRatio > 1.25 { return 2 }
        return 1
    }

    private static func areNearDuplicates(
        _ first: MontagePhotoInsight,
        _ second: MontagePhotoInsight
    ) -> Bool {
        // Global feature prints can overvalue a repeated classroom or stage
        // background. Do not collapse people moments when faces may differ.
        guard first.peopleCount == 0,
              second.peopleCount == 0,
              let firstPrint = first.featurePrint,
              let secondPrint = second.featurePrint,
              let distance = try? firstPrint.distance(to: secondPrint) else {
            return false
        }
        return distance <= 7
    }
}

struct MontagePlanItem: Hashable, Sendable {
    let asset: TripAsset
    let frameStyle: MontageFrameStyle
    let motionStyle: MontageMotionStyle
    let isSimilar: Bool
    let protectsPeople: Bool
    let cropScale: Double
    let cropOffsetX: Double
    let cropOffsetY: Double
}

/// Creates a small editorial arc for each day while keeping the trip's days in
/// order. Vision scores choose strong openers and category/orientation variety;
/// unavailable analysis falls back to a stable chronological sequence.
enum MontageSequencePlanner {
    static func plan(
        assets: [TripAsset],
        insights: [String: MontagePhotoInsight],
        calendar: Calendar = .current
    ) -> [MontagePlanItem] {
        guard !assets.isEmpty else { return [] }
        let chronological = assets.sorted(by: chronologicalOrder)
        let dayGroups = Dictionary(grouping: chronological) { asset -> Date in
            guard let date = asset.creationDate else { return .distantPast }
            return calendar.startOfDay(for: date)
        }
        let orderedDays = dayGroups.keys.sorted()
        let editorial = orderedDays.flatMap { day in
            editorialOrder(dayGroups[day] ?? [], insights: insights)
        }

        return editorial.enumerated().map { index, asset in
            let ratio = aspectRatio(of: asset)
            let insight = insights[asset.id]
            let protectsPeople = (insight?.peopleCount ?? 0) > 0
            let style: MontageFrameStyle
            if protectsPeople {
                // A fit-based frame preserves the complete person/group
                // composition instead of forcing a landscape photo to fill a
                // tall movie and cropping people at the sides.
                style = ratio >= 1.25 ? .cinematic : .portraitMatte
            } else if ratio < 0.88 {
                // Portrait photos should start large and legible. Postcards can
                // still be selected manually, but are too small as an automatic
                // default on a phone-sized vertical film.
                style = .portraitMatte
            } else if ratio >= 1.72 {
                style = .cinematic
            } else if index % 5 == 2 {
                style = .postcard
            } else {
                style = .fullBleed
            }

            let previous = index > 0 ? editorial[index - 1] : nil
            let crop = cropRecommendation(
                frameStyle: style,
                aspectRatio: ratio,
                insight: insight
            )
            return MontagePlanItem(
                asset: asset,
                frameStyle: style,
                motionStyle: motionStyle(
                    at: index,
                    asset: asset,
                    insight: insight
                ),
                isSimilar: previous.map {
                    areVisuallySimilar($0, asset, insights: insights)
                } ?? false,
                protectsPeople: protectsPeople,
                cropScale: crop.scale,
                cropOffsetX: crop.offsetX,
                cropOffsetY: crop.offsetY
            )
        }
    }

    private static func editorialOrder(
        _ assets: [TripAsset],
        insights: [String: MontagePhotoInsight]
    ) -> [TripAsset] {
        guard assets.count > 2, !insights.isEmpty else {
            return assets.sorted(by: chronologicalOrder)
        }

        let source = assets.sorted(by: chronologicalOrder)
        let ranks = Dictionary(uniqueKeysWithValues: source.enumerated().map { ($0.element.id, $0.offset) })
        var remaining = source
        var ordered: [TripAsset] = []

        while !remaining.isEmpty {
            let targetRank = ordered.count
            let previous = ordered.last
            let bestIndex = remaining.indices.max { left, right in
                candidateScore(
                    remaining[left],
                    previous: previous,
                    targetRank: targetRank,
                    chronologicalRank: ranks[remaining[left].id] ?? 0,
                    insights: insights
                ) < candidateScore(
                    remaining[right],
                    previous: previous,
                    targetRank: targetRank,
                    chronologicalRank: ranks[remaining[right].id] ?? 0,
                    insights: insights
                )
            } ?? remaining.startIndex
            ordered.append(remaining.remove(at: bestIndex))
        }
        return ordered
    }

    private static func candidateScore(
        _ asset: TripAsset,
        previous: TripAsset?,
        targetRank: Int,
        chronologicalRank: Int,
        insights: [String: MontagePhotoInsight]
    ) -> Double {
        let insight = insights[asset.id] ?? MontagePhotoInsight()
        var score = (0.58 * insight.memoryScore) + (0.30 * insight.aestheticScore)
        if targetRank == 0 {
            score += insight.contentKind == .scenery ? 0.32 : 0.08
            score += aspectRatio(of: asset) >= 1.2 ? 0.08 : 0
        } else {
            score -= Double(abs(chronologicalRank - targetRank)) * 0.012
        }

        if let previous {
            let previousInsight = insights[previous.id] ?? MontagePhotoInsight()
            if previousInsight.contentKind == insight.contentKind { score -= 0.22 }
            let previousPortrait = aspectRatio(of: previous) < 0.88
            if previousPortrait == (aspectRatio(of: asset) < 0.88) { score -= 0.07 }
            if areVisuallySimilar(previous, asset, insights: insights) { score -= 0.55 }
        }
        return score
    }

    private static func areVisuallySimilar(
        _ first: TripAsset,
        _ second: TripAsset,
        insights: [String: MontagePhotoInsight]
    ) -> Bool {
        guard let firstInsight = insights[first.id],
              let secondInsight = insights[second.id],
              let firstPrint = firstInsight.featurePrint,
              let secondPrint = secondInsight.featurePrint,
              NativePhotoSimilarity.areSimilar(
                first,
                firstPrint: firstPrint,
                second,
                secondPrint: secondPrint,
                firstProtectsPeople: firstInsight.peopleCount > 0,
                secondProtectsPeople: secondInsight.peopleCount > 0
              ) else {
            return false
        }
        return true
    }

    private static func aspectRatio(of asset: TripAsset) -> Double {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 4.0 / 3.0 }
        return Double(asset.pixelWidth) / Double(asset.pixelHeight)
    }

    private static func motionStyle(
        at index: Int,
        asset: TripAsset,
        insight: MontagePhotoInsight?
    ) -> MontageMotionStyle {
        let ratio = aspectRatio(of: asset)
        if ratio < 0.88 {
            return index.isMultiple(of: 2) ? .rise : .settle
        }
        if insight?.contentKind == .people {
            return index.isMultiple(of: 2) ? .zoomIn : .zoomOut
        }
        if ratio >= 1.72 {
            return index.isMultiple(of: 2) ? .panLeft : .panRight
        }
        return MontageMotionStyle.allCases[index % MontageMotionStyle.allCases.count]
    }

    private static func cropRecommendation(
        frameStyle: MontageFrameStyle,
        aspectRatio: Double,
        insight: MontagePhotoInsight?
    ) -> (scale: Double, offsetX: Double, offsetY: Double) {
        if (insight?.peopleCount ?? 0) > 0 {
            // Keep the whole detected human composition visible by default.
            // Users can still choose a tighter frame explicitly in the editor.
            return (1, 0, 0)
        }

        guard let focalPoint = insight?.focalPoint else {
            // A small overscan keeps portrait motion fluid and makes the
            // preserve-composition matte feel intentional rather than tiny.
            return aspectRatio < 0.88 ? (1.06, 0, 0) : (1, 0, 0)
        }

        // A wide union usually represents a group. Keep that composition roomy;
        // a small single subject can tolerate a little more emphasis.
        let protectsGroup = focalPoint.source == .faces && focalPoint.coverage >= 0.24
        let scale: Double
        if protectsGroup {
            scale = 1.06
        } else if aspectRatio < 0.88 || frameStyle == .portraitMatte {
            scale = 1.10
        } else {
            scale = 1.06
        }

        let focusStrength = protectsGroup ? 0.78 : 1.35
        // The crop transform moves by 24% of the frame per normalized unit.
        // Limit the offset to the extra image supplied by the zoom so Auto can
        // never reveal a blank edge.
        let offsetLimit = min(0.52, max(0, (scale - 1) / 0.48))
        let horizontal = min(
            max((0.5 - focalPoint.x) * focusStrength, -offsetLimit),
            offsetLimit
        )
        // Vision uses a lower-left origin; SwiftUI and the exporter use a
        // top-left visual coordinate system, hence the inverted sign here.
        let vertical = min(
            max((focalPoint.y - 0.5) * focusStrength, -offsetLimit),
            offsetLimit
        )
        return (scale, horizontal, vertical)
    }

    private static func chronologicalOrder(_ lhs: TripAsset, _ rhs: TripAsset) -> Bool {
        switch (lhs.creationDate, rhs.creationDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.id < rhs.id
        }
    }
}

struct LocalTitlePlan: Hashable, Sendable {
    let enabledCards: Set<TitleCardKind>
    let drafts: [TitleCardKind: TitleCardDraft]
}

/// Turns PhotoKit time/place metadata and Apple's on-device Vision labels into
/// restrained editorial language. This deliberately uses a small deterministic
/// vocabulary: local classification can suggest a useful theme, but it should
/// never invent a landmark, activity, or relationship that the phone did not
/// actually observe.
enum LocalStoryIntelligence {
    private enum Theme: Hashable, Sendable {
        case people
        case event
        case food
        case water
        case nature
        case city
        case mixed
    }

    static func collectionTitle(
        for trip: Trip,
        isNearby: Bool,
        calendar: Calendar = .current
    ) -> String {
        let place = friendlyPlaceName(from: trip.place)
        let days = inclusiveDayCount(for: trip, calendar: calendar)

        if isNearby {
            let moment = nearbyMoment(for: trip, calendar: calendar)
            return place.map { "\(moment) around \($0)" }
                ?? "\(moment) nearby"
        }

        guard let place else {
            if days == 1 { return "A day away" }
            if (6...8).contains(days) { return "A week away" }
            return "\(dayWord(days)) days away"
        }
        if days == 1 { return "A day in \(place)" }
        if (6...8).contains(days) { return "A week in \(place)" }
        return "\(dayWord(days)) days in \(place)"
    }

    static func locationContext(for trip: Trip) -> String? {
        let trimmed = trip.place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPlaceholderPlace(trimmed) else { return nil }
        return trimmed
    }

    static func friendlyPlaceName(from rawPlace: String) -> String? {
        guard !isPlaceholderPlace(rawPlace) else { return nil }
        var name = rawPlace
            .split(separator: ",", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        name = removingPrefix("Mueang ", from: name)
        for suffix in [" Metropolitan District", " Municipality", " Province", " District"] {
            name = removingSuffix(suffix, from: name)
        }
        if name.compare("Singapore Island", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            name = "Singapore"
        }
        return name.isEmpty ? nil : name
    }

    static func makeTitlePlan(
        for trip: Trip,
        photos: [ReelPhoto],
        insights: [String: MontagePhotoInsight],
        isNearby: Bool,
        calendar: Calendar = .current
    ) -> LocalTitlePlan {
        let photoIDs = Set(photos.map(\.id))
        let relevantInsights = insights.filter { photoIDs.contains($0.key) }
        let theme = dominantTheme(for: photos, insights: relevantInsights)
        let place = friendlyPlaceName(from: trip.place)
        let openingTitle = openingHeadline(
            theme: theme,
            trip: trip,
            place: place,
            isNearby: isNearby,
            calendar: calendar
        )
        let exactPlace = locationContext(for: trip)
        let openingSubtitle: String
        if let exactPlace,
           openingTitle.range(
               of: place ?? exactPlace,
               options: [.caseInsensitive, .diacriticInsensitive]
           ) == nil {
            openingSubtitle = "\(exactPlace) · \(trip.dates)"
        } else {
            openingSubtitle = trip.dates
        }

        var enabled: Set<TitleCardKind> = [.opening]
        var drafts: [TitleCardKind: TitleCardDraft] = [
            .opening: TitleCardDraft(
                title: openingTitle,
                subtitle: openingSubtitle,
                style: theme == .event ? .bold : .editorial,
                duration: TitleCardKind.opening.defaultDuration
            )
        ]

        if photos.count >= 6,
           let insertion = middleInsertion(
               for: trip,
               photos: photos,
               insights: relevantInsights,
               calendar: calendar
           ) {
            enabled.insert(.place)
            drafts[.place] = TitleCardDraft(
                title: middleHeadline(for: insertion.theme),
                subtitle: insertion.dayNumber.map { "Day \($0) of \(insertion.totalDays)" } ?? "",
                style: insertion.theme == .event ? .bold : .clean,
                duration: TitleCardKind.place.defaultDuration,
                afterPhotoID: insertion.afterPhotoID
            )
        } else {
            drafts[.place] = TitleCardDraft(
                title: "A new chapter",
                subtitle: "",
                style: .clean,
                duration: TitleCardKind.place.defaultDuration
            )
        }

        if photos.count >= 12 {
            enabled.insert(.ending)
        }
        drafts[.ending] = TitleCardDraft(
            title: theme == .people ? "The moments we shared" : "Until next time",
            subtitle: monthYear(for: trip.startDate),
            style: .editorial,
            duration: TitleCardKind.ending.defaultDuration
        )

        return LocalTitlePlan(enabledCards: enabled, drafts: drafts)
    }

    private struct MiddleInsertion {
        let afterPhotoID: String
        let theme: Theme
        let dayNumber: Int?
        let totalDays: Int
    }

    private static func middleInsertion(
        for trip: Trip,
        photos: [ReelPhoto],
        insights: [String: MontagePhotoInsight],
        calendar: Calendar
    ) -> MiddleInsertion? {
        guard photos.count >= 4 else { return nil }
        let datesByID = Dictionary(uniqueKeysWithValues: trip.assets.compactMap { asset in
            asset.creationDate.map { (asset.id, $0) }
        })
        let midpoint = Double(photos.count - 1) / 2
        let dayBoundaries = photos.indices.dropFirst().compactMap { index -> Int? in
            guard index >= 2, index <= photos.count - 2,
                  let previous = datesByID[photos[index - 1].id],
                  let current = datesByID[photos[index].id],
                  !calendar.isDate(previous, inSameDayAs: current) else { return nil }
            return index
        }
        if let boundary = dayBoundaries.min(by: {
            abs(Double($0) - midpoint) < abs(Double($1) - midpoint)
        }) {
            let dayStarts = Set(photos.prefix(boundary + 1).compactMap { photo in
                datesByID[photo.id].map { calendar.startOfDay(for: $0) }
            })
            return MiddleInsertion(
                afterPhotoID: photos[boundary - 1].id,
                theme: dominantTheme(
                    for: Array(photos[boundary...]),
                    insights: insights
                ),
                dayNumber: max(2, dayStarts.count),
                totalDays: inclusiveDayCount(for: trip, calendar: calendar)
            )
        }

        let validRange = 2...(photos.count - 2)
        let transitions = validRange.filter { index in
            guard let left = insights[photos[index - 1].id],
                  let right = insights[photos[index].id] else { return false }
            return left.contentKind != right.contentKind
        }
        let boundary = transitions.min(by: {
            abs(Double($0) - midpoint) < abs(Double($1) - midpoint)
        }) ?? max(2, min(photos.count - 2, photos.count / 2))
        return MiddleInsertion(
            afterPhotoID: photos[boundary - 1].id,
            theme: dominantTheme(for: Array(photos[boundary...]), insights: insights),
            dayNumber: nil,
            totalDays: inclusiveDayCount(for: trip, calendar: calendar)
        )
    }

    private static func dominantTheme(
        for photos: [ReelPhoto],
        insights: [String: MontagePhotoInsight]
    ) -> Theme {
        var evidence: [Theme: Double] = [:]
        var observed = 0
        for photo in photos {
            guard let insight = insights[photo.id] else { continue }
            observed += 1
            switch insight.contentKind {
            case .people:
                evidence[.people, default: 0] += 1 + min(0.35, Double(insight.peopleCount) * 0.08)
            case .food:
                evidence[.food, default: 0] += 1
            case .scenery:
                evidence[.nature, default: 0] += 0.62
            case .moment:
                break
            }

            for classification in insight.classifications {
                let label = normalized(classification.identifier)
                if let (theme, _) = classificationTerms.first(where: { _, terms in
                    terms.contains(where: label.contains)
                }) {
                    let confidence = min(max(Double(classification.confidence), 0), 1)
                    let multiplier = theme == .event ? 1.45 : 1.25
                    evidence[theme, default: 0] += confidence * multiplier
                }
            }
        }

        let ranked = evidence.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return themeOrder(lhs.key) < themeOrder(rhs.key)
        }
        guard observed >= 2,
              let strongest = ranked.first,
              strongest.value >= max(1.15, Double(observed) * 0.24) else {
            return .mixed
        }
        return strongest.key
    }

    private static func openingHeadline(
        theme: Theme,
        trip: Trip,
        place: String?,
        isNearby: Bool,
        calendar: Calendar
    ) -> String {
        switch theme {
        case .people:
            return place.map { "Together in \($0)" } ?? "Better together"
        case .event:
            return "The day came alive"
        case .food:
            return place.map { "A taste of \($0)" } ?? "A taste of the day"
        case .water:
            return "By the water"
        case .nature:
            return "Out in the open"
        case .city:
            return place.map { "Around \($0)" } ?? "Around the city"
        case .mixed:
            return collectionTitle(for: trip, isNearby: isNearby, calendar: calendar)
        }
    }

    private static func middleHeadline(for theme: Theme) -> String {
        switch theme {
        case .people: "The people in the story"
        case .event: "The day came alive"
        case .food: "A taste of the place"
        case .water: "Toward the water"
        case .nature: "Into the landscape"
        case .city: "Into the streets"
        case .mixed: "A new chapter"
        }
    }

    private static func inclusiveDayCount(for trip: Trip, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.startOfDay(for: trip.endDate)
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private static func nearbyMoment(for trip: Trip, calendar: Calendar) -> String {
        let dates = trip.assets.compactMap(\.creationDate).sorted()
        let representative = dates.isEmpty ? trip.startDate : dates[dates.count / 2]
        switch calendar.component(.hour, from: representative) {
        case 5..<12: return "A morning"
        case 12..<17: return "An afternoon"
        case 17..<24: return "An evening"
        default: return "A day"
        }
    }

    private static func monthYear(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: date)
    }

    private static func dayWord(_ day: Int) -> String {
        switch day {
        case 2: "Two"
        case 3: "Three"
        case 4: "Four"
        case 5: "Five"
        default: String(day)
        }
    }

    private static func isPlaceholderPlace(_ place: String) -> Bool {
        let normalized = place.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || normalized == "photo trip"
            || normalized == "photo memory"
            || normalized == "nearby outing"
            || normalized == "local memory"
            || normalized.hasPrefix("travel ·")
    }

    private static func removingPrefix(_ prefix: String, from value: String) -> String {
        guard value.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil else {
            return value
        }
        return String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingSuffix(_ suffix: String, from value: String) -> String {
        guard value.range(of: suffix, options: [.anchored, .backwards, .caseInsensitive]) != nil else {
            return value
        }
        return String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().map { character in
            character.isLetter || character.isNumber ? character : " "
        }.reduce(into: "") { result, character in
            if character != " " || result.last != " " { result.append(character) }
        }
    }

    private static func themeOrder(_ theme: Theme) -> Int {
        switch theme {
        case .people: 0
        case .event: 1
        case .food: 2
        case .water: 3
        case .nature: 4
        case .city: 5
        case .mixed: 6
        }
    }

    /// Ordered from specific story signals to broad scene labels so a label
    /// such as “beach sunset” becomes water, rather than being counted twice
    /// as both a coast and generic nature.
    private static let classificationTerms: [(Theme, [String])] = [
        (.event, ["award", "ceremony", "concert", "festival", "performance", "stage", "wedding", "classroom", "student", "school", "sports", "party"]),
        (.water, ["beach", "coast", "harbor", "lake", "marina", "ocean", "river", "sea", "waterfront", "waterfall", "boat"]),
        (.food, ["beverage", "cafe", "coffee", "cuisine", "dessert", "dish", "drink", "food", "meal", "restaurant"]),
        (.city, ["architecture", "building", "city", "cityscape", "landmark", "market", "street", "urban", "skyscraper"]),
        (.nature, ["forest", "garden", "landscape", "mountain", "nature", "park", "sunset", "trail", "tree"]),
        (.people, ["crowd", "family", "group", "people", "person", "portrait"])
    ]
}

enum TitleCardKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case opening
    case place
    case ending

    var id: String { rawValue }

    var name: String {
        switch self {
        case .opening: "Intro"
        case .place: "Story beat"
        case .ending: "Ending"
        }
    }

    var placement: String {
        switch self {
        case .opening: "Before the first photo"
        case .place: "At a natural chapter break"
        case .ending: "After the last photo"
        }
    }

    var defaultDuration: Double {
        switch self {
        case .opening: 2.4
        case .place: 1.9
        case .ending: 2.2
        }
    }
}

enum MontageTitleStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case editorial
    case clean
    case bold

    var id: String { rawValue }

    var name: String {
        switch self {
        case .editorial: "Editorial"
        case .clean: "Clean"
        case .bold: "Bold"
        }
    }
}

struct TitleCardDraft: Hashable, Sendable {
    var title: String
    var subtitle: String
    var style: MontageTitleStyle
    var duration: Double
    /// The photo after which a middle title appears. Opening and ending cards
    /// leave this nil. Keeping the anchor as an asset ID makes the placement
    /// survive editorial reordering and remain reversible.
    var afterPhotoID: String? = nil
}

struct MontageTitleCard: Identifiable, Hashable, Sendable {
    let kind: TitleCardKind
    let title: String
    let subtitle: String
    let style: MontageTitleStyle
    let duration: Double
    let afterPhotoID: String?

    init(
        kind: TitleCardKind,
        title: String,
        subtitle: String,
        style: MontageTitleStyle,
        duration: Double,
        afterPhotoID: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.duration = duration
        self.afterPhotoID = afterPhotoID
    }

    var id: String { "title-\(kind.rawValue)" }
}

enum MontageTimelineItem: Identifiable, Hashable, Sendable {
    case photo(ReelPhoto)
    case title(MontageTitleCard)

    var id: String {
        switch self {
        case let .photo(photo): "photo-\(photo.id)"
        case let .title(card): card.id
        }
    }

    func duration(defaultPhotoDuration: Double) -> Double {
        switch self {
        case let .photo(photo): photo.durationSeconds ?? defaultPhotoDuration
        case let .title(card): card.duration
        }
    }
}

enum MontageTimelineBuilder {
    static func make(
        photos: [ReelPhoto],
        titleCards: [MontageTitleCard]
    ) -> [MontageTimelineItem] {
        let titleByKind = Dictionary(uniqueKeysWithValues: titleCards.map { ($0.kind, $0) })
        let middleCard = titleByKind[.place]
        let requestedMiddleIndex = middleCard?.afterPhotoID.flatMap { anchorID in
            photos.firstIndex(where: { $0.id == anchorID })
        }
        // Older saved/default cards have no anchor and retain their original
        // placement after photo one. If a locally suggested anchor was later
        // removed, fall back to the nearest useful midpoint instead of silently
        // dropping the title from the film.
        let middleIndex: Int? = {
            guard middleCard != nil, !photos.isEmpty else { return nil }
            if let requestedMiddleIndex { return requestedMiddleIndex }
            if middleCard?.afterPhotoID != nil {
                return max(0, min(photos.count - 1, (photos.count / 2) - 1))
            }
            return 0
        }()
        var result: [MontageTimelineItem] = []
        if let opening = titleByKind[.opening] {
            result.append(.title(opening))
        }

        for (index, photo) in photos.enumerated() {
            result.append(.photo(photo))
            if index == middleIndex, let place = middleCard {
                result.append(.title(place))
            }
        }

        if photos.isEmpty, let place = titleByKind[.place] {
            result.append(.title(place))
        }
        if let ending = titleByKind[.ending] {
            result.append(.title(ending))
        }
        return result
    }
}

struct MusicTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let mood: String
    let tag: String
    let symbol: String
    let tint: Color
    let bars: [CGFloat]
    let resourceName: String?
    let sourceURL: String?
}

struct ProjectFormat: Identifiable, Hashable {
    let id: String
    let name: String
    let apps: String
    let fileExtension: String
}

struct PhotoDecision: Equatable {
    let id: String
    let previousIndex: Int
    let previousWasCut: Bool
}

private struct LibraryDetectionResult: Sendable {
    let trips: [DetectedTrip]
    let nearbyEvents: [DetectedTrip]
}

enum ExportQuality: Equatable, Sendable {
    case standard
    case hd

    var includesWatermark: Bool { self == .standard }
}

enum ExportHandoff: Equatable, Sendable {
    case normal
    case capCut
}

enum ExportIntent: Equatable, Sendable {
    case standard
    case highDefinition
    case capCut

    var quality: ExportQuality {
        self == .highDefinition ? .hd : .standard
    }

    var handoff: ExportHandoff {
        self == .capCut ? .capCut : .normal
    }
}

enum TripCutSource: String, Equatable, Sendable {
    case firstCut
    case aiCut
    case working

    var title: String {
        switch self {
        case .firstCut: "First Cut"
        case .aiCut: "AI Cut"
        case .working: "Your Cut"
        }
    }
}

struct TripEditSnapshot: Hashable, Sendable {
    let photos: [ReelPhoto]
    let cutPhotoIDs: Set<String>
    let pace: Double
    let montageLook: MontageLook
    let motionIntensity: MontageMotionIntensity
    let titleCards: Set<TitleCardKind>
    let titleDrafts: [TitleCardKind: TitleCardDraft]
    let textOverlays: [MontageTextOverlay]
    let selectedTrackID: String?
    let cutToBeat: Bool

    var keptPhotos: [ReelPhoto] {
        photos.filter { !cutPhotoIDs.contains($0.id) }
    }

    var montageTitleCards: [MontageTitleCard] {
        TitleCardKind.allCases.compactMap { kind in
            guard titleCards.contains(kind), let draft = titleDrafts[kind] else { return nil }
            return MontageTitleCard(
                kind: kind,
                title: draft.title,
                subtitle: draft.subtitle,
                style: draft.style,
                duration: draft.duration,
                afterPhotoID: draft.afterPhotoID
            )
        }
    }

    var durationSeconds: Double {
        let defaultPhotoDuration = 1.85 - (pace * 1.25)
        let photoDuration = keptPhotos.reduce(0) { partial, photo in
            partial + (photo.durationSeconds ?? defaultPhotoDuration)
        }
        return photoDuration + montageTitleCards.reduce(0) { $0 + $1.duration }
    }
}

enum MontageTextPlacement: String, CaseIterable, Identifiable, Hashable, Sendable {
    case top
    case center
    case bottom

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

enum MontageTextAnimation: String, CaseIterable, Identifiable, Hashable, Sendable {
    case fade
    case rise
    case pop

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

struct MontageTextOverlay: Identifiable, Hashable, Sendable {
    let id: String
    let photoID: String
    var text: String
    var style: MontageTitleStyle
    var placement: MontageTextPlacement
    var animation: MontageTextAnimation
}

struct AICutRecommendation: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case story
        case titles
        case music
        case treatment
    }

    let kind: Kind
    let title: String
    let detail: String

    var id: Kind { kind }
}

private struct AICutCandidatePhoto: Sendable {
    let photo: ReelPhoto
    let localSelection: CloudPhotoLocalSelection
}

struct AICutPhotoOption: Identifiable, Hashable, Sendable {
    let photo: ReelPhoto
    let localSelection: CloudPhotoLocalSelection

    var id: String { photo.id }
}

private struct AICutCandidate: Sendable {
    let photo: ReelPhoto
    let asset: TripAsset
    let localSelection: CloudPhotoLocalSelection
}

@MainActor
final class TripReelModel: ObservableObject {
    @Published var screen: AppScreen = .welcome
    @Published private(set) var navigationDirection: TRNavigationDirection = .replace
    @Published var buildCount = 0
    @Published var currentPhotoIndex = 0
    @Published var cutPhotoIDs: Set<String> = []
    @Published var history: [PhotoDecision] = []
    @Published var pace: Double = 0.46
    @Published var showCutHint = true
    @Published var renderProgress = 0.0
    @Published var titleCards: Set<TitleCardKind> = [.opening]
    @Published private(set) var titleDrafts: [TitleCardKind: TitleCardDraft] = [:]
    @Published private(set) var textOverlays: [MontageTextOverlay] = []
    @Published var selectedTrackID: String? = "wanderlust"
    @Published var cutToBeat = true
    @Published var selectedFormatID = "sequence"
    @Published var cleanupSelection: Set<String> = []
    @Published var cleanupShowsGrid = false
    @Published private(set) var isDeletingPhotos = false
    @Published private(set) var cleanupDeletionErrorMessage: String?
    @Published var selectedPhotoCount = 0
    @Published var exportQuality: ExportQuality = .standard
    @Published private(set) var exportHandoff: ExportHandoff = .normal
    @Published private(set) var pendingExportIntent: ExportIntent?
    @Published var montageLook: MontageLook = .story
    @Published var montageMotionIntensity: MontageMotionIntensity = .gentle
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var nearbyEvents: [Trip] = []
    @Published private(set) var selectedTrip: Trip?
    @Published private(set) var photos: [ReelPhoto] = []
    @Published private(set) var libraryPreviewPhotos: [ReelPhoto] = []
    @Published private(set) var libraryPhotoCount = 0
    @Published private(set) var isScanningLibrary = false
    @Published private(set) var libraryErrorMessage: String?
    @Published private(set) var cloudAnalysisPreference: CloudAnalysisPreference
    @Published var isCloudAnalysisConsentPresented = false
    @Published private(set) var cloudConsentIsSettings = false
    @Published private(set) var selectedAICutDirection: AICutDirection?
    @Published private(set) var selectedAICutPhotoIDs: Set<String> = []
    @Published var aiCutStoryContext = ""
    @Published private(set) var firstCutSnapshot: TripEditSnapshot?
    @Published private(set) var aiCutSnapshot: TripEditSnapshot?
    @Published private(set) var selectedCutSource: TripCutSource = .firstCut
    @Published private(set) var aiCutSummary: String?
    @Published private(set) var aiCutRecommendations: [AICutRecommendation] = []
    @Published private(set) var aiCutDiagnosis: AICutDiagnosis?
    @Published private(set) var aiCutComparison: AICutComparison?
    @Published private(set) var aiCutProgress = 0.0
    @Published private(set) var aiCutStatus = "Finding the strongest moments…"
    @Published private(set) var aiCutFailureMessage: String?
    @Published private(set) var aiVideoSource: TripCutSource = .aiCut
    @Published private(set) var aiVideoSelectedPhotoIDs: [String] = []
    @Published private(set) var aiVideoRecommendedPhotoIDs: [String] = []
    @Published private(set) var aiVideoRecommendationIsVisionBased = false
    @Published private(set) var aiVideoProgress = 0.0
    @Published private(set) var aiVideoStatus = "Preparing your memory…"
    @Published private(set) var aiVideoFailureMessage: String?
    @Published private(set) var aiVideoURL: URL?
    @Published private(set) var isSavingAIVideo = false
    @Published private(set) var aiVideoSaveMessage: String?
    @Published private(set) var isAnalyzingPhotos = false
    @Published private(set) var photoAnalysisProgress = 0.0
    @Published private(set) var photoAnalysisStatus = "Preparing smart selection"
    @Published private(set) var photoAnalysisCurrentAsset: TripAsset?
    @Published private(set) var photoAnalysisRecentAssets: [TripAsset] = []
    @Published private(set) var photoAnalysisProcessedCount = 0
    @Published private(set) var photoAnalysisTotalCount = 0
    @Published private(set) var excludedPhotos: [SmartExcludedPhoto] = []
    @Published private(set) var photoAnalysisFollowUp: PhotoAnalysisFollowUp?
    @Published var isSmartSelectionReviewPresented = false
    @Published private(set) var exportedVideoURL: URL?
    @Published private(set) var exportErrorMessage: String?
    @Published private(set) var exportErrorTitle = "Export couldn't finish"
    @Published private(set) var exportCanRetryPhotoDownload = false
    @Published private(set) var exportProgressPhase: TripReelVideoExportPhase = .preparingPhotos(
        ready: 0,
        total: 0,
        currentLabel: nil,
        downloadProgress: nil
    )
    @Published private(set) var isSavingExport = false
    @Published private(set) var exportSaveMessage: String?

    let usesDemoData: Bool

    private let photoLibrary: any PhotoLibraryServing
    private let cloudPhotoAnalysis: any CloudPhotoAnalysisServing
    private let aiVideoGeneration: any AIVideoGenerationServing
    private let photoAnalysisThumbnails: any PhotoAnalysisThumbnailServing
    private let nativePhotoIntelligence: any NativePhotoIntelligenceServing
    private let preferenceStore: UserDefaults
    private let manualPhotoImporter = ManualPhotoImportService()
    private var workTask: Task<Void, Never>?
    private var photoAnalysisTask: Task<Void, Never>?
    private var aiCutTask: Task<Void, Never>?
    private var aiVideoTask: Task<Void, Never>?
    private var photoAnalysisGeneration = UUID()
    private var aiCutGeneration = UUID()
    private var aiVideoGenerationID = UUID()
    private var exportGeneration = UUID()
    private var exportReturnScreen: AppScreen = .secondWatch
    private var studioReturnScreen: AppScreen = .firstCutOptions
    private var placeTask: Task<Void, Never>?
    private var detectorTask: Task<LibraryDetectionResult, Never>?
    private var scanGeneration = UUID()
    private var manualSelectionGeneration = UUID()
    private var pendingResultNavigation = false
    private var isManualSelectionInProgress = false
    private var scanCoordinatorActive = false
    private var scanAgainRequested = false
    private var hasScannedLibrary = false
    private var hasManualSelection = false
    private var hasPermissionFreeSelection = false
    private var lastAuthorizationStatus: PHAuthorizationStatus?
    private let placeResolver = TripPlaceResolver()
    private var resolvedCoordinates: [String: PhotoCoordinate] = [:]
    private var activeImportedPhotos: [ManualImportedPhoto] = []
    private var pendingBuildTrip: Trip?
    private var activeAnalysisTrip: Trip?
    private var activePhotoInsights: [String: MontagePhotoInsight] = [:]
    private var cloudBlockedPhotoIDs: Set<String> = []
    private var aiCutConsentGranted = false
    private var manuallyIncludedPhotoIDs: Set<String> = []
    private var photoEditOverrides: [String: PhotoEditOverride] = [:]
    private let videoExporter: any TripReelVideoExporting

    private static let cloudPreferenceKey = "tripreel.cloud-photo-analysis-preference.v1"
    private static let welcomeCompletedKey = "memories.welcome-completed.v1"

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        useDemoData: Bool? = nil,
        photoLibrary: (any PhotoLibraryServing)? = nil,
        cloudPhotoAnalysis: (any CloudPhotoAnalysisServing)? = nil,
        aiVideoGeneration: (any AIVideoGenerationServing)? = nil,
        photoAnalysisThumbnails: (any PhotoAnalysisThumbnailServing)? = nil,
        nativePhotoIntelligence: (any NativePhotoIntelligenceServing)? = nil,
        videoExporter: (any TripReelVideoExporting)? = nil,
        preferenceStore: UserDefaults = .standard
    ) {
        let demoMode = useDemoData ?? arguments.contains("-qaScreen")
        usesDemoData = demoMode
        self.photoLibrary = photoLibrary ?? PhotoLibraryService()
        self.cloudPhotoAnalysis = cloudPhotoAnalysis ?? CloudPhotoAnalysisClient()
        self.aiVideoGeneration = aiVideoGeneration ?? OpenRouterAIVideoClient()
        self.photoAnalysisThumbnails = photoAnalysisThumbnails ?? PhotoAnalysisThumbnailService()
        self.nativePhotoIntelligence = nativePhotoIntelligence ?? NativePhotoIntelligenceService()
        self.videoExporter = videoExporter ?? TripReelVideoExporter()
        self.preferenceStore = preferenceStore
        cloudAnalysisPreference = CloudAnalysisPreference(
            rawValue: preferenceStore.string(forKey: Self.cloudPreferenceKey) ?? ""
        ) ?? .undecided

        if !demoMode, preferenceStore.bool(forKey: Self.welcomeCompletedKey) {
            switch self.photoLibrary.authorizationStatus {
            case .authorized, .limited:
                screen = .trips
            case .notDetermined, .denied, .restricted:
                screen = .access
            @unknown default:
                screen = .access
            }
        }

        if demoMode {
            let fixtures = Self.makeDemoTrips()
            trips = fixtures
            selectedTrip = fixtures.first
            photos = fixtures.first.map { Self.makeReelPhotos(from: $0) } ?? []
            libraryPreviewPhotos = Array(photos.prefix(6))
            libraryPhotoCount = fixtures.reduce(0) { $0 + $1.photoCount }
            selectedPhotoCount = 3
            titleText = fixtures.first?.shortPlace ?? "My memory"
        } else {
            self.photoLibrary.onLibraryChange = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          !self.hasPermissionFreeSelection,
                          !self.isManualSelectionInProgress else { return }
                    if self.hasManualSelection {
                        await self.reconcilePhotoKitManualSelection()
                    } else {
                        await self.refreshPhotoLibraryIfAuthorized(force: true)
                    }
                }
            }
        }

#if DEBUG
        if let flagIndex = arguments.firstIndex(of: "-qaScreen"),
           arguments.indices.contains(flagIndex + 1),
           let requestedScreen = AppScreen(rawValue: arguments[flagIndex + 1]) {
            screen = requestedScreen
        }
        if arguments.contains("-qaNoHint") {
            showCutHint = false
        }
        if arguments.contains("-qaPhotoAnalysis"), let trip = trips.first {
            isAnalyzingPhotos = true
            photoAnalysisProgress = 0.48
            photoAnalysisStatus = "Comparing similar frames"
            photoAnalysisProcessedCount = 41
            photoAnalysisTotalCount = trip.assets.count
            photoAnalysisRecentAssets = Array(trip.assets.prefix(5))
            photoAnalysisCurrentAsset = trip.assets.dropFirst(5).first
        }
        if arguments.contains("-qaAISending"), screen == .aiProcessing {
            selectedAICutDirection = .surpriseMe
            aiCutProgress = 0.58
            aiCutStatus = "Directing a different cut…"
            resetAICutPhotoSelection()
        }
#endif
        if demoMode {
            resetTitleDrafts()
            firstCutSnapshot = makeCurrentEditSnapshot()
            if screen == .aiComparison {
                installDemoAICut()
            } else if screen == .aiDirection {
                aiCutConsentGranted = true
                selectedAICutDirection = recommendedAICutDirection
                resetAICutPhotoSelection()
            }
        }
    }

    static let assetNames = [
        "my-khe-beach",
        "street-food",
        "golden-bridge",
        "hoi-an-lanes",
        "night-market",
        "han-river"
    ]

    static let photoLabels = [
        "MY KHE BEACH",
        "STREET FOOD, 8PM",
        "GOLDEN BRIDGE",
        "HOI AN LANES",
        "NIGHT MARKET",
        "HAN RIVER BOAT"
    ]

    let tracks = [
        MusicTrack(id: "wanderlust", name: "Wanderlust", mood: "Folksy, warm, carefree", tag: "FOLK", symbol: "guitars", tint: TR.accent, bars: [12, 21, 15, 25, 18], resourceName: "wanderlust", sourceURL: "https://www.scottbuckley.com.au/library/wanderlust/"),
        MusicTrack(id: "simplicity", name: "Simplicity", mood: "Bright, acoustic, uplifting", tag: "LIGHT", symbol: "music.note", tint: Color(red: 0.64, green: 0.79, blue: 0.57), bars: [13, 20, 16, 24, 19], resourceName: "simplicity", sourceURL: "https://www.scottbuckley.com.au/library/simplicity/"),
        MusicTrack(id: "castles", name: "Castles in the Sky", mood: "Dreamy, gentle, urban", tag: "DREAMY", symbol: "sparkles", tint: Color(red: 0.56, green: 0.70, blue: 0.86), bars: [8, 15, 11, 20, 13], resourceName: "castles-in-the-sky", sourceURL: "https://www.scottbuckley.com.au/library/castles-in-the-sky/"),
        MusicTrack(id: "long-way-home", name: "The Long Way Home", mood: "Nostalgic piano and strings", tag: "PIANO", symbol: "pianokeys", tint: Color(red: 0.77, green: 0.62, blue: 0.86), bars: [10, 18, 13, 23, 16], resourceName: "the-long-way-home", sourceURL: "https://www.scottbuckley.com.au/library/the-long-way-home/"),
        MusicTrack(id: "none", name: "No music", mood: "Just the cut", tag: "—", symbol: "speaker.slash", tint: Color.white.opacity(0.35), bars: [4, 4, 4, 4, 4], resourceName: nil, sourceURL: nil)
    ]

    let formats = [
        ProjectFormat(id: "sequence", name: "Photo timing sheet", apps: "Spreadsheets and custom workflows", fileExtension: "CSV"),
        ProjectFormat(id: "fcpxml", name: "Final Cut XML", apps: "Final Cut Pro, DaVinci Resolve", fileExtension: "FCPXML"),
        ProjectFormat(id: "edl", name: "Edit decision list", apps: "Premiere Pro, Avid", fileExtension: "EDL")
    ]

    var currentPhoto: ReelPhoto {
        guard !photos.isEmpty else { return Self.placeholderPhoto }
        return photos[min(max(0, currentPhotoIndex), photos.count - 1)]
    }

    var keptPhotos: [ReelPhoto] {
        photos.filter { !cutPhotoIDs.contains($0.id) }
    }

    /// Original PhotoKit items that the user cut from this film and can choose
    /// to remove from Apple Photos. Permission-free imports stay out of cleanup
    /// because deleting TripReel's temporary copy cannot delete the original.
    var cleanupCandidatePhotos: [ReelPhoto] {
        if usesDemoData {
            let demoCuts = photos.filter { cutPhotoIDs.contains($0.id) }
            return demoCuts.isEmpty ? Array(photos.prefix(24)) : demoCuts
        }

        let libraryCuts = photos.filter { photo in
            guard cutPhotoIDs.contains(photo.id) else { return false }
            if case .library = photo.source { return true }
            return false
        }
        return libraryCuts
    }

    var cleanupSelectedCount: Int {
        cleanupSelection.intersection(cleanupCandidatePhotoIDs).count
    }

    var areAllCleanupCandidatesSelected: Bool {
        let candidates = cleanupCandidatePhotoIDs
        return !candidates.isEmpty && candidates.isSubset(of: cleanupSelection)
    }

    private var cleanupCandidatePhotoIDs: Set<String> {
        Set(cleanupCandidatePhotos.map(\.id))
    }

    var customizedPhotoCount: Int {
        keptPhotos.reduce(into: 0) { count, photo in
            if photo.hasCustomFrameStyle
                || photo.motionStyle != photo.automaticMotionStyle
                || photo.cropScale != photo.automaticCropScale
                || photo.cropOffsetX != photo.automaticCropOffsetX
                || photo.cropOffsetY != photo.automaticCropOffsetY
                || photo.durationSeconds != nil {
                count += 1
            }
        }
    }

    var keptCount: Int { keptPhotos.count }

    var secondsPerPhoto: Double {
        1.85 - (pace * 1.25)
    }

    var durationText: String {
        Self.durationText(seconds: keptPhotos.reduce(0) { partial, photo in
            partial + duration(for: photo)
        })
    }

    var rawDurationText: String {
        let titleDuration = montageTitleCards.reduce(0) { $0 + $1.duration }
        return Self.durationText(
            seconds: (Double(photos.count) * (4.0 / 3.0)) + titleDuration
        )
    }

    var filmDurationText: String {
        Self.durationText(seconds: filmDurationSeconds)
    }

    var filmDurationSeconds: Double {
        let titleDuration = montageTitleCards.reduce(0) { $0 + $1.duration }
        let photoDuration = keptPhotos.reduce(0) { $0 + duration(for: $1) }
        return photoDuration + titleDuration
    }

    var firstCutDurationText: String {
        Self.durationText(seconds: firstCutSnapshot?.durationSeconds ?? 0)
    }

    var aiCutDurationText: String {
        Self.durationText(seconds: aiCutSnapshot?.durationSeconds ?? 0)
    }

    var currentCutTitle: String {
        selectedCutSource.title
    }

    func editSnapshot(for source: TripCutSource) -> TripEditSnapshot? {
        switch source {
        case .firstCut:
            firstCutSnapshot
        case .aiCut:
            aiCutSnapshot
        case .working:
            makeCurrentEditSnapshot()
        }
    }

    private func makeCurrentEditSnapshot() -> TripEditSnapshot {
        TripEditSnapshot(
            photos: photos,
            cutPhotoIDs: cutPhotoIDs,
            pace: pace,
            montageLook: montageLook,
            motionIntensity: montageMotionIntensity,
            titleCards: titleCards,
            titleDrafts: Dictionary(
                uniqueKeysWithValues: TitleCardKind.allCases.map { ($0, titleDraft(for: $0)) }
            ),
            textOverlays: textOverlays,
            selectedTrackID: selectedTrackID,
            cutToBeat: cutToBeat
        )
    }

    private func applyEditSnapshot(_ snapshot: TripEditSnapshot, source: TripCutSource) {
        photos = snapshot.photos
        cutPhotoIDs = snapshot.cutPhotoIDs
        pace = snapshot.pace
        montageLook = snapshot.montageLook
        montageMotionIntensity = snapshot.motionIntensity
        titleCards = snapshot.titleCards
        titleDrafts = snapshot.titleDrafts
        textOverlays = snapshot.textOverlays
        selectedTrackID = snapshot.selectedTrackID
        cutToBeat = snapshot.cutToBeat
        selectedCutSource = source
        currentPhotoIndex = 0
        history = []
        cleanupSelection = []
        rebuildPhotoEditOverrides()
    }

    private func rebuildPhotoEditOverrides() {
        photoEditOverrides = Dictionary(
            uniqueKeysWithValues: photos.compactMap { photo in
                let customized = photo.hasCustomFrameStyle
                    || photo.motionStyle != photo.automaticMotionStyle
                    || photo.cropScale != photo.automaticCropScale
                    || photo.cropOffsetX != photo.automaticCropOffsetX
                    || photo.cropOffsetY != photo.automaticCropOffsetY
                    || photo.durationSeconds != nil
                guard customized else { return nil }
                return (
                    photo.id,
                    PhotoEditOverride(
                        frameStyle: photo.hasCustomFrameStyle ? photo.frameStyle : nil,
                        motionStyle: photo.motionStyle,
                        cropScale: photo.cropScale,
                        cropOffsetX: photo.cropOffsetX,
                        cropOffsetY: photo.cropOffsetY,
                        durationSeconds: photo.durationSeconds
                    )
                )
            }
        )
    }

    var exportProgressTitle: String {
        switch exportProgressPhase {
        case .preparingPhotos:
            "Gathering full-quality photos"
        case .rendering:
            "Rendering"
        case .addingSoundtrack:
            "Adding your soundtrack"
        case .finalizing:
            "Finishing your film"
        }
    }

    var exportProgressDetail: String {
        switch exportProgressPhase {
        case let .preparingPhotos(ready, total, currentLabel, downloadProgress):
            let count = "\(ready) of \(total) ready"
            guard let currentLabel else { return count }
            if let downloadProgress {
                return "\(count) · iCloud \(Int(downloadProgress * 100))%"
            }
            return "\(count) · \(currentLabel)"
        case .rendering:
            return "\(Int(renderProgress * 100))% · full-resolution video"
        case .addingSoundtrack:
            return "Picture complete · mixing audio"
        case .finalizing:
            return "Saving the finished file"
        }
    }

    var montageTitleCards: [MontageTitleCard] {
        TitleCardKind.allCases.compactMap { kind in
            guard titleCards.contains(kind) else { return nil }
            return montageTitleCard(for: kind)
        }
    }

    func montageTitleCard(for kind: TitleCardKind) -> MontageTitleCard {
        let draft = titleDraft(for: kind)
        return MontageTitleCard(
            kind: kind,
            title: draft.title,
            subtitle: draft.subtitle,
            style: draft.style,
            duration: draft.duration,
            afterPhotoID: draft.afterPhotoID
        )
    }

    func titleDraft(for kind: TitleCardKind) -> TitleCardDraft {
        if let draft = titleDrafts[kind] { return draft }
        switch kind {
        case .opening:
            return TitleCardDraft(
                title: selectedTrip.map { trip in
                    LocalStoryIntelligence.collectionTitle(
                        for: trip,
                        isNearby: nearbyEvents.contains(where: { $0.id == trip.id })
                    )
                } ?? tripShortPlace,
                subtitle: tripDates,
                style: .editorial,
                duration: kind.defaultDuration
            )
        case .place:
            return TitleCardDraft(
                title: "A new chapter",
                subtitle: "",
                style: .clean,
                duration: kind.defaultDuration
            )
        case .ending:
            return TitleCardDraft(
                title: tripMonthYear,
                subtitle: "Made with Memories",
                style: .editorial,
                duration: kind.defaultDuration
            )
        }
    }

    func setTitleText(_ text: String, for kind: TitleCardKind) {
        var draft = titleDraft(for: kind)
        draft.title = String(text.prefix(80))
        titleDrafts[kind] = draft
    }

    func setTitleSubtitle(_ text: String, for kind: TitleCardKind) {
        var draft = titleDraft(for: kind)
        draft.subtitle = String(text.prefix(100))
        titleDrafts[kind] = draft
    }

    func setTitleStyle(_ style: MontageTitleStyle, for kind: TitleCardKind) {
        var draft = titleDraft(for: kind)
        draft.style = style
        titleDrafts[kind] = draft
    }

    func setTitleDuration(_ duration: Double, for kind: TitleCardKind) {
        var draft = titleDraft(for: kind)
        draft.duration = min(max(duration, 1.0), 4.0)
        titleDrafts[kind] = draft
    }

    func setTitleCardEnabled(_ enabled: Bool, for kind: TitleCardKind) {
        if enabled {
            titleCards.insert(kind)
        } else {
            titleCards.remove(kind)
        }
    }

    func setTextOverlayText(_ text: String, id: String) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[index].text = String(text.prefix(80))
    }

    func setTextOverlayStyle(_ style: MontageTitleStyle, id: String) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[index].style = style
    }

    func setTextOverlayPlacement(_ placement: MontageTextPlacement, id: String) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[index].placement = placement
    }

    func setTextOverlayAnimation(_ animation: MontageTextAnimation, id: String) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[index].animation = animation
    }

    func removeTextOverlay(id: String) {
        textOverlays.removeAll { $0.id == id }
    }

    private func resetTitleDrafts() {
        titleDrafts = Dictionary(
            uniqueKeysWithValues: TitleCardKind.allCases.map { kind in
                (kind, titleDraft(for: kind))
            }
        )
    }

    func duration(for photo: ReelPhoto) -> Double {
        photo.durationSeconds ?? secondsPerPhoto
    }

    var selectedTrack: MusicTrack? {
        tracks.first { $0.id == selectedTrackID }
    }

    func musicTrack(withID id: String?) -> MusicTrack? {
        guard let id else { return nil }
        return tracks.first { $0.id == id && $0.id != "none" }
    }

    var recommendedAICutDirection: AICutDirection {
        let relevantIDs = Set((activeAnalysisTrip ?? selectedTrip)?.assets.map(\.id) ?? [])
        let insights = activePhotoInsights.filter { relevantIDs.isEmpty || relevantIDs.contains($0.key) }.values
        let analyzedCount = insights.count
        guard analyzedCount > 0 else { return .betterStory }

        let peopleMoments = insights.filter { $0.peopleCount > 0 || $0.contentKind == .people }.count
        if peopleMoments >= max(3, Int(ceil(Double(analyzedCount) * 0.34))) {
            return .people
        }

        let scenicMoments = insights.filter { $0.contentKind == .scenery }.count
        if scenicMoments >= max(3, Int(ceil(Double(analyzedCount) * 0.45))) {
            return .calm
        }

        let candidateCount = firstCutSnapshot?.keptPhotos.count ?? photos.count
        return candidateCount >= 24 ? .betterStory : .surpriseMe
    }

    var recommendedAICutReason: String {
        switch recommendedAICutDirection {
        case .people:
            "Recommended because this film contains several distinct people moments."
        case .calm:
            "Recommended because scenery is one of the strongest themes in this film."
        case .betterStory:
            "Recommended to shape a larger set of moments into a clear beginning, middle and ending."
        case .surpriseMe:
            "Recommended for a varied set where the director can choose the strongest overall rhythm."
        case .dynamic:
            "Recommended for a quicker, more energetic sequence."
        }
    }

    /// Short, optional creator prompts. These are intentionally broad: the app
    /// never invents an event or relationship, and sends a hint only after the
    /// user taps one or writes their own.
    var aiCutStoryContextSuggestions: [String] {
        switch recommendedAICutDirection {
        case .people:
            ["The people made the day", "A shared achievement", "Small moments together"]
        case .calm:
            ["A quiet escape", "The feeling of being there", "Slow moments worth keeping"]
        case .dynamic:
            ["A day full of energy", "The best moments, fast", "From start to celebration"]
        case .betterStory:
            ["How the day unfolded", "The moments behind the memory", "From arrival to goodbye"]
        case .surpriseMe:
            ["What made this memorable", "The story between the photos", "Find the unexpected thread"]
        }
    }

    var selectedFormat: ProjectFormat {
        formats.first { $0.id == selectedFormatID } ?? formats[0]
    }

    var overseasMemoriesEyebrow: String {
        if isScanningLibrary { return "Scanning \(libraryPhotoCount) photos" }
        if !usesDemoData {
            return "\(trips.count) memor\(trips.count == 1 ? "y" : "ies") · \(libraryPhotoCount) photos scanned"
        }
        return "\(trips.count) memor\(trips.count == 1 ? "y" : "ies") found"
    }

    var localMemoriesEyebrow: String {
        if isScanningLibrary { return "Finding local memories" }
        return "\(nearbyEvents.count) local memor\(nearbyEvents.count == 1 ? "y" : "ies") · on this iPhone"
    }

    var tripPlace: String { selectedTrip?.place ?? "Your memory" }
    var tripShortPlace: String { selectedTrip?.shortPlace ?? "Your memory" }
    var tripDates: String { selectedTrip?.dates ?? "Selected photos" }

    /// Backward-compatible opening-title access. Each title card now keeps an
    /// independent editable draft, but existing callers can still use this
    /// property for the opening card.
    var titleText: String {
        get { titleDraft(for: .opening).title }
        set { setTitleText(newValue, for: .opening) }
    }

    var tripMonthYear: String {
        guard let date = selectedTrip?.startDate else { return "Your memory" }
        return Self.monthYearFormatter.string(from: date)
    }

    func previewSource(at index: Int) -> PhotoSource {
        guard !photos.isEmpty else {
            return .bundled(Self.assetNames[index.modulo(Self.assetNames.count)])
        }
        return photos[index.modulo(photos.count)].source
    }

    func previewSource(forTitle kind: TitleCardKind) -> PhotoSource {
        if let anchorID = titleDraft(for: kind).afterPhotoID,
           let anchored = photos.first(where: { $0.id == anchorID }) {
            return anchored.source
        }
        switch kind {
        case .opening:
            return previewSource(at: 0)
        case .place:
            return previewSource(at: max(0, (photos.count / 2) - 1))
        case .ending:
            return previewSource(at: max(0, photos.count - 1))
        }
    }

    func go(
        _ next: AppScreen,
        direction explicitDirection: TRNavigationDirection? = nil
    ) {
        workTask?.cancel()
        navigationDirection = explicitDirection ?? Self.navigationDirection(
            from: screen,
            to: next
        )
        screen = next
    }

    /// The brand welcome appears once. Photos permission remains Apple's
    /// persisted choice, so returning users with access go straight to their
    /// stories instead of seeing the permission screen again.
    func continueFromWelcome() {
        preferenceStore.set(true, forKey: Self.welcomeCompletedKey)
        switch photoLibrary.authorizationStatus {
        case .authorized, .limited:
            if hasScannedLibrary {
                showTripResults()
            } else {
                go(.trips, direction: .forward)
                Task { [weak self] in
                    await self?.scanPhotoLibrary(navigateToResults: true)
                }
            }
        case .notDetermined, .denied, .restricted:
            go(.access, direction: .forward)
        @unknown default:
            go(.access, direction: .forward)
        }
    }

    func requestPhotoLibraryAuthorization() async -> PHAuthorizationStatus {
        await photoLibrary.requestAuthorization()
    }

    /// Back is navigation chrome, not another decision in the film-making
    /// flow. Every destination is explicit so transient processing screens are
    /// never accidentally revisited.
    var canNavigateBack: Bool {
        switch screen {
        case .access, .limited, .firstWatch, .firstCutOptions, .aiDirection, .aiComparison,
             .aiVideoIntro, .aiVideoReady, .secondWatch, .pace, .export, .paywall, .done:
            true
        case .welcome, .trips, .empty, .building, .aiProcessing, .aiVideoGenerating,
             .cut, .rendering, .cleanup:
            false
        }
    }

    func navigateBack() {
        switch screen {
        case .access:
            go(.welcome, direction: .backward)
        case .limited:
            go(.access, direction: .backward)
        case .firstWatch:
            go(.trips, direction: .backward)
        case .firstCutOptions:
            go(.firstWatch, direction: .backward)
        case .aiDirection, .aiComparison:
            go(.firstCutOptions, direction: .backward)
        case .aiVideoIntro, .aiVideoReady:
            go(.aiComparison, direction: .backward)
        case .secondWatch:
            go(studioReturnScreen, direction: .backward)
        case .pace:
            go(.secondWatch, direction: .backward)
        case .export:
            go(exportReturnScreen, direction: .backward)
        case .paywall:
            pendingExportIntent = nil
            go(.export, direction: .backward)
        case .done:
            go(.export, direction: .backward)
        case .welcome, .trips, .empty, .building, .aiProcessing, .aiVideoGenerating,
             .cut, .rendering, .cleanup:
            break
        }
    }

    func continueFromFirstWatch() {
        go(.firstCutOptions, direction: .forward)
    }

    func openExport() {
        if screen == .firstWatch || screen == .secondWatch {
            exportReturnScreen = screen
        }
        go(.export, direction: .forward)
    }

    private static func navigationDirection(
        from current: AppScreen,
        to next: AppScreen
    ) -> TRNavigationDirection {
        guard current != next else { return .replace }
        if next == .trips && (current == .cleanup || current == .done || current == .empty) {
            return .replace
        }
        if next.motionOrder == current.motionOrder { return .replace }
        return next.motionOrder > current.motionOrder ? .forward : .backward
    }

    func dismissLibraryMessage() {
        libraryErrorMessage = nil
    }

    var cloudAnalysisIsEnabled: Bool {
        cloudAnalysisPreference == .enabled
    }

    var cloudAnalysisIsConfigured: Bool {
        cloudPhotoAnalysis.isConfigured
    }

    var aiCutPhotoOptions: [AICutPhotoOption] {
        availableAICutCandidatePhotos().map {
            AICutPhotoOption(photo: $0.photo, localSelection: $0.localSelection)
        }
    }

    var aiCutPhotoSelectionLimit: Int {
        CloudPhotoAnalysisClient.maximumBatchSize
    }

    var aiCutSelectedPhotoCount: Int {
        selectedAICutPhotoIDs.count
    }

    var aiVideoPhotoOptions: [ReelPhoto] {
        editSnapshot(for: aiVideoSource)?.keptPhotos ?? []
    }

    var aiVideoSelectedPhotoID: String? {
        aiVideoSelectedPhotoIDs.first
    }

    var aiVideoSelectedPhotos: [ReelPhoto] {
        let options = Dictionary(uniqueKeysWithValues: aiVideoPhotoOptions.map { ($0.id, $0) })
        return aiVideoSelectedPhotoIDs.compactMap { options[$0] }
    }

    var aiVideoSelectedPhoto: ReelPhoto? {
        aiVideoSelectedPhotos.first ?? aiVideoPhotoOptions.first
    }

    var aiVideoEndingPhoto: ReelPhoto? {
        aiVideoSelectedPhotos.dropFirst().first
    }

    var aiVideoHasStoryPair: Bool {
        aiVideoSelectedPhotos.count == 2
    }

    var aiVideoSelectionIsRecommended: Bool {
        aiVideoSelectedPhotoIDs == aiVideoRecommendedPhotoIDs
    }

    var aiVideoIsConfigured: Bool {
        aiVideoGeneration.isConfigured
    }

    var aiVideoTitle: String {
        let snapshot = editSnapshot(for: aiVideoSource)
        let opening = snapshot?.montageTitleCards.first(where: { $0.kind == .opening })?.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return opening?.isEmpty == false ? opening! : tripShortPlace
    }

    var aiCutCanCreate: Bool {
        aiCutConsentGranted
            && selectedAICutDirection != nil
            && !selectedAICutPhotoIDs.isEmpty
    }

    /// Photos omitted from the cut currently on screen. An AI cut can restore
    /// a locally omitted moment without mutating the saved First Cut; filtering
    /// here keeps More Photos truthful and makes reverting fully reversible.
    var visibleExcludedPhotos: [SmartExcludedPhoto] {
        let visiblePhotoIDs = Set(keptPhotos.map(\.id))
        return excludedPhotos.filter { !visiblePhotoIDs.contains($0.id) }
    }

    var smartSelectionSummary: String? {
        let count = visibleExcludedPhotos.count
        guard count > 0 else { return nil }
        return "\(count) photo\(count == 1 ? "" : "s") left in More Photos"
    }

    /// Entry point used by the trip list. First Cut is always created locally;
    /// this path never prepares an upload or presents cloud consent.
    func requestBuild(trip: Trip) {
        guard !trip.assets.isEmpty else { return }
        if usesDemoData {
            startBuild(trip: trip)
            return
        }
        pendingBuildTrip = nil
        beginSmartPhotoSelection(for: trip)
    }

    func presentCloudAnalysisSettings() {
        pendingBuildTrip = nil
        cloudConsentIsSettings = true
        isCloudAnalysisConsentPresented = true
    }

    func useCloudEnhancement() {
        guard cloudPhotoAnalysis.isConfigured else { return }
        setCloudAnalysisPreference(.enabled)
        aiCutConsentGranted = true
        isCloudAnalysisConsentPresented = false
        guard !cloudConsentIsSettings else { return }
        go(.aiDirection, direction: .forward)
    }

    func keepAnalysisOnDevice() {
        setCloudAnalysisPreference(.onDeviceOnly)
        aiCutConsentGranted = false
        isCloudAnalysisConsentPresented = false
        guard !cloudConsentIsSettings else { return }
    }

    func openAICutDirections() {
        aiCutFailureMessage = nil
        selectedAICutDirection = recommendedAICutDirection
        resetAICutPhotoSelection()
        aiCutConsentGranted = false
        cloudConsentIsSettings = false
        isCloudAnalysisConsentPresented = true
    }

    func selectAICutDirection(_ direction: AICutDirection) {
        selectedAICutDirection = direction
    }

    func continueWithAICutDirection() {
        guard aiCutCanCreate else { return }
        beginAICut()
    }

    func toggleAICutPhotoSelection(_ photoID: String) {
        let validIDs = Set(aiCutPhotoOptions.map(\.id))
        guard validIDs.contains(photoID) else { return }
        if selectedAICutPhotoIDs.contains(photoID) {
            selectedAICutPhotoIDs.remove(photoID)
        } else if selectedAICutPhotoIDs.count < aiCutPhotoSelectionLimit {
            selectedAICutPhotoIDs.insert(photoID)
        }
    }

    func selectSuggestedAICutPhotos() {
        resetAICutPhotoSelection()
    }

    func clearAICutPhotoSelection() {
        selectedAICutPhotoIDs = []
    }

    func beginAICut() {
        guard aiCutConsentGranted else { return }
        aiCutTask?.cancel()
        let generation = UUID()
        aiCutGeneration = generation
        aiCutFailureMessage = nil
        aiCutSnapshot = nil
        aiCutSummary = nil
        aiCutRecommendations = []
        aiCutDiagnosis = nil
        aiCutComparison = nil
        aiCutProgress = 0
        aiCutStatus = "Finding the strongest moments…"
        go(.aiProcessing, direction: .forward)

        guard cloudPhotoAnalysis.isConfigured else {
            aiCutFailureMessage = "AI couldn't create another cut right now. Your First Cut is still ready."
            return
        }
        guard let firstCutSnapshot else {
            aiCutFailureMessage = "Your First Cut needs to be ready before creating another version."
            return
        }

        if usesDemoData {
            installDemoAICut()
            aiCutProgress = 1
            go(.aiComparison, direction: .forward)
            return
        }

        guard let direction = selectedAICutDirection else {
            aiCutFailureMessage = "Choose a direction before creating another cut. Your First Cut is unchanged."
            return
        }
        guard let sourceTrip = activeAnalysisTrip ?? selectedTrip else {
            aiCutFailureMessage = "The original memory photos aren't available for another cut. Your First Cut is unchanged."
            return
        }
        let sourceAssets = sourceTrip.assets
        let assetsByID = Dictionary(uniqueKeysWithValues: sourceAssets.map { ($0.id, $0) })
        let allPhotos = applyingPhotoEdits(
            to: Self.makeReelPhotos(from: sourceTrip, insights: activePhotoInsights)
        )
        let allPhotosByID = Dictionary(uniqueKeysWithValues: allPhotos.map { ($0.id, $0) })
        let selectedOptions = availableAICutCandidatePhotos().filter {
            selectedAICutPhotoIDs.contains($0.photo.id)
        }
        let candidates = selectedOptions.compactMap { candidate -> AICutCandidate? in
            guard let asset = assetsByID[candidate.photo.id], !asset.isScreenshot else { return nil }
            return AICutCandidate(
                photo: candidate.photo,
                asset: asset,
                localSelection: candidate.localSelection
            )
        }

        guard !candidates.isEmpty else {
            aiCutFailureMessage = "There aren't enough privacy-safe previews for another cut. Your First Cut is unchanged."
            return
        }

        let editorialContexts = Self.aiEditorialContexts(
            for: candidates,
            sourceAssets: sourceAssets,
            tripStartDate: sourceTrip.startDate,
            insights: activePhotoInsights
        )

        aiCutTask = Task { [weak self] in
            guard let self else { return }
            var wireInputs: [CloudPhotoAnalysisInput] = []
            var localIDsByWireID: [String: String] = [:]

            for (index, candidate) in candidates.enumerated() {
                guard self.aiCutGeneration == generation, !Task.isCancelled else { return }
                do {
                    let prepared = try await self.photoAnalysisThumbnails.prepare(asset: candidate.asset)
                    let wireID = "p\(wireInputs.count)"
                    wireInputs.append(CloudPhotoAnalysisInput(
                        id: wireID,
                        jpegData: prepared.jpegData,
                        localSelection: candidate.localSelection,
                        context: editorialContexts[candidate.photo.id]
                    ))
                    localIDsByWireID[wireID] = candidate.photo.id
                } catch is CancellationError {
                    return
                } catch {
                    // A temporarily unavailable preview is omitted from this
                    // optional remix; the original First Cut remains intact.
                }

                guard self.aiCutGeneration == generation else { return }
                self.aiCutProgress = 0.08 + (Double(index + 1) / Double(candidates.count) * 0.42)
                switch index % 3 {
                case 0: self.aiCutStatus = "Finding the strongest moments…"
                case 1: self.aiCutStatus = "Looking for a new story shape…"
                default: self.aiCutStatus = "Balancing people and places…"
                }
            }

            guard self.aiCutGeneration == generation,
                  !Task.isCancelled,
                  !wireInputs.isEmpty else {
                if self.aiCutGeneration == generation {
                    self.aiCutFailureMessage = "The selected previews aren't available right now. Your First Cut is still ready."
                }
                return
            }

            self.aiCutProgress = 0.58
            self.aiCutStatus = "Directing a different cut…"
            do {
                guard let baseline = Self.cloudFirstCutBaseline(
                    firstCutSnapshot,
                    localIDsByWireID: localIDsByWireID
                ) else {
                    throw CloudPhotoAnalysisError.invalidBaseline
                }
                let plan = try await self.cloudPhotoAnalysis.createEditPlan(
                    direction: direction,
                    storyContext: self.aiCutStoryContext,
                    baseline: baseline,
                    photos: wireInputs
                )
                guard self.aiCutGeneration == generation, !Task.isCancelled else { return }
                self.aiCutProgress = 0.88
                self.aiCutStatus = "Writing your hook and matching music…"
                let snapshot = try self.materializeAICut(
                    plan: plan,
                    firstCut: firstCutSnapshot,
                    direction: direction,
                    localIDsByWireID: localIDsByWireID,
                    candidatePhotosByLocalID: allPhotosByID
                )
                guard self.aiCutGeneration == generation, !Task.isCancelled else { return }
                self.aiCutSnapshot = snapshot
                self.aiCutSummary = plan.summary
                self.aiCutRecommendations = Self.recommendations(for: plan)
                self.aiCutDiagnosis = plan.diagnosis
                self.aiCutComparison = plan.comparison
                self.aiCutProgress = 1
                self.aiCutTask = nil
                self.go(.aiComparison, direction: .forward)
            } catch is CancellationError {
                return
            } catch {
                guard self.aiCutGeneration == generation else { return }
                self.aiCutTask = nil
                let localizedMessage = (error as? any LocalizedError)?.errorDescription?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.aiCutFailureMessage = localizedMessage?.isEmpty == false
                    ? localizedMessage
                    : "AI couldn't create another cut right now. Your First Cut is still ready."
            }
        }
    }

    func cancelAICut() {
        aiCutGeneration = UUID()
        aiCutTask?.cancel()
        aiCutTask = nil
        aiCutFailureMessage = nil
        aiCutProgress = 0
        aiCutConsentGranted = false
        go(.firstCutOptions, direction: .backward)
    }

    func retryAICut() {
        beginAICut()
    }

    func useAICut() {
        exportCut(.aiCut)
    }

    func openAIVideoIntro(from source: TripCutSource) {
        guard let snapshot = editSnapshot(for: source), !snapshot.keptPhotos.isEmpty else { return }
        aiVideoTask?.cancel()
        aiVideoGenerationID = UUID()
        aiVideoSource = source
        let recommendation = AIVideoMomentRecommender.recommend(
            photos: snapshot.keptPhotos,
            insights: activePhotoInsights
        )
        aiVideoRecommendedPhotoIDs = recommendation.photoIDs
        aiVideoSelectedPhotoIDs = recommendation.photoIDs
        aiVideoRecommendationIsVisionBased = recommendation.isVisionBased
        aiVideoProgress = 0
        aiVideoStatus = "Preparing your memory…"
        aiVideoFailureMessage = nil
        aiVideoSaveMessage = nil
        go(.aiVideoIntro, direction: .forward)
    }

    func selectAIVideoPhoto(_ photoID: String) {
        selectAIVideoPhoto(photoID, for: .beginning)
    }

    func selectAIVideoPhoto(_ photoID: String, for role: AIVideoMomentRole) {
        guard aiVideoPhotoOptions.contains(where: { $0.id == photoID }) else { return }
        guard aiVideoPhotoOptions.count > 1 else {
            aiVideoSelectedPhotoIDs = [photoID]
            return
        }

        var selection = aiVideoSelectedPhotoIDs
        if selection.count < 2 {
            selection = Array(aiVideoPhotoOptions.prefix(2).map(\.id))
        }
        let target = role == .beginning ? 0 : 1
        let other = target == 0 ? 1 : 0
        if selection[other] == photoID {
            selection.swapAt(target, other)
        } else {
            selection[target] = photoID
        }
        aiVideoSelectedPhotoIDs = selection
    }

    func beginAIVideoGeneration() {
        let selectedPhotos = aiVideoSelectedPhotos
        guard !selectedPhotos.isEmpty else { return }
        guard aiVideoGeneration.isConfigured else {
            aiVideoFailureMessage = "AI video is not configured yet. Your existing cut is unchanged."
            return
        }

        aiVideoTask?.cancel()
        let generation = UUID()
        aiVideoGenerationID = generation
        aiVideoFailureMessage = nil
        aiVideoSaveMessage = nil
        aiVideoProgress = 0.02
        aiVideoStatus = selectedPhotos.count == 2
            ? "Preparing two reduced previews…"
            : "Preparing one reduced preview…"
        go(.aiVideoGenerating, direction: .forward)

        let assets = selectedPhotos.map { photo in
            TripAsset(
                id: photo.id,
                source: photo.source,
                creationDate: nil,
                filename: photo.label,
                pixelWidth: photo.pixelWidth,
                pixelHeight: photo.pixelHeight
            )
        }
        let prompt = Self.aiVideoPrompt(for: selectedPhotos)
        let thumbnailService = photoAnalysisThumbnails
        let generationService = aiVideoGeneration
        let exporter = videoExporter
        let title = aiVideoTitle

        aiVideoTask = Task { [weak self] in
            guard let self else { return }
            do {
                var preparedFrames: [PreparedPhotoThumbnail] = []
                for asset in assets {
                    preparedFrames.append(
                        try await thumbnailService.prepareVideoFrame(asset: asset)
                    )
                }
                guard self.aiVideoGenerationID == generation, !Task.isCancelled else { return }
                self.aiVideoProgress = 0.08
                let rawURL = try await generationService.generate(
                    AIVideoGenerationInput(
                        jpegFrames: preparedFrames.map(\.jpegData),
                        prompt: prompt,
                        localResumeIdentifier: selectedPhotos.map(\.id).joined(separator: "\0")
                    )
                ) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.aiVideoGenerationID == generation else { return }
                        self.aiVideoProgress = update.fraction
                        self.aiVideoStatus = update.status
                    }
                }
                guard self.aiVideoGenerationID == generation, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: rawURL)
                    return
                }
                self.aiVideoStatus = "Adding your title…"
                self.aiVideoProgress = 0.97
                let finishedURL = try await exporter.finishGeneratedClip(
                    rawURL,
                    title: title
                )
                if finishedURL != rawURL {
                    try? FileManager.default.removeItem(at: rawURL)
                }
                guard self.aiVideoGenerationID == generation, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: finishedURL)
                    return
                }
                if let previous = self.aiVideoURL, previous != finishedURL {
                    try? FileManager.default.removeItem(at: previous)
                }
                self.aiVideoURL = finishedURL
                self.aiVideoProgress = 1
                self.aiVideoTask = nil
                self.go(.aiVideoReady, direction: .forward)
            } catch is CancellationError {
                return
            } catch {
                guard self.aiVideoGenerationID == generation else { return }
                self.aiVideoTask = nil
                self.aiVideoFailureMessage = (error as? LocalizedError)?.errorDescription
                    ?? "The AI video could not be finished. Your existing cut is unchanged."
                self.go(.aiVideoIntro, direction: .backward)
            }
        }
    }

    func cancelAIVideoGeneration() {
        aiVideoGenerationID = UUID()
        aiVideoTask?.cancel()
        aiVideoTask = nil
        aiVideoProgress = 0
        aiVideoFailureMessage = nil
        go(.aiVideoIntro, direction: .backward)
    }

    func dismissAIVideoMessage() {
        aiVideoFailureMessage = nil
        aiVideoSaveMessage = nil
    }

    @discardableResult
    func saveAIVideoToPhotos() async -> Bool {
        guard let aiVideoURL, !isSavingAIVideo else { return false }
        isSavingAIVideo = true
        aiVideoSaveMessage = nil
        defer { isSavingAIVideo = false }
        do {
            try await videoExporter.saveToPhotoLibrary(aiVideoURL)
            aiVideoSaveMessage = "Saved to Photos"
            return true
        } catch {
            aiVideoFailureMessage = (error as? LocalizedError)?.errorDescription
                ?? "Memories couldn't save this AI video to Photos."
            return false
        }
    }

    private static func aiVideoPrompt(for photos: [ReelPhoto]) -> String {
        aiVideoPrompt(
            hasPeople: photos.contains(where: \.protectsPeople),
            hasStoryPair: photos.count == 2
        )
    }

    /// Kept as one bounded prompt because the app and Worker both reject more
    /// than 600 characters before any image leaves the device.
    static func aiVideoPrompt(hasPeople: Bool, hasStoryPair: Bool) -> String {
        let opening = hasStoryPair
            ? "Create a polished six-second 9:16 story. Start exactly on the first frame and finish exactly on the second."
            : "Create a polished four-second 9:16 shot anchored to this exact frame."
        let fidelity = hasPeople
            ? "Preserve every face, body, expression, identity, and important object. Use only subtle natural gestures."
            : "Preserve the subjects, objects, lighting, and composition."
        let transition = hasStoryPair
            ? "Connect them with motivated camera movement and subtle environmental motion; never morph people or objects."
            : "Add subtle environmental motion and one confident camera move."
        return """
        \(opening) \(fidelity) \(transition) \
        Do not add or remove people or important objects. No speech, text, logos, or watermarks. \
        Avoid warped hands, distorted faces, abrupt motion, and invented scenes.
        """
    }

    func exportCut(_ source: TripCutSource) {
        guard let snapshot = editSnapshot(for: source) else { return }
        applyEditSnapshot(snapshot, source: source)
        exportReturnScreen = .aiComparison
        go(.export, direction: .forward)
    }

    func keepFirstCut() {
        guard let firstCutSnapshot else { return }
        applyEditSnapshot(firstCutSnapshot, source: .firstCut)
        go(.firstCutOptions, direction: .backward)
    }

    func keepFirstCutForExport() {
        guard let firstCutSnapshot else { return }
        applyEditSnapshot(firstCutSnapshot, source: .firstCut)
        exportReturnScreen = .firstCutOptions
        go(.export, direction: .forward)
    }

    func editCut(_ source: TripCutSource) {
        guard let snapshot = editSnapshot(for: source) else { return }
        studioReturnScreen = screen == .aiComparison ? .aiComparison : .firstCutOptions
        applyEditSnapshot(snapshot, source: .working)
        go(.secondWatch, direction: .forward)
    }

    func tryAnotherAICut() {
        aiCutFailureMessage = nil
        selectedAICutDirection = recommendedAICutDirection
        go(.aiDirection, direction: .backward)
    }

    private func materializeAICut(
        plan: AICutEditPlan,
        firstCut: TripEditSnapshot,
        direction: AICutDirection,
        localIDsByWireID: [String: String],
        candidatePhotosByLocalID: [String: ReelPhoto]
    ) throws -> TripEditSnapshot {
        let validated = try AICutPlanValidator.validate(
            plan,
            requestedIDs: Set(localIDsByWireID.keys),
            direction: direction
        )
        var plannedPhotos: [ReelPhoto] = []
        var previousMotion: MontageMotionStyle?
        for (index, item) in validated.sequence.enumerated() {
            guard let localID = localIDsByWireID[item.photoID],
                  var photo = candidatePhotosByLocalID[localID] else {
                throw AICutPlanValidationError.unknownPhotoID
            }
            photo.durationSeconds = item.emphasis == .highlight
                ? max(2.2, item.durationSeconds)
                : item.durationSeconds
            photo.motionStyle = Self.choreographedMotionStyle(
                for: item,
                photo: photo,
                index: index,
                previous: previousMotion
            )
            previousMotion = photo.motionStyle
            plannedPhotos.append(photo)
        }

        let includedIDs = Set(plannedPhotos.map(\.id))
        let remaining = firstCut.photos.filter { !includedIDs.contains($0.id) }
        let settings = Self.aiSettings(for: direction, fallback: firstCut)
        var titleCards = firstCut.titleCards
        var titleDrafts = firstCut.titleDrafts
        titleCards.insert(.opening)
        titleCards.remove(.place)
        titleDrafts[.opening] = TitleCardDraft(
            title: validated.hook.title,
            subtitle: validated.hook.subtitle,
            style: Self.titleStyle(for: validated.hook.style),
            duration: validated.hook.durationSeconds
        )
        let normalizedHook = validated.hook.title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let normalizedChapter = validated.story.title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        if plannedPhotos.count >= 5, normalizedChapter != normalizedHook {
            let anchor = plannedPhotos[max(1, (plannedPhotos.count / 2) - 1)]
            titleCards.insert(.place)
            titleDrafts[.place] = TitleCardDraft(
                title: validated.story.title,
                subtitle: "",
                style: .clean,
                duration: 1.6,
                afterPhotoID: anchor.id
            )
        }
        if validated.ending.enabled {
            titleCards.insert(.ending)
            titleDrafts[.ending] = TitleCardDraft(
                title: validated.ending.title,
                subtitle: validated.ending.subtitle,
                style: Self.titleStyle(for: validated.ending.style),
                duration: validated.ending.durationSeconds
            )
        } else {
            titleCards.remove(.ending)
        }
        return TripEditSnapshot(
            photos: plannedPhotos + remaining,
            cutPhotoIDs: Set(remaining.map(\.id)),
            pace: settings.pace,
            montageLook: MontageLook(rawValue: validated.treatment.look.rawValue) ?? settings.look,
            motionIntensity: MontageMotionIntensity(
                rawValue: validated.treatment.motionIntensity.rawValue
            ) ?? settings.motion,
            titleCards: titleCards,
            titleDrafts: titleDrafts,
            textOverlays: Self.aiTextOverlays(
                for: validated,
                plannedPhotos: plannedPhotos
            ),
            selectedTrackID: validated.soundtrack.trackID.rawValue,
            cutToBeat: true
        )
    }

    private static func aiTextOverlays(
        for plan: AICutEditPlan,
        plannedPhotos: [ReelPhoto]
    ) -> [MontageTextOverlay] {
        guard !plannedPhotos.isEmpty else { return [] }
        var result: [MontageTextOverlay] = []
        var usedPhotoIDs: Set<String> = []
        var usedText: Set<String> = []

        func append(_ rawText: String, photo: ReelPhoto, placement: MontageTextPlacement, animation: MontageTextAnimation, style: MontageTitleStyle) {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !text.isEmpty, !usedPhotoIDs.contains(photo.id), !usedText.contains(normalized) else { return }
            usedPhotoIDs.insert(photo.id)
            usedText.insert(normalized)
            result.append(MontageTextOverlay(
                id: "ai-text-\(photo.id)",
                photoID: photo.id,
                text: String(text.prefix(80)),
                style: style,
                placement: placement,
                animation: animation
            ))
        }

        append(
            plan.hook.title,
            photo: plannedPhotos[0],
            placement: plannedPhotos[0].protectsPeople ? .top : .bottom,
            animation: .rise,
            style: titleStyle(for: plan.hook.style)
        )
        if plannedPhotos.count >= 5 {
            append(
                plan.story.title,
                photo: plannedPhotos[plannedPhotos.count / 2],
                placement: .bottom,
                animation: .fade,
                style: .clean
            )
        }
        if plan.ending.enabled, let finalPhoto = plannedPhotos.last {
            append(
                plan.ending.title,
                photo: finalPhoto,
                placement: finalPhoto.protectsPeople ? .top : .bottom,
                animation: .pop,
                style: titleStyle(for: plan.ending.style)
            )
        }
        return result
    }

    private static func titleStyle(for style: AICutTitleStyle) -> MontageTitleStyle {
        switch style {
        case .editorial: .editorial
        case .clean: .clean
        case .bold: .bold
        }
    }

    private static func recommendations(for plan: AICutEditPlan) -> [AICutRecommendation] {
        let hasChapter = plan.sequence.count >= 5 && plan.story.title.compare(
            plan.hook.title,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != .orderedSame
        let chapter = hasChapter ? ", adds “\(plan.story.title)” as a chapter" : ""
        let closing = plan.ending.enabled
            ? "Opens with “\(plan.hook.title)”\(chapter), and closes with “\(plan.ending.title)”."
            : "Opens with “\(plan.hook.title)”\(chapter), and lets the final photo close the film."
        return [
            AICutRecommendation(
                kind: .story,
                title: plan.story.title,
                detail: plan.story.arc
            ),
            AICutRecommendation(
                kind: .titles,
                title: "Titles with a story",
                detail: closing
            ),
            AICutRecommendation(
                kind: .music,
                title: plan.soundtrack.trackID.displayName,
                detail: plan.soundtrack.reason
            ),
            AICutRecommendation(
                kind: .treatment,
                title: "\(plan.treatment.look.displayName) · \(plan.treatment.motionIntensity.displayName)",
                detail: plan.treatment.reason
            )
        ]
    }

    private static func cloudFirstCutBaseline(
        _ firstCut: TripEditSnapshot,
        localIDsByWireID: [String: String]
    ) -> CloudFirstCutInput? {
        let wireIDsByLocalID = Dictionary(
            uniqueKeysWithValues: localIDsByWireID.map { ($0.value, $0.key) }
        )
        let defaultDuration = 1.85 - (firstCut.pace * 1.25)
        let submittedPhotos = firstCut.keptPhotos.compactMap { photo -> (String, ReelPhoto)? in
            guard let wireID = wireIDsByLocalID[photo.id] else { return nil }
            return (wireID, photo)
        }
        guard !submittedPhotos.isEmpty else { return nil }

        let sequence = submittedPhotos.enumerated().map { index, value in
            CloudFirstCutSequenceItem(
                photoID: value.0,
                order: index,
                durationSeconds: min(max(value.1.durationSeconds ?? defaultDuration, 0.6), 4),
                motion: cloudMotion(value.1.motionStyle),
                frameStyle: cloudFrameStyle(value.1.frameStyle)
            )
        }
        let titles = firstCut.montageTitleCards.compactMap { card -> CloudFirstCutTitle? in
            let title = boundedCloudText(
                cloudPlainText(card.title),
                maximumUTF16Units: 60
            )
            guard !title.isEmpty else { return nil }
            return CloudFirstCutTitle(
                kind: cloudTitleKind(card.kind),
                title: title,
                subtitle: boundedCloudText(
                    cloudPlainText(card.subtitle),
                    maximumUTF16Units: 100
                ),
                style: cloudTitleStyle(card.style),
                durationSeconds: min(max(card.duration, 1), 4)
            )
        }
        return CloudFirstCutInput(
            photoCount: firstCut.keptPhotos.count,
            durationSeconds: firstCut.durationSeconds,
            omittedPhotoCount: firstCut.keptPhotos.count - sequence.count,
            sequence: sequence,
            titles: titles,
            soundtrackID: firstCut.selectedTrackID ?? "none",
            look: AICutLook(rawValue: firstCut.montageLook.rawValue) ?? .story,
            motionIntensity: AICutMotionIntensity(rawValue: firstCut.motionIntensity.rawValue) ?? .gentle
        )
    }

    private static func aiEditorialContexts(
        for candidates: [AICutCandidate],
        sourceAssets: [TripAsset],
        tripStartDate: Date,
        insights: [String: MontagePhotoInsight],
        calendar: Calendar = .current
    ) -> [String: CloudPhotoEditorialContext] {
        let chronological = sourceAssets.sorted { left, right in
            switch (left.creationDate, right.creationDate) {
            case let (leftDate?, rightDate?) where leftDate != rightDate: return leftDate < rightDate
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.id < right.id
            }
        }
        let positions = Dictionary(uniqueKeysWithValues: chronological.enumerated().map { ($0.element.id, $0.offset) })
        let similarityGroups = aiSimilarityGroups(candidates: candidates, insights: insights)
        let startDay = calendar.startOfDay(for: tripStartDate)

        return Dictionary(uniqueKeysWithValues: candidates.map { candidate in
            let asset = candidate.asset
            let position = positions[asset.id] ?? 0
            let previous = position > 0 ? chronological[position - 1] : nil
            let insight = insights[asset.id] ?? MontagePhotoInsight()
            let assetDay = calendar.startOfDay(for: asset.creationDate ?? tripStartDate)
            let dayIndex = max(0, min(365, calendar.dateComponents([.day], from: startDay, to: assetDay).day ?? 0))
            return (asset.id, CloudPhotoEditorialContext(
                captureIndex: min(100_000, position),
                dayIndex: dayIndex,
                timeGap: cloudTimeGap(from: previous?.creationDate, to: asset.creationDate, calendar: calendar),
                orientation: cloudOrientation(width: asset.pixelWidth, height: asset.pixelHeight),
                contentKind: CloudPhotoContentKind(rawValue: insight.contentKind.rawValue) ?? .moment,
                peopleCount: min(20, insight.peopleCount),
                memory: cloudScoreBand(insight.memoryScore),
                aesthetic: cloudScoreBand(insight.aestheticScore),
                similarityGroup: similarityGroups[asset.id] ?? "",
                sceneLabels: cloudSceneLabels(insight.classifications)
            ))
        })
    }

    private static func aiSimilarityGroups(
        candidates: [AICutCandidate],
        insights: [String: MontagePhotoInsight]
    ) -> [String: String] {
        guard candidates.count > 1 else { return [:] }
        var parent = Array(0..<candidates.count)
        func root(_ value: Int) -> Int {
            var current = value
            while parent[current] != current { current = parent[current] }
            return current
        }
        for left in 0..<(candidates.count - 1) {
            guard let leftInsight = insights[candidates[left].asset.id],
                  let leftPrint = leftInsight.featurePrint else { continue }
            for right in (left + 1)..<candidates.count {
                guard let rightInsight = insights[candidates[right].asset.id],
                      let rightPrint = rightInsight.featurePrint,
                      NativePhotoSimilarity.areSimilar(
                          candidates[left].asset,
                          firstPrint: leftPrint,
                          candidates[right].asset,
                          secondPrint: rightPrint,
                          firstProtectsPeople: leftInsight.peopleCount > 0,
                          secondProtectsPeople: rightInsight.peopleCount > 0
                      ) else { continue }
                let leftRoot = root(left)
                let rightRoot = root(right)
                if leftRoot != rightRoot { parent[rightRoot] = leftRoot }
            }
        }

        var membersByRoot: [Int: [Int]] = [:]
        for index in candidates.indices { membersByRoot[root(index), default: []].append(index) }
        var result: [String: String] = [:]
        var groupIndex = 0
        for members in membersByRoot.values.sorted(by: { ($0.first ?? 0) < ($1.first ?? 0) }) where members.count > 1 {
            let group = "g\(groupIndex)"
            groupIndex += 1
            for index in members { result[candidates[index].asset.id] = group }
        }
        return result
    }

    private static func cloudSceneLabels(
        _ classifications: [NativePhotoClassification]
    ) -> [String] {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-")
        var seen: Set<String> = []
        var result: [String] = []
        for classification in classifications {
            var scalars = String.UnicodeScalarView()
            for scalar in classification.identifier.unicodeScalars {
                scalars.append(allowed.contains(scalar) ? scalar : " ")
            }
            let normalized = String(String(scalars).prefix(48))
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !normalized.isEmpty, seen.insert(normalized.lowercased()).inserted else { continue }
            result.append(normalized)
            if result.count == 3 { break }
        }
        return result
    }

    private static func boundedCloudText(
        _ value: String,
        maximumUTF16Units: Int
    ) -> String {
        var result = ""
        for character in value {
            let addition = String(character)
            guard result.utf16.count + addition.utf16.count <= maximumUTF16Units else { break }
            result.append(character)
        }
        return result
    }

    private static func cloudPlainText(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func cloudTimeGap(
        from previous: Date?,
        to current: Date?,
        calendar: Calendar
    ) -> CloudPhotoTimeGap {
        guard let current else { return .later }
        guard let previous else { return .start }
        let interval = max(0, current.timeIntervalSince(previous))
        if interval <= 2 * 60 { return .burst }
        if interval <= 30 * 60 { return .sameSession }
        if calendar.isDate(previous, inSameDayAs: current) { return .sameDay }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: previous),
            to: calendar.startOfDay(for: current)
        ).day ?? 2
        return days <= 1 ? .nextDay : .later
    }

    private static func cloudOrientation(width: Int, height: Int) -> CloudPhotoOrientation {
        guard width > 0, height > 0 else { return .landscape }
        let ratio = Double(width) / Double(height)
        if ratio < 0.9 { return .portrait }
        if ratio > 1.1 { return .landscape }
        return .square
    }

    private static func cloudScoreBand(_ value: Double) -> CloudPhotoScoreBand {
        if value < 0.36 { return .low }
        if value >= 0.7 { return .high }
        return .medium
    }

    private static func cloudMotion(_ style: MontageMotionStyle) -> AICutMotion {
        switch style {
        case .zoomIn: .zoomIn
        case .zoomOut: .zoomOut
        case .panLeft: .panLeft
        case .panRight: .panRight
        case .rise: .rise
        case .settle: .settle
        }
    }

    private static func cloudFrameStyle(_ style: MontageFrameStyle) -> CloudFirstCutFrameStyle {
        switch style {
        case .fullBleed: .fullBleed
        case .portraitMatte: .portraitMatte
        case .cinematic: .cinematic
        case .postcard: .postcard
        }
    }

    private static func cloudTitleKind(_ kind: TitleCardKind) -> CloudFirstCutTitleKind {
        switch kind {
        case .opening: .opening
        case .place: .chapter
        case .ending: .ending
        }
    }

    private static func cloudTitleStyle(_ style: MontageTitleStyle) -> AICutTitleStyle {
        switch style {
        case .editorial: .editorial
        case .clean: .clean
        case .bold: .bold
        }
    }

    private func availableAICutCandidatePhotos() -> [AICutCandidatePhoto] {
        guard let firstCutSnapshot,
              let sourceTrip = activeAnalysisTrip ?? selectedTrip else { return [] }

        let firstCutIDs = Set(firstCutSnapshot.keptPhotos.map(\.id))
        let recoverableIDs = Set(excludedPhotos.compactMap { excluded in
            excluded.reason.isEligibleForCloudReconsideration ? excluded.id : nil
        })
        let eligibleIDs = firstCutIDs.union(recoverableIDs).subtracting(cloudBlockedPhotoIDs)
        let allPhotos = applyingPhotoEdits(
            to: Self.makeReelPhotos(from: sourceTrip, insights: activePhotoInsights)
        )

        return allPhotos.compactMap { photo in
            guard eligibleIDs.contains(photo.id) else { return nil }
            return AICutCandidatePhoto(
                photo: photo,
                localSelection: firstCutIDs.contains(photo.id) ? .firstCut : .morePhotos
            )
        }
    }

    private func resetAICutPhotoSelection() {
        guard let firstCutSnapshot else {
            selectedAICutPhotoIDs = []
            return
        }
        let options = availableAICutCandidatePhotos()
        let eligibleFirstCutIDs = Set(
            options.filter { $0.localSelection == .firstCut }.map { $0.photo.id }
        )
        let morePhotos = options.filter { $0.localSelection == .morePhotos }.map(\.photo)
        selectedAICutPhotoIDs = Set(
            Self.balancedAICandidatePhotos(
                firstCut: firstCutSnapshot.keptPhotos.filter { photo in
                    eligibleFirstCutIDs.contains(photo.id)
                },
                morePhotos: morePhotos,
                blockedIDs: cloudBlockedPhotoIDs,
                limit: aiCutPhotoSelectionLimit
            ).map { $0.photo.id }
        )
    }

    /// Gives the AI a balanced view of the local First Cut and safe, locally
    /// analyzed omissions. When one pool is small, the other fills the unused
    /// slots. This makes a 3-of-26 local cut become 3 First Cut + 23 More Photos
    /// candidates instead of hiding those 23 moments from the visual editor.
    private static func balancedAICandidatePhotos(
        firstCut: [ReelPhoto],
        morePhotos: [ReelPhoto],
        blockedIDs: Set<String>,
        limit: Int
    ) -> [AICutCandidatePhoto] {
        guard limit > 0 else { return [] }

        let eligibleFirstCut = firstCut.filter { !blockedIDs.contains($0.id) }
        let firstCutIDs = Set(eligibleFirstCut.map(\.id))
        let eligibleMorePhotos = morePhotos.filter {
            !blockedIDs.contains($0.id) && !firstCutIDs.contains($0.id)
        }

        let desiredMoreCount = min(eligibleMorePhotos.count, limit / 2)
        var firstCount = min(eligibleFirstCut.count, limit - desiredMoreCount)
        var moreCount = desiredMoreCount
        var unfilled = limit - firstCount - moreCount
        if unfilled > 0 {
            let additionalMore = min(unfilled, eligibleMorePhotos.count - moreCount)
            moreCount += additionalMore
            unfilled -= additionalMore
        }
        if unfilled > 0 {
            firstCount += min(unfilled, eligibleFirstCut.count - firstCount)
        }

        let selectedFirstCut = evenlySampled(eligibleFirstCut, limit: firstCount).map {
            AICutCandidatePhoto(photo: $0, localSelection: .firstCut)
        }
        let selectedMorePhotos = evenlySampled(eligibleMorePhotos, limit: moreCount).map {
            AICutCandidatePhoto(photo: $0, localSelection: .morePhotos)
        }

        var interleaved: [AICutCandidatePhoto] = []
        interleaved.reserveCapacity(selectedFirstCut.count + selectedMorePhotos.count)
        for index in 0..<max(selectedFirstCut.count, selectedMorePhotos.count) {
            if index < selectedFirstCut.count { interleaved.append(selectedFirstCut[index]) }
            if index < selectedMorePhotos.count { interleaved.append(selectedMorePhotos[index]) }
        }
        return interleaved
    }

    private static func evenlySampled<Element>(_ values: [Element], limit: Int) -> [Element] {
        guard limit > 0 else { return [] }
        guard values.count > limit else { return values }
        guard limit > 1 else { return [values[values.count / 2]] }
        return (0..<limit).map { index in
            let position = Double(index) * Double(values.count - 1) / Double(limit - 1)
            return values[Int(position.rounded())]
        }
    }

    private static func choreographedMotionStyle(
        for item: AICutPlanItem,
        photo: ReelPhoto,
        index: Int,
        previous: MontageMotionStyle?
    ) -> MontageMotionStyle {
        // Preserve the face-aware motion chosen on-device. A cloud suggestion
        // must never turn a safe group composition into an aggressive crop.
        if photo.protectsPeople {
            return photo.automaticMotionStyle
        }

        let requested: MontageMotionStyle
        switch item.motion {
        case .automatic:
            switch item.role {
            case .opening, .establishing, .scenery:
                requested = index.isMultiple(of: 2) ? .panLeft : .panRight
            case .people:
                requested = index.isMultiple(of: 2) ? .zoomIn : .settle
            case .detail, .food:
                requested = index.isMultiple(of: 2) ? .rise : .zoomIn
            case .bridge:
                requested = index.isMultiple(of: 2) ? .zoomOut : .panRight
            case .closing:
                requested = .settle
            }
        case .zoomIn: requested = .zoomIn
        case .zoomOut: requested = .zoomOut
        case .panLeft: requested = .panLeft
        case .panRight: requested = .panRight
        case .rise: requested = .rise
        case .settle: requested = .settle
        }

        guard requested == previous else { return requested }
        switch requested {
        case .zoomIn: return .panLeft
        case .zoomOut: return .rise
        case .panLeft: return .zoomIn
        case .panRight: return .settle
        case .rise: return .panRight
        case .settle: return .zoomOut
        }
    }

    private static func aiSettings(
        for direction: AICutDirection,
        fallback: TripEditSnapshot
    ) -> (pace: Double, look: MontageLook, motion: MontageMotionIntensity) {
        switch direction {
        case .betterStory: (0.50, .story, .gentle)
        case .dynamic: (0.72, .clean, .expressive)
        case .calm: (0.24, .cinema, .gentle)
        case .people: (0.48, .journal, .gentle)
        case .surpriseMe: (0.57, fallback.montageLook, .expressive)
        }
    }

    private func installDemoAICut() {
        guard let firstCutSnapshot else { return }
        let included = firstCutSnapshot.keptPhotos.enumerated().compactMap { index, photo -> ReelPhoto? in
            guard index % 3 != 1 else { return nil }
            var edited = photo
            edited.durationSeconds = index % 4 == 0 ? 2.4 : 1.1
            edited.motionStyle = index.isMultiple(of: 2) ? .zoomIn : .panLeft
            return edited
        }
        let includedIDs = Set(included.map(\.id))
        let remaining = firstCutSnapshot.photos.filter { !includedIDs.contains($0.id) }
        aiCutSnapshot = TripEditSnapshot(
            photos: included + remaining,
            cutPhotoIDs: Set(remaining.map(\.id)),
            pace: 0.68,
            montageLook: .story,
            motionIntensity: .expressive,
            titleCards: firstCutSnapshot.titleCards.union([.opening, .ending]),
            titleDrafts: firstCutSnapshot.titleDrafts.merging([
                .opening: TitleCardDraft(
                    title: "One memory, many little turns",
                    subtitle: "A different way to remember it",
                    style: .editorial,
                    duration: 2.4
                ),
                .ending: TitleCardDraft(
                    title: "Until the next road",
                    subtitle: "Made with Memories",
                    style: .clean,
                    duration: 2.0
                )
            ]) { _, aiDraft in aiDraft },
            textOverlays: included.isEmpty ? [] : [
                MontageTextOverlay(
                    id: "demo-ai-text",
                    photoID: included[0].id,
                    text: "The moments between the moments",
                    style: .editorial,
                    placement: .bottom,
                    animation: .rise
                )
            ],
            selectedTrackID: "simplicity",
            cutToBeat: true
        )
        aiCutSummary = "A tighter alternative with a stronger opening, fewer repeated moments and a quicker finish."
        aiCutRecommendations = [
            AICutRecommendation(kind: .story, title: "Arrival to afterglow", detail: "Open with discovery, build through people and details, then finish on a quiet memory."),
            AICutRecommendation(kind: .titles, title: "Titles with a story", detail: "Opens with “One memory, many little turns”, adds a chapter beat, and closes with a brief final thought."),
            AICutRecommendation(kind: .music, title: "Simplicity", detail: "A light acoustic rhythm supports the warmer, quicker edit."),
            AICutRecommendation(kind: .treatment, title: "Story · Expressive", detail: "Varied framing and movement give each moment a distinct role.")
        ]
        aiCutDiagnosis = AICutDiagnosis(
            verdict: "The First Cut needs a clearer build and a more intentional finish.",
            issues: [
                AICutDiagnosisIssue(
                    kind: .flatPacing,
                    title: "One steady rhythm",
                    detail: "Hero moments need longer holds while connective moments can move faster.",
                    evidencePhotoIDs: []
                )
            ]
        )
        aiCutComparison = AICutComparison(
            firstCutPhotoCount: firstCutSnapshot.keptPhotos.count,
            aiCutPhotoCount: included.count,
            restoredCount: 0,
            removedCount: remaining.count,
            reorderedCount: max(0, included.count / 4),
            retimedCount: included.count,
            motionChangedCount: included.count,
            titleChangedCount: 2,
            soundtrackChanged: true,
            treatmentChanged: true,
            score: 68,
            materiallyDifferent: true
        )
    }

    func cancelPhotoAnalysis() {
        photoAnalysisGeneration = UUID()
        photoAnalysisTask?.cancel()
        photoAnalysisTask = nil
        isAnalyzingPhotos = false
        photoAnalysisProgress = 0
        photoAnalysisStatus = "Preparing smart selection"
        photoAnalysisCurrentAsset = nil
        photoAnalysisRecentAssets = []
        photoAnalysisProcessedCount = 0
        photoAnalysisTotalCount = 0
    }

    func includeExcludedPhoto(id: String) {
        guard let excludedIndex = excludedPhotos.firstIndex(where: { $0.id == id }),
              let selectedTrip else { return }
        let restored = excludedPhotos.remove(at: excludedIndex)
        guard let updatedTrip = selectedTrip.replacingAssets(selectedTrip.assets + [restored.asset]) else {
            return
        }
        manuallyIncludedPhotoIDs.insert(restored.id)
        selectedCutSource = .working
        self.selectedTrip = updatedTrip
        photos = applyingPhotoEdits(
            to: Self.makeReelPhotos(from: updatedTrip, insights: activePhotoInsights)
        )
        cutPhotoIDs.formIntersection(Set(photos.map(\.id)))
        currentPhotoIndex = min(currentPhotoIndex, max(0, photos.count - 1))
    }

    /// Rechecks the source trip on demand while leaving the current preview
    /// intact until a refreshed cut is ready. This deliberately happens only
    /// after the user asks, so temporary iCloud work never blocks first watch.
    func retryPhotoAnalysisFollowUp() {
        guard let trip = activeAnalysisTrip,
              photoAnalysisFollowUp?.hasAnythingToCheck == true,
              !isAnalyzingPhotos else { return }
        beginSmartPhotoSelection(for: trip, preservesExistingFollowUp: true)
    }

    private func setCloudAnalysisPreference(_ preference: CloudAnalysisPreference) {
        cloudAnalysisPreference = preference
        preferenceStore.set(preference.rawValue, forKey: Self.cloudPreferenceKey)
    }

    private func beginSmartPhotoSelection(
        for trip: Trip,
        preservesExistingFollowUp: Bool = false
    ) {
        photoAnalysisTask?.cancel()
        activeAnalysisTrip = trip
        if !preservesExistingFollowUp {
            photoAnalysisFollowUp = nil
            manuallyIncludedPhotoIDs = []
        }
        let generation = UUID()
        photoAnalysisGeneration = generation
        excludedPhotos = []
        photoAnalysisProgress = 0
        photoAnalysisStatus = "Gathering your moments"
        photoAnalysisCurrentAsset = nil
        photoAnalysisRecentAssets = []
        photoAnalysisProcessedCount = 0
        photoAnalysisTotalCount = trip.assets.count
        activePhotoInsights = [:]
        cloudBlockedPhotoIDs = []

        // The analysis coordinator is installed below; keeping this launch in a
        // cancellable task prevents a second trip tap from racing the first.
        photoAnalysisTask = Task { [weak self] in
            guard let self else { return }
            await self.analyzeAndBuild(trip: trip, generation: generation)
        }
    }

    private func analyzeAndBuild(trip: Trip, generation: UUID) async {
        guard photoAnalysisGeneration == generation else { return }
        isAnalyzingPhotos = true
        var decisions: [String: SmartExcludedPhoto] = [:]
        var analyzedCount = 0
        var unavailableCount = 0
        var followUp = PhotoAnalysisFollowUp()
        var montageInsights: [String: MontagePhotoInsight] = [:]
        var nativeResults: [String: NativePhotoIntelligenceResult] = [:]

        for (index, asset) in trip.assets.enumerated() {
            guard photoAnalysisGeneration == generation, !Task.isCancelled else {
                finishPhotoAnalysisCancellation(generation: generation)
                return
            }

            photoAnalysisCurrentAsset = asset

            if let metadataDecision = SmartPhotoSelectionPolicy.metadataDecision(for: asset) {
                decisions[asset.id] = metadataDecision
                cloudBlockedPhotoIDs.insert(asset.id)
                recordProcessedPhoto(asset, index: index, total: trip.assets.count)
                continue
            }

            do {
                let thumbnail = try await photoAnalysisThumbnails.prepare(asset: asset)
                let nativeResult = try await nativePhotoIntelligence.analyze(
                    cgImage: thumbnail.cgImage,
                    orientation: .up,
                    metadata: NativePhotoIntelligenceMetadata(
                        sourceIdentifier: asset.id,
                        isScreenshot: asset.isScreenshot
                    )
                )
                analyzedCount += 1
                nativeResults[asset.id] = nativeResult
                montageInsights[asset.id] = MontagePhotoInsight(result: nativeResult)
                if nativeResult.cloudReviewGate.disposition == .blockedSensitiveContent {
                    // The optional director sees only locally approved previews.
                    // A meaningful photo may remain in First Cut while its
                    // document/text content is still withheld from the cloud.
                    cloudBlockedPhotoIDs.insert(asset.id)
                }

                if let localDecision = SmartPhotoSelectionPolicy.nativeDecision(
                    for: asset,
                    result: nativeResult
                ) {
                    decisions[asset.id] = localDecision
                    switch localDecision.reason {
                    case .screenshot, .document, .utilityImage:
                        cloudBlockedPhotoIDs.insert(asset.id)
                    case .waitingForPhotos, .lowQuality, .similarMoment, .notAHighlight:
                        break
                    }
                }
            } catch is CancellationError {
                finishPhotoAnalysisCancellation(generation: generation)
                return
            } catch {
                // A photo that is not locally readable stays recoverable in
                // More Photos, but never becomes an empty frame in the first
                // preview. A later retry rebuilds the cut and can restore it.
                unavailableCount += 1
                let followUpReason = Self.photoAnalysisFollowUpReason(for: error)
                switch followUpReason {
                case .syncingFromPhotos:
                    followUp.syncingFromPhotosCount += 1
                case .anotherLook:
                    followUp.anotherLookCount += 1
                case .accessNeeded:
                    followUp.accessNeededCount += 1
                }
                decisions[asset.id] = SmartExcludedPhoto(
                    asset: asset,
                    reason: .waitingForPhotos,
                    detail: Self.photoAnalysisDeferredDetail(for: followUpReason),
                    confidence: 1,
                    origin: .onDevice
                )
            }

            recordProcessedPhoto(asset, index: index, total: trip.assets.count)
        }

        guard photoAnalysisGeneration == generation, !Task.isCancelled else {
            finishPhotoAnalysisCancellation(generation: generation)
            return
        }
        photoAnalysisStatus = "Shaping the strongest story"
        let selectionAssets = trip.assets
        let selectionResults = nativeResults
        let existingDecisions = decisions
        let contextualDecisions = await Task.detached(priority: .userInitiated) {
            SmartHighlightSelector.decisions(
                for: selectionAssets,
                nativeResults: selectionResults,
                excluding: existingDecisions
            )
        }.value
        guard photoAnalysisGeneration == generation, !Task.isCancelled else {
            finishPhotoAnalysisCancellation(generation: generation)
            return
        }
        for decision in contextualDecisions where decisions[decision.id] == nil {
            decisions[decision.id] = decision
        }
        for photoID in manuallyIncludedPhotoIDs {
            decisions.removeValue(forKey: photoID)
        }

        // Never allow automation to create an empty film. If every image was a
        // high-confidence utility photo, keep one readable image and let the
        // user decide in the regular cut flow. Never use an unreadable iCloud
        // item as that fallback, because it would create a blank preview.
        var includedAssets = trip.assets.filter { decisions[$0.id] == nil }
        if includedAssets.isEmpty, !trip.assets.isEmpty {
            let readableFallbacks = trip.assets.filter {
                decisions[$0.id]?.reason != .waitingForPhotos
            }
            if let fallback = readableFallbacks.dropFirst(readableFallbacks.count / 2).first {
                decisions.removeValue(forKey: fallback.id)
                includedAssets = [fallback]
            } else {
                excludedPhotos = trip.assets.compactMap { decisions[$0.id] }
                photoAnalysisProgress = 1
                photoAnalysisStatus = "Waiting for Photos to finish syncing"
                isAnalyzingPhotos = false
                photoAnalysisCurrentAsset = nil
                photoAnalysisTask = nil
                activePhotoInsights = montageInsights
                photoAnalysisFollowUp = followUp.hasAnythingToCheck ? followUp : nil
                libraryErrorMessage = "Your memory is safe in Photos. These moments are still syncing from iCloud, so Memories held back the preview instead of showing empty frames. Check your connection and try this memory again shortly."
                return
            }
        }
        guard let selected = trip.replacingAssets(includedAssets) else {
            finishPhotoAnalysisCancellation(generation: generation)
            return
        }

        excludedPhotos = trip.assets.compactMap { decisions[$0.id] }
        photoAnalysisProgress = 1
        photoAnalysisStatus = "First Cut complete on this iPhone"
        isAnalyzingPhotos = false
        photoAnalysisCurrentAsset = nil
        photoAnalysisTask = nil
        activePhotoInsights = montageInsights
        photoAnalysisFollowUp = followUp.hasAnythingToCheck ? followUp : nil

        startBuild(trip: selected)
    }

    private static func photoAnalysisFollowUpReason(
        for error: Error
    ) -> PhotoAnalysisFollowUpReason {
        if let thumbnailError = error as? PhotoAnalysisThumbnailError {
            switch thumbnailError {
            case .unavailable:
                return .syncingFromPhotos
            case .inaccessible:
                return .accessNeeded
            case .decodeFailed, .encodeFailed, .tooLarge:
                return .anotherLook
            }
        }

        if let nativeError = error as? NativePhotoIntelligenceError {
            switch nativeError {
            case .photoLibraryAccessUnavailable, .assetNotFound:
                return .accessNeeded
            case .assetUnavailableLocally, .imageRequestFailed:
                return .syncingFromPhotos
            case .invalidImage, .visionRequestFailed:
                return .anotherLook
            }
        }

        let error = error as NSError
        if error.domain == PHPhotosErrorDomain {
            return .syncingFromPhotos
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("icloud") || message.contains("network") || message.contains("download") {
            return .syncingFromPhotos
        }
        return .anotherLook
    }

    private static func photoAnalysisDeferredDetail(
        for reason: PhotoAnalysisFollowUpReason
    ) -> String {
        switch reason {
        case .syncingFromPhotos:
            "Still syncing from iCloud. Check again when Photos has finished."
        case .anotherLook:
            "Memories couldn't read this copy yet. Check it again later."
        case .accessNeeded:
            "Photos access changed. Review access, then check this moment again."
        }
    }

    private func recordProcessedPhoto(_ asset: TripAsset, index: Int, total: Int) {
        photoAnalysisRecentAssets.removeAll { $0.id == asset.id }
        photoAnalysisRecentAssets.append(asset)
        if photoAnalysisRecentAssets.count > 6 {
            photoAnalysisRecentAssets.removeFirst(photoAnalysisRecentAssets.count - 6)
        }
        photoAnalysisProcessedCount = index + 1
        let completed = Double(index + 1)
        photoAnalysisProgress = total == 0 ? 1 : min(0.92, completed / Double(total) * 0.92)
        switch (index / 7) % 4 {
        case 0: photoAnalysisStatus = "Reading light and composition"
        case 1: photoAnalysisStatus = "Finding faces and shared moments"
        case 2: photoAnalysisStatus = "Comparing similar frames"
        default: photoAnalysisStatus = "Building the rhythm of your memory"
        }
    }

    private func finishPhotoAnalysisCancellation(generation: UUID) {
        guard photoAnalysisGeneration == generation else { return }
        isAnalyzingPhotos = false
        photoAnalysisProgress = 0
        photoAnalysisStatus = "Preparing smart selection"
        photoAnalysisCurrentAsset = nil
        photoAnalysisRecentAssets = []
        photoAnalysisProcessedCount = 0
        photoAnalysisTotalCount = 0
        photoAnalysisTask = nil
    }

    func scanPhotoLibrary(navigateToResults: Bool) async {
        guard !usesDemoData else {
            if navigateToResults { showTripResults() }
            return
        }

        pendingResultNavigation = pendingResultNavigation || navigateToResults
        if scanCoordinatorActive {
            scanAgainRequested = true
            return
        }

        scanCoordinatorActive = true
        defer {
            scanCoordinatorActive = false
            scanAgainRequested = false
        }

        var completedGeneration: UUID?
        repeat {
            scanAgainRequested = false
            guard let generation = await performPhotoLibraryScan() else { return }
            completedGeneration = generation
        } while scanAgainRequested && !Task.isCancelled

        guard let completedGeneration, !Task.isCancelled else {
            pendingResultNavigation = false
            return
        }

        if pendingResultNavigation {
            pendingResultNavigation = false
            showTripResults()
        } else if screen == .trips && trips.isEmpty && nearbyEvents.isEmpty {
            go(.empty)
        } else if screen == .empty && (!trips.isEmpty || !nearbyEvents.isEmpty) {
            go(.trips)
        }

        placeTask = Task { [weak self] in
            await self?.resolveTripNames(generation: completedGeneration)
        }
    }

    private func performPhotoLibraryScan() async -> UUID? {
        let generation = UUID()
        scanGeneration = generation
        placeTask?.cancel()
        detectorTask?.cancel()
        isScanningLibrary = true
        libraryErrorMessage = nil
        lastAuthorizationStatus = photoLibrary.authorizationStatus
        defer {
            if scanGeneration == generation {
                isScanningLibrary = false
                if Task.isCancelled {
                    pendingResultNavigation = false
                }
            }
        }

        let metadata = await photoLibrary.fetchAllPhotos()
        guard scanGeneration == generation, !Task.isCancelled else { return nil }

        libraryPhotoCount = metadata.count
        selectedPhotoCount = metadata.count
        libraryPreviewPhotos = Self.makePreviewPhotos(from: metadata)

        let task = Task.detached(priority: .userInitiated) {
            let trips = TripDetector.detect(in: metadata, shouldCancel: { Task.isCancelled })
            guard !Task.isCancelled else {
                return LibraryDetectionResult(trips: [], nearbyEvents: [])
            }
            let nearbyEvents = NearbyEventDetector.detect(
                in: metadata,
                shouldCancel: { Task.isCancelled }
            )
            return LibraryDetectionResult(trips: trips, nearbyEvents: nearbyEvents)
        }
        detectorTask = task
        let detected = await task.value
        if scanGeneration == generation {
            detectorTask = nil
        }
        guard scanGeneration == generation, !Task.isCancelled else { return nil }

        trips = detected.trips.map { Self.makeTrip(from: $0) }
        nearbyEvents = detected.nearbyEvents.map { Self.makeNearbyEvent(from: $0) }
        discardImportedPhotoFiles()
        hasManualSelection = false
        hasPermissionFreeSelection = false
        isManualSelectionInProgress = false
        resolvedCoordinates = Dictionary(
            uniqueKeysWithValues: (detected.trips + detected.nearbyEvents).compactMap { trip in
                trip.centroid.map { (trip.id, $0) }
            }
        )
        reconcileActiveFilm(withAvailableLibraryIDs: Set(metadata.map(\.id)))
        hasScannedLibrary = true
        return generation
    }

    func refreshPhotoLibraryIfAuthorized(force: Bool = false) async {
        guard !usesDemoData else { return }
        // Keep the one-time brand entrance fluid and predictable. Existing
        // users who already granted Photos access begin scanning after they
        // continue, rather than competing with the welcome animation.
        guard screen != .welcome else { return }
        let status = photoLibrary.authorizationStatus
        let previousStatus = lastAuthorizationStatus

        guard status == .authorized || status == .limited else {
            if hasPermissionFreeSelection { return }
            clearLibraryState(afterAuthorizationChangedTo: status)
            return
        }

        if hasManualSelection && !force {
            if !hasPermissionFreeSelection {
                await reconcilePhotoKitManualSelection()
            }
            return
        }

        let upgradedFromLimited = status == .authorized && previousStatus == .limited
        let shouldNavigate = (upgradedFromLimited && screen == .limited) || screen == .access
        guard force || shouldNavigate || !hasScannedLibrary || previousStatus != status else { return }
        await scanPhotoLibrary(navigateToResults: shouldNavigate)
    }

    @discardableResult
    func loadManualSelection(identifiers: [String]) async -> Bool {
        guard !identifiers.isEmpty else { return false }
        let generation = beginManualSelection()
        defer {
            if manualSelectionGeneration == generation {
                isManualSelectionInProgress = false
            }
        }
        let metadata = await photoLibrary.fetchPhotos(withLocalIdentifiers: identifiers)
        guard manualSelectionGeneration == generation, !Task.isCancelled else { return false }
        guard !metadata.isEmpty, Set(metadata.map(\.id)) == Set(identifiers) else {
            isManualSelectionInProgress = false
            libraryErrorMessage = "Some selected photos are outside Memories' current Photo Library access. Allow Full Access or add them to Limited Access, then try again."
            return false
        }

        return await installPhotoKitManualSelection(
            metadata: metadata,
            identifiers: identifiers,
            generation: generation
        )
    }

    private func installPhotoKitManualSelection(
        metadata: [PhotoMetadata],
        identifiers: [String],
        generation: UUID
    ) async -> Bool {
        guard manualSelectionGeneration == generation, !Task.isCancelled else { return false }
        invalidateAutomaticScan()
        var order: [String: Int] = [:]
        for (index, identifier) in identifiers.enumerated() where order[identifier] == nil {
            order[identifier] = index
        }
        let sorted = metadata.sorted {
            let left = order[$0.id] ?? .max
            let right = order[$1.id] ?? .max
            return left == right ? $0.id < $1.id : left < right
        }
        let dated = sorted.compactMap(\.creationDate)
        let startDate = dated.min() ?? Date()
        let endDate = dated.max() ?? startDate
        let assets = sorted.map {
            TripAsset(
                id: $0.id,
                source: .library($0.id),
                creationDate: $0.creationDate,
                filename: $0.filename,
                isScreenshot: $0.isScreenshot,
                pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight
            )
        }
        let coordinate = sorted.compactMap(\.coordinate).first
        return await installManualTrip(
            assets: assets,
            startDate: startDate,
            endDate: endDate,
            coordinate: coordinate,
            importedPhotos: [],
            generation: generation
        )
    }

    /// Imports picker items directly when PhotoKit identifiers are unavailable
    /// or outside the current Limited-access set. This keeps the manual picker
    /// useful even when the user declines library-wide access.
    @discardableResult
    func loadManualSelection(items: [PhotosPickerItem]) async -> Bool {
        guard !items.isEmpty else { return false }
        let generation = beginManualSelection()
        defer {
            if manualSelectionGeneration == generation {
                isManualSelectionInProgress = false
            }
        }

        let identifiers = items.compactMap(\.itemIdentifier)
        if identifiers.count == items.count {
            let metadata = await photoLibrary.fetchPhotos(withLocalIdentifiers: identifiers)
            guard manualSelectionGeneration == generation, !Task.isCancelled else { return false }
            if Set(metadata.map(\.id)) == Set(identifiers) {
                return await installPhotoKitManualSelection(
                    metadata: metadata,
                    identifiers: identifiers,
                    generation: generation
                )
            }
        }

        let result = await manualPhotoImporter.importItems(items)
        guard manualSelectionGeneration == generation, !Task.isCancelled else {
            await manualPhotoImporter.removeImportedFiles(for: result.photos)
            return false
        }
        invalidateAutomaticScan()

        var seen = Set<String>()
        let imported = result.photos.filter { seen.insert($0.id).inserted }
        guard !imported.isEmpty else {
            isManualSelectionInProgress = false
            libraryErrorMessage = "Memories couldn't import the selected photos. Check your iCloud connection and try again."
            return false
        }

        let assets = imported.map { photo in
            TripAsset(
                id: photo.id,
                source: .imported(photo.filePath),
                creationDate: photo.creationDate,
                filename: photo.filename,
                pixelWidth: photo.pixelWidth,
                pixelHeight: photo.pixelHeight
            )
        }
        let dated = imported.compactMap(\.creationDate)
        let startDate = dated.min() ?? Date()
        let endDate = dated.max() ?? startDate
        if result.failureCount > 0 {
            libraryErrorMessage = "Imported \(imported.count) photos. \(result.failureCount) couldn't be downloaded from Photos; you can try those again when iCloud is available."
        }

        return await installManualTrip(
            assets: assets,
            startDate: startDate,
            endDate: endDate,
            coordinate: imported.compactMap(\.coordinate).first,
            importedPhotos: imported,
            generation: generation
        )
    }

    private func installManualTrip(
        assets: [TripAsset],
        startDate: Date,
        endDate: Date,
        coordinate: PhotoCoordinate?,
        importedPhotos: [ManualImportedPhoto],
        generation: UUID
    ) async -> Bool {
        guard !assets.isEmpty,
              manualSelectionGeneration == generation,
              !Task.isCancelled else {
            if !importedPhotos.isEmpty {
                await manualPhotoImporter.removeImportedFiles(for: importedPhotos)
            }
            return false
        }
        let trip = Trip(
            id: "manual-\(assets[0].id)",
            place: "Selected photos",
            dates: Self.dateText(from: startDate, to: endDate),
            startDate: startDate,
            endDate: endDate,
            assets: assets,
            coverID: assets[assets.count / 2].id
        )

        discardImportedPhotoFiles()
        activeImportedPhotos = importedPhotos
        hasManualSelection = true
        hasPermissionFreeSelection = !importedPhotos.isEmpty
        isManualSelectionInProgress = false
        trips = [trip]
        nearbyEvents = []
        selectedTrip = nil
        photos = []
        selectedPhotoCount = assets.count
        libraryPhotoCount = max(libraryPhotoCount, assets.count)
        libraryPreviewPhotos = Array(Self.makeReelPhotos(from: trip).prefix(6))
        hasScannedLibrary = true
        isScanningLibrary = false
        showTripResults()

        if let coordinate,
           let name = await placeResolver.placeName(for: coordinate),
           manualSelectionGeneration == generation,
           trips.first?.id == trip.id {
            let renamed = trip.renamed(name)
            trips[0] = renamed
            if selectedTrip?.id == trip.id { selectedTrip = renamed }
        }
        return true
    }

    func showTripResults() {
        go(trips.isEmpty && nearbyEvents.isEmpty ? .empty : .trips)
    }

    func startBuild(trip: Trip) {
        guard !trip.assets.isEmpty else { return }
        let isNearbyTrip = nearbyEvents.contains(where: { $0.id == trip.id })
        selectedTrip = trip
        photoEditOverrides = [:]
        photos = Self.makeReelPhotos(from: trip, insights: activePhotoInsights)
        let localTitlePlan = LocalStoryIntelligence.makeTitlePlan(
            for: trip,
            photos: photos,
            insights: activePhotoInsights,
            isNearby: isNearbyTrip
        )
        titleDrafts = localTitlePlan.drafts
        titleCards = localTitlePlan.enabledCards
        textOverlays = []
        exportHandoff = .normal
        pendingExportIntent = nil
        exportedVideoURL = nil
        exportErrorMessage = nil
        exportSaveMessage = nil
        workTask?.cancel()
        buildCount = 0
        currentPhotoIndex = 0
        cutPhotoIDs = []
        history = []
        cleanupSelection = []
        selectedCutSource = .firstCut
        selectedAICutPhotoIDs = []
        aiCutStoryContext = ""
        aiCutConsentGranted = false
        aiCutSnapshot = nil
        aiCutSummary = nil
        aiCutRecommendations = []
        aiCutDiagnosis = nil
        aiCutComparison = nil
        aiCutFailureMessage = nil
        aiCutProgress = 0
        aiVideoGenerationID = UUID()
        aiVideoTask?.cancel()
        aiVideoTask = nil
        aiVideoSelectedPhotoIDs = []
        aiVideoRecommendedPhotoIDs = []
        aiVideoRecommendationIsVisionBased = false
        aiVideoProgress = 0
        aiVideoFailureMessage = nil
        aiVideoSaveMessage = nil
        if let aiVideoURL {
            try? FileManager.default.removeItem(at: aiVideoURL)
            self.aiVideoURL = nil
        }
        firstCutSnapshot = makeCurrentEditSnapshot()
        go(.building)

        let total = photos.count
        let steps = min(30, max(1, total))
        workTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                let currentTotal = self.photos.count
                self.buildCount = min(currentTotal, Int(ceil(Double(total * step) / Double(steps))))
            }
            self.buildCount = self.photos.count
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            self.go(.firstWatch)
        }
    }

    func startBuild() {
        guard let trip = selectedTrip ?? trips.first else { return }
        startBuild(trip: trip)
    }

    func decideCurrentPhoto(cut: Bool) {
        guard !photos.isEmpty else { return }
        decidePhoto(id: currentPhoto.id, cut: cut)
    }

    func decidePhoto(id: String, cut: Bool) {
        guard let photoIndex = photos.firstIndex(where: { $0.id == id }) else { return }

        history.append(
            PhotoDecision(
                id: id,
                previousIndex: currentPhotoIndex,
                previousWasCut: cutPhotoIDs.contains(id)
            )
        )

        if cut {
            cutPhotoIDs.insert(id)
        } else {
            cutPhotoIDs.remove(id)
        }

        if photoIndex >= photos.count - 1 {
            finishPhotoSelection()
        } else {
            currentPhotoIndex = photoIndex + 1
        }
    }

    func undoLastDecision() {
        guard let last = history.popLast() else { return }
        if last.previousWasCut {
            cutPhotoIDs.insert(last.id)
        } else {
            cutPhotoIDs.remove(last.id)
        }
        currentPhotoIndex = last.previousIndex
    }

    func editPhotoSelection() {
        currentPhotoIndex = 0
        history.removeAll()
        go(.cut, direction: .forward)
    }

    func finishPhotoSelection() {
        history.removeAll()
        currentPhotoIndex = min(currentPhotoIndex, max(0, photos.count - 1))
        go(.secondWatch, direction: .backward)
    }

    /// Reorders only the kept-photo slots, leaving cut photos where they are
    /// for the cleanup flow. This keeps timeline edits reversible and avoids
    /// changing which images belong to the film.
    func moveKeptPhoto(id: String, before targetID: String) {
        guard id != targetID else { return }
        var reordered = keptPhotos
        guard let sourceIndex = reordered.firstIndex(where: { $0.id == id }),
              let targetIndex = reordered.firstIndex(where: { $0.id == targetID }) else { return }
        let moving = reordered.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        reordered.insert(moving, at: adjustedTarget)

        var nextKeptIndex = 0
        for index in photos.indices where !cutPhotoIDs.contains(photos[index].id) {
            photos[index] = reordered[nextKeptIndex]
            nextKeptIndex += 1
        }
        selectedCutSource = .working
    }

    func selectTrack(_ track: MusicTrack) {
        if track.id == "none" {
            selectedTrackID = nil
            cutToBeat = false
        } else {
            selectedTrackID = track.id
        }
    }

    func setFrameStyle(_ frameStyle: MontageFrameStyle, forPhotoID id: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].frameStyle = frameStyle
        photos[index].hasCustomFrameStyle = true
        var edit = photoEditOverrides[id] ?? PhotoEditOverride()
        edit.frameStyle = frameStyle
        photoEditOverrides[id] = edit
    }

    func setMotionStyle(_ motionStyle: MontageMotionStyle, forPhotoID id: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].motionStyle = motionStyle
        var edit = photoEditOverrides[id] ?? PhotoEditOverride()
        edit.motionStyle = motionStyle
        photoEditOverrides[id] = edit
    }

    func setPhotoCrop(
        scale: Double,
        offsetX: Double,
        offsetY: Double,
        forPhotoID id: String
    ) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let scale = min(max(scale, 1), 3)
        let offsetX = min(max(offsetX, -1), 1)
        let offsetY = min(max(offsetY, -1), 1)
        photos[index].cropScale = scale
        photos[index].cropOffsetX = offsetX
        photos[index].cropOffsetY = offsetY
        var edit = photoEditOverrides[id] ?? PhotoEditOverride()
        edit.cropScale = scale
        edit.cropOffsetX = offsetX
        edit.cropOffsetY = offsetY
        photoEditOverrides[id] = edit
    }

    func setPhotoDuration(_ duration: Double, forPhotoID id: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let duration = min(max(duration, 0.6), 4)
        photos[index].durationSeconds = duration
        var edit = photoEditOverrides[id] ?? PhotoEditOverride()
        edit.durationSeconds = duration
        photoEditOverrides[id] = edit
    }

    func resetPhotoEdit(id: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photoEditOverrides[id] = nil
        photos[index].frameStyle = photos[index].automaticFrameStyle
        photos[index].hasCustomFrameStyle = false
        photos[index].motionStyle = photos[index].automaticMotionStyle
        photos[index].cropScale = photos[index].automaticCropScale
        photos[index].cropOffsetX = photos[index].automaticCropOffsetX
        photos[index].cropOffsetY = photos[index].automaticCropOffsetY
        photos[index].durationSeconds = nil
    }

    func requestExport(_ intent: ExportIntent, isPremium: Bool) {
        let requirement = ExportAccessPolicy.premiumRequirement(
            photoCount: keptCount,
            durationSeconds: filmDurationSeconds,
            quality: intent.quality
        )

        guard isPremium || requirement == nil else {
            pendingExportIntent = intent
            go(.paywall, direction: .forward)
            return
        }

        pendingExportIntent = nil
        startRender(hd: intent.quality == .hd, handoff: intent.handoff)
    }

    var pendingExportPremiumRequirement: ExportPremiumRequirement {
        ExportAccessPolicy.premiumRequirement(
            photoCount: keptCount,
            durationSeconds: filmDurationSeconds,
            quality: (pendingExportIntent ?? .highDefinition).quality
        ) ?? ExportPremiumRequirement(
            photoCount: keptCount,
            durationSeconds: filmDurationSeconds,
            freePhotoLimit: ExportAccessPolicy.freePhotoLimit,
            freeDurationLimit: ExportAccessPolicy.freeDurationLimit,
            requiresHighDefinition: true
        )
    }

    func resumePendingExportAfterPurchase() {
        let intent = pendingExportIntent ?? .highDefinition
        pendingExportIntent = nil
        startRender(hd: intent.quality == .hd, handoff: intent.handoff)
    }

    func keepEditingInsteadOfUpgrading() {
        pendingExportIntent = nil
        go(.export, direction: .backward)
    }

    func startRender(hd: Bool = false) {
        startRender(hd: hd, handoff: .normal)
    }

    func startCapCutRender() {
        startRender(hd: false, handoff: .capCut)
    }

    private func startRender(hd: Bool, handoff: ExportHandoff) {
        workTask?.cancel()
        let generation = UUID()
        exportGeneration = generation
        exportQuality = hd ? .hd : .standard
        exportHandoff = handoff
        renderProgress = 0
        exportErrorMessage = nil
        exportErrorTitle = "Export couldn't finish"
        exportCanRetryPhotoDownload = false
        exportProgressPhase = .preparingPhotos(
            ready: 0,
            total: keptPhotos.count,
            currentLabel: keptPhotos.first?.label,
            downloadProgress: nil
        )
        exportSaveMessage = nil
        go(.rendering)

        if usesDemoData {
            exportProgressPhase = .rendering
            workTask = Task { [weak self] in
                guard let self else { return }
                for step in 1...40 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled, self.exportGeneration == generation else { return }
                    self.renderProgress = Double(step) / 40.0
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled, self.exportGeneration == generation else { return }
                self.go(.done)
            }
            return
        }

        guard !keptPhotos.isEmpty else {
            exportErrorMessage = "Keep at least one photo before exporting."
            go(.export)
            return
        }

        let request = TripReelVideoExportRequest(
            photos: keptPhotos,
            titleCards: montageTitleCards,
            textOverlays: textOverlays,
            secondsPerPhoto: secondsPerPhoto,
            look: montageLook,
            motionIntensity: montageMotionIntensity,
            quality: exportQuality,
            soundtrackURL: selectedTrack?.resourceName.flatMap {
                Bundle.main.url(forResource: $0, withExtension: "m4a")
            }
        )
        let exporter = videoExporter
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await exporter.export(request) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.exportGeneration == generation else { return }
                        self.renderProgress = max(self.renderProgress, progress.fraction)
                        self.exportProgressPhase = progress.phase
                    }
                }
                guard !Task.isCancelled, self.exportGeneration == generation else { return }
                self.exportedVideoURL = url
                self.renderProgress = 1
                self.go(.done)
            } catch is CancellationError {
                return
            } catch {
                guard self.exportGeneration == generation else { return }
                if let exportError = error as? TripReelVideoExportError,
                   case .photoUnavailable = exportError {
                    self.exportErrorTitle = "A photo needs a little longer"
                    self.exportCanRetryPhotoDownload = true
                } else {
                    self.exportErrorTitle = "Export couldn't finish"
                    self.exportCanRetryPhotoDownload = false
                }
                self.exportErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Memories couldn't finish this export. Please try again."
                self.go(.export)
            }
        }
    }

    func cancelRender() {
        exportGeneration = UUID()
        workTask?.cancel()
        workTask = nil
        renderProgress = 0
        go(.export, direction: .backward)
    }

    func retryExportPhotoDownload() {
        guard exportCanRetryPhotoDownload else { return }
        let shouldUseHD = exportQuality == .hd
        let handoff = exportHandoff
        dismissExportMessage()
        startRender(hd: shouldUseHD, handoff: handoff)
    }

    @discardableResult
    func saveExportToPhotos() async -> Bool {
        guard let exportedVideoURL, !isSavingExport else { return false }
        isSavingExport = true
        exportSaveMessage = nil
        defer { isSavingExport = false }
        do {
            try await videoExporter.saveToPhotoLibrary(exportedVideoURL)
            exportSaveMessage = "Saved to Photos"
            return true
        } catch {
            exportErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Memories couldn't save this film to Photos."
            return false
        }
    }

    func dismissExportMessage() {
        exportErrorMessage = nil
        exportErrorTitle = "Export couldn't finish"
        exportCanRetryPhotoDownload = false
        exportSaveMessage = nil
    }

    func restart() {
        cleanupSelection = []
        cleanupShowsGrid = false
        cleanupDeletionErrorMessage = nil
        showCutHint = true
        go(.trips)
    }

    func toggleCleanupPhotoSelection(_ photoID: String) {
        guard !isDeletingPhotos, cleanupCandidatePhotoIDs.contains(photoID) else { return }
        if cleanupSelection.contains(photoID) {
            cleanupSelection.remove(photoID)
        } else {
            cleanupSelection.insert(photoID)
        }
    }

    func selectAllCleanupPhotos() {
        guard !isDeletingPhotos else { return }
        cleanupSelection = cleanupCandidatePhotoIDs
    }

    func clearCleanupSelection() {
        guard !isDeletingPhotos else { return }
        cleanupSelection.removeAll()
    }

    /// Deletes only explicitly selected, already-cut PhotoKit assets. Imported
    /// picker files and bundled demo art can never reach the Photos delete API.
    @discardableResult
    func deleteCleanupSelection() async -> Int? {
        guard !isDeletingPhotos, !cleanupSelection.isEmpty else { return nil }
        cleanupDeletionErrorMessage = nil

        let selectedPhotos = photos.filter { cleanupSelection.contains($0.id) }
        let libraryPairs = selectedPhotos.compactMap { photo -> (photoID: String, assetID: String)? in
            guard case let .library(identifier) = photo.source else { return nil }
            return (photo.id, identifier)
        }
        guard libraryPairs.count == cleanupSelection.count,
              libraryPairs.allSatisfy({ cutPhotoIDs.contains($0.photoID) }) else {
            cleanupDeletionErrorMessage = "Only cut photos from your Apple Photos library can be deleted. Nothing was deleted."
            return nil
        }

        isDeletingPhotos = true
        defer { isDeletingPhotos = false }
        do {
            let count = try await photoLibrary.deletePhotos(
                withLocalIdentifiers: libraryPairs.map(\.assetID)
            )
            let deletedPhotoIDs = Set(libraryPairs.map(\.photoID))
            let deletedAssetIDs = Set(libraryPairs.map(\.assetID))
            applySuccessfulDeletion(
                photoIDs: deletedPhotoIDs,
                libraryAssetIDs: deletedAssetIDs
            )
            return count
        } catch {
            cleanupDeletionErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Apple Photos couldn't delete these photos. Nothing was deleted."
            return nil
        }
    }

    private func applySuccessfulDeletion(
        photoIDs: Set<String>,
        libraryAssetIDs: Set<String>
    ) {
        photos.removeAll { photoIDs.contains($0.id) }
        for id in photoIDs { photoEditOverrides[id] = nil }
        cutPhotoIDs.subtract(photoIDs)
        cleanupSelection.subtract(photoIDs)
        history.removeAll { photoIDs.contains($0.id) }
        excludedPhotos.removeAll { photoIDs.contains($0.id) }
        manuallyIncludedPhotoIDs.subtract(photoIDs)
        activePhotoInsights = activePhotoInsights.filter { !photoIDs.contains($0.key) }
        libraryPreviewPhotos.removeAll { photo in
            if case let .library(identifier) = photo.source {
                return libraryAssetIDs.contains(identifier)
            }
            return false
        }

        let retainedIDs: (Trip) -> Set<String> = { trip in
            Set(trip.assets.compactMap { asset in
                if case let .library(identifier) = asset.source,
                   libraryAssetIDs.contains(identifier) { return nil }
                return asset.id
            })
        }
        trips = trips.compactMap { $0.retainingAssets(withIDs: retainedIDs($0)) }
        nearbyEvents = nearbyEvents.compactMap { $0.retainingAssets(withIDs: retainedIDs($0)) }
        if let selectedTrip {
            self.selectedTrip = selectedTrip.retainingAssets(withIDs: retainedIDs(selectedTrip))
        }
        currentPhotoIndex = min(currentPhotoIndex, max(0, photos.count - 1))
        buildCount = min(buildCount, photos.count)
        libraryPhotoCount = max(0, libraryPhotoCount - libraryAssetIDs.count)
        selectedPhotoCount = max(0, selectedPhotoCount - libraryAssetIDs.count)
    }

    private func resolveTripNames(generation: UUID) async {
        let tripIDs = trips.map(\.id) + nearbyEvents.map(\.id)
        for tripID in tripIDs {
            guard !Task.isCancelled, scanGeneration == generation else { return }
            let isNearby = nearbyEvents.contains(where: { $0.id == tripID })
            guard trips.contains(where: { $0.id == tripID }) || isNearby else { continue }
            guard let detectedCoordinate = resolvedCoordinates[tripID] else { continue }
            guard let name = await placeResolver.placeName(
                for: detectedCoordinate,
                style: isNearby ? .nearby : .destination
            ) else { continue }
            guard !Task.isCancelled, scanGeneration == generation else { return }
            if let currentIndex = trips.firstIndex(where: { $0.id == tripID }) {
                let renamed = trips[currentIndex].renamed(name)
                trips[currentIndex] = renamed
                if selectedTrip?.id == tripID { selectedTrip = renamed }
            } else if let currentIndex = nearbyEvents.firstIndex(where: { $0.id == tripID }) {
                let renamed = nearbyEvents[currentIndex].renamed(name)
                nearbyEvents[currentIndex] = renamed
                if selectedTrip?.id == tripID { selectedTrip = renamed }
            }
        }
    }

    func clearLibraryState(afterAuthorizationChangedTo status: PHAuthorizationStatus) {
        cancelPhotoAnalysis()
        aiCutGeneration = UUID()
        aiCutTask?.cancel()
        aiCutTask = nil
        aiCutSnapshot = nil
        firstCutSnapshot = nil
        aiCutSummary = nil
        aiCutRecommendations = []
        aiCutDiagnosis = nil
        aiCutComparison = nil
        aiCutFailureMessage = nil
        aiCutProgress = 0
        selectedAICutPhotoIDs = []
        aiCutStoryContext = ""
        aiCutConsentGranted = false
        aiVideoGenerationID = UUID()
        aiVideoTask?.cancel()
        aiVideoTask = nil
        aiVideoSelectedPhotoIDs = []
        aiVideoRecommendedPhotoIDs = []
        aiVideoRecommendationIsVisionBased = false
        aiVideoFailureMessage = nil
        aiVideoProgress = 0
        aiVideoSaveMessage = nil
        if let aiVideoURL {
            try? FileManager.default.removeItem(at: aiVideoURL)
            self.aiVideoURL = nil
        }
        pendingBuildTrip = nil
        activeAnalysisTrip = nil
        photoAnalysisFollowUp = nil
        manuallyIncludedPhotoIDs = []
        isCloudAnalysisConsentPresented = false
        cloudConsentIsSettings = false
        isSmartSelectionReviewPresented = false
        excludedPhotos = []
        scanGeneration = UUID()
        pendingResultNavigation = false
        scanAgainRequested = false
        detectorTask?.cancel()
        detectorTask = nil
        placeTask?.cancel()
        lastAuthorizationStatus = status
        hasScannedLibrary = false
        hasManualSelection = false
        hasPermissionFreeSelection = false
        isScanningLibrary = false
        trips = []
        nearbyEvents = []
        selectedTrip = nil
        photos = []
        libraryPreviewPhotos = []
        libraryPhotoCount = 0
        selectedPhotoCount = 0
        resolvedCoordinates = [:]
        activePhotoInsights = [:]
        cloudBlockedPhotoIDs = []
        photoEditOverrides = [:]
        cutPhotoIDs = []
        history = []
        cleanupSelection = []
        cleanupDeletionErrorMessage = nil
        isDeletingPhotos = false

        if screen != .welcome && screen != .access {
            go(.access)
        }
    }

    @discardableResult
    private func beginManualSelection() -> UUID {
        let generation = UUID()
        manualSelectionGeneration = generation
        isManualSelectionInProgress = true
        invalidateAutomaticScan()
        libraryErrorMessage = nil
        return generation
    }

    private func invalidateAutomaticScan() {
        scanGeneration = UUID()
        pendingResultNavigation = false
        scanAgainRequested = false
        detectorTask?.cancel()
        detectorTask = nil
        placeTask?.cancel()
        isScanningLibrary = false
    }

    private func discardImportedPhotoFiles() {
        guard !activeImportedPhotos.isEmpty else { return }
        let discarded = activeImportedPhotos
        activeImportedPhotos = []
        Task { [manualPhotoImporter] in
            await manualPhotoImporter.removeImportedFiles(for: discarded)
        }
    }

    private func reconcilePhotoKitManualSelection() async {
        guard hasManualSelection,
              !hasPermissionFreeSelection,
              !isManualSelectionInProgress,
              let manualTrip = trips.first else { return }

        let status = photoLibrary.authorizationStatus
        guard status == .authorized || status == .limited else {
            clearLibraryState(afterAuthorizationChangedTo: status)
            return
        }

        let generation = manualSelectionGeneration
        let identifiers = manualTrip.assets.compactMap { asset -> String? in
            if case let .library(identifier) = asset.source { return identifier }
            return nil
        }
        guard !identifiers.isEmpty else { return }

        let availableMetadata = await photoLibrary.fetchPhotos(withLocalIdentifiers: identifiers)
        guard manualSelectionGeneration == generation,
              hasManualSelection,
              !Task.isCancelled else { return }

        let availableIDs = Set(availableMetadata.map(\.id))
        guard availableIDs.count != Set(identifiers).count else { return }
        let removedCount = Set(identifiers).subtracting(availableIDs).count
        let retainedTrip = manualTrip.retainingAssets(withIDs: availableIDs)

        trips = retainedTrip.map { [$0] } ?? []
        selectedPhotoCount = retainedTrip?.photoCount ?? 0
        libraryPreviewPhotos = retainedTrip.map {
            Array(Self.makeReelPhotos(from: $0).prefix(6))
        } ?? []
        if selectedTrip?.id == manualTrip.id {
            selectedTrip = retainedTrip
        }
        libraryErrorMessage = "\(removedCount) selected photo\(removedCount == 1 ? " is" : "s are") no longer available and \(removedCount == 1 ? "was" : "were") removed."
        reconcileActiveFilm(withAvailableLibraryIDs: availableIDs)

        if retainedTrip == nil {
            hasManualSelection = false
            hasScannedLibrary = false
            if photos.isEmpty {
                go(.empty)
            }
        }
    }

    private func reconcileActiveFilm(withAvailableLibraryIDs availableIDs: Set<String>) {
        guard !photos.isEmpty else { return }

        let retainedPhotoIDs = Set(photos.compactMap { photo -> String? in
            switch photo.source {
            case .bundled:
                return photo.id
            case let .library(identifier):
                return availableIDs.contains(identifier) ? photo.id : nil
            case .imported:
                return photo.id
            }
        })
        guard retainedPhotoIDs.count != photos.count else { return }

        photos.removeAll { !retainedPhotoIDs.contains($0.id) }
        cutPhotoIDs.formIntersection(retainedPhotoIDs)
        cleanupSelection.formIntersection(retainedPhotoIDs)
        history.removeAll { !retainedPhotoIDs.contains($0.id) }
        currentPhotoIndex = min(currentPhotoIndex, max(0, photos.count - 1))
        buildCount = min(buildCount, photos.count)
        selectedTrip = selectedTrip?.retainingAssets(withIDs: retainedPhotoIDs)

        guard !photos.isEmpty else {
            workTask?.cancel()
            selectedTrip = nil
            go(trips.isEmpty ? .empty : .trips)
            return
        }

        libraryErrorMessage = "Some photos in this film are no longer available, so Memories removed those frames."
    }

    private static func makeTrip(from detected: DetectedTrip) -> Trip {
        let assets = detected.photos.map {
            TripAsset(
                id: $0.id,
                source: .library($0.id),
                creationDate: $0.creationDate,
                filename: $0.filename,
                isScreenshot: $0.isScreenshot,
                pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight
            )
        }
        let fallbackPlace = detected.centroid == nil
            ? "Photo memory"
            : "Travel · \(monthYearFormatter.string(from: detected.startDate))"
        return Trip(
            id: detected.id,
            place: fallbackPlace,
            dates: dateText(from: detected.startDate, to: detected.endDate),
            startDate: detected.startDate,
            endDate: detected.endDate,
            assets: assets,
            coverID: detected.coverID
        )
    }

    private static func makeNearbyEvent(from detected: DetectedTrip) -> Trip {
        let trip = makeTrip(from: detected)
        return trip.renamed("Local memory")
    }

    private static func makePreviewPhotos(from metadata: [PhotoMetadata]) -> [ReelPhoto] {
        let assets = metadata.suffix(6).map {
            TripAsset(
                id: $0.id,
                source: .library($0.id),
                creationDate: $0.creationDate,
                filename: $0.filename,
                isScreenshot: $0.isScreenshot,
                pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight
            )
        }
        return makeReelPhotos(
            from: Trip(
                id: "library-preview",
                place: "Library",
                dates: "",
                startDate: Date(),
                endDate: Date(),
                assets: assets,
                coverID: assets.first?.id ?? ""
            )
        )
    }

    private static func makeReelPhotos(
        from trip: Trip,
        insights: [String: MontagePhotoInsight] = [:]
    ) -> [ReelPhoto] {
        MontageSequencePlanner.plan(assets: trip.assets, insights: insights)
            .enumerated().map { index, item in
            let asset = item.asset
            let fallbackLabel = "PHOTO_\(String(format: "%04d", index + 1))"
            let label = asset.filename.isEmpty ? fallbackLabel : asset.filename
            return ReelPhoto(
                id: asset.id,
                source: asset.source,
                label: label,
                time: asset.creationDate.map(timeFormatter.string) ?? "—",
                isSimilar: item.isSimilar || {
                    if case .bundled = asset.source { return index % 4 == 1 }
                    return false
                }(),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                protectsPeople: item.protectsPeople,
                frameStyle: item.frameStyle,
                motionStyle: item.motionStyle,
                cropScale: item.cropScale,
                cropOffsetX: item.cropOffsetX,
                cropOffsetY: item.cropOffsetY
            )
        }
    }

    private func applyingPhotoEdits(to source: [ReelPhoto]) -> [ReelPhoto] {
        source.map { photo in
            guard let edit = photoEditOverrides[photo.id] else { return photo }
            var edited = photo
            edited.frameStyle = edit.frameStyle ?? photo.automaticFrameStyle
            edited.hasCustomFrameStyle = edit.frameStyle != nil
            edited.motionStyle = edit.motionStyle ?? photo.automaticMotionStyle
            edited.cropScale = edit.cropScale ?? photo.automaticCropScale
            edited.cropOffsetX = edit.cropOffsetX ?? photo.automaticCropOffsetX
            edited.cropOffsetY = edit.cropOffsetY ?? photo.automaticCropOffsetY
            edited.durationSeconds = edit.durationSeconds
            return edited
        }
    }

    private static func makeDemoTrips() -> [Trip] {
        [
            makeDemoTrip(id: "da-nang", place: "Da Nang, Vietnam", dates: "Aug 2 – Aug 9, 2026", count: 84, start: date(2026, 8, 2), end: date(2026, 8, 9), coverName: "my-khe-beach"),
            makeDemoTrip(id: "kyoto", place: "Kyoto, Japan", dates: "Apr 11 – Apr 18, 2026", count: 212, start: date(2026, 4, 11), end: date(2026, 4, 18), coverName: "hoi-an-lanes"),
            makeDemoTrip(id: "lisbon", place: "Lisbon, Portugal", dates: "Nov 3 – Nov 8, 2025", count: 96, start: date(2025, 11, 3), end: date(2025, 11, 8), coverName: "night-market"),
            makeDemoTrip(id: "big-sur", place: "Big Sur, California", dates: "Jun 21 – Jun 23, 2025", count: 41, start: date(2025, 6, 21), end: date(2025, 6, 23), coverName: "han-river")
        ]
    }

    private static func makeDemoTrip(
        id: String,
        place: String,
        dates: String,
        count: Int,
        start: Date,
        end: Date,
        coverName: String
    ) -> Trip {
        let duration = end.timeIntervalSince(start)
        let assets = (0..<count).map { index in
            let imageName = assetNames[index % assetNames.count]
            let progress = count <= 1 ? 0 : Double(index) / Double(count - 1)
            return TripAsset(
                id: "demo-\(id)-\(index)",
                source: .bundled(imageName),
                creationDate: start.addingTimeInterval(duration * progress),
                filename: "IMG_\(2140 + index)",
                pixelWidth: 1_024,
                pixelHeight: 1_536
            )
        }
        let coverID = assets.first(where: {
            if case let .bundled(name) = $0.source { return name == coverName }
            return false
        })?.id ?? assets[0].id
        return Trip(
            id: "demo-\(id)",
            place: place,
            dates: dates,
            startDate: start,
            endDate: end,
            assets: assets,
            coverID: coverID
        )
    }

    private static func durationText(seconds: Double) -> String {
        let seconds = max(1, Int(seconds.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private static func dateText(from startDate: Date, to endDate: Date) -> String {
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return singleDateFormatter.string(from: startDate)
        }
        return intervalFormatter.string(from: startDate, to: endDate)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 8))!
    }

    private static let placeholderPhoto = ReelPhoto(
        id: "placeholder",
        source: .bundled("my-khe-beach"),
        label: "PHOTO",
        time: "—",
        isSimilar: false,
        pixelWidth: 1_024,
        pixelHeight: 1_536,
        frameStyle: .portraitMatte,
        motionStyle: .rise
    )

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return formatter
    }()

    private static let singleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        return formatter
    }()

    private static let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
