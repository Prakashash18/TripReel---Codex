import CryptoKit
@preconcurrency import DeviceCheck
import Foundation
import Security

enum TripReelAppAttestEnvironment: String, Codable, Sendable {
    case development
    case production

    // TripReel's production Worker accepts production attestations only. Local
    // Debug runs continue to prefer the explicitly supplied development bearer.
    static let current: Self = .production
}

enum TripReelAppAttestPurpose: String, Codable, Sendable {
    case attestation
    case assertion
}

enum TripReelAppAttestServiceError: LocalizedError, Equatable, Sendable {
    case featureUnsupported
    case invalidInput
    case invalidKey
    case serverUnavailable
    case systemFailure

    var errorDescription: String? {
        switch self {
        case .featureUnsupported:
            "Secure AI editing isn't supported on this iPhone. Your First Cut is still ready."
        case .invalidInput, .invalidKey:
            "This iPhone's secure AI access needs to be refreshed. Please try again."
        case .serverUnavailable:
            "Apple's secure device check is temporarily unavailable. Please try again shortly."
        case .systemFailure:
            "This iPhone couldn't complete its secure device check. Please try again."
        }
    }
}

enum TripReelAppAttestError: LocalizedError, Equatable, Sendable {
    case unsupported
    case invalidEndpoint
    case invalidChallenge
    case invalidKeyIdentifier
    case invalidServerResponse
    case keyStore(status: OSStatus)
    case keyStoreCorrupt
    case server(statusCode: Int, code: String?)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "Secure AI editing isn't supported on this iPhone. Your First Cut is still ready."
        case .invalidEndpoint:
            "Memories' secure AI service address isn't valid. Your First Cut is still ready."
        case .invalidChallenge, .invalidServerResponse:
            "Memories couldn't complete the secure device check. Please try again shortly."
        case .invalidKeyIdentifier, .keyStoreCorrupt:
            "This iPhone's secure AI access needs to be refreshed. Please try again."
        case .keyStore:
            "Memories couldn't access this iPhone's secure AI key. Please unlock your iPhone and try again."
        case let .server(statusCode, code):
            Self.serverMessage(statusCode: statusCode, code: code)
        }
    }

    private static func serverMessage(statusCode: Int, code: String?) -> String {
        switch code {
        case "internal_error", "server_misconfigured":
            "Memories' secure device check hit a temporary setup problem. Your First Cut is still ready."
        case "rate_limited":
            "Secure AI editing is busy right now. Please wait a minute and try again."
        case "authentication_unavailable":
            "Secure device verification is temporarily unavailable. Please try again shortly."
        case "invalid_attestation", "invalid_assertion", "counter_replay",
             "key_not_registered", "unknown_key", "invalid_key":
            "This iPhone couldn't be securely verified. Please try once more."
        default:
            "Memories' secure device check returned error \(statusCode). Your First Cut is still ready."
        }
    }
}

protocol TripReelAppAttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

final class DeviceCheckAppAttestService: TripReelAppAttestServicing, @unchecked Sendable {
    private let service: DCAppAttestService

    init(service: DCAppAttestService = .shared) {
        self.service = service
    }

    var isSupported: Bool { service.isSupported }

