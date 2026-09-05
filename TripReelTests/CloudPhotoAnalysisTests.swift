import CoreGraphics
import CryptoKit
import Foundation
import XCTest
@testable import TripReel

final class CloudPhotoAnalysisTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testClientRejectsAnUnconfiguredEndpointWithoutNetworking() async {
        let client = CloudPhotoAnalysisClient(
            endpoint: nil,
            session: makeSession(),
            authorizer: TestCloudAuthorizer()
        )

        do {
            _ = try await client.analyze([.init(id: "one", jpegData: Data([1, 2, 3]))])
            XCTFail("Expected an unconfigured error")
        } catch let error as CloudPhotoAnalysisError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientSendsOnlyTheBoundedThumbnailPayloadAndValidatesRetention() async throws {
        let response = """
        {
          "model":"gpt-5.6-luna",
          "photos":[{
            "id":"asset-1","scenic":0.91,"people":0.1,"group":0.0,
            "food":0.0,"document":0.02,"screenshot":0.01,"lowQuality":0.04,
            "confidence":0.95,"action":"keep","reason":"Scenic waterfront"
          }],
          "retention":{"proxyStored":false,"openAIStore":false,"abuseMonitoring":"up_to_30_days_unless_zdr"}
        }
        """
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
            XCTAssertEqual(photos.count, 1)
            XCTAssertEqual(photos[0]["id"] as? String, "asset-1")
            XCTAssertEqual(photos[0]["imageBase64"] as? String, Data([0xFF, 0xD8, 0xFF]).base64EncodedString())
            XCTAssertNil(json["apiKey"])

            let httpResponse = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (httpResponse, Data(response.utf8))
        }

