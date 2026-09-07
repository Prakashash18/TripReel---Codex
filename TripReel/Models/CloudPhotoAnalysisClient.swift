import Foundation

struct CloudPhotoAnalysisInput: Sendable {
    let id: String
    let jpegData: Data
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
        case .betterStory: "Tell a Better Story"
        case .dynamic: "Make It More Dynamic"
        case .calm: "Keep It Calm"
        case .people: "Focus on People"
        case .surpriseMe: "Surprise Me"
        }
    }

    var detail: String {
        switch self {
        case .betterStory: "Build a stronger beginning, middle and ending."
        case .dynamic: "Quicker pacing, bolder movement and less repetition."
        case .calm: "Scenic moments, longer holds and a gentler rhythm."
        case .people: "Prioritize faces, shared moments and human connection."
        case .surpriseMe: "Let the director choose the strongest overall shape."
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

struct AICutEditPlan: Codable, Hashable, Sendable {
    let version: Int
    let direction: AICutDirection
    let summary: String
    let sequence: [AICutPlanItem]
}

enum AICutPlanValidationError: Error, Equatable {
    case invalidVersion
    case mismatchedDirection
    case emptySequence
    case excessiveSequence
    case unknownPhotoID
    case duplicatePhotoID
    case invalidOrder
    case invalidDuration
    case invalidSummary
}

enum AICutPlanValidator {
    static let minimumDuration = 0.6
    static let maximumDuration = 4.0

    static func validate(
        _ plan: AICutEditPlan,
        requestedIDs: Set<String>,
        direction: AICutDirection
    ) throws -> AICutEditPlan {
        guard plan.version == 1 else { throw AICutPlanValidationError.invalidVersion }
        guard plan.direction == direction else { throw AICutPlanValidationError.mismatchedDirection }
        guard !plan.sequence.isEmpty else { throw AICutPlanValidationError.emptySequence }
        guard plan.sequence.count <= requestedIDs.count,
              plan.sequence.count <= CloudPhotoAnalysisClient.maximumBatchSize else {
            throw AICutPlanValidationError.excessiveSequence
        }
        guard !plan.summary.isEmpty, plan.summary.count <= 240 else {
            throw AICutPlanValidationError.invalidSummary
        }
        guard !plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AICutPlanValidationError.invalidSummary
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
        guard ordered.allSatisfy({ $0.durationSeconds.isFinite }) else {
            throw AICutPlanValidationError.invalidDuration
        }

        return AICutEditPlan(
            version: 1,
            direction: direction,
            summary: plan.summary,
            sequence: ordered.enumerated().map { index, item in
                AICutPlanItem(
                    photoID: item.photoID,
                    order: index,
                    durationSeconds: min(max(item.durationSeconds, minimumDuration), maximumDuration),
                    role: item.role,
                    emphasis: item.emphasis,
                    motion: item.motion
                )
            }
        )
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
        photos: [CloudPhotoAnalysisInput]
    ) async throws -> AICutEditPlan
}

protocol CloudPhotoAnalysisAuthorizing: Sendable {
    var isReady: Bool { get }
    func authorizationHeaders(for body: Data) async throws -> [String: String]
    func recoverAuthorization(afterStatusCode statusCode: Int, responseBody: Data) async -> Bool
}

extension CloudPhotoAnalysisAuthorizing {
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
    case invalidResponse
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "AI couldn't create another cut right now. Your First Cut is still ready."
        case .invalidEndpoint:
            "TripReel's cloud analysis endpoint must use HTTPS."
        case .emptyRequest:
            "There were no eligible previews for an AI cut."
        case .tooManyPhotos:
            "Too many photos were included in one analysis request."
        case .thumbnailTooLarge:
            "A reduced thumbnail was larger than the privacy limit."
        case .invalidEphemeralIdentifier:
            "AI preview identifiers must be temporary per-request values."
        case .invalidResponse:
            "TripReel received an invalid cloud analysis response."
        case let .server(statusCode):
            "TripReel's cloud analysis service returned error \(statusCode)."
        }
    }
}

/// Talks only to the TripReel-owned proxy. An OpenAI API key must never be
/// embedded in the app binary. The proxy chooses the configured model and is
/// responsible for using the Responses API with `store: false`.
final class CloudPhotoAnalysisClient: CloudPhotoAnalysisServing, @unchecked Sendable {
    static let maximumBatchSize = 24
    static let maximumThumbnailBytes = 128 * 1_024
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

        let requestBody = CloudRequest(
            version: 1,
            direction: direction,
            photos: photos.map {
                CloudRequest.Photo(id: $0.id, imageBase64: $0.jpegData.base64EncodedString())
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
            request.setValue("TripReel-iOS/1", forHTTPHeaderField: "X-TripReel-Client")

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
            throw CloudPhotoAnalysisError.server(statusCode: httpResponse.statusCode)
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

    private static func isValidHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    private static func hasExactResponseShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["model", "plan", "retention"],
              let plan = root["plan"] as? [String: Any],
              Set(plan.keys) == ["version", "direction", "summary", "sequence"],
              let sequence = plan["sequence"] as? [[String: Any]],
              sequence.allSatisfy({ item in
                  Set(item.keys) == ["photoId", "order", "durationSeconds", "role", "emphasis", "motion"]
              }),
              let retention = root["retention"] as? [String: Any],
              Set(retention.keys) == ["proxyStored", "openAIStore", "abuseMonitoring"] else {
            return false
        }
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
    }

    let version: Int
    let direction: AICutDirection
    let photos: [Photo]
}

private struct CloudResponse: Decodable {
    let model: String
    let plan: AICutEditPlan
    let retention: CloudPhotoAnalysisRetention
}