    func generateKey() async throws -> String {
        do {
            return try await service.generateKey()
        } catch {
            throw Self.map(error)
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        do {
            return try await service.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        do {
            return try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> TripReelAppAttestServiceError {
        guard let deviceCheckError = error as? DCError else { return .systemFailure }
        switch deviceCheckError.code {
        case .featureUnsupported:
            return .featureUnsupported
        case .invalidInput:
            return .invalidInput
        case .invalidKey:
            return .invalidKey
        case .serverUnavailable:
            return .serverUnavailable
        case .unknownSystemFailure:
            return .systemFailure
        @unknown default:
            return .systemFailure
        }
    }
}

struct TripReelAppAttestChallenge: Equatable, Sendable {
    let encodedValue: String
    let data: Data
    let expiresAt: Date

    init(encodedValue: String, expiresAt: Date) throws {
        guard let data = TripReelBase64URL.decode(encodedValue),
              data.count == 32,
              TripReelBase64URL.encode(data) == encodedValue else {
            throw TripReelAppAttestError.invalidChallenge
        }
        self.encodedValue = encodedValue
        self.data = data
        self.expiresAt = expiresAt
    }
}

protocol TripReelAppAttestBackendServing: Sendable {
    func challenge(
        purpose: TripReelAppAttestPurpose,
        keyID: String
    ) async throws -> TripReelAppAttestChallenge

    func register(
        keyID: String,
        challenge: String,
        attestationObject: Data
    ) async throws
}

struct TripReelAppAttestKeyRecord: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case generated
        case registrationPending
        case registered
    }

    let keyID: String
    let state: State
    let pendingChallenge: String?
    let pendingChallengeExpiresAt: Date?
    let pendingAttestationObject: Data?

    init(
        keyID: String,
        state: State,
        pendingChallenge: String? = nil,
        pendingChallengeExpiresAt: Date? = nil,
        pendingAttestationObject: Data? = nil
    ) {
        self.keyID = keyID
        self.state = state
        self.pendingChallenge = pendingChallenge
        self.pendingChallengeExpiresAt = pendingChallengeExpiresAt
        self.pendingAttestationObject = pendingAttestationObject
    }
}

protocol TripReelAppAttestKeyStoring: Sendable {
    func load(environment: TripReelAppAttestEnvironment) async throws -> TripReelAppAttestKeyRecord?
    func save(
        _ record: TripReelAppAttestKeyRecord,
        environment: TripReelAppAttestEnvironment
    ) async throws
    func delete(environment: TripReelAppAttestEnvironment) async throws
}

/// The identifier isn't a secret, but Keychain persistence keeps it tied to this
/// installation's protected app data. A stale identifier left after reinstall is
/// safely discarded when DeviceCheck reports `invalidKey`.
struct KeychainTripReelAppAttestKeyStore: TripReelAppAttestKeyStoring, Sendable {
    private let service = "com.prakashash18.tripreel.app-attest"

    func load(environment: TripReelAppAttestEnvironment) async throws -> TripReelAppAttestKeyRecord? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: environment.rawValue,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw TripReelAppAttestError.keyStore(status: status)
        }
        guard let data = result as? Data,
              let record = try? JSONDecoder().decode(TripReelAppAttestKeyRecord.self, from: data) else {
            throw TripReelAppAttestError.keyStoreCorrupt
        }
        return record
    }

    func save(
        _ record: TripReelAppAttestKeyRecord,
        environment: TripReelAppAttestEnvironment
    ) async throws {
        let data = try JSONEncoder().encode(record)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: environment.rawValue
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw TripReelAppAttestError.keyStore(status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TripReelAppAttestError.keyStore(status: addStatus)
        }
    }

    func delete(environment: TripReelAppAttestEnvironment) async throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: environment.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TripReelAppAttestError.keyStore(status: status)
        }
    }
}

final class HTTPTripReelAppAttestBackendClient: TripReelAppAttestBackendServing, @unchecked Sendable {
    private let challengeEndpoint: URL
    private let registrationEndpoint: URL
    private let session: URLSession

    init?(analysisEndpoint: URL, session: URLSession) {
        guard let challengeEndpoint = Self.endpoint(
            path: "/v1/app-attest/challenge",
            from: analysisEndpoint
        ), let registrationEndpoint = Self.endpoint(
            path: "/v1/app-attest/register",
            from: analysisEndpoint
        ) else {
            return nil
        }
        self.challengeEndpoint = challengeEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.session = session
    }

    func challenge(
        purpose: TripReelAppAttestPurpose,
        keyID: String
    ) async throws -> TripReelAppAttestChallenge {
        let body = try JSONEncoder().encode(ChallengeRequest(purpose: purpose, keyId: keyID))
        let (data, _) = try await send(to: challengeEndpoint, body: body)
        guard data.count <= 4_096,
              let decoded = try? JSONDecoder().decode(ChallengeResponse.self, from: data),
              let expiry = Self.parseRFC3339(decoded.expiresAt) else {
            throw TripReelAppAttestError.invalidServerResponse
        }
        return try TripReelAppAttestChallenge(
            encodedValue: decoded.challenge,
            expiresAt: expiry
        )
    }

    func register(
        keyID: String,
        challenge: String,
        attestationObject: Data
    ) async throws {
        guard !attestationObject.isEmpty, attestationObject.count <= 65_536 else {
            throw TripReelAppAttestError.invalidServerResponse
        }
        let body = try JSONEncoder().encode(RegistrationRequest(
            keyId: keyID,
            challenge: challenge,
            attestationObject: TripReelBase64URL.encode(attestationObject)
        ))
        let (data, _) = try await send(to: registrationEndpoint, body: body)
        guard data.count <= 4_096 else {
            throw TripReelAppAttestError.invalidServerResponse
        }
    }

