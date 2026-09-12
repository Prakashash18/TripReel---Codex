import CryptoKit
import Foundation

enum CloudPhotoLocalSelection: String, Codable, Hashable, Sendable {
    case firstCut = "first_cut"
    case morePhotos = "more_photos"
}

enum CloudPhotoOrientation: String, Codable, Hashable, Sendable {
    case portrait
    case landscape
    case square
}

enum CloudPhotoTimeGap: String, Codable, Hashable, Sendable {
    case start
    case burst
    case sameSession = "same_session"
    case sameDay = "same_day"
    case nextDay = "next_day"
    case later
}

enum CloudPhotoScoreBand: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high
}

enum CloudPhotoContentKind: String, Codable, Hashable, Sendable {
    case scenery
    case people
    case food
    case moment
}

enum CloudMediaKind: String, Codable, Hashable, Sendable {
    case photo
    case video
}

enum CloudVideoMotionBand: String, Codable, Hashable, Sendable {
    case still
    case gentle
    case active
}

/// Coarse editorial signals produced on-device. This deliberately contains no
/// timestamps, coordinates, filenames, OCR text, faces, or stable Photos IDs.
struct CloudPhotoEditorialContext: Codable, Hashable, Sendable {
    let captureIndex: Int
    let dayIndex: Int
    let timeGap: CloudPhotoTimeGap
    let orientation: CloudPhotoOrientation
    let contentKind: CloudPhotoContentKind
    let peopleCount: Int
    let memory: CloudPhotoScoreBand
    let aesthetic: CloudPhotoScoreBand
    let similarityGroup: String
    let sceneLabels: [String]
    let mediaKind: CloudMediaKind
    let clipDurationSeconds: Double
    let hasOriginalAudio: Bool
    let videoMotion: CloudVideoMotionBand
}

struct CloudPhotoAnalysisInput: Sendable {
    let id: String
    let jpegData: Data
    let localSelection: CloudPhotoLocalSelection
    let context: CloudPhotoEditorialContext?

    init(
        id: String,
        jpegData: Data,
        localSelection: CloudPhotoLocalSelection = .firstCut,
        context: CloudPhotoEditorialContext? = nil
    ) {
        self.id = id
        self.jpegData = jpegData
        self.localSelection = localSelection
        self.context = context
    }
}

enum CloudFirstCutFrameStyle: String, Codable, Hashable, Sendable {
    case fullBleed = "full_bleed"
    case portraitMatte = "portrait_matte"
    case cinematic
    case postcard
}

enum CloudFirstCutTitleKind: String, Codable, Hashable, Sendable {
    case opening
    case chapter
    case ending
}

struct CloudFirstCutSequenceItem: Codable, Hashable, Sendable {
    let photoID: String
    let order: Int
    let durationSeconds: Double
    let motion: AICutMotion
    let frameStyle: CloudFirstCutFrameStyle

    enum CodingKeys: String, CodingKey {
        case photoID = "photoId"
        case order
        case durationSeconds
        case motion
        case frameStyle
    }
}

struct CloudFirstCutTitle: Codable, Hashable, Sendable {
    let kind: CloudFirstCutTitleKind
    let title: String
    let subtitle: String
    let style: AICutTitleStyle
    let durationSeconds: Double
}

/// A privacy-safe description of the edit already created on-device. The AI
/// can now improve a real baseline instead of independently ranking stills.
struct CloudFirstCutInput: Codable, Hashable, Sendable {
    let photoCount: Int
    let durationSeconds: Double
    let omittedPhotoCount: Int
    let sequence: [CloudFirstCutSequenceItem]
    let titles: [CloudFirstCutTitle]
    let soundtrackID: String
    let look: AICutLook
    let motionIntensity: AICutMotionIntensity

    enum CodingKeys: String, CodingKey {
        case photoCount
        case durationSeconds
        case omittedPhotoCount
        case sequence
        case titles
        case soundtrackID = "soundtrackId"
        case look
        case motionIntensity
    }
}

enum AICutDirection: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case betterStory = "better_story"
    case dynamic
    case calm
    case people
    case surpriseMe = "surprise_me"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .betterStory: "Story Arc"
        case .dynamic: "Fast Highlights"
        case .calm: "Cinematic Calm"
        case .people: "People & Connection"
        case .surpriseMe: "Director's Choice"
        }
    }

    var detail: String {
        switch self {
        case .betterStory: "A clear opening, turning point and satisfying ending."
        case .dynamic: "Quick cuts, energetic motion and punchier music."
        case .calm: "Longer scenic holds, restrained motion and room to breathe."
        case .people: "Build the story around faces, reactions and shared moments."
        case .surpriseMe: "Let the director choose the strongest complete treatment."
        }
    }

    var symbol: String {
        switch self {
        case .betterStory: "point.3.connected.trianglepath.dotted"
        case .dynamic: "bolt.fill"
        case .calm: "water.waves"
        case .people: "person.2.fill"
        case .surpriseMe: "sparkles"
        }
    }
}

enum AICutEditorialRole: String, Codable, CaseIterable, Hashable, Sendable {
    case opening
    case establishing
    case people
    case scenery
    case detail
    case food
    case bridge
    case closing
}

enum AICutEmphasis: String, Codable, CaseIterable, Hashable, Sendable {
    case normal
    case highlight
}

enum AICutMotion: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case panLeft = "pan_left"
    case panRight = "pan_right"
    case rise
    case settle
}

enum AICutTitleStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case editorial
    case clean
    case bold
}

enum AICutSoundtrackID: String, Codable, CaseIterable, Hashable, Sendable {
    case wanderlust
    case simplicity
    case castles
    case longWayHome = "long-way-home"

    var displayName: String {
        switch self {
        case .wanderlust: "Wanderlust"
        case .simplicity: "Simplicity"
        case .castles: "Castles in the Sky"
        case .longWayHome: "The Long Way Home"
        }
    }
}

enum AICutLook: String, Codable, CaseIterable, Hashable, Sendable {
    case story
    case cinema
    case journal
    case clean

    var displayName: String { rawValue.capitalized }
}

enum AICutMotionIntensity: String, Codable, CaseIterable, Hashable, Sendable {
    case still
    case gentle
    case expressive

    var displayName: String { rawValue.capitalized }
}

struct AICutStory: Codable, Hashable, Sendable {
    let title: String
    let arc: String
}

struct AICutTitleCardPlan: Codable, Hashable, Sendable {
    let title: String
    let subtitle: String
    let style: AICutTitleStyle
    let durationSeconds: Double
}