        let client = CloudPhotoAnalysisClient(
            endpoint: URL(string: "https://analysis.example.test/v1/photo-analysis"),
            session: makeSession(),
            authorizer: TestCloudAuthorizer()
        )
        let results = try await client.analyze([
            .init(id: "asset-1", jpegData: Data([0xFF, 0xD8, 0xFF]))
        ])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.action, .keep)
        XCTAssertEqual(results.first?.scenic, 0.91)
    }

    func testClientRetriesOnceWithTheSameBodyAfterRecoverableAuthenticationFailure() async throws {
        let response = """
        {
          "model":"gpt-5.6-luna",
          "photos":[{
            "id":"asset-1","scenic":0.91,"people":0.1,"group":0.0,
            "food":0.0,"document":0.02,"screenshot":0.01,"lowQuality":0.04,
            "confidence":0.95,"action":"keep","reason":"Scenic waterfront"
          }],
          "retention":{"proxyStored":false,"openAIStore":false,"abuseMonitoring":"up_to_30_days_unless_zdr"}
        }
        """
        let requests = LockedRequestList()
        URLProtocolStub.handler = { request in
            requests.append(request)
            let attempt = requests.values().count
            let statusCode = attempt == 1 ? 404 : 200
            let body = attempt == 1
                ? Data(#"{"error":{"code":"key_not_registered","message":"Unknown key"}}"#.utf8)
                : Data(response.utf8)
            let httpResponse = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (httpResponse, body)
        }
        let authorizer = RecoveringCloudAuthorizer()
        let client = CloudPhotoAnalysisClient(
            endpoint: URL(string: "https://analysis.example.test/v1/analyze"),
            session: makeSession(),
            authorizer: authorizer
        )

        _ = try await client.analyze([
            .init(id: "asset-1", jpegData: Data([0xFF, 0xD8, 0xFF]))
        ])

        let captured = requests.values()
        let authorizerSnapshot = await authorizer.snapshot()
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].httpBody, captured[1].httpBody)
        XCTAssertEqual(captured[0].value(forHTTPHeaderField: "Authorization"), "AppAttest attempt-1")
        XCTAssertEqual(captured[1].value(forHTTPHeaderField: "Authorization"), "AppAttest attempt-2")
        XCTAssertEqual(authorizerSnapshot.authorizationCount, 2)
        XCTAssertEqual(authorizerSnapshot.recoveryStatuses, [404])
    }

    func testCloudPolicyExcludesOnlyHighConfidenceUtilityContent() {
        let asset = TripAsset(
            id: "order",
            source: .library("order"),
            creationDate: Date(),
            filename: "IMG_1001.HEIC"
        )
        let order = makeResult(
            id: asset.id,
            scenic: 0.05,
            people: 0,
            group: 0,
            document: 0.98,
            confidence: 0.95,
            action: .discard
        )

        let decision = SmartPhotoSelectionPolicy.cloudDecision(for: asset, result: order)

        XCTAssertEqual(decision?.reason, .document)
        XCTAssertEqual(decision?.origin, .cloud)
    }

    func testCloudPolicyProtectsGroupAndScenicMemories() {
        let asset = TripAsset(
            id: "friends",
            source: .library("friends"),
            creationDate: Date(),
            filename: "IMG_1002.HEIC"
        )
        let groupPhoto = makeResult(
            id: asset.id,
            scenic: 0.92,
            people: 0.96,
            group: 0.94,
            document: 0.10,
            confidence: 0.99,
            action: .discard
        )

        XCTAssertNil(SmartPhotoSelectionPolicy.cloudDecision(for: asset, result: groupPhoto))
    }

    func testCloudPolicyProtectsGroupPhotoWithConflictingDocumentScore() {
        let asset = TripAsset(
            id: "friends-at-menu",
            source: .library("friends-at-menu"),
            creationDate: Date(),
            filename: "IMG_1003.HEIC"
        )
        let conflictingResult = CloudPhotoAnalysisResult(
            id: asset.id,
            scenic: 0.90,
            people: 0.99,
            group: 0.98,
            food: 0.25,
            document: 0.97,
            screenshot: 0.02,
            lowQuality: 0.04,
            confidence: 0.99,
            action: .discard,
            reason: "Document or text-heavy image."
        )

        XCTAssertNil(SmartPhotoSelectionPolicy.cloudDecision(for: asset, result: conflictingResult))
    }

    func testCloudThumbnailJPEGContainsNoExifPhotoshopOrCommentSegments() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())

        let jpeg = try PhotoAnalysisThumbnailService.encodeMetadataStrippedJPEG(
            image,
            quality: 0.72
        )

        XCTAssertEqual(jpeg.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertEqual(jpeg.suffix(2), Data([0xFF, 0xD9]))
        XCTAssertTrue(forbiddenMetadataMarkers(in: jpeg).isEmpty)
    }

    func testMetadataScreenshotNeverRequiresCloudAnalysis() {
        let asset = TripAsset(
            id: "screenshot",
            source: .library("screenshot"),
            creationDate: Date(),
            filename: "",
            isScreenshot: true
        )

        let decision = SmartPhotoSelectionPolicy.metadataDecision(for: asset)

        XCTAssertEqual(decision?.reason, .screenshot)
        XCTAssertEqual(decision?.origin, .metadata)
        XCTAssertEqual(decision?.confidence, 1)
    }

    func testAppAttestAuthorizerRegistersThenSignsTheExactAnalysisBody() async throws {
        let keyID = Data(repeating: 0xA5, count: 32).base64EncodedString()
        let attestationChallengeData = Data(repeating: 0x11, count: 32)
        let assertionChallengeData = Data(repeating: 0x22, count: 32)
        let attestationChallenge = try makeChallenge(data: attestationChallengeData)
        let assertionChallenge = try makeChallenge(data: assertionChallengeData)
        let service = TestAppAttestService(keyIDs: [keyID])
        let backend = TestAppAttestBackend(
            attestationChallenge: attestationChallenge,
            assertionChallenge: assertionChallenge
        )
        let store = TestAppAttestKeyStore()
        let authorizer = AppAttestCloudPhotoAnalysisAuthorizer(
            service: service,
            backend: backend,
            keyStore: store,
            environment: .production,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let body = Data(#"{"photos":[{"id":"p0","imageBase64":"/9j/"}]}"#.utf8)

        let headers = try await authorizer.authorizationHeaders(for: body)

        XCTAssertEqual(headers["Authorization"], "AppAttest \(keyID)")
        XCTAssertEqual(headers["X-TripReel-Challenge"], assertionChallenge.encodedValue)
        XCTAssertEqual(
            headers["X-TripReel-App-Attest"],
            TripReelBase64URL.encode(TestAppAttestService.assertionObject)
        )

        let serviceSnapshot = await service.snapshot()
        XCTAssertEqual(serviceSnapshot.generatedKeyIDs, [keyID])
        XCTAssertEqual(serviceSnapshot.attestations.count, 1)
        XCTAssertEqual(serviceSnapshot.attestations[0].keyID, keyID)
        XCTAssertEqual(
            serviceSnapshot.attestations[0].clientDataHash,
            expectedAttestationHash(challenge: attestationChallengeData)
        )
        XCTAssertEqual(serviceSnapshot.assertions.count, 1)
        XCTAssertEqual(
            serviceSnapshot.assertions[0].clientDataHash,
            expectedAssertionHash(challenge: assertionChallengeData, body: body)
        )

        let backendSnapshot = await backend.snapshot()
        XCTAssertEqual(backendSnapshot.registrations.count, 1)
        XCTAssertEqual(backendSnapshot.registrations[0].keyID, keyID)
        XCTAssertEqual(
            backendSnapshot.registrations[0].attestationObject,
            TestAppAttestService.attestationObject
        )
        let storedRecord = try await store.load(environment: .production)
        XCTAssertEqual(storedRecord, .init(keyID: keyID, state: .registered))
    }

    func testAppAttestRetriesServerUnavailableUsingTheSameKeyAndHash() async throws {
        let keyID = Data(repeating: 0xB5, count: 32).base64EncodedString()
        let attestationChallenge = try makeChallenge(data: Data(repeating: 0x31, count: 32))
        let assertionChallenge = try makeChallenge(data: Data(repeating: 0x32, count: 32))
        let service = TestAppAttestService(
            keyIDs: [keyID],
            attestationFailures: [.serverUnavailable, .serverUnavailable]
        )
        let backend = TestAppAttestBackend(
            attestationChallenge: attestationChallenge,
            assertionChallenge: assertionChallenge
        )
        let store = TestAppAttestKeyStore()
        let delays = TestDelayRecorder()
        let authorizer = AppAttestCloudPhotoAnalysisAuthorizer(
            service: service,
            backend: backend,
            keyStore: store,
            environment: .production,
            sleep: { delay in await delays.append(delay) },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        _ = try await authorizer.authorizationHeaders(for: Data("body".utf8))

        let snapshot = await service.snapshot()
        let recordedDelays = await delays.values()
        XCTAssertEqual(snapshot.attestations.count, 3)
        XCTAssertEqual(Set(snapshot.attestations.map(\.keyID)), [keyID])
        XCTAssertEqual(Set(snapshot.attestations.map(\.clientDataHash)).count, 1)
        XCTAssertEqual(recordedDelays, [300_000_000, 900_000_000])
    }

    func testAppAttestInvalidKeyClearsStoredKeyAndRetriesOnlyOnce() async throws {
        let firstKeyID = Data(repeating: 0xC1, count: 32).base64EncodedString()
        let secondKeyID = Data(repeating: 0xC2, count: 32).base64EncodedString()
        let service = TestAppAttestService(
            keyIDs: [firstKeyID, secondKeyID],
            assertionFailures: [.invalidKey]
        )
        let backend = TestAppAttestBackend(
            attestationChallenge: try makeChallenge(data: Data(repeating: 0x41, count: 32)),
            assertionChallenge: try makeChallenge(data: Data(repeating: 0x42, count: 32))
        )
        let store = TestAppAttestKeyStore()
        let authorizer = AppAttestCloudPhotoAnalysisAuthorizer(
            service: service,
            backend: backend,
            keyStore: store,
            environment: .production,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let headers = try await authorizer.authorizationHeaders(for: Data("body".utf8))

        XCTAssertEqual(headers["Authorization"], "AppAttest \(secondKeyID)")
        let serviceSnapshot = await service.snapshot()
        let deletionCount = await store.deleteCount()
        XCTAssertEqual(serviceSnapshot.generatedKeyIDs, [firstKeyID, secondKeyID])
        XCTAssertEqual(serviceSnapshot.attestations.map(\.keyID), [firstKeyID, secondKeyID])
        XCTAssertEqual(serviceSnapshot.assertions.map(\.keyID), [firstKeyID, secondKeyID])
        XCTAssertEqual(deletionCount, 1)
    }

    func testAppAttestRecoverableServerResponseInvalidatesKeyForOneClientRetry() async throws {
        let firstKeyID = Data(repeating: 0xD1, count: 32).base64EncodedString()
        let secondKeyID = Data(repeating: 0xD2, count: 32).base64EncodedString()
        let service = TestAppAttestService(keyIDs: [firstKeyID, secondKeyID])
        let backend = TestAppAttestBackend(
            attestationChallenge: try makeChallenge(data: Data(repeating: 0x51, count: 32)),
            assertionChallenge: try makeChallenge(data: Data(repeating: 0x52, count: 32))
        )
        let store = TestAppAttestKeyStore()
        let authorizer = AppAttestCloudPhotoAnalysisAuthorizer(
            service: service,
            backend: backend,
            keyStore: store,
            environment: .production,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let firstHeaders = try await authorizer.authorizationHeaders(for: Data("same-body".utf8))
        let recovered = await authorizer.recoverAuthorization(
            afterStatusCode: 404,
            responseBody: Data(#"{"error":{"code":"key_not_registered","message":"Unknown key"}}"#.utf8)
        )
        let secondHeaders = try await authorizer.authorizationHeaders(for: Data("same-body".utf8))
        let deletionCount = await store.deleteCount()

        XCTAssertTrue(recovered)
        XCTAssertEqual(firstHeaders["Authorization"], "AppAttest \(firstKeyID)")
        XCTAssertEqual(secondHeaders["Authorization"], "AppAttest \(secondKeyID)")
        XCTAssertEqual(deletionCount, 1)
    }

    func testAppAttestTreatsAlreadyRegisteredAsAnIdempotentRegistrationSuccess() async throws {
        let keyID = Data(repeating: 0xD3, count: 32).base64EncodedString()
        let generatedRecord = TripReelAppAttestKeyRecord(keyID: keyID, state: .generated)
        let service = TestAppAttestService(keyIDs: [])
        let backend = TestAppAttestBackend(
            attestationChallenge: try makeChallenge(data: Data(repeating: 0x61, count: 32)),
            assertionChallenge: try makeChallenge(data: Data(repeating: 0x62, count: 32)),
            attestationChallengeError: .server(
                statusCode: 409,
                code: "key_already_registered"
            )
        )
        let store = TestAppAttestKeyStore(record: generatedRecord)
        let authorizer = AppAttestCloudPhotoAnalysisAuthorizer(
            service: service,
            backend: backend,
            keyStore: store,
            environment: .production,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let headers = try await authorizer.authorizationHeaders(for: Data("body".utf8))
        let storedRecord = try await store.load(environment: .production)

        XCTAssertEqual(headers["Authorization"], "AppAttest \(keyID)")
        XCTAssertEqual(
            storedRecord,
            .init(keyID: keyID, state: .registered)
        )
        let serviceSnapshot = await service.snapshot()
        XCTAssertTrue(serviceSnapshot.generatedKeyIDs.isEmpty)
        XCTAssertTrue(serviceSnapshot.attestations.isEmpty)
        XCTAssertEqual(serviceSnapshot.assertions.map(\.keyID), [keyID])
    }

    func testHTTPAppAttestBackendUsesDerivedEndpointsAndBase64URLPayloads() async throws {
        let challengeData = Data(repeating: 0xFE, count: 32)
        let challenge = TripReelBase64URL.encode(challengeData)
        let keyID = Data(repeating: 0xE1, count: 32).base64EncodedString()
        let attestationObject = Data([0xFB, 0xFF, 0xEF])
        let requests = LockedRequestList()

        URLProtocolStub.handler = { request in
            requests.append(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: request.url?.path == "/v1/app-attest/register" ? 204 : 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            if request.url?.path == "/v1/app-attest/challenge" {
                return (response, Data("{\"challenge\":\"\(challenge)\",\"expiresAt\":\"2099-01-01T00:00:00.000Z\"}".utf8))
            }
            return (response, Data())
        }

        let backend = try XCTUnwrap(HTTPTripReelAppAttestBackendClient(
            analysisEndpoint: URL(string: "https://analysis.example.test/v1/analyze")!,
            session: makeSession()
        ))
        let receivedChallenge = try await backend.challenge(purpose: .attestation, keyID: keyID)
        try await backend.register(
            keyID: keyID,
            challenge: receivedChallenge.encodedValue,
            attestationObject: attestationObject
        )

        let captured = requests.values()
        XCTAssertEqual(captured.map { $0.url?.path }, [
            "/v1/app-attest/challenge",
            "/v1/app-attest/register"
        ])
        let challengeJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(captured[0].httpBody)) as? [String: String]
        )
        XCTAssertEqual(challengeJSON, ["purpose": "attestation", "keyId": keyID])
        let registrationJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(captured[1].httpBody)) as? [String: String]
        )
        XCTAssertEqual(registrationJSON["keyId"], keyID)
        XCTAssertEqual(registrationJSON["challenge"], challenge)
        XCTAssertEqual(
            registrationJSON["attestationObject"],
            TripReelBase64URL.encode(attestationObject)
        )
        XCTAssertFalse(try XCTUnwrap(registrationJSON["attestationObject"]).contains("="))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeResult(
        id: String,
        scenic: Double,
        people: Double,
        group: Double,
        document: Double,
        confidence: Double,
        action: CloudPhotoAnalysisAction
    ) -> CloudPhotoAnalysisResult {
        CloudPhotoAnalysisResult(
            id: id,
            scenic: scenic,
            people: people,
            group: group,
            food: 0,
            document: document,
            screenshot: 0,
            lowQuality: 0,
            confidence: confidence,
            action: action,
            reason: "Automated test"
        )
    }

    private func makeChallenge(data: Data) throws -> TripReelAppAttestChallenge {
        try TripReelAppAttestChallenge(
            encodedValue: TripReelBase64URL.encode(data),
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
        )
    }

    private func expectedAttestationHash(challenge: Data) -> Data {
        var clientData = Data("TripReel-App-Attest/v1\nattestation\n".utf8)
        clientData.append(challenge)
        return Data(SHA256.hash(data: clientData))
    }

    private func expectedAssertionHash(challenge: Data, body: Data) -> Data {
        var clientData = Data("TripReel-App-Attest/v1\nassertion\nPOST\n/v1/analyze\n".utf8)
        clientData.append(challenge)
        clientData.append(Data(SHA256.hash(data: body)))
        return Data(SHA256.hash(data: clientData))
    }

    private func forbiddenMetadataMarkers(in data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return [0] }
        var markers: [UInt8] = []
        var offset = 2

        while offset + 3 < bytes.count, bytes[offset] == 0xFF {
            while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
            guard offset < bytes.count else { break }
            let marker = bytes[offset]
            offset += 1
            if marker == 0xDA || marker == 0xD9 { break }
            guard offset + 1 < bytes.count else { break }
            let length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            guard length >= 2, offset + length <= bytes.count else { break }
            if marker == 0xE1 || marker == 0xED || marker == 0xFE {
                markers.append(marker)
            }
            offset += length
        }
        return markers
    }
}

private struct TestCloudAuthorizer: CloudPhotoAnalysisAuthorizing {
    let isReady = true
    func authorizationHeaders(for body: Data) async throws -> [String: String] {
        ["Authorization": "Bearer unit-test-token"]
    }
}

private actor RecoveringCloudAuthorizer: CloudPhotoAnalysisAuthorizing {
    struct Snapshot: Equatable, Sendable {
        let authorizationCount: Int
        let recoveryStatuses: [Int]
    }

    nonisolated let isReady = true
    private var authorizationCount = 0
    private var recoveryStatuses: [Int] = []

    func authorizationHeaders(for body: Data) async throws -> [String: String] {
        authorizationCount += 1
        return ["Authorization": "AppAttest attempt-\(authorizationCount)"]
    }

    func recoverAuthorization(afterStatusCode statusCode: Int, responseBody: Data) async -> Bool {
        recoveryStatuses.append(statusCode)
        return statusCode == 404
    }

    func snapshot() -> Snapshot {
        Snapshot(
            authorizationCount: authorizationCount,
            recoveryStatuses: recoveryStatuses
        )
    }
}

private actor TestAppAttestService: TripReelAppAttestServicing {
    struct Invocation: Equatable, Sendable {
        let keyID: String
        let clientDataHash: Data
    }

    struct Snapshot: Equatable, Sendable {
        let generatedKeyIDs: [String]
        let attestations: [Invocation]
        let assertions: [Invocation]
    }

    nonisolated static let attestationObject = Data([0xA3, 0x01, 0x02])
    nonisolated static let assertionObject = Data([0xA2, 0x03, 0x04])
    nonisolated let isSupported: Bool

    private let keyIDs: [String]
    private var nextKeyIndex = 0
    private var generatedKeyIDs: [String] = []
    private var attestationFailures: [TripReelAppAttestServiceError]
    private var assertionFailures: [TripReelAppAttestServiceError]
    private var attestationInvocations: [Invocation] = []
    private var assertionInvocations: [Invocation] = []

    init(
        isSupported: Bool = true,
        keyIDs: [String],
        attestationFailures: [TripReelAppAttestServiceError] = [],
        assertionFailures: [TripReelAppAttestServiceError] = []
    ) {
        self.isSupported = isSupported
        self.keyIDs = keyIDs
        self.attestationFailures = attestationFailures
        self.assertionFailures = assertionFailures
    }

    func generateKey() async throws -> String {
        guard keyIDs.indices.contains(nextKeyIndex) else {
            throw TripReelAppAttestServiceError.systemFailure
        }
        let keyID = keyIDs[nextKeyIndex]
        nextKeyIndex += 1
        generatedKeyIDs.append(keyID)
        return keyID
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        attestationInvocations.append(.init(keyID: keyID, clientDataHash: clientDataHash))
        if !attestationFailures.isEmpty {
            throw attestationFailures.removeFirst()
        }
        return Self.attestationObject
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        assertionInvocations.append(.init(keyID: keyID, clientDataHash: clientDataHash))
        if !assertionFailures.isEmpty {
            throw assertionFailures.removeFirst()
        }
        return Self.assertionObject
    }

    func snapshot() -> Snapshot {
        Snapshot(
            generatedKeyIDs: generatedKeyIDs,
            attestations: attestationInvocations,
            assertions: assertionInvocations
        )
    }
}

private actor TestAppAttestBackend: TripReelAppAttestBackendServing {
    struct Registration: Equatable, Sendable {
        let keyID: String
        let challenge: String
        let attestationObject: Data
    }

    struct Snapshot: Equatable, Sendable {
        let challengePurposes: [TripReelAppAttestPurpose]
        let registrations: [Registration]
    }

    private let attestationChallenge: TripReelAppAttestChallenge
    private let assertionChallenge: TripReelAppAttestChallenge
    private let attestationChallengeError: TripReelAppAttestError?
    private var challengePurposes: [TripReelAppAttestPurpose] = []
    private var registrations: [Registration] = []

    init(
        attestationChallenge: TripReelAppAttestChallenge,
        assertionChallenge: TripReelAppAttestChallenge,
        attestationChallengeError: TripReelAppAttestError? = nil
    ) {
        self.attestationChallenge = attestationChallenge
        self.assertionChallenge = assertionChallenge
        self.attestationChallengeError = attestationChallengeError
    }

    func challenge(
        purpose: TripReelAppAttestPurpose,
        keyID: String
    ) async throws -> TripReelAppAttestChallenge {
        challengePurposes.append(purpose)
        if purpose == .attestation, let attestationChallengeError {
            throw attestationChallengeError
        }
        return purpose == .attestation ? attestationChallenge : assertionChallenge
    }

    func register(
        keyID: String,
        challenge: String,
        attestationObject: Data
    ) async throws {
        registrations.append(.init(
            keyID: keyID,
            challenge: challenge,
            attestationObject: attestationObject
        ))
    }

    func snapshot() -> Snapshot {
        Snapshot(challengePurposes: challengePurposes, registrations: registrations)
    }
}

private actor TestAppAttestKeyStore: TripReelAppAttestKeyStoring {
    private var record: TripReelAppAttestKeyRecord?
    private var deletionCount = 0

    init(record: TripReelAppAttestKeyRecord? = nil) {
        self.record = record
    }

    func load(environment: TripReelAppAttestEnvironment) async throws -> TripReelAppAttestKeyRecord? {
        record
    }

    func save(
        _ record: TripReelAppAttestKeyRecord,
        environment: TripReelAppAttestEnvironment
    ) async throws {
        self.record = record
    }

    func delete(environment: TripReelAppAttestEnvironment) async throws {
        record = nil
        deletionCount += 1
    }

    func deleteCount() -> Int { deletionCount }
}

private actor TestDelayRecorder {
    private var recordedValues: [UInt64] = []

    func append(_ value: UInt64) {
        recordedValues.append(value)
    }

    func values() -> [UInt64] { recordedValues }
}

private final class LockedRequestList: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func values() -> [URLRequest] {
        lock.withLock { requests }
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: CloudPhotoAnalysisError.invalidResponse)
            return
        }
        do {
            var normalizedRequest = request
            if normalizedRequest.httpBody == nil,
               let bodyStream = normalizedRequest.httpBodyStream {
                bodyStream.open()
                defer { bodyStream.close() }
                var body = Data()
                var buffer = [UInt8](repeating: 0, count: 4_096)
                while bodyStream.hasBytesAvailable {
                    let count = bodyStream.read(&buffer, maxLength: buffer.count)
                    guard count >= 0 else { throw bodyStream.streamError ?? URLError(.cannotDecodeContentData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
                normalizedRequest.httpBody = body
            }
            let (response, data) = try handler(normalizedRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