    private func send(to endpoint: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TripReel-iOS/1", forHTTPHeaderField: "X-TripReel-Client")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TripReelAppAttestError.invalidServerResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorCode = Self.errorCode(from: data)
            throw TripReelAppAttestError.server(
                statusCode: httpResponse.statusCode,
                code: errorCode
            )
        }
        return (data, httpResponse)
    }

    private static func endpoint(path: String, from analysisEndpoint: URL) -> URL? {
        guard var components = URLComponents(
            url: analysisEndpoint,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == "https",
           components.host?.isEmpty == false,
           components.user == nil,
           components.password == nil,
           components.query == nil,
           components.fragment == nil,
           components.path == "/v1/analyze" else {
            return nil
        }
        components.path = path
        return components.url
    }

    static func errorCode(from data: Data) -> String? {
        guard data.count <= 4_096 else { return nil }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.code
    }

    private static func parseRFC3339(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }
}

private extension HTTPTripReelAppAttestBackendClient {
    struct ChallengeRequest: Encodable {
        let purpose: TripReelAppAttestPurpose
        let keyId: String
    }

    struct ChallengeResponse: Decodable {
        let challenge: String
        let expiresAt: String
    }

    struct RegistrationRequest: Encodable {
        let keyId: String
        let challenge: String
        let attestationObject: String
    }

    struct ErrorEnvelope: Decodable {
        struct Problem: Decodable {
            let code: String
        }

        let error: Problem
    }
}

enum TripReelAppAttestRequestBinding {
    private static let attestationPrefix = Data("TripReel-App-Attest/v1\nattestation\n".utf8)
    private static let allowedPaths: Set<String> = [
        "/v1/analyze",
        "/v1/video/generate",
        "/v1/video/status",
        "/v1/video/content"
    ]

    static func attestationClientDataHash(challenge: Data) -> Data {
        var clientData = attestationPrefix
        clientData.append(challenge)
        return digest(clientData)
    }

    static func assertionClientDataHash(challenge: Data, body: Data) -> Data {
        assertionClientDataHash(challenge: challenge, body: body, path: "/v1/analyze")
    }

    static func assertionClientDataHash(challenge: Data, body: Data, path: String) -> Data {
        precondition(allowedPaths.contains(path), "Unsupported App Attest request path")
        var clientData = Data("TripReel-App-Attest/v1\nassertion\nPOST\n\(path)\n".utf8)
        clientData.append(challenge)
        clientData.append(digest(body))
        return digest(clientData)
    }