struct AICutEndingPlan: Codable, Hashable, Sendable {
    let enabled: Bool
    let title: String
    let subtitle: String
    let style: AICutTitleStyle
    let durationSeconds: Double
}

struct AICutSoundtrackPlan: Codable, Hashable, Sendable {
    let trackID: AICutSoundtrackID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case reason
    }
}

struct AICutTreatmentPlan: Codable, Hashable, Sendable {
    let look: AICutLook
    let motionIntensity: AICutMotionIntensity
    let reason: String
}

struct AICutPlanItem: Codable, Hashable, Sendable {
    let photoID: String
    let order: Int
    let durationSeconds: Double
    let role: AICutEditorialRole
    let emphasis: AICutEmphasis
    let motion: AICutMotion

    enum CodingKeys: String, CodingKey {
        case photoID = "photoId"
        case order
        case durationSeconds
        case role
        case emphasis
        case motion
    }
}

enum AICutDiagnosisKind: String, Codable, CaseIterable, Hashable, Sendable {
    case weakHook = "weak_hook"
    case flatPacing = "flat_pacing"
    case repetition
    case missingContext = "missing_context"
    case weakEnding = "weak_ending"
    case limitedVariety = "limited_variety"
}

struct AICutDiagnosisIssue: Codable, Hashable, Sendable {
    let kind: AICutDiagnosisKind
    let title: String
    let detail: String
    let evidencePhotoIDs: [String]

    enum CodingKeys: String, CodingKey {
        case kind
        case title
        case detail
        case evidencePhotoIDs = "evidencePhotoIds"
    }
}

struct AICutDiagnosis: Codable, Hashable, Sendable {
    let verdict: String
    let issues: [AICutDiagnosisIssue]
}

/// Computed by TripReel's Worker from the submitted First Cut and returned AI
/// timeline. These figures are never self-reported by the model.
struct AICutComparison: Codable, Hashable, Sendable {
    let firstCutPhotoCount: Int
    let aiCutPhotoCount: Int
    let restoredCount: Int
    let removedCount: Int
    let reorderedCount: Int
    let retimedCount: Int
    let motionChangedCount: Int
    let titleChangedCount: Int
    let soundtrackChanged: Bool
    let treatmentChanged: Bool
    let score: Int
    let materiallyDifferent: Bool
}

struct AICutEditPlan: Codable, Hashable, Sendable {
    let version: Int
    let direction: AICutDirection
    let summary: String
    let story: AICutStory
    let hook: AICutTitleCardPlan
    let ending: AICutEndingPlan
    let soundtrack: AICutSoundtrackPlan
    let treatment: AICutTreatmentPlan
    let sequence: [AICutPlanItem]
    let diagnosis: AICutDiagnosis?
    let comparison: AICutComparison?

    init(
        version: Int,
        direction: AICutDirection,
        summary: String,
        story: AICutStory,
        hook: AICutTitleCardPlan,
        ending: AICutEndingPlan,
        soundtrack: AICutSoundtrackPlan,
        treatment: AICutTreatmentPlan,
        sequence: [AICutPlanItem],
        diagnosis: AICutDiagnosis? = nil,
        comparison: AICutComparison? = nil
    ) {
        self.version = version
        self.direction = direction
        self.summary = summary
        self.story = story
        self.hook = hook
        self.ending = ending
        self.soundtrack = soundtrack
        self.treatment = treatment
        self.sequence = sequence
        self.diagnosis = diagnosis
        self.comparison = comparison
    }
}

enum AICutPlanValidationError: Error, Equatable {
    case invalidVersion
    case mismatchedDirection
    case emptySequence
    case excessiveSequence
    case insufficientSequence
    case unknownPhotoID
    case duplicatePhotoID
    case invalidOrder
    case invalidDuration
    case invalidSummary
    case invalidStory
    case invalidHook
    case invalidEnding
    case invalidSoundtrack
    case invalidTreatment
    case invalidDiagnosis
    case invalidComparison
}

enum AICutPlanValidator {
    static let minimumDuration = 0.6
    static let maximumDuration = 4.0

