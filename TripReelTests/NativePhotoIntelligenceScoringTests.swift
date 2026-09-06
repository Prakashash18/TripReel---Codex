import Foundation
import XCTest
@testable import TripReel

final class NativePhotoIntelligenceScoringTests: XCTestCase {
    func testFocalPointPrefersTheUnionOfFacesOverGenericSaliency() throws {
        let focalPoint = try XCTUnwrap(
            NativePhotoFocalPointResolver.resolve(
                faceBoxes: [
                    CGRect(x: 0.12, y: 0.48, width: 0.16, height: 0.24),
                    CGRect(x: 0.64, y: 0.42, width: 0.20, height: 0.28)
                ],
                salientBoxes: [CGRect(x: 0.40, y: 0.05, width: 0.12, height: 0.12)]
            )
        )

        XCTAssertEqual(focalPoint.source, .faces)
        XCTAssertEqual(focalPoint.x, 0.48, accuracy: 0.001)
        XCTAssertEqual(focalPoint.y, 0.57, accuracy: 0.001)
        XCTAssertEqual(focalPoint.coverage, 0.72 * 0.30, accuracy: 0.001)
    }

    func testFocalPointUsesLargestSalientRegionWhenNoFaceExists() throws {
        let focalPoint = try XCTUnwrap(
            NativePhotoFocalPointResolver.resolve(
                faceBoxes: [],
                salientBoxes: [
                    CGRect(x: 0.08, y: 0.08, width: 0.12, height: 0.12),
                    CGRect(x: 0.55, y: 0.52, width: 0.30, height: 0.32)
                ]
            )
        )

        XCTAssertEqual(focalPoint.source, .saliency)
        XCTAssertEqual(focalPoint.x, 0.70, accuracy: 0.001)
        XCTAssertEqual(focalPoint.y, 0.68, accuracy: 0.001)
        XCTAssertEqual(focalPoint.coverage, 0.096, accuracy: 0.001)
    }

    func testFocalPointUsesWholePeopleBoundsInsteadOfCroppingAroundFaces() throws {
        let focalPoint = try XCTUnwrap(
            NativePhotoFocalPointResolver.resolve(
                faceBoxes: [CGRect(x: 0.18, y: 0.62, width: 0.10, height: 0.12)],
                salientBoxes: [CGRect(x: 0.70, y: 0.70, width: 0.10, height: 0.10)],
                humanBoxes: [
                    CGRect(x: 0.08, y: 0.10, width: 0.30, height: 0.72),
                    CGRect(x: 0.58, y: 0.08, width: 0.30, height: 0.74)
                ]
            )
        )

        XCTAssertEqual(focalPoint.source, .people)
        XCTAssertEqual(focalPoint.x, 0.48, accuracy: 0.001)
        XCTAssertEqual(focalPoint.y, 0.45, accuracy: 0.001)
        XCTAssertEqual(focalPoint.coverage, 0.80 * 0.74, accuracy: 0.001)
    }

    func testHumanRectanglesProtectGroupWhenFacesAreTurnedAway() {
        let signals = NativePhotoIntelligenceSignals(
            faces: .init(count: 0),
            humans: .init(count: 3),
            availability: .init(aesthetics: false)
        )

        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)