    static func isAllowed(path: String) -> Bool {
        allowedPaths.contains(path)
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

enum TripReelBase64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> Data? {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({
                  ("A"..."Z").contains(Character(String($0))) ||
                  ("a"..."z").contains(Character(String($0))) ||
                  ("0"..."9").contains(Character(String($0))) ||
                  $0 == "-" || $0 == "_"
              }) else {
            return nil
        }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

actor TripReelAppAttestCoordinator {
    typealias Sleep = @Sendable (UInt64) async throws -> Void
    typealias Now = @Sendable () -> Date

    private let service: any TripReelAppAttestServicing
    private let backend: any TripReelAppAttestBackendServing
    private let keyStore: any TripReelAppAttestKeyStoring
    private let environment: TripReelAppAttestEnvironment
    private let sleep: Sleep
    private let now: Now

    init(
        service: any TripReelAppAttestServicing,
        backend: any TripReelAppAttestBackendServing,
        keyStore: any TripReelAppAttestKeyStoring,
        environment: TripReelAppAttestEnvironment,
        sleep: @escaping Sleep = { nanoseconds in
            try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
        },
        now: @escaping Now = { Date() }
    ) {
        self.service = service
        self.backend = backend
        self.keyStore = keyStore
        self.environment = environment
        self.sleep = sleep
        self.now = now
    }

    func authorizationHeaders(for body: Data, path: String = "/v1/analyze") async throws -> [String: String] {
        guard service.isSupported else { throw TripReelAppAttestError.unsupported }
        guard TripReelAppAttestRequestBinding.isAllowed(path: path) else {
            throw TripReelAppAttestError.invalidServerResponse
        }
        var didResetKey = false

        while true {
            do {
                let keyID = try await registeredKey()
                let challenge = try await backend.challenge(
                    purpose: .assertion,
                    keyID: keyID
                )
                try validateFresh(challenge)
                let clientDataHash = TripReelAppAttestRequestBinding.assertionClientDataHash(
                    challenge: challenge.data,
                    body: body,
                    path: path
                )
                let assertion = try await service.generateAssertion(
                    keyID,
                    clientDataHash: clientDataHash
                )
                guard !assertion.isEmpty, assertion.count <= 65_536 else {
                    throw TripReelAppAttestError.invalidServerResponse
                }
                return [
                    "Authorization": "AppAttest \(keyID)",
                    "X-TripReel-Challenge": challenge.encodedValue,
                    "X-TripReel-App-Attest": TripReelBase64URL.encode(assertion)
                ]
            } catch {
                guard !didResetKey, Self.requiresKeyReset(error) else { throw error }
                try await keyStore.delete(environment: environment)
                didResetKey = true
            }
        }
    }

    func recoverFromServerRejection(statusCode: Int, responseBody: Data) async -> Bool {
        let error = TripReelAppAttestError.server(
            statusCode: statusCode,
            code: HTTPTripReelAppAttestBackendClient.errorCode(from: responseBody)
        )
        guard Self.requiresKeyReset(error) else { return false }
        do {
            try await keyStore.delete(environment: environment)
            return true
        } catch {
            return false
        }
    }

    private func registeredKey() async throws -> String {
        let existingRecord = try await keyStore.load(environment: environment)
        var record: TripReelAppAttestKeyRecord
        if let existingRecord {
            try Self.validate(keyID: existingRecord.keyID)
            record = existingRecord
        } else {
            let keyID = try await service.generateKey()
            try Self.validate(keyID: keyID)
            record = TripReelAppAttestKeyRecord(keyID: keyID, state: .generated)
            try await keyStore.save(record, environment: environment)
        }

        if record.state == .registered { return record.keyID }

        if record.state == .registrationPending {
            guard let encodedChallenge = record.pendingChallenge,
                  let challengeExpiresAt = record.pendingChallengeExpiresAt,
                  let attestationObject = record.pendingAttestationObject,
                  !attestationObject.isEmpty,
                  attestationObject.count <= 65_536 else {
                throw TripReelAppAttestError.keyStoreCorrupt
            }
            guard challengeExpiresAt > now() else {
                throw TripReelAppAttestError.server(
                    statusCode: 410,
                    code: "challenge_expired"
                )
            }
            do {
                _ = try TripReelAppAttestChallenge(
                    encodedValue: encodedChallenge,
                    expiresAt: challengeExpiresAt
                )
            } catch {
                throw TripReelAppAttestError.keyStoreCorrupt
            }
            do {
                try await backend.register(
                    keyID: record.keyID,
                    challenge: encodedChallenge,
                    attestationObject: attestationObject
                )
            } catch let error as TripReelAppAttestError where Self.isAlreadyRegistered(error) {
                // A lost registration response is safe to resume because the
                // server treats this key identifier idempotently.
            }
            try await keyStore.save(
                TripReelAppAttestKeyRecord(keyID: record.keyID, state: .registered),
                environment: environment
            )
            return record.keyID
        }

        do {
            let challenge = try await backend.challenge(
                purpose: .attestation,
                keyID: record.keyID
            )
            try validateFresh(challenge)
            let clientDataHash = TripReelAppAttestRequestBinding.attestationClientDataHash(
                challenge: challenge.data
            )
            let attestationObject = try await attestKeyWithRetry(
                record.keyID,
                clientDataHash: clientDataHash
            )
            record = TripReelAppAttestKeyRecord(
                keyID: record.keyID,
                state: .registrationPending,
                pendingChallenge: challenge.encodedValue,
                pendingChallengeExpiresAt: challenge.expiresAt,
                pendingAttestationObject: attestationObject
            )
            try await keyStore.save(record, environment: environment)
            try await backend.register(
                keyID: record.keyID,
                challenge: challenge.encodedValue,
                attestationObject: attestationObject
            )
        } catch let error as TripReelAppAttestError where Self.isAlreadyRegistered(error) {
            // The server may have committed registration even if its response
            // was lost. It remains the authority, so its idempotency signal is
            // enough to advance the local record without generating a new key.
        }
        try await keyStore.save(
            TripReelAppAttestKeyRecord(keyID: record.keyID, state: .registered),
            environment: environment
        )
        return record.keyID
    }

    private func attestKeyWithRetry(
        _ keyID: String,
        clientDataHash: Data
    ) async throws -> Data {
        let retryDelays: [UInt64] = [300_000_000, 900_000_000]
        var retryIndex = 0
        while true {
            do {
                return try await service.attestKey(
                    keyID,
                    clientDataHash: clientDataHash
                )
            } catch TripReelAppAttestServiceError.serverUnavailable where retryIndex < retryDelays.count {
                let delay = retryDelays[retryIndex]
                retryIndex += 1
                try await sleep(delay)
            }
        }
    }

    private func validateFresh(_ challenge: TripReelAppAttestChallenge) throws {
        guard challenge.expiresAt > now() else {
            throw TripReelAppAttestError.invalidChallenge
        }
    }

    private static func validate(keyID: String) throws {
        guard !keyID.contains("\n"),
              !keyID.contains("\r"),
              let decoded = Data(base64Encoded: keyID),
              decoded.count == 32 else {
            throw TripReelAppAttestError.invalidKeyIdentifier
        }
    }

    private static func requiresKeyReset(_ error: Error) -> Bool {
        if let serviceError = error as? TripReelAppAttestServiceError {
            return serviceError == .invalidKey || serviceError == .invalidInput
        }
        if let appAttestError = error as? TripReelAppAttestError {
            switch appAttestError {
            case .invalidKeyIdentifier, .keyStoreCorrupt:
                return true
            case let .server(statusCode, code):
                if statusCode == 404 {
                    return code == "key_not_registered" || code == "unknown_key" || code == "invalid_key"
                }
                if statusCode == 401 {
                    return code == "invalid_attestation" ||
                        code == "invalid_assertion" ||
                        code == "unauthorized"
                }
                if statusCode == 409 {
                    return code == "counter_replay" || code == "challenge_used"
                }
                if statusCode == 410 {
                    return code == "challenge_expired"
                }
                return false
            default:
                return false
            }
        }
        return false
    }

    private static func isAlreadyRegistered(_ error: TripReelAppAttestError) -> Bool {
        guard case let .server(statusCode, code) = error else { return false }
        return statusCode == 409 && code == "key_already_registered"
    }
}

final class AppAttestCloudPhotoAnalysisAuthorizer: CloudPhotoAnalysisAuthorizing, @unchecked Sendable {
    let isReady: Bool
    private let coordinator: TripReelAppAttestCoordinator

    convenience init?(analysisEndpoint: URL, session: URLSession) {
        guard let backend = HTTPTripReelAppAttestBackendClient(
            analysisEndpoint: analysisEndpoint,
            session: session
        ) else {
            return nil
        }
        self.init(
            service: DeviceCheckAppAttestService(),
            backend: backend,
            keyStore: KeychainTripReelAppAttestKeyStore(),
            environment: .current
        )
    }

    init(
        service: any TripReelAppAttestServicing,
        backend: any TripReelAppAttestBackendServing,
        keyStore: any TripReelAppAttestKeyStoring,
        environment: TripReelAppAttestEnvironment,
        sleep: @escaping TripReelAppAttestCoordinator.Sleep = { nanoseconds in
            try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
        },
        now: @escaping TripReelAppAttestCoordinator.Now = { Date() }
    ) {
        isReady = service.isSupported
        coordinator = TripReelAppAttestCoordinator(
            service: service,
            backend: backend,
            keyStore: keyStore,
            environment: environment,
            sleep: sleep,
            now: now
        )
    }

    func authorizationHeaders(for body: Data) async throws -> [String: String] {
        guard isReady else { throw TripReelAppAttestError.unsupported }
        return try await coordinator.authorizationHeaders(for: body)
    }

    func authorizationHeaders(for body: Data, path: String) async throws -> [String: String] {
        guard isReady else { throw TripReelAppAttestError.unsupported }
        return try await coordinator.authorizationHeaders(for: body, path: path)
    }

    func recoverAuthorization(afterStatusCode statusCode: Int, responseBody: Data) async -> Bool {
        await coordinator.recoverFromServerRejection(
            statusCode: statusCode,
            responseBody: responseBody
        )
    }
}