    static func validate(
        _ plan: AICutEditPlan,
        requestedIDs: Set<String>,
        direction: AICutDirection
    ) throws -> AICutEditPlan {
        guard plan.version == 2 || plan.version == 3 else { throw AICutPlanValidationError.invalidVersion }
        guard plan.direction == direction else { throw AICutPlanValidationError.mismatchedDirection }
        guard !plan.sequence.isEmpty else { throw AICutPlanValidationError.emptySequence }
        guard plan.sequence.count <= requestedIDs.count,
              plan.sequence.count <= CloudPhotoAnalysisClient.maximumBatchSize else {
            throw AICutPlanValidationError.excessiveSequence
        }
        guard let summary = normalizedText(plan.summary, minimum: 1, maximum: 240) else {
            throw AICutPlanValidationError.invalidSummary
        }
        guard let storyTitle = normalizedText(plan.story.title, minimum: 1, maximum: 60),
              let storyArc = normalizedText(plan.story.arc, minimum: 1, maximum: 240) else {
            throw AICutPlanValidationError.invalidStory
        }
        guard let hookTitle = normalizedText(plan.hook.title, minimum: 1, maximum: 60),
              let hookSubtitle = normalizedText(plan.hook.subtitle, minimum: 0, maximum: 100),
              plan.hook.durationSeconds.isFinite else {
            throw AICutPlanValidationError.invalidHook
        }
        guard let endingTitle = normalizedText(
            plan.ending.title,
            minimum: plan.ending.enabled ? 1 : 0,
            maximum: 60
        ),
              let endingSubtitle = normalizedText(plan.ending.subtitle, minimum: 0, maximum: 100),
              plan.ending.durationSeconds.isFinite else {
            throw AICutPlanValidationError.invalidEnding
        }
        guard let soundtrackReason = normalizedText(plan.soundtrack.reason, minimum: 1, maximum: 180) else {
            throw AICutPlanValidationError.invalidSoundtrack
        }
        guard let treatmentReason = normalizedText(plan.treatment.reason, minimum: 1, maximum: 180) else {
            throw AICutPlanValidationError.invalidTreatment
        }

        let diagnosis: AICutDiagnosis?
        let comparison: AICutComparison?
        if plan.version == 3 {
            guard let sourceDiagnosis = plan.diagnosis,
                  let verdict = normalizedText(sourceDiagnosis.verdict, minimum: 1, maximum: 180),
                  (1...3).contains(sourceDiagnosis.issues.count) else {
                throw AICutPlanValidationError.invalidDiagnosis
            }
            var issues: [AICutDiagnosisIssue] = []
            for issue in sourceDiagnosis.issues {
                guard let title = normalizedText(issue.title, minimum: 1, maximum: 60),
                      let detail = normalizedText(issue.detail, minimum: 1, maximum: 180),
                      issue.evidencePhotoIDs.count <= 3,
                      issue.evidencePhotoIDs.allSatisfy(requestedIDs.contains) else {
                    throw AICutPlanValidationError.invalidDiagnosis
                }
                var seenEvidence: Set<String> = []
                let evidence = issue.evidencePhotoIDs.filter {
                    seenEvidence.insert($0).inserted
                }
                issues.append(AICutDiagnosisIssue(
                    kind: issue.kind,
                    title: title,
                    detail: detail,
                    evidencePhotoIDs: evidence
                ))
            }
            guard let sourceComparison = plan.comparison,
                  (0...10_000).contains(sourceComparison.firstCutPhotoCount),
                  sourceComparison.aiCutPhotoCount == plan.sequence.count,
                  (0...sourceComparison.aiCutPhotoCount).contains(sourceComparison.restoredCount),
                  (0...sourceComparison.firstCutPhotoCount).contains(sourceComparison.removedCount),
                  (0...sourceComparison.aiCutPhotoCount).contains(sourceComparison.reorderedCount),
                  (0...sourceComparison.aiCutPhotoCount).contains(sourceComparison.retimedCount),
                  (0...sourceComparison.aiCutPhotoCount).contains(sourceComparison.motionChangedCount),
                  (0...3).contains(sourceComparison.titleChangedCount),
                  (0...100).contains(sourceComparison.score) else {
                throw AICutPlanValidationError.invalidComparison
            }
            diagnosis = AICutDiagnosis(verdict: verdict, issues: issues)
            comparison = sourceComparison
        } else {
            diagnosis = nil
            comparison = nil
        }

        let ordered = plan.sequence.sorted { $0.order < $1.order }
        guard ordered.map(\.order) == Array(0..<ordered.count) else {
            throw AICutPlanValidationError.invalidOrder
        }
        let ids = ordered.map(\.photoID)
        guard ids.allSatisfy(requestedIDs.contains) else {
            throw AICutPlanValidationError.unknownPhotoID
        }
        guard Set(ids).count == ids.count else {
            throw AICutPlanValidationError.duplicatePhotoID
        }
        guard ordered.count >= minimumSequenceCount(
            requestedCount: requestedIDs.count,
            direction: direction
        ) else {
            throw AICutPlanValidationError.insufficientSequence
        }
        guard ordered.allSatisfy({ $0.durationSeconds.isFinite }) else {
            throw AICutPlanValidationError.invalidDuration
        }

        return AICutEditPlan(
            version: plan.version,
            direction: direction,
            summary: summary,
            story: AICutStory(title: storyTitle, arc: storyArc),
            hook: AICutTitleCardPlan(
                title: hookTitle,
                subtitle: hookSubtitle,
                style: plan.hook.style,
                durationSeconds: min(max(plan.hook.durationSeconds, 1), 4)
            ),
            ending: AICutEndingPlan(
                enabled: plan.ending.enabled,
                title: endingTitle,
                subtitle: endingSubtitle,
                style: plan.ending.style,
                durationSeconds: min(max(plan.ending.durationSeconds, 1), 4)
            ),
            soundtrack: AICutSoundtrackPlan(
                trackID: plan.soundtrack.trackID,
                reason: soundtrackReason
            ),
            treatment: AICutTreatmentPlan(
                look: plan.treatment.look,
                motionIntensity: plan.treatment.motionIntensity,
                reason: treatmentReason
            ),
            sequence: ordered.enumerated().map { index, item in
                AICutPlanItem(
                    photoID: item.photoID,
                    order: index,
                    durationSeconds: min(max(item.durationSeconds, minimumDuration), maximumDuration),
                    role: item.role,
                    emphasis: item.emphasis,
                    motion: item.motion
                )
            },
            diagnosis: diagnosis,
            comparison: comparison
        )
    }

    private static func normalizedText(
        _ value: String,
        minimum: Int,
        maximum: Int
    ) -> String? {
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        let result = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return (minimum...maximum).contains(result.count) ? result : nil
    }

    static func minimumSequenceCount(
        requestedCount: Int,
        direction: AICutDirection
    ) -> Int {
        guard requestedCount > 1 else { return max(0, requestedCount) }
        let coverage = direction == .people ? 0.75 : 0.60
        return min(requestedCount, max(2, Int(ceil(Double(requestedCount) * coverage))))
    }
}

struct CloudPhotoAnalysisRetention: Codable, Equatable, Sendable {
    let proxyStored: Bool
    let openAIStore: Bool
    let abuseMonitoring: String
}

