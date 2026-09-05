import Foundation

struct CloudPhotoAnalysisInput: Sendable {
    let id: String
    let jpegData: Data
}

enum CloudPhotoAnalysisAction: String, Codable, Sendable {
    case keep
    case review
    case discard
}

struct CloudPhotoAnalysisResult: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let scenic: Double
    let people: Double
    let group: Double
    let food: Double
    let document: Double
    let screenshot: Double
    let lowQuality: Double
    let confidence: Double
    let action: CloudPhotoAnalysisAction
    let reason: String

    var scoresAreValid: Bool {
        [scenic, people, group, food, document, screenshot, lowQuality, confidence]
            .allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

struct CloudPhotoAnalysisRetention: Codable, Equatable, Sendable {
    let proxyStored: Bool
    let openAIStore: Bool
    let abuseMonitoring: String
}

protocol CloudPhotoAnalysisServing: Sendable {
    var isConfigured: Bool { get }
    func analyze(_ photos: [CloudPhotoAnalysisInput]) async throws -> [CloudPhotoAnalysisResult]
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
    case invalidResponse
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Cloud enhancement is not configured yet. TripReel kept the analysis on this iPhone."
        case .invalidEndpoint:
            "TripReel's cloud analysis endpoint must use HTTPS."
        case .emptyRequest:
            "There were no photos to analyze."
        case .tooManyPhotos:
            "Too many photos were included in one analysis request."
        case .thumbnailTooLarge:
            "A reduced thumbnail was larger than the privacy limit."
        case .invalidResponse:
            "TripReel received an invalid cloud analysis response."
        case let .server(statusCode):
            "TripReel's cloud analysis service returned error \(statusCode)."
        }
    }
}

/// Talks only to the TripReel-owned proxy. An OpenAI API key must never be
/// embedded in the app binary. The proxy is responsible for calling the
/// Responses API with `model: "gpt-5.6-luna"` and `store: false`.
final class CloudPhotoAnalysisClient: CloudPhotoAnalysisServing, @unchecked Sendable {
    static let modelName = "gpt-5.6-luna"
    static let maximumBatchSize = 12
    static let maximumThumbnailBytes = 256 * 1_024
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

    func analyze(_ photos: [CloudPhotoAnalysisInput]) async throws -> [CloudPhotoAnalysisResult] {
        guard let endpoint, authorizer.isReady else { throw CloudPhotoAnalysisError.notConfigured }
        guard Self.isValidHTTPSURL(endpoint) else { throw CloudPhotoAnalysisError.invalidEndpoint }
        guard !photos.isEmpty else { throw CloudPhotoAnalysisError.emptyRequest }
        guard photos.count <= Self.maximumBatchSize else { throw CloudPhotoAnalysisError.tooManyPhotos }
        guard photos.allSatisfy({ !$0.jpegData.isEmpty && $0.jpegData.count <= Self.maximumThumbnailBytes }) else {
            throw CloudPhotoAnalysisError.thumbnailTooLarge
        }

        let requestBody = CloudRequest(
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

        let decoded = try JSONDecoder().decode(CloudResponse.self, from: data)
        guard decoded.model == Self.modelName,
              decoded.retention.proxyStored == false,
              decoded.retention.openAIStore == false else {
            throw CloudPhotoAnalysisError.invalidResponse
        }

        let requestedIDs = Set(photos.map(\.id))
        let responseIDs = decoded.photos.map(\.id)
        guard responseIDs.count == Set(responseIDs).count,
              Set(responseIDs) == requestedIDs,
              decoded.photos.allSatisfy(\.scoresAreValid) else {
            throw CloudPhotoAnalysisError.invalidResponse
        }
        return decoded.photos
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

    let photos: [Photo]
}

private struct CloudResponse: Decodable {
    let model: String
    let photos: [CloudPhotoAnalysisResult]
    let retention: CloudPhotoAnalysisRetention
}
