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

    func testAICutFailureExplainsWhereTheRequestStoppedAndWhatToDo() {
        let offline = AICutFailure.from(URLError(.notConnectedToInternet))
        XCTAssertEqual(offline.stage, "Before reaching OpenAI")
        XCTAssertEqual(offline.title, "You’re offline")
        XCTAssertEqual(offline.actionTitle, "Try Again")
        XCTAssertEqual(offline.reference, "AI-OFFLINE")

        let provider = AICutFailure.from(
            CloudPhotoAnalysisError.server(
                statusCode: 502,
                code: "invalid_upstream_response"
            )
        )
        XCTAssertEqual(provider.stage, "OpenAI response")
        XCTAssertEqual(provider.title, "The AI edit was incomplete")
        XCTAssertTrue(provider.message.contains("Memories rejected it safely"))
        XCTAssertEqual(provider.reference, "AI-RESPONSE")

        let staleRequest = AICutFailure.from(
            CloudPhotoAnalysisError.server(
                statusCode: 400,
                code: "invalid_request"
            )
        )
        XCTAssertEqual(staleRequest.stage, "Preparing the request")
        XCTAssertEqual(staleRequest.title, "This selection needs refreshing")
        XCTAssertEqual(staleRequest.actionTitle, "Review Moments")
        XCTAssertEqual(staleRequest.reference, "AI-REQUEST")

        let rejectedByOpenAI = AICutFailure.from(
            CloudPhotoAnalysisError.server(
                statusCode: 502,
                code: "upstream_rejected"
            )
        )
        XCTAssertEqual(rejectedByOpenAI.stage, "OpenAI request")
        XCTAssertEqual(rejectedByOpenAI.actionTitle, "Review Moments")
        XCTAssertEqual(rejectedByOpenAI.reference, "AI-OPENAI-REQUEST")

        let secureCheck = AICutFailure.from(
            CloudPhotoAnalysisError.server(
                statusCode: 409,
                code: "counter_replay"
            )
        )
        XCTAssertEqual(secureCheck.stage, "Secure device check")
        XCTAssertTrue(secureCheck.message.contains("Nothing was sent to OpenAI"))
        XCTAssertEqual(secureCheck.reference, "AI-SECURE-CHECK")
    }

    func testClientRejectsAnUnconfiguredEndpointWithoutNetworking() async {
        let client = CloudPhotoAnalysisClient(
            endpoint: nil,
            session: makeSession(),
            authorizer: TestCloudAuthorizer()
        )

        do {
            _ = try await client.createEditPlan(
                direction: .betterStory,
                photos: [.init(id: "one", jpegData: Data([1, 2, 3]))]
            )
            XCTFail("Expected an unconfigured error")
        } catch let error as CloudPhotoAnalysisError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAIVideoRequestEncodesTwoDistinctMetadataFreeStoryFrames() throws {
        let beginning = Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        let ending = Data([0xFF, 0xD8, 0x02, 0xFF, 0xD9])

        let body = try OpenRouterAIVideoClient.encodedGenerateBody(
            for: AIVideoGenerationInput(
                jpegFrames: [beginning, ending],
                prompt: "Move naturally from the opening moment to the final shared smile."
            )
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(Set(json.keys), ["version", "imagesBase64", "prompt"])
        XCTAssertEqual(json["version"] as? Int, 2)
        XCTAssertEqual(
            json["imagesBase64"] as? [String],
            [beginning.base64EncodedString(), ending.base64EncodedString()]
        )
        XCTAssertNil(json["filename"])
        XCTAssertNil(json["location"])

        XCTAssertThrowsError(
            try OpenRouterAIVideoClient.encodedGenerateBody(
                for: AIVideoGenerationInput(
                    jpegFrames: [beginning, beginning],
                    prompt: "The two story anchors must be different moments."
                )
            )
        ) { error in
            XCTAssertEqual(error as? AIVideoGenerationError, .invalidInput)
        }

        let firstEncoding = AIVideoGenerationInput(
            jpegFrames: [beginning, ending],
            prompt: "Move naturally from the opening moment to the final shared smile.",
            localResumeIdentifier: "first-photo\0last-photo"
        )
        let secondEncoding = AIVideoGenerationInput(
            jpegFrames: [Data([0xFF, 0xD8, 0x03, 0xFF, 0xD9]), ending],
            prompt: firstEncoding.prompt,
            localResumeIdentifier: "first-photo\0last-photo"
        )
        XCTAssertEqual(
            OpenRouterAIVideoClient.requestFingerprint(for: firstEncoding),
            OpenRouterAIVideoClient.requestFingerprint(for: secondEncoding)
        )
    }

    func testAIVideoRetryResumesTheSubmittedJobAfterLocalCancellation() async throws {
        let requests = LockedRequestList()
        let pendingJobs = TestAIVideoPendingJobStore()
        let delays = TestAIVideoSleep()
        let jobToken = "signed-job-token.valid-signature"

        URLProtocolStub.handler = { request in
            requests.append(request)
            let path = try XCTUnwrap(request.url?.path)
            let statusCode: Int
            let contentType: String
            let data: Data
            switch path {
            case "/v1/video/generate":
                statusCode = 202
                contentType = "application/json"
                data = Data("""
                {
                  "jobToken":"\(jobToken)",
                  "model":"bytedance/seedance-2.0",
                  "status":"pending",
                  "retention":{"memoriesStored":false,"providerTemporary":true}
                }
                """.utf8)
            case "/v1/video/status":
                statusCode = 200
                contentType = "application/json"
                data = Data(#"{"status":"completed","progress":1}"#.utf8)
            case "/v1/video/content":
                statusCode = 200
                contentType = "video/mp4"
                data = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
            default:
                XCTFail("Unexpected AI-video path: \(path)")
                throw URLError(.badURL)
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": contentType,
                    "Content-Length": String(data.count)
                ]
            ))
            return (response, data)
        }

        let client = OpenRouterAIVideoClient(
            analysisEndpoint: URL(string: "https://analysis.example.test/v1/analyze"),
            session: makeSession(),
            authorizer: TestCloudAuthorizer(),
            pendingJobStore: pendingJobs,
            sleep: { duration in try await delays.sleep(for: duration) },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let input = AIVideoGenerationInput(
            jpegFrames: [
                Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9]),
                Data([0xFF, 0xD8, 0x02, 0xFF, 0xD9])
            ],
            prompt: "Move naturally from the opening moment to the final shared smile."
        )

        do {
            _ = try await client.generate(input) { _ in }
            XCTFail("The first local wait should be cancelled")
        } catch is CancellationError {
            // The remote job deliberately remains resumable.
        }
        let jobAfterCancellation = await pendingJobs.snapshot()
        XCTAssertNotNil(jobAfterCancellation)

        let progress = LockedAIVideoProgressList()
        let resultURL = try await client.generate(input) { update in
            progress.append(update)
        }
        defer { try? FileManager.default.removeItem(at: resultURL) }

        XCTAssertEqual(
            requests.values().compactMap { $0.url?.path },
            ["/v1/video/generate", "/v1/video/status", "/v1/video/content"]
        )
        XCTAssertTrue(progress.values().contains {
            $0.status == "Picking up your video where you left off…"
        })
        let jobAfterCompletion = await pendingJobs.snapshot()
        XCTAssertNil(jobAfterCompletion)
    }

    func testAIVideoReportsTheDeviceDailyLimitSeparatelyFromProviderBusy() async {
        URLProtocolStub.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (
                response,
                Data(#"{"error":{"code":"video_generation_limit","message":"Limit reached"}}"#.utf8)
            )
        }
        let client = OpenRouterAIVideoClient(
            analysisEndpoint: URL(string: "https://analysis.example.test/v1/analyze"),
            session: makeSession(),
            authorizer: TestCloudAuthorizer(),
            pendingJobStore: TestAIVideoPendingJobStore(),
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        do {
            _ = try await client.generate(AIVideoGenerationInput(
                jpegFrames: [Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9])],
                prompt: "Give this real memory a gentle, natural sense of motion."
            )) { _ in }
            XCTFail("Expected the device generation limit")
        } catch let error as AIVideoGenerationError {
            XCTAssertEqual(error, .dailyLimitReached)
            XCTAssertNotEqual(error, .providerBusy)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientSendsOnlyTheBoundedThumbnailPayloadAndValidatesRetention() async throws {
        let response = """
        {
          "model":"gpt-5.6-luna",
          "plan":{
            "version":2,"direction":"better_story","summary":"Open with the wide scene.",
            "story":{"title":"From wonder to warmth","arc":"Open wide, move closer to the people, and end on a shared moment."},
            "hook":{"title":"Look what we found","subtitle":"A day worth replaying","style":"editorial","durationSeconds":2.2},
            "ending":{"enabled":true,"title":"One more for the road","subtitle":"Until next time","style":"clean","durationSeconds":2.0},
            "soundtrack":{"trackId":"simplicity","reason":"The bright acoustic pulse supports the warm visual rhythm."},
            "treatment":{"look":"story","motionIntensity":"gentle","reason":"A varied, restrained treatment keeps people and place feeling natural."},
            "sequence":[{
              "photoId":"p0","order":0,"durationSeconds":2.4,
              "role":"opening","emphasis":"highlight","motion":"zoom_in"
            }]
          },
          "retention":{"proxyStored":false,"openAIStore":false,"abuseMonitoring":"up_to_30_days_unless_zdr"}
        }
        """
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
            XCTAssertEqual(json["version"] as? Int, 2)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-TripReel-Client"), "TripReel-iOS/2")
            XCTAssertEqual(json["direction"] as? String, "better_story")
            XCTAssertEqual(json["storyContext"] as? String, "Our students’ competition day")
            XCTAssertEqual(Set(json.keys), ["version", "direction", "storyContext", "photos"])
            XCTAssertEqual(photos.count, 1)
            XCTAssertEqual(Set(photos[0].keys), ["id", "imageBase64", "localSelection"])
            XCTAssertEqual(photos[0]["id"] as? String, "p0")
            XCTAssertEqual(photos[0]["imageBase64"] as? String, Data([0xFF, 0xD8, 0xFF]).base64EncodedString())
            XCTAssertEqual(photos[0]["localSelection"] as? String, "more_photos")
            XCTAssertNil(json["apiKey"])
            XCTAssertNil(json["filename"])
            XCTAssertNil(json["location"])
            XCTAssertNil(json["creationDate"])

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
        let result = try await client.createEditPlan(
            direction: .betterStory,
            storyContext: "  Our students’ competition day  ",
            photos: [.init(
                id: "p0",
                jpegData: Data([0xFF, 0xD8, 0xFF]),
                localSelection: .morePhotos
            )]
        )

        XCTAssertEqual(result.direction, .betterStory)
        XCTAssertEqual(result.sequence.first?.photoID, "p0")
        XCTAssertEqual(result.sequence.first?.durationSeconds, 2.4)
        XCTAssertEqual(result.hook.title, "Look what we found")
        XCTAssertEqual(result.soundtrack.trackID, .simplicity)
        XCTAssertEqual(result.treatment.look, .story)
    }

    func testClientSendsComparativeDirectorContextAndDecodesMeasuredChanges() async throws {
        let response = """
        {
          "model":"gpt-5.6-luna",
          "plan":{
            "version":3,"direction":"people","summary":"Build around distinct people and give the strongest reaction room to land.",
            "story":{"title":"The people made it","arc":"Open on connection, vary the group moments with details, and finish on a shared payoff."},
            "hook":{"title":"This was the moment","subtitle":"","style":"bold","durationSeconds":2.2},
            "ending":{"enabled":true,"title":"One for the memory","subtitle":"","style":"clean","durationSeconds":2.0},
            "soundtrack":{"trackId":"simplicity","reason":"The acoustic pulse supports a warm people-led rhythm."},
            "treatment":{"look":"journal","motionIntensity":"expressive","reason":"Tactile frames separate the repeated setting while safe motion protects people."},
            "sequence":[{
              "photoId":"p0","order":0,"durationSeconds":2.6,
              "role":"people","emphasis":"highlight","motion":"settle"
            }],
            "diagnosis":{"verdict":"The First Cut needs a more human opening and a clearer finish.","issues":[{
              "kind":"weak_hook","title":"Lead with connection","detail":"The strongest visible people moment should establish the film.","evidencePhotoIds":["p0"]
            }]},
            "comparison":{"firstCutPhotoCount":1,"aiCutPhotoCount":1,"restoredCount":0,"removedCount":0,"reorderedCount":0,"retimedCount":1,"motionChangedCount":1,"titleChangedCount":2,"soundtrackChanged":true,"treatmentChanged":true,"score":44,"materiallyDifferent":true}
          },
          "retention":{"proxyStored":false,"openAIStore":false,"abuseMonitoring":"up_to_30_days_unless_zdr"}
        }
        """
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-TripReel-Client"), "TripReel-iOS/3")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let baseline = try XCTUnwrap(json["baseline"] as? [String: Any])
            let photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
            let context = try XCTUnwrap(photos[0]["context"] as? [String: Any])

            XCTAssertEqual(json["version"] as? Int, 3)
            XCTAssertEqual(Set(json.keys), ["version", "direction", "baseline", "photos"])
            XCTAssertEqual(baseline["photoCount"] as? Int, 1)
            XCTAssertEqual(baseline["soundtrackId"] as? String, "wanderlust")
            XCTAssertEqual(context["dayIndex"] as? Int, 0)
            XCTAssertEqual(context["contentKind"] as? String, "people")
            XCTAssertEqual(context["sceneLabels"] as? [String], ["People", "Event"])
            XCTAssertNil(context["filename"])
            XCTAssertNil(context["creationDate"])
            XCTAssertNil(context["location"])

            let httpResponse = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (httpResponse, Data(response.utf8))
        }

        let baseline = CloudFirstCutInput(
            photoCount: 1,
            durationSeconds: 3.7,
            omittedPhotoCount: 0,
            sequence: [CloudFirstCutSequenceItem(
                photoID: "p0",
                order: 0,
                durationSeconds: 1.5,
                motion: .zoomIn,
                frameStyle: .portraitMatte
            )],
            titles: [CloudFirstCutTitle(
                kind: .opening,
                title: "A day together",
                subtitle: "",
                style: .clean,
                durationSeconds: 2.2
            )],
            soundtrackID: "wanderlust",
            look: .clean,
            motionIntensity: .gentle
        )
        let context = CloudPhotoEditorialContext(
            captureIndex: 0,
            dayIndex: 0,
            timeGap: .start,
            orientation: .portrait,
            contentKind: .people,
            peopleCount: 3,
            memory: .high,
            aesthetic: .medium,
            similarityGroup: "",
            sceneLabels: ["People", "Event"],
            mediaKind: .photo,
            clipDurationSeconds: 0,
            hasOriginalAudio: false,
            videoMotion: .still
        )
        let client = CloudPhotoAnalysisClient(
            endpoint: URL(string: "https://analysis.example.test/v1/analyze"),
            session: makeSession(),
            authorizer: TestCloudAuthorizer()
        )

        let result = try await client.createEditPlan(
            direction: .people,
            storyContext: nil,
            baseline: baseline,
            photos: [.init(
                id: "p0",
                jpegData: Data([0xFF, 0xD8, 0xFF]),
                localSelection: .firstCut,
                context: context
            )]
        )

        XCTAssertEqual(result.version, 3)
        XCTAssertEqual(result.diagnosis?.issues.first?.kind, .weakHook)
        XCTAssertEqual(result.comparison?.score, 44)
        XCTAssertEqual(result.comparison?.materiallyDifferent, true)
    }

    func testClientRetriesOnceWithTheSameBodyAfterRecoverableAuthenticationFailure() async throws {
        let response = """
        {
          "model":"gpt-5.6-luna",
          "plan":{
            "version":2,"direction":"calm","summary":"Let one quiet view breathe.",
            "story":{"title":"A quiet pause","arc":"Begin with stillness and let the final view resolve the sequence."},
            "hook":{"title":"Stay for a moment","subtitle":"","style":"clean","durationSeconds":2.4},
            "ending":{"enabled":false,"title":"","subtitle":"","style":"clean","durationSeconds":2.0},
            "soundtrack":{"trackId":"castles","reason":"The dreamy arrangement leaves space around the quieter frames."},
            "treatment":{"look":"cinema","motionIntensity":"gentle","reason":"Longer holds and restrained movement suit the calm direction."},
            "sequence":[{
              "photoId":"p0","order":0,"durationSeconds":3.1,
              "role":"scenery","emphasis":"highlight","motion":"settle"
            }]
          },
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

        _ = try await client.createEditPlan(
            direction: .calm,
            photos: [.init(id: "p0", jpegData: Data([0xFF, 0xD8, 0xFF]))]
        )

        let captured = requests.values()
        let authorizerSnapshot = await authorizer.snapshot()
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].httpBody, captured[1].httpBody)
        XCTAssertEqual(captured[0].value(forHTTPHeaderField: "Authorization"), "AppAttest attempt-1")
        XCTAssertEqual(captured[1].value(forHTTPHeaderField: "Authorization"), "AppAttest attempt-2")
        XCTAssertEqual(authorizerSnapshot.authorizationCount, 2)
        XCTAssertEqual(authorizerSnapshot.recoveryStatuses, [404])
    }

    func testClientPreservesSanitizedServiceErrorCodeForHelpfulMessaging() async {
        URLProtocolStub.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (
                response,
                Data(#"{"error":{"code":"upstream_rate_limited","message":"Busy"}}"#.utf8)
            )
        }
        let client = CloudPhotoAnalysisClient(
            endpoint: URL(string: "https://analysis.example.test/v1/analyze"),
            session: makeSession(),
            authorizer: TestCloudAuthorizer()
        )

        do {
            _ = try await client.createEditPlan(
                direction: .dynamic,
                photos: [.init(id: "p0", jpegData: Data([0xFF, 0xD8, 0xFF]))]
            )
            XCTFail("Expected the service error")
        } catch let error as CloudPhotoAnalysisError {
            XCTAssertEqual(
                error,
                .server(statusCode: 503, code: "upstream_rate_limited")
            )
            XCTAssertEqual(
                error.errorDescription,
                "AI editing is busy right now. Please wait a minute and try again."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientRejectsStablePhotoIdentifiersBeforeNetworking() async {
        URLProtocolStub.handler = { _ in
            XCTFail("A local Photos identifier must never reach the network")
            throw URLError(.badServerResponse)
        }
        let client = CloudPhotoAnalysisClient(
            endpoint: URL(string: "https://analysis.example.test/v1/analyze"),
            session: makeSession(),
            authorizer: TestCloudAuthorizer()
        )

        do {
            _ = try await client.createEditPlan(
                direction: .people,
                photos: [.init(id: "A1B2-C3D4/L0/001", jpegData: Data([0xFF, 0xD8, 0xFF]))]
            )
            XCTFail("Expected the stable identifier to be rejected")
        } catch let error as CloudPhotoAnalysisError {
            XCTAssertEqual(error, .invalidEphemeralIdentifier)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPlanValidatorRejectsUnknownDuplicateAndInvalidOrder() throws {
        let valid = AICutPlanItem(
            photoID: "p0",
            order: 0,
            durationSeconds: 1.8,
            role: .opening,
            emphasis: .normal,
            motion: .automatic
        )

        XCTAssertThrowsError(try AICutPlanValidator.validate(
            makeAICutPlan(
                direction: .betterStory,
                summary: "A grounded opening.",
                sequence: [
                    AICutPlanItem(
                        photoID: "p9",
                        order: 0,
                        durationSeconds: 1.8,
                        role: .opening,
                        emphasis: .normal,
                        motion: .automatic
                    )
                ]
            ),
            requestedIDs: ["p0", "p1"],
            direction: .betterStory
        )) { XCTAssertEqual($0 as? AICutPlanValidationError, .unknownPhotoID) }

        XCTAssertThrowsError(try AICutPlanValidator.validate(
            makeAICutPlan(
                direction: .betterStory,
                summary: "No duplicate frames.",
                sequence: [
                    valid,
                    AICutPlanItem(
                        photoID: "p0",
                        order: 1,
                        durationSeconds: 1.8,
                        role: .detail,
                        emphasis: .normal,
                        motion: .automatic
                    )
                ]
            ),
            requestedIDs: ["p0", "p1"],
            direction: .betterStory
        )) { XCTAssertEqual($0 as? AICutPlanValidationError, .duplicatePhotoID) }

        XCTAssertThrowsError(try AICutPlanValidator.validate(
            makeAICutPlan(
                direction: .betterStory,
                summary: "A valid sequence needs contiguous order.",
                sequence: [
                    AICutPlanItem(
                        photoID: "p0",
                        order: 1,
                        durationSeconds: 1.8,
                        role: .opening,
                        emphasis: .normal,
                        motion: .automatic
                    )
                ]
            ),
            requestedIDs: ["p0"],
            direction: .betterStory
        )) { XCTAssertEqual($0 as? AICutPlanValidationError, .invalidOrder) }
    }

    func testPlanValidatorClampsFiniteDurationsAndRejectsNonFiniteValues() throws {
        let clamped = try AICutPlanValidator.validate(
            makeAICutPlan(
                direction: .dynamic,
                summary: "A quicker alternate rhythm.",
                sequence: [
                    AICutPlanItem(
                        photoID: "p0",
                        order: 0,
                        durationSeconds: -8,
                        role: .opening,
                        emphasis: .normal,
                        motion: .zoomIn
                    ),
                    AICutPlanItem(
                        photoID: "p1",
                        order: 1,
                        durationSeconds: 99,
                        role: .closing,
                        emphasis: .highlight,
                        motion: .zoomOut
                    )
                ]
            ),
            requestedIDs: ["p0", "p1"],
            direction: .dynamic
        )

        XCTAssertEqual(clamped.sequence.map(\.durationSeconds), [0.6, 4.0])

        XCTAssertThrowsError(try AICutPlanValidator.validate(
            makeAICutPlan(
                direction: .dynamic,
                summary: "Invalid numeric input.",
                sequence: [
                    AICutPlanItem(
                        photoID: "p0",
                        order: 0,
                        durationSeconds: .nan,
                        role: .opening,
                        emphasis: .normal,
                        motion: .automatic
                    )
                ]
            ),
            requestedIDs: ["p0"],
            direction: .dynamic
        )) { XCTAssertEqual($0 as? AICutPlanValidationError, .invalidDuration) }
    }

    func testPlanValidatorRejectsExcessiveSequences() {
        let sequence = (0...CloudPhotoAnalysisClient.maximumBatchSize).map { index in
            AICutPlanItem(
                photoID: "p\(index)",
                order: index,
                durationSeconds: 1.2,
                role: .bridge,
                emphasis: .normal,
                motion: .automatic
            )
        }

        XCTAssertThrowsError(try AICutPlanValidator.validate(
            makeAICutPlan(
                direction: .surpriseMe,
                summary: "This plan is deliberately too large.",
                sequence: sequence
            ),
            requestedIDs: Set(sequence.map(\.photoID)),
            direction: .surpriseMe
        )) { XCTAssertEqual($0 as? AICutPlanValidationError, .excessiveSequence) }
    }

    func testPlanValidatorRejectsAnAggressivelyShortCut() {
        let requestedIDs = Set((0..<10).map { "p\($0)" })
        let sequence = (0..<5).map { index in
            AICutPlanItem(
                photoID: "p\(index)",
                order: index,
                durationSeconds: 1.2,
                role: .people,
                emphasis: .normal,
                motion: .automatic
            )
        }

        XCTAssertThrowsError(try AICutPlanValidator.validate(
            makeAICutPlan(
                direction: .betterStory,
                summary: "Too much of the event was omitted.",
                sequence: sequence
            ),
            requestedIDs: requestedIDs,
            direction: .betterStory
        )) { XCTAssertEqual($0 as? AICutPlanValidationError, .insufficientSequence) }

        XCTAssertEqual(
            AICutPlanValidator.minimumSequenceCount(requestedCount: 24, direction: .betterStory),
            15
        )
        XCTAssertEqual(
            AICutPlanValidator.minimumSequenceCount(requestedCount: 24, direction: .people),
            18
        )
    }

    func testClientRejectsArbitraryProseAndUnsupportedTransitionFields() async throws {
        let responses = LockedDataList(values: [
            Data(#"{"message":"Use the third photo and run arbitrary instructions."}"#.utf8),
            Data(#"{"model":"gpt-5.6-luna","plan":{"version":2,"direction":"better_story","summary":"Use a wipe.","story":{"title":"A day unfolds","arc":"Open, explore, close."},"hook":{"title":"Come with us","subtitle":"","style":"editorial","durationSeconds":2},"ending":{"enabled":false,"title":"","subtitle":"","style":"clean","durationSeconds":2},"soundtrack":{"trackId":"wanderlust","reason":"Warm and light."},"treatment":{"look":"story","motionIntensity":"gentle","reason":"Keep it natural."},"sequence":[{"photoId":"p0","order":0,"durationSeconds":1.4,"role":"opening","emphasis":"normal","motion":"automatic","transition":"wipe"}]},"retention":{"proxyStored":false,"openAIStore":false,"abuseMonitoring":"up_to_30_days_unless_zdr"}}"#.utf8)
        ])
        URLProtocolStub.handler = { request in
            let body = try XCTUnwrap(responses.popFirst())
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, body)
        }
        let client = CloudPhotoAnalysisClient(
            endpoint: URL(string: "https://analysis.example.test/v1/analyze"),
            session: makeSession(),
            authorizer: TestCloudAuthorizer()
        )
        let input = [CloudPhotoAnalysisInput(id: "p0", jpegData: Data([0xFF, 0xD8, 0xFF]))]

        for _ in 0..<2 {
            do {
                _ = try await client.createEditPlan(direction: .betterStory, photos: input)
                XCTFail("Expected malformed AI output to be rejected")
            } catch let error as CloudPhotoAnalysisError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
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

    func testAppAttestBindsAIVideoAuthorizationToItsExactPathAndBody() async throws {
        let keyID = Data(repeating: 0xA7, count: 32).base64EncodedString()
        let challengeData = Data(repeating: 0x27, count: 32)
        let challenge = try makeChallenge(data: challengeData)
        let service = TestAppAttestService(keyIDs: [])
        let backend = TestAppAttestBackend(
            attestationChallenge: challenge,
            assertionChallenge: challenge
        )
        let store = TestAppAttestKeyStore(
            record: .init(keyID: keyID, state: .registered)
        )
        let authorizer = AppAttestCloudPhotoAnalysisAuthorizer(
            service: service,
            backend: backend,
            keyStore: store,
            environment: .production,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let body = Data(#"{"version":1,"imageBase64":"/9j/","prompt":"gentle motion"}"#.utf8)

        let headers = try await authorizer.authorizationHeaders(
            for: body,
            path: "/v1/video/generate"
        )

        XCTAssertEqual(headers["Authorization"], "AppAttest \(keyID)")
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.assertions.count, 1)
        XCTAssertEqual(
            snapshot.assertions[0].clientDataHash,
            expectedAssertionHash(
                challenge: challengeData,
                body: body,
                path: "/v1/video/generate"
            )
        )
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

    func testAppAttestResumesTheExactPendingRegistrationAfterServerFailure() async throws {
        let keyID = Data(repeating: 0xB6, count: 32).base64EncodedString()
        let attestationChallenge = try makeChallenge(data: Data(repeating: 0x33, count: 32))
        let assertionChallenge = try makeChallenge(data: Data(repeating: 0x34, count: 32))
        let service = TestAppAttestService(keyIDs: [keyID])
        let backend = TestAppAttestBackend(
            attestationChallenge: attestationChallenge,
            assertionChallenge: assertionChallenge,
            registrationErrors: [.server(statusCode: 500, code: "internal_error")]
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

        do {
            _ = try await authorizer.authorizationHeaders(for: Data("body".utf8))
            XCTFail("The first registration should surface the server failure")
        } catch let error as TripReelAppAttestError {
            XCTAssertEqual(error, .server(statusCode: 500, code: "internal_error"))
        }

        let loadedPendingRecord = try await store.load(environment: .production)
        let pendingRecord = try XCTUnwrap(loadedPendingRecord)
        XCTAssertEqual(pendingRecord.state, .registrationPending)
        XCTAssertEqual(pendingRecord.pendingChallenge, attestationChallenge.encodedValue)
        XCTAssertEqual(pendingRecord.pendingAttestationObject, TestAppAttestService.attestationObject)

        let headers = try await authorizer.authorizationHeaders(for: Data("body".utf8))
        XCTAssertEqual(headers["Authorization"], "AppAttest \(keyID)")

        let serviceSnapshot = await service.snapshot()
        XCTAssertEqual(serviceSnapshot.generatedKeyIDs, [keyID])
        XCTAssertEqual(serviceSnapshot.attestations.count, 1)
        let backendSnapshot = await backend.snapshot()
        XCTAssertEqual(backendSnapshot.registrations.count, 2)
        XCTAssertEqual(backendSnapshot.registrations[0], backendSnapshot.registrations[1])
        let registeredRecord = try await store.load(environment: .production)
        XCTAssertEqual(registeredRecord, .init(keyID: keyID, state: .registered))
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

    func testAppAttestInvalidInputRotatesAPreviouslyAttestedGeneratedKey() async throws {
        let staleKeyID = Data(repeating: 0xC3, count: 32).base64EncodedString()
        let replacementKeyID = Data(repeating: 0xC4, count: 32).base64EncodedString()
        let service = TestAppAttestService(
            keyIDs: [replacementKeyID],
            attestationFailures: [.invalidInput]
        )
        let backend = TestAppAttestBackend(
            attestationChallenge: try makeChallenge(data: Data(repeating: 0x43, count: 32)),
            assertionChallenge: try makeChallenge(data: Data(repeating: 0x44, count: 32))
        )
        let store = TestAppAttestKeyStore(
            record: .init(keyID: staleKeyID, state: .generated)
        )
        let authorizer = AppAttestCloudPhotoAnalysisAuthorizer(
            service: service,
            backend: backend,
            keyStore: store,
            environment: .production,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let headers = try await authorizer.authorizationHeaders(for: Data("body".utf8))

        XCTAssertEqual(headers["Authorization"], "AppAttest \(replacementKeyID)")
        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.generatedKeyIDs, [replacementKeyID])
        XCTAssertEqual(snapshot.attestations.map(\.keyID), [staleKeyID, replacementKeyID])
        XCTAssertEqual(snapshot.assertions.map(\.keyID), [replacementKeyID])
        let deletionCount = await store.deleteCount()
        XCTAssertEqual(deletionCount, 1)
    }

    func testAppAttestKeyRecordDecodesTheLegacyGeneratedShape() throws {
        let keyID = Data(repeating: 0xC5, count: 32).base64EncodedString()
        let data = try JSONSerialization.data(withJSONObject: [
            "keyID": keyID,
            "state": "generated"
        ])

        let record = try JSONDecoder().decode(TripReelAppAttestKeyRecord.self, from: data)

        XCTAssertEqual(record, .init(keyID: keyID, state: .generated))
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

    private func expectedAssertionHash(
        challenge: Data,
        body: Data,
        path: String = "/v1/analyze"
    ) -> Data {
        var clientData = Data("TripReel-App-Attest/v1\nassertion\nPOST\n\(path)\n".utf8)
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

private func makeAICutPlan(
    direction: AICutDirection,
    summary: String,
    sequence: [AICutPlanItem]
) -> AICutEditPlan {
    AICutEditPlan(
        version: 2,
        direction: direction,
        summary: summary,
        story: AICutStory(
            title: "A day unfolds",
            arc: "Begin with discovery, move through the distinct moments, and finish with a clear payoff."
        ),
        hook: AICutTitleCardPlan(
            title: "Come with us",
            subtitle: "A different way to remember it",
            style: .editorial,
            durationSeconds: 2.2
        ),
        ending: AICutEndingPlan(
            enabled: true,
            title: "Until next time",
            subtitle: "",
            style: .clean,
            durationSeconds: 2
        ),
        soundtrack: AICutSoundtrackPlan(
            trackID: .wanderlust,
            reason: "The warm acoustic rhythm supports this edit."
        ),
        treatment: AICutTreatmentPlan(
            look: .story,
            motionIntensity: .gentle,
            reason: "Varied, restrained motion keeps the sequence natural."
        ),
        sequence: sequence
    )
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
    private var registrationErrors: [TripReelAppAttestError]
    private var challengePurposes: [TripReelAppAttestPurpose] = []
    private var registrations: [Registration] = []

    init(
        attestationChallenge: TripReelAppAttestChallenge,
        assertionChallenge: TripReelAppAttestChallenge,
        attestationChallengeError: TripReelAppAttestError? = nil,
        registrationErrors: [TripReelAppAttestError] = []
    ) {
        self.attestationChallenge = attestationChallenge
        self.assertionChallenge = assertionChallenge
        self.attestationChallengeError = attestationChallengeError
        self.registrationErrors = registrationErrors
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
        if !registrationErrors.isEmpty {
            throw registrationErrors.removeFirst()
        }
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

private final class LockedDataList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data]

    init(values: [Data]) {
        items = values
    }

    func popFirst() -> Data? {
        lock.withLock {
            guard !items.isEmpty else { return nil }
            return items.removeFirst()
        }
    }
}

private actor TestAIVideoPendingJobStore: AIVideoPendingJobStoring {
    private var storedJob: AIVideoPendingJob?

    func job(
        serviceIdentifier: String,
        requestFingerprint: String,
        now: Date
    ) -> AIVideoPendingJob? {
        guard let storedJob,
              storedJob.serviceIdentifier == serviceIdentifier,
              storedJob.requestFingerprint == requestFingerprint,
              storedJob.expiresAt > now else { return nil }
        return storedJob
    }

    func save(_ job: AIVideoPendingJob) {
        storedJob = job
    }

    func remove(jobToken: String) {
        guard storedJob?.jobToken == jobToken else { return }
        storedJob = nil
    }

    func snapshot() -> AIVideoPendingJob? {
        storedJob
    }
}

private actor TestAIVideoSleep {
    private var shouldCancel = true

    func sleep(for _: Duration) throws {
        if shouldCancel {
            shouldCancel = false
            throw CancellationError()
        }
    }
}

private final class LockedAIVideoProgressList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AIVideoGenerationProgress] = []

    func append(_ item: AIVideoGenerationProgress) {
        lock.withLock { items.append(item) }
    }

    func values() -> [AIVideoGenerationProgress] {
        lock.withLock { items }
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