protocol CloudPhotoAnalysisServing: Sendable {
    var isConfigured: Bool { get }
    func createEditPlan(
        direction: AICutDirection,
        storyContext: String?,
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan
    func createEditPlan(
        direction: AICutDirection,
        storyContext: String?,
        baseline: CloudFirstCutInput?,
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan
}

extension CloudPhotoAnalysisServing {
    func createEditPlan(
        direction: AICutDirection,
        storyContext: String?,
        baseline: CloudFirstCutInput?,
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan {
        try await createEditPlan(direction: direction, storyContext: storyContext, photos: photos)
    }
}

protocol CloudPhotoAnalysisAuthorizing: Sendable {
    var isReady: Bool { get }
    func authorizationHeaders(for body: Data) async throws -> [String: String]
    func authorizationHeaders(for body: Data, path: String) async throws -> [String: String]
    func recoverAuthorization(afterStatusCode statusCode: Int, responseBody: Data) async -> Bool
}

extension CloudPhotoAnalysisAuthorizing {
    func authorizationHeaders(for body: Data, path: String) async throws -> [String: String] {
        try await authorizationHeaders(for: body)
    }

    func recoverAuthorization(afterStatusCode statusCode: Int, responseBody: Data) async -> Bool {
        false
    }
}

struct UnavailableCloudPhotoAnalysisAuthorizer: CloudPhotoAnalysisAuthorizing {
    let isReady = false
    func authorizationHeaders(for body: Data) async throws -> [String: String] { [:] }
}

/// Local-development bridge only. The token comes from the Run scheme's process
/// environment and is never compiled into the app. Release/TestFlight builds use
/// App Attest instead and never enable this authorizer.
struct DevelopmentCloudPhotoAnalysisAuthorizer: CloudPhotoAnalysisAuthorizing {
    let isReady: Bool
    private let token: String?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
#if DEBUG
        let candidate = environment["TRIPREEL_DEVELOPMENT_AUTH_TOKEN"]
        if let candidate, candidate.utf8.count >= 32, candidate.utf8.count <= 512 {
            token = candidate
            isReady = true
        } else {
            token = nil
            isReady = false
        }
#else
        token = nil
        isReady = false
#endif
    }

    func authorizationHeaders(for body: Data) async throws -> [String: String] {
        guard let token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
}

enum CloudPhotoAnalysisError: LocalizedError, Equatable {
    case notConfigured
    case invalidEndpoint
    case emptyRequest
    case tooManyPhotos
    case thumbnailTooLarge
    case invalidEphemeralIdentifier
    case invalidStoryContext
    case invalidBaseline
    case invalidResponse
    case server(statusCode: Int, code: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "AI couldn't create another cut right now. Your First Cut is still ready."
        case .invalidEndpoint:
            "Memories' cloud analysis endpoint must use HTTPS."
        case .emptyRequest:
            "There were no eligible previews for an AI cut."
        case .tooManyPhotos:
            "Too many photos were included in one analysis request."
        case .thumbnailTooLarge:
            "A reduced thumbnail was larger than the privacy limit."
        case .invalidEphemeralIdentifier:
            "AI preview identifiers must be temporary per-request values."
        case .invalidStoryContext:
            "Keep the story hint under 160 characters."
        case .invalidBaseline:
            "The First Cut could not be prepared for comparison."
        case .invalidResponse:
            "Memories received an invalid cloud analysis response."
        case let .server(statusCode, code):
            Self.serverMessage(statusCode: statusCode, code: code)
        }
    }

    private static func serverMessage(statusCode: Int, code: String?) -> String {
        switch code {
        case "rate_limited", "upstream_rate_limited":
            "AI editing is busy right now. Please wait a minute and try again."
        case "upstream_timeout", "upstream_unavailable", "upstream_error":
            "The AI editor is temporarily unavailable. Your First Cut is still ready."
        case "internal_error", "server_misconfigured":
            "Memories' secure AI service hit a temporary setup problem. Your First Cut is still ready."
        case "invalid_attestation", "invalid_assertion", "counter_replay",
             "key_not_registered", "authentication_unavailable":
            "This iPhone couldn't be securely verified. Please try once more."
        case "invalid_upstream_response":
            "The AI editor returned an unusable cut. Please try a different direction."
        default:
            "Memories' AI service returned error \(statusCode). Your First Cut is still ready."
        }
    }
}

/// Talks only to the TripReel-owned proxy. An OpenAI API key must never be
/// embedded in the app binary. The proxy chooses the configured model and is
/// responsible for using the Responses API with `store: false`.
final class CloudPhotoAnalysisClient: CloudPhotoAnalysisServing, @unchecked Sendable {
    static let maximumBatchSize = 36
    static let maximumThumbnailBytes = 128 * 1_024
    static let maximumStoryContextCharacters = 160
    static let endpointInfoPlistKey = "TRIPREEL_PHOTO_ANALYSIS_ENDPOINT"

    let isConfigured: Bool

    private let endpoint: URL?
    private let session: URLSession
    private let authorizer: any CloudPhotoAnalysisAuthorizing

    convenience init(bundle: Bundle = .main) {
        var rawValue = bundle.object(forInfoDictionaryKey: Self.endpointInfoPlistKey) as? String
#if DEBUG
        rawValue = ProcessInfo.processInfo.environment[Self.endpointInfoPlistKey] ?? rawValue
#endif
        let endpoint = Self.validEndpoint(from: rawValue)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 35
        configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration)
        let authorizer: any CloudPhotoAnalysisAuthorizing
#if DEBUG
        let developmentAuthorizer = DevelopmentCloudPhotoAnalysisAuthorizer()
        if developmentAuthorizer.isReady {
            authorizer = developmentAuthorizer
        } else if let endpoint,
                  let appAttestAuthorizer = AppAttestCloudPhotoAnalysisAuthorizer(
                      analysisEndpoint: endpoint,
                      session: session
                  ) {
            authorizer = appAttestAuthorizer
        } else {
            authorizer = UnavailableCloudPhotoAnalysisAuthorizer()
        }
#else
        if let endpoint,
           let appAttestAuthorizer = AppAttestCloudPhotoAnalysisAuthorizer(
               analysisEndpoint: endpoint,
               session: session
           ) {
            authorizer = appAttestAuthorizer
        } else {
            authorizer = UnavailableCloudPhotoAnalysisAuthorizer()
        }
#endif
        self.init(endpoint: endpoint, session: session, authorizer: authorizer)
    }

    init(
        endpoint: URL?,
        session: URLSession,
        authorizer: any CloudPhotoAnalysisAuthorizing
    ) {
        self.endpoint = endpoint
        self.session = session
        self.authorizer = authorizer
        isConfigured = (endpoint.map { Self.isValidHTTPSURL($0) } ?? false) && authorizer.isReady
    }

    func createEditPlan(
        direction: AICutDirection,
        storyContext: String? = nil,
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan {
        try await createEditPlan(
            direction: direction,
            storyContext: storyContext,
            baseline: nil,
            photos: photos
        )
    }

    func createEditPlan(
        direction: AICutDirection,
        storyContext: String? = nil,
        baseline: CloudFirstCutInput?,
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan {
        guard let endpoint, authorizer.isReady else { throw CloudPhotoAnalysisError.notConfigured }
        guard Self.isValidHTTPSURL(endpoint) else { throw CloudPhotoAnalysisError.invalidEndpoint }
        guard !photos.isEmpty else { throw CloudPhotoAnalysisError.emptyRequest }
        guard photos.count <= Self.maximumBatchSize else { throw CloudPhotoAnalysisError.tooManyPhotos }
        guard photos.enumerated().allSatisfy({ index, photo in photo.id == "p\(index)" }) else {
            throw CloudPhotoAnalysisError.invalidEphemeralIdentifier
        }
        guard photos.allSatisfy({ !$0.jpegData.isEmpty && $0.jpegData.count <= Self.maximumThumbnailBytes }) else {
            throw CloudPhotoAnalysisError.thumbnailTooLarge
        }
        let normalizedStoryContext = try Self.normalizedStoryContext(storyContext)
        if baseline != nil {
            guard photos.allSatisfy({ $0.context.map(Self.isValidContext) == true }),
                  Self.isValidBaseline(baseline, requestedIDs: Set(photos.map(\.id))) else {
                throw CloudPhotoAnalysisError.invalidBaseline
            }
        }

        let requestVersion = baseline == nil ? 2 : 3

        let requestBody = CloudRequest(
            version: requestVersion,
            direction: direction,
            storyContext: normalizedStoryContext,
            baseline: baseline,
            photos: photos.map {
                CloudRequest.Photo(
                    id: $0.id,
                    imageBase64: $0.jpegData.base64EncodedString(),
                    localSelection: $0.localSelection,
                    context: $0.context
                )
            }
        )
        let encodedBody = try JSONEncoder().encode(requestBody)
        var responseData: Data?

        for attempt in 0..<2 {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 35
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("TripReel-iOS/\(requestVersion)", forHTTPHeaderField: "X-TripReel-Client")

            let authorizationHeaders = try await authorizer.authorizationHeaders(for: encodedBody)
            guard !authorizationHeaders.isEmpty else { throw CloudPhotoAnalysisError.notConfigured }
            for (name, value) in authorizationHeaders {
                guard Self.allowedAuthorizationHeaderNames.contains(name.lowercased()),
                      !value.contains("\n"), !value.contains("\r") else {
                    throw CloudPhotoAnalysisError.notConfigured
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.httpBody = encodedBody

            // Never log the request, response body, image data, or asset identifiers.
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudPhotoAnalysisError.invalidResponse
            }
            if (200..<300).contains(httpResponse.statusCode) {
                responseData = data
                break
            }
            if attempt == 0,
               await authorizer.recoverAuthorization(
                   afterStatusCode: httpResponse.statusCode,
                   responseBody: data
               ) {
                continue
            }
            throw CloudPhotoAnalysisError.server(
                statusCode: httpResponse.statusCode,
                code: HTTPTripReelAppAttestBackendClient.errorCode(from: data)
            )
        }

        guard let data = responseData else { throw CloudPhotoAnalysisError.invalidResponse }

        guard Self.hasExactResponseShape(data) else {
            throw CloudPhotoAnalysisError.invalidResponse
        }
        guard let decoded = try? JSONDecoder().decode(CloudResponse.self, from: data),
              decoded.model.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$"#, options: .regularExpression) != nil,
              decoded.retention.proxyStored == false,
              decoded.retention.openAIStore == false else {
            throw CloudPhotoAnalysisError.invalidResponse
        }

        let requestedIDs = Set(photos.map(\.id))
        do {
            return try AICutPlanValidator.validate(
                decoded.plan,
                requestedIDs: requestedIDs,
                direction: direction
            )
        } catch {
            throw CloudPhotoAnalysisError.invalidResponse
        }
    }

    private static func validEndpoint(from rawValue: String?) -> URL? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              isValidHTTPSURL(url) else {
            return nil
        }
        return url
    }

    private static func normalizedStoryContext(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CloudPhotoAnalysisError.invalidStoryContext
        }
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count <= maximumStoryContextCharacters else {
            throw CloudPhotoAnalysisError.invalidStoryContext
        }
        return normalized.isEmpty ? nil : normalized
    }

    private static func isValidHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    private static func isValidBaseline(
        _ baseline: CloudFirstCutInput?,
        requestedIDs: Set<String>
    ) -> Bool {
        guard let baseline,
              baseline.photoCount >= baseline.sequence.count,
              baseline.photoCount <= 10_000,
              baseline.omittedPhotoCount == baseline.photoCount - baseline.sequence.count,
              baseline.durationSeconds.isFinite,
              (0...40_000).contains(baseline.durationSeconds),
              baseline.sequence.count <= maximumBatchSize,
              baseline.titles.count <= 3,
              Set(baseline.titles.map(\.kind)).count == baseline.titles.count,
              (Set(AICutSoundtrackID.allCases.map(\.rawValue)).union(["none"]))
                .contains(baseline.soundtrackID) else { return false }
        let ids = baseline.sequence.map(\.photoID)
        guard Set(ids).count == ids.count,
              ids.allSatisfy(requestedIDs.contains),
              baseline.sequence.sorted(by: { $0.order < $1.order }).map(\.order) == Array(0..<ids.count),
              baseline.sequence.allSatisfy({
                  $0.durationSeconds.isFinite && (0.6...4).contains($0.durationSeconds)
              }) else { return false }
        return baseline.titles.allSatisfy {
            !$0.title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                && !$0.subtitle.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                && $0.title.count <= 60
                && $0.subtitle.count <= 100
                && $0.durationSeconds.isFinite
                && (1...4).contains($0.durationSeconds)
        }
    }

    private static func isValidContext(_ context: CloudPhotoEditorialContext) -> Bool {
        let labelPattern = #"^[A-Za-z0-9][A-Za-z0-9 _-]{0,47}$"#
        let groupPattern = #"^(?:|g(?:0|[1-9][0-9]?))$"#
        return (0...100_000).contains(context.captureIndex)
            && (0...365).contains(context.dayIndex)
            && (0...20).contains(context.peopleCount)
            && context.clipDurationSeconds.isFinite
            && (0...4).contains(context.clipDurationSeconds)
            && (
                (context.mediaKind == .video && context.clipDurationSeconds >= 0.8)
                    || (context.mediaKind == .photo
                        && context.clipDurationSeconds == 0
                        && !context.hasOriginalAudio
                        && context.videoMotion == .still)
            )
            && context.similarityGroup.range(of: groupPattern, options: .regularExpression) != nil
            && context.sceneLabels.count <= 3
            && context.sceneLabels.allSatisfy {
                $0.range(of: labelPattern, options: .regularExpression) != nil
            }
    }

    private static func hasExactResponseShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["model", "plan", "retention"],
              let plan = root["plan"] as? [String: Any],
              let version = plan["version"] as? Int,
              ((version == 2 && Set(plan.keys) == [
                  "version", "direction", "summary", "story", "hook", "ending",
                  "soundtrack", "treatment", "sequence"
              ]) || (version == 3 && Set(plan.keys) == [
                  "version", "direction", "summary", "story", "hook", "ending",
                  "soundtrack", "treatment", "sequence", "diagnosis", "comparison"
              ])),
              let story = plan["story"] as? [String: Any],
              Set(story.keys) == ["title", "arc"],
              let hook = plan["hook"] as? [String: Any],
              Set(hook.keys) == ["title", "subtitle", "style", "durationSeconds"],
              let ending = plan["ending"] as? [String: Any],
              Set(ending.keys) == ["enabled", "title", "subtitle", "style", "durationSeconds"],
              let soundtrack = plan["soundtrack"] as? [String: Any],
              Set(soundtrack.keys) == ["trackId", "reason"],
              let treatment = plan["treatment"] as? [String: Any],
              Set(treatment.keys) == ["look", "motionIntensity", "reason"],
              let sequence = plan["sequence"] as? [[String: Any]],
              sequence.allSatisfy({ item in
                  Set(item.keys) == ["photoId", "order", "durationSeconds", "role", "emphasis", "motion"]
              }),
              (version != 3 || Self.hasExactDirectorFields(plan)),
              let retention = root["retention"] as? [String: Any],
              Set(retention.keys) == ["proxyStored", "openAIStore", "abuseMonitoring"] else {
            return false
        }
        return true
    }

    private static func hasExactDirectorFields(_ plan: [String: Any]) -> Bool {
        guard let diagnosis = plan["diagnosis"] as? [String: Any],
              Set(diagnosis.keys) == ["verdict", "issues"],
              let issues = diagnosis["issues"] as? [[String: Any]],
              issues.allSatisfy({
                  Set($0.keys) == ["kind", "title", "detail", "evidencePhotoIds"]
              }),
              let comparison = plan["comparison"] as? [String: Any],
              Set(comparison.keys) == [
                  "firstCutPhotoCount", "aiCutPhotoCount", "restoredCount", "removedCount",
                  "reorderedCount", "retimedCount", "motionChangedCount", "titleChangedCount",
                  "soundtrackChanged", "treatmentChanged", "score", "materiallyDifferent"
              ] else { return false }
        return true
    }

    private static let allowedAuthorizationHeaderNames: Set<String> = [
        "authorization",
        "x-tripreel-app-attest",
        "x-tripreel-challenge"
    ]
}

private struct CloudRequest: Encodable {
    struct Photo: Encodable {
        let id: String
        let imageBase64: String
        let localSelection: CloudPhotoLocalSelection
        let context: CloudPhotoEditorialContext?
    }

