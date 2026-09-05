import CoreGraphics
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
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