        XCTAssertTrue(assessment.tags.contains(.people))
        XCTAssertTrue(assessment.tags.contains(.groupPhoto))
        XCTAssertGreaterThan(assessment.scores.peopleScore, 0.85)
    }

    func testAppealingGroupPhotoRanksAsStrongMemoryWithoutCloudReview() {
        let signals = NativePhotoIntelligenceSignals(
            classifications: [
                NativePhotoClassification(identifier: "outdoor landscape", confidence: 0.88)
            ],
            faces: NativePhotoFaceSignal(
                count: 4,
                averageCaptureQuality: 0.84,
                bestCaptureQuality: 0.94
            ),
            aesthetics: NativePhotoAestheticsSignal(overallScore: 0.62, isUtility: false),
            availability: .init(featurePrint: true, aesthetics: true)
        )

        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)

        XCTAssertGreaterThan(assessment.scores.memoryScore, 0.80)
        XCTAssertLessThan(assessment.scores.utilityProbability, 0.20)
        XCTAssertEqual(assessment.cloudReviewGate.disposition, .unnecessary)
        XCTAssertEqual(assessment.cloudReviewGate.reason, .highMemoryConfidence)
        XCTAssertTrue(assessment.tags.contains(.groupPhoto))
        XCTAssertTrue(assessment.tags.contains(.scenery))
        XCTAssertTrue(assessment.tags.contains(.strongMemory))
    }

    func testScreenshotMetadataOverridesOtherwiseAttractivePixels() {
        let signals = NativePhotoIntelligenceSignals(
            isScreenshot: true,
            classifications: [
                NativePhotoClassification(identifier: "beach sunset", confidence: 0.95)
            ],
            text: NativePhotoTextSignal(
                lineCount: 18,
                characterCount: 520,
                coverage: 0.31,
                averageConfidence: 0.91
            ),
            aesthetics: NativePhotoAestheticsSignal(overallScore: 0.80, isUtility: false),
            availability: .init(aesthetics: true)
        )

        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)

        XCTAssertEqual(assessment.scores.utilityProbability, 1, accuracy: 0.000_1)
        XCTAssertLessThanOrEqual(assessment.scores.memoryScore, 0.06)
        XCTAssertEqual(assessment.cloudReviewGate.disposition, .blockedSensitiveContent)
        XCTAssertEqual(assessment.cloudReviewGate.reason, .screenshot)
        XCTAssertTrue(assessment.tags.contains(.screenshot))
        XCTAssertTrue(assessment.tags.contains(.utility))
    }

    func testPhotographedOrderIsRecognizedAsSensitiveDocument() {
        let signals = NativePhotoIntelligenceSignals(
            classifications: [
                NativePhotoClassification(identifier: "menu document", confidence: 0.87)
            ],
            text: NativePhotoTextSignal(
                lineCount: 28,
                characterCount: 1_100,
                coverage: 0.38,
                averageConfidence: 0.89
            ),
            document: NativePhotoDocumentSignal(
                detected: true,
                confidence: 0.93,
                coverage: 0.78
            )
        )

        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)

        XCTAssertGreaterThan(assessment.scores.documentProbability, 0.75)
        XCTAssertGreaterThan(assessment.scores.utilityProbability, 0.70)
        XCTAssertLessThan(assessment.scores.memoryScore, 0.25)
        XCTAssertEqual(assessment.cloudReviewGate.disposition, .blockedSensitiveContent)
        XCTAssertEqual(assessment.cloudReviewGate.reason, .documentOrTextHeavy)
        XCTAssertTrue(assessment.tags.contains(.likelyDocument))
        XCTAssertTrue(assessment.tags.contains(.textHeavy))
    }

    func testScenicPhotoWithDocumentInFrameStaysInFilm() {
        let signals = NativePhotoIntelligenceSignals(
            classifications: [
                NativePhotoClassification(identifier: "outdoor landscape", confidence: 0.91),
                NativePhotoClassification(identifier: "document sign", confidence: 0.88)
            ],
            text: NativePhotoTextSignal(
                lineCount: 24,
                characterCount: 900,
                coverage: 0.34,
                averageConfidence: 0.90
            ),
            document: NativePhotoDocumentSignal(
                detected: true,
                confidence: 0.95,
                coverage: 0.72
            )
        )
        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)
        let result = NativePhotoIntelligenceResult(
            sourceIdentifier: "landmark-sign",
            analyzedPixelWidth: 512,
            analyzedPixelHeight: 384,
            signals: signals,
            scores: assessment.scores,
            tags: assessment.tags,
            cloudReviewGate: assessment.cloudReviewGate
        )
        let asset = TripAsset(
            id: "landmark-sign",
            source: .library("landmark-sign"),
            creationDate: Date(),
            filename: "IMG_1234.HEIC"
        )

        XCTAssertTrue(result.tags.contains(.scenery))
        XCTAssertNil(SmartPhotoSelectionPolicy.nativeDecision(for: asset, result: result))
    }

    func testUnclearPhotoRequiresExplicitConsentBeforeCloudEligibility() {
        let signals = NativePhotoIntelligenceSignals()

        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)

        XCTAssertEqual(assessment.cloudReviewGate.disposition, .eligibleAfterExplicitConsent)
        XCTAssertEqual(assessment.cloudReviewGate.reason, .ambiguousNativeResult)
        XCTAssertTrue(assessment.tags.contains(.cloudReviewCandidate))
    }

    func testAestheticsUtilityFlagCanResolveNonDocumentUtilityImageLocally() {
        let signals = NativePhotoIntelligenceSignals(
            aesthetics: NativePhotoAestheticsSignal(overallScore: 0, isUtility: true),
            availability: .init(aesthetics: true)
        )

        let assessment = NativePhotoIntelligenceScorer.score(signals: signals)

        XCTAssertGreaterThanOrEqual(assessment.scores.utilityProbability, 0.90)
        XCTAssertEqual(assessment.cloudReviewGate.disposition, .unnecessary)
        XCTAssertEqual(assessment.cloudReviewGate.reason, .highUtilityConfidence)
        XCTAssertTrue(assessment.tags.contains(.utility))
    }

    func testVeryLowAestheticNonMemoryIsKeptOutLocally() {
        let asset = TripAsset(
            id: "accidental",
            source: .library("accidental"),
            creationDate: Date(),
            filename: "IMG_0001.HEIC"
        )
        let signals = NativePhotoIntelligenceSignals(
            aesthetics: NativePhotoAestheticsSignal(overallScore: -0.92, isUtility: false),
            availability: .init(aesthetics: true)
        )
        let scored = NativePhotoIntelligenceScorer.score(signals: signals)
        let result = NativePhotoIntelligenceResult(
            sourceIdentifier: asset.id,
            analyzedPixelWidth: 512,
            analyzedPixelHeight: 384,
            signals: signals,
            scores: scored.scores,
            tags: scored.tags,
            cloudReviewGate: scored.cloudReviewGate
        )

        let decision = SmartPhotoSelectionPolicy.nativeDecision(for: asset, result: result)

        XCTAssertEqual(decision?.reason, .lowQuality)
        XCTAssertEqual(decision?.origin, .onDevice)
    }

    func testMalformedSignalValuesCannotEscapeNormalizedScoreRanges() {
        let signals = NativePhotoIntelligenceSignals(
            classifications: [
                NativePhotoClassification(identifier: "LANDSCAPE", confidence: 3)
            ],
            text: NativePhotoTextSignal(
                lineCount: -1,
                characterCount: -50,
                coverage: .infinity,
                averageConfidence: -.infinity
            ),
            faces: NativePhotoFaceSignal(
                count: 2,
                averageCaptureQuality: 4,
                bestCaptureQuality: 4
            ),
            document: NativePhotoDocumentSignal(
                detected: true,
                confidence: -2,
                coverage: -.infinity
            ),
            aesthetics: NativePhotoAestheticsSignal(overallScore: .nan, isUtility: false),
            availability: .init(aesthetics: true)
        )

        let scores = NativePhotoIntelligenceScorer.score(signals: signals).scores

        XCTAssertTrue((0...1).contains(scores.memoryScore))
        XCTAssertTrue((0...1).contains(scores.utilityProbability))
        XCTAssertTrue((0...1).contains(scores.documentProbability))
        XCTAssertTrue((0...1).contains(scores.peopleScore))
        XCTAssertTrue((0...1).contains(scores.nativeConfidence))
        XCTAssertEqual(scores.aestheticScore, 0)
    }

    func testFeaturePrintDistanceIsValueOnlyAndDeterministic() throws {
        let first = NativePhotoFeaturePrint(
            revision: 2,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: data(for: [Float(0), 1, 2])
        )
        let second = NativePhotoFeaturePrint(
            revision: 2,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: data(for: [Float(0), 4, 6])
        )

        XCTAssertEqual(try first.distance(to: second), 5, accuracy: 0.000_1)
        XCTAssertThrowsError(try first.distance(to: NativePhotoFeaturePrint(
            revision: 1,
            elementTypeRawValue: 1,
            elementCount: 3,
            data: data(for: [Float(0), 1, 2])
        ))) { error in
            XCTAssertEqual(error as? NativePhotoFeaturePrintError, .incompatiblePrints)
        }
    }

    func testConfigurationEnforcesBoundedImageAndOutputSizes() {
        let tooSmall = NativePhotoIntelligenceConfiguration(
            maximumImageDimension: 1,
            maximumClassifications: 0,
            maximumTextObservations: 0
        )
        let tooLarge = NativePhotoIntelligenceConfiguration(
            maximumImageDimension: 20_000,
            maximumClassifications: 1_000,
            maximumTextObservations: 1_000
        )

        XCTAssertEqual(tooSmall.maximumImageDimension, 256)
        XCTAssertEqual(tooSmall.maximumClassifications, 1)
        XCTAssertEqual(tooSmall.maximumTextObservations, 1)
        XCTAssertEqual(tooLarge.maximumImageDimension, 2_048)
        XCTAssertEqual(tooLarge.maximumClassifications, 24)
        XCTAssertEqual(tooLarge.maximumTextObservations, 256)
    }

    private func data(for values: [Float]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }
}