    let version: Int
    let direction: AICutDirection
    let storyContext: String?
    let baseline: CloudFirstCutInput?
    let photos: [Photo]
}

private struct CloudResponse: Decodable {
    let model: String
    let plan: AICutEditPlan
    let retention: CloudPhotoAnalysisRetention
}

struct AIVideoGenerationInput: Sendable {
    let jpegFrames: [Data]
    let prompt: String
    /// Stable only inside the app and never encoded into the network request.
    /// Its hash keeps retries resumable even if JPEG encoding differs slightly.
    let localResumeIdentifier: String?

    init(
        jpegFrames: [Data],
        prompt: String,
        localResumeIdentifier: String? = nil
    ) {
        self.jpegFrames = jpegFrames
        self.prompt = prompt
        self.localResumeIdentifier = localResumeIdentifier
    }
}

struct AIVideoGenerationProgress: Equatable, Sendable {
    let fraction: Double
    let status: String

    init(fraction: Double, status: String) {
        self.fraction = min(1, max(0, fraction))
        self.status = status
    }
}

protocol AIVideoGenerationServing: Sendable {
    var isConfigured: Bool { get }
    func generate(
        _ input: AIVideoGenerationInput,
        progress: @escaping @Sendable (AIVideoGenerationProgress) -> Void
    ) async throws -> URL
}

enum AIVideoGenerationError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case invalidInput
    case dailyLimitReached
    case providerBusy
    case providerRejected
    case generationFailed
    case timedOut
    case invalidResponse
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "AI video is not configured yet. Your existing cut is unchanged."
        case .invalidInput:
            "These moments could not be prepared safely for AI video."
        case .dailyLimitReached:
            "You’ve reached today’s AI video safety limit. It resets automatically tomorrow."
        case .providerBusy:
            "Seedance is busy right now. Please wait a moment and try again."
        case .providerRejected:
            "Seedance could not animate these moments. Try another pair."
        case .generationFailed:
            "The AI video could not be finished. Try another pair or direction."
        case .timedOut:
            "The AI video is taking longer than expected. Try again later."
        case .invalidResponse:
            "Memories received an invalid AI video response."
        case .downloadFailed:
            "The generated video could not be downloaded securely."
        }
    }
}

struct AIVideoPendingJob: Codable, Equatable, Sendable {
    let serviceIdentifier: String
    let requestFingerprint: String
    let jobToken: String
    let expiresAt: Date
}

protocol AIVideoPendingJobStoring: Sendable {
    func job(
        serviceIdentifier: String,
        requestFingerprint: String,
        now: Date
    ) async -> AIVideoPendingJob?
    func save(_ job: AIVideoPendingJob) async
    func remove(jobToken: String) async
}

/// The token contains no photo bytes and remains bound to this app installation
/// by App Attest. Keeping it briefly lets an interrupted generation reconnect
/// without submitting and charging for the same video a second time.
actor UserDefaultsAIVideoPendingJobStore: AIVideoPendingJobStoring {
    private static let storageKey = "Memories.PendingAIVideoJob.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func job(
        serviceIdentifier: String,
        requestFingerprint: String,
        now: Date
    ) -> AIVideoPendingJob? {
        guard let data = defaults.data(forKey: Self.storageKey),
              let job = try? JSONDecoder().decode(AIVideoPendingJob.self, from: data) else {
            defaults.removeObject(forKey: Self.storageKey)
            return nil
        }
        guard job.expiresAt > now else {
            defaults.removeObject(forKey: Self.storageKey)
            return nil
        }
        guard job.serviceIdentifier == serviceIdentifier,
              job.requestFingerprint == requestFingerprint else {
            return nil
        }
        return job
    }

    func save(_ job: AIVideoPendingJob) {
        guard let data = try? JSONEncoder().encode(job) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func remove(jobToken: String) {
        guard let data = defaults.data(forKey: Self.storageKey),
              let job = try? JSONDecoder().decode(AIVideoPendingJob.self, from: data),
              job.jobToken == jobToken else { return }
        defaults.removeObject(forKey: Self.storageKey)
    }
}

/// Generates a short first-to-last-frame story through the Memories Worker.
/// The OpenRouter credential never enters the app; App Attest signs every
/// request and the Worker returns an opaque, device-bound job token.
final class OpenRouterAIVideoClient: AIVideoGenerationServing, @unchecked Sendable {
    static let maximumImageBytes = PhotoAnalysisThumbnailService.maximumVideoJPEGBytes
    static let maximumPromptCharacters = 600

    let isConfigured: Bool

    private let endpoints: Endpoints?
    private let session: URLSession
    private let authorizer: any CloudPhotoAnalysisAuthorizing
    private let pendingJobStore: any AIVideoPendingJobStoring
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    convenience init(bundle: Bundle = .main) {
        var rawValue = bundle.object(
            forInfoDictionaryKey: CloudPhotoAnalysisClient.endpointInfoPlistKey
        ) as? String
#if DEBUG
        rawValue = ProcessInfo.processInfo.environment[
            CloudPhotoAnalysisClient.endpointInfoPlistKey
        ] ?? rawValue
#endif
        let analysisEndpoint = Self.validAnalysisEndpoint(from: rawValue)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 50
        configuration.timeoutIntervalForResource = 70
        let session = URLSession(configuration: configuration)

        let authorizer: any CloudPhotoAnalysisAuthorizing
#if DEBUG
        let developmentAuthorizer = DevelopmentCloudPhotoAnalysisAuthorizer()
        if developmentAuthorizer.isReady {
            authorizer = developmentAuthorizer
        } else if let analysisEndpoint,
                  let appAttest = AppAttestCloudPhotoAnalysisAuthorizer(
                      analysisEndpoint: analysisEndpoint,
                      session: session
                  ) {
            authorizer = appAttest
        } else {
            authorizer = UnavailableCloudPhotoAnalysisAuthorizer()
        }
#else
        if let analysisEndpoint,
           let appAttest = AppAttestCloudPhotoAnalysisAuthorizer(
               analysisEndpoint: analysisEndpoint,
               session: session
           ) {
            authorizer = appAttest
        } else {
            authorizer = UnavailableCloudPhotoAnalysisAuthorizer()
        }
#endif
        self.init(
            analysisEndpoint: analysisEndpoint,
            session: session,
            authorizer: authorizer,
            pendingJobStore: UserDefaultsAIVideoPendingJobStore()
        )
    }

    init(
        analysisEndpoint: URL?,
        session: URLSession,
        authorizer: any CloudPhotoAnalysisAuthorizing,
        pendingJobStore: any AIVideoPendingJobStoring = UserDefaultsAIVideoPendingJobStore(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        endpoints = analysisEndpoint.flatMap(Endpoints.init)
        self.session = session
        self.authorizer = authorizer
        self.pendingJobStore = pendingJobStore
        self.sleep = sleep
        self.now = now
        isConfigured = endpoints != nil && authorizer.isReady
    }

    func generate(
        _ input: AIVideoGenerationInput,
        progress: @escaping @Sendable (AIVideoGenerationProgress) -> Void
    ) async throws -> URL {
        guard let endpoints, authorizer.isReady else {
            throw AIVideoGenerationError.notConfigured
        }
        let generateBody = try Self.encodedGenerateBody(for: input)
        let requestFingerprint = Self.requestFingerprint(for: input)
        let serviceIdentifier = endpoints.generate.absoluteString

        let frameCount = input.jpegFrames.count
        progress(.init(
            fraction: 0.05,
            status: frameCount == 2
                ? "Preparing two reduced previews…"
                : "Preparing one reduced preview…"
        ))
        let resumedJob = await pendingJobStore.job(
            serviceIdentifier: serviceIdentifier,
            requestFingerprint: requestFingerprint,
            now: now()
        )
        let jobToken: String
        if let resumedJob {
            jobToken = resumedJob.jobToken
            progress(.init(fraction: 0.14, status: "Picking up your video where you left off…"))
        } else {
            let generatedData = try await sendJSON(
                body: generateBody,
                endpoint: endpoints.generate,
                path: "/v1/video/generate"
            )
            guard Self.hasExactKeys(generatedData, ["jobToken", "model", "status", "retention"]),
                  let response = try? JSONDecoder().decode(GenerateResponse.self, from: generatedData),
                  response.model == "bytedance/seedance-2.0",
                  response.status == .pending || response.status == .inProgress,
                  Self.isValidJobToken(response.jobToken),
                  response.retention.memoriesStored == false,
                  response.retention.providerTemporary == true else {
                throw AIVideoGenerationError.invalidResponse
            }
            jobToken = response.jobToken
            await pendingJobStore.save(AIVideoPendingJob(
                serviceIdentifier: serviceIdentifier,
                requestFingerprint: requestFingerprint,
                jobToken: jobToken,
                expiresAt: now().addingTimeInterval(29 * 60)
            ))
        }

        progress(.init(fraction: 0.16, status: "Seedance is directing the motion…"))
        do {
            let started = ContinuousClock.now
            var pollCount = 0
            var pollImmediately = resumedJob != nil
            while started.duration(to: .now) < .seconds(8 * 60) {
                try Task.checkCancellation()
                if pollImmediately {
                    pollImmediately = false
                } else {
                    try await sleep(.seconds(pollCount == 0 ? 12 : 24))
                }
                pollCount += 1
                let statusBody = try JSONEncoder().encode(JobRequest(
                    version: 1,
                    jobToken: jobToken
                ))
                let statusData = try await sendJSON(
                    body: statusBody,
                    endpoint: endpoints.status,
                    path: "/v1/video/status"
                )
                guard Self.hasExactKeys(statusData, ["status", "progress"]),
                      let status = try? JSONDecoder().decode(StatusResponse.self, from: statusData),
                      status.progress.isFinite,
                      (0...1).contains(status.progress) else {
                    throw AIVideoGenerationError.invalidResponse
                }
                switch status.status {
                case .pending:
                    progress(.init(
                        fraction: max(0.18, min(0.42, status.progress)),
                        status: "Waiting for the director…"
                    ))
                case .inProgress:
                    progress(.init(
                        fraction: max(0.42, min(0.91, status.progress)),
                        status: "Animating movement and atmosphere…"
                    ))
                case .completed:
                    progress(.init(fraction: 0.94, status: "Bringing your video back…"))
                    let url = try await download(jobToken: jobToken, endpoints: endpoints)
                    await pendingJobStore.remove(jobToken: jobToken)
                    return url
                case .failed, .cancelled, .expired:
                    await pendingJobStore.remove(jobToken: jobToken)
                    throw AIVideoGenerationError.generationFailed
                }
            }
            throw AIVideoGenerationError.timedOut
        } catch let error as AIVideoGenerationError {
            if error == .providerRejected || error == .generationFailed {
                await pendingJobStore.remove(jobToken: jobToken)
            }
            throw error
        }
    }

    static func encodedGenerateBody(for input: AIVideoGenerationInput) throws -> Data {
        guard (1...2).contains(input.jpegFrames.count),
              input.jpegFrames.allSatisfy({ !$0.isEmpty && $0.count <= maximumImageBytes }),
              Set(input.jpegFrames).count == input.jpegFrames.count,
              !input.prompt.isEmpty,
              input.prompt.count <= maximumPromptCharacters,
              !input.prompt.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw AIVideoGenerationError.invalidInput
        }
        return try JSONEncoder().encode(GenerateRequest(
            version: 2,
            imagesBase64: input.jpegFrames.map { $0.base64EncodedString() },
            prompt: input.prompt
        ))
    }

    static func requestFingerprint(for input: AIVideoGenerationInput) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("Memories-AI-Video/v1\0".utf8))
        if let identifier = input.localResumeIdentifier, !identifier.isEmpty {
            hasher.update(data: Data("local-selection\0".utf8))
            hasher.update(data: Data(SHA256.hash(data: Data(identifier.utf8))))
        } else {
            hasher.update(data: Data("prepared-frames\0".utf8))
            hasher.update(data: Data([UInt8(input.jpegFrames.count)]))
            for frame in input.jpegFrames {
                hasher.update(data: Data(SHA256.hash(data: frame)))
            }
        }
        hasher.update(data: Data(SHA256.hash(data: Data(input.prompt.utf8))))
        return Data(hasher.finalize()).base64EncodedString()
    }

    private func sendJSON(
        body: Data,
        endpoint: URL,
        path: String
    ) async throws -> Data {
        for attempt in 0..<2 {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Memories-iOS/1", forHTTPHeaderField: "X-TripReel-Client")
            let headers = try await authorizer.authorizationHeaders(for: body, path: path)
            guard !headers.isEmpty else { throw AIVideoGenerationError.notConfigured }
            for (name, value) in headers {
                guard Self.allowedAuthorizationHeaderNames.contains(name.lowercased()),
                      !value.contains("\n"), !value.contains("\r") else {
                    throw AIVideoGenerationError.notConfigured
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.httpBody = body
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIVideoGenerationError.invalidResponse
            }
            if (200..<300).contains(http.statusCode) { return data }
            if attempt == 0,
               await authorizer.recoverAuthorization(
                afterStatusCode: http.statusCode,
                responseBody: data
               ) {
                continue
            }
            throw Self.error(statusCode: http.statusCode, body: data)
        }
        throw AIVideoGenerationError.invalidResponse
    }

    private func download(jobToken: String, endpoints: Endpoints) async throws -> URL {
        let body = try JSONEncoder().encode(JobRequest(version: 1, jobToken: jobToken))
        for attempt in 0..<2 {
            var request = URLRequest(url: endpoints.content)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("video/mp4", forHTTPHeaderField: "Accept")
            let headers = try await authorizer.authorizationHeaders(
                for: body,
                path: "/v1/video/content"
            )
            guard !headers.isEmpty else { throw AIVideoGenerationError.notConfigured }
            for (name, value) in headers where Self.allowedAuthorizationHeaderNames.contains(name.lowercased()) {
                guard !value.contains("\n"), !value.contains("\r") else {
                    throw AIVideoGenerationError.notConfigured
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.httpBody = body

            let (temporaryURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIVideoGenerationError.downloadFailed
            }
            if !(200..<300).contains(http.statusCode) {
                let errorData = (try? Data(contentsOf: temporaryURL, options: .mappedIfSafe)) ?? Data()
                if attempt == 0,
                   await authorizer.recoverAuthorization(
                    afterStatusCode: http.statusCode,
                    responseBody: errorData
                   ) {
                    continue
                }
                throw Self.error(statusCode: http.statusCode, body: errorData)
            }
            guard http.value(forHTTPHeaderField: "Content-Type")?
                .lowercased().hasPrefix("video/") == true else {
                throw AIVideoGenerationError.invalidResponse
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard (1...100_000_000).contains(byteCount) else {
                throw AIVideoGenerationError.downloadFailed
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Memories-AI-Videos", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("Memory-\(UUID().uuidString).mp4")
            try FileManager.default.copyItem(at: temporaryURL, to: destination)
            return destination
        }
        throw AIVideoGenerationError.downloadFailed
    }

    private static func validAnalysisEndpoint(from rawValue: String?) -> URL? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path == "/v1/analyze" else { return nil }
        return url
    }

    private static func hasExactKeys(_ data: Data, _ keys: Set<String>) -> Bool {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return Set(value.keys) == keys
    }

    private static func error(statusCode: Int, body: Data) -> AIVideoGenerationError {
        let code = HTTPTripReelAppAttestBackendClient.errorCode(from: body)
        switch code {
        case "video_generation_limit":
            return .dailyLimitReached
        case "rate_limited", "upstream_rate_limited", "provider_busy":
            return .providerBusy
        case "content_policy", "provider_rejected", "invalid_image":
            return .providerRejected
        case "generation_failed", "generation_cancelled", "generation_expired", "invalid_job":
            return .generationFailed
        default:
            if statusCode == 429 { return .providerBusy }
            return statusCode >= 500 ? .generationFailed : .invalidResponse
        }
    }

    private static func isValidJobToken(_ value: String) -> Bool {
        value.count <= 1_024 && value.range(
            of: #"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static let allowedAuthorizationHeaderNames: Set<String> = [
        "authorization",
        "x-tripreel-app-attest",
        "x-tripreel-challenge"
    ]

    private struct Endpoints {
        let generate: URL
        let status: URL
        let content: URL

        init?(analysisEndpoint: URL) {
            guard analysisEndpoint.path == "/v1/analyze" else { return nil }
            var components = URLComponents(url: analysisEndpoint, resolvingAgainstBaseURL: false)
            components?.path = "/v1/video/generate"
            guard let generate = components?.url else { return nil }
            components?.path = "/v1/video/status"
            guard let status = components?.url else { return nil }
            components?.path = "/v1/video/content"
            guard let content = components?.url else { return nil }
            self.generate = generate
            self.status = status
            self.content = content
        }
    }

    private struct GenerateRequest: Encodable {
        let version: Int
        let imagesBase64: [String]
        let prompt: String
    }

    private struct JobRequest: Encodable {
        let version: Int
        let jobToken: String
    }

    private struct GenerateResponse: Decodable {
        let jobToken: String
        let model: String
        let status: JobStatus
        let retention: Retention
    }

    private struct StatusResponse: Decodable {
        let status: JobStatus
        let progress: Double
    }

    private struct Retention: Decodable {
        let memoriesStored: Bool
        let providerTemporary: Bool
    }

    private enum JobStatus: String, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
        case cancelled
        case expired
    }
}
