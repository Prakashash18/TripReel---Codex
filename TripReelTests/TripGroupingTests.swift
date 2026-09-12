import XCTest
@testable import TripReel

final class TripGroupingTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testMinimumCountDurationAndCalendarDayRequirements() {
        let qualifying = photos(prefix: "q", count: 15, hours: 20, coordinate: .singapore)
        XCTAssertEqual(TripDetector.detect(in: qualifying, calendar: utcCalendar).count, 1)

        XCTAssertTrue(TripDetector.detect(in: Array(qualifying.dropLast()), calendar: utcCalendar).isEmpty)
        XCTAssertTrue(TripDetector.detect(
            in: photos(prefix: "short", count: 15, hours: 4, coordinate: .singapore),
            calendar: utcCalendar
        ).isEmpty)
    }

    func testVideoMomentsParticipateInMemoryGroupingAndKeepDuration() throws {
        var input = photos(prefix: "mixed", count: 14, hours: 20, coordinate: .singapore)
        input.append(PhotoMetadata(
            id: "mixed-video",
            creationDate: origin.addingTimeInterval(10 * 60 * 60),
            coordinate: .singapore,
            filename: "moment.mov",
            pixelWidth: 1_080,
            pixelHeight: 1_920,
            isScreenshot: false,
            mediaKind: .video,
            durationSeconds: 12.4
        ))

        let trip = try XCTUnwrap(TripDetector.detect(in: input, calendar: utcCalendar).first)
        let video = try XCTUnwrap(trip.photos.first { $0.id == "mixed-video" })

        XCTAssertEqual(trip.photoCount, 15)
        XCTAssertEqual(video.mediaKind, .video)
        XCTAssertEqual(video.durationSeconds, 12.4, accuracy: 0.001)
    }

    func testShuffledInputProducesStableMembershipAndOrdering() {
        let older = photos(prefix: "old", count: 18, hours: 24, coordinate: .singapore)
        let newerStart = origin.addingTimeInterval(10 * 24 * 60 * 60)
        let newer = photos(prefix: "new", count: 18, hours: 24, coordinate: .tokyo, start: newerStart)
        let ordered = older + newer
        let shuffled = Array(ordered.reversed())

        let first = TripDetector.detect(in: ordered, calendar: utcCalendar)
        let second = TripDetector.detect(in: shuffled, calendar: utcCalendar)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), ["new-000", "old-000"])
        XCTAssertEqual(first[0].photos.map(\.id), newer.map(\.id))
    }

    func testTemporalGapOverFortyEightHoursSplitsTrips() {
        let first = photos(prefix: "a", count: 15, hours: 20, coordinate: .singapore)
        let secondStart = first.last!.creationDate!.addingTimeInterval((48 * 60 * 60) + 1)
        let second = photos(prefix: "b", count: 15, hours: 20, coordinate: .singapore, start: secondStart)

        let trips = TripDetector.detect(in: first + second, calendar: utcCalendar)

        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(Set(trips.map(\.photoCount)), [15])
    }

    func testDistantDestinationsSplitInsideOneTemporalWindow() {
        let singapore = photos(prefix: "sg", count: 15, hours: 20, coordinate: .singapore)
        let tokyoStart = singapore.last!.creationDate!.addingTimeInterval(60 * 60)
        let tokyo = photos(prefix: "jp", count: 15, hours: 20, coordinate: .tokyo, start: tokyoStart)

        let trips = TripDetector.detect(in: singapore + tokyo, calendar: utcCalendar)

        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips.map(\.photoCount), [15, 15])
        XCTAssertTrue(trips.allSatisfy { $0.centroid != nil })
    }

    func testNoLocationPhotosAttachToNearestDestinationAndScreenshotsRemain() throws {
        let singapore = photos(prefix: "sg", count: 15, hours: 20, coordinate: .singapore)
        let tokyoStart = singapore.last!.creationDate!.addingTimeInterval(2 * 60 * 60)
        let tokyo = photos(prefix: "jp", count: 15, hours: 20, coordinate: .tokyo, start: tokyoStart)
        let nearSingapore = photo(
            id: "sg-screen",
            date: singapore.last!.creationDate!.addingTimeInterval(5 * 60),
            coordinate: nil,
            isScreenshot: true
        )
        let nearTokyo = photo(
            id: "jp-noloc",
            date: tokyo.first!.creationDate!.addingTimeInterval(5 * 60),
            coordinate: nil
        )

        let trips = TripDetector.detect(
            in: singapore + [nearSingapore, nearTokyo] + tokyo,
            calendar: utcCalendar
        )

        XCTAssertEqual(trips.count, 2)
        let screenshotTrip = try XCTUnwrap(trips.first { $0.photos.contains(where: { $0.id == "sg-screen" }) })
        XCTAssertTrue(screenshotTrip.photos.first(where: { $0.id == "sg-screen" })!.isScreenshot)
        XCTAssertTrue(trips.contains { $0.photos.contains(where: { $0.id == "jp-noloc" }) })
    }

    func testScreenshotsDoNotMakeAnUndersizedCollectionQualifyAsATrip() {
        let cameraPhotos = photos(prefix: "camera", count: 14, hours: 20, coordinate: .singapore)
        let screenshot = photo(
            id: "order-screen",
            date: cameraPhotos[7].creationDate!,
            coordinate: nil,
            isScreenshot: true
        )

        XCTAssertTrue(
            TripDetector.detect(in: cameraPhotos + [screenshot], calendar: utcCalendar).isEmpty
        )
    }

    func testSingleBogusCoordinateDoesNotSplitOrMoveCentroid() throws {
        var singapore = photos(prefix: "sg", count: 20, hours: 24, coordinate: .singapore)
        singapore[10] = photo(
            id: singapore[10].id,
            date: singapore[10].creationDate!,
            coordinate: .paris
        )

        let trip = try XCTUnwrap(TripDetector.detect(in: singapore, calendar: utcCalendar).first)

        XCTAssertEqual(trip.photoCount, 20)
        XCTAssertEqual(trip.centroid!.latitude, PhotoCoordinate.singapore.latitude, accuracy: 0.01)
        XCTAssertEqual(trip.centroid!.longitude, PhotoCoordinate.singapore.longitude, accuracy: 0.01)
    }

    func testAllNoLocationPhotosFormTimeOnlyTrip() throws {
        let input = photos(prefix: "none", count: 15, hours: 20, coordinate: nil)
        let trip = try XCTUnwrap(TripDetector.detect(in: input, calendar: utcCalendar).first)

        XCTAssertNil(trip.centroid)
        XCTAssertEqual(trip.coverID, "none-007")
    }

    func testSparseLocationMetadataKeepsTheWholeContinuousTrip() throws {
        var input = photos(prefix: "sparse", count: 15, hours: 7 * 24, coordinate: nil)
        input[0] = photo(
            id: input[0].id,
            date: input[0].creationDate!,
            coordinate: .singapore
        )

        let trip = try XCTUnwrap(TripDetector.detect(in: input, calendar: utcCalendar).first)

        XCTAssertEqual(trip.photoCount, 15)
        XCTAssertEqual(Set(trip.photos.map(\.id)), Set(input.map(\.id)))
        XCTAssertNotNil(trip.centroid)
    }

    func testCentroidHandlesTheInternationalDateLine() throws {
        var input: [PhotoMetadata] = []
        for index in 0..<15 {
            let longitude = index.isMultiple(of: 2) ? 179.5 : -179.5
            input.append(photo(
                id: String(format: "date-line-%03d", index),
                date: origin.addingTimeInterval(Double(index) * 20 * 60 * 60 / 14),
                coordinate: PhotoCoordinate(latitude: 10, longitude: longitude)
            ))
        }

        let trip = try XCTUnwrap(TripDetector.detect(in: input, calendar: utcCalendar).first)

        XCTAssertGreaterThan(abs(trip.centroid!.longitude), 179)
        XCTAssertEqual(trip.startDate, input.first!.creationDate)
        XCTAssertEqual(trip.endDate, input.last!.creationDate)
    }

    func testMissingDatesAndSubthresholdDistantGroupAreNotMerged() {
        let valid = photos(prefix: "valid", count: 15, hours: 20, coordinate: .singapore)
        let tokyoStart = valid.last!.creationDate!.addingTimeInterval(60 * 60)
        let tooSmall = photos(prefix: "small", count: 10, hours: 20, coordinate: .tokyo, start: tokyoStart)
        let missingDate = PhotoMetadata(
            id: "missing-date",
            creationDate: nil,
            coordinate: .singapore,
            filename: "missing-date.jpg",
            pixelWidth: 100,
            pixelHeight: 100,
            isScreenshot: false
        )

        let trips = TripDetector.detect(in: valid + tooSmall + [missingDate], calendar: utcCalendar)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].photos.map(\.id), valid.map(\.id))
    }

    func testCandidateLongerThanFortyFiveDaysIsRejectedRatherThanSplit() {
        let input = photos(
            prefix: "long-screenshots",
            count: 60,
            hours: 46 * 24,
            coordinate: nil,
            isScreenshot: true
        )

        let trips = TripDetector.detect(in: input, calendar: utcCalendar)

        XCTAssertTrue(trips.isEmpty)
    }

    func testCandidateAtFortyFiveDayMaximumIsRetained() throws {
        let input = photos(
            prefix: "long-trip",
            count: 46,
            hours: 45 * 24,
            coordinate: .tokyo
        )

        let trip = try XCTUnwrap(TripDetector.detect(in: input, calendar: utcCalendar).first)

        XCTAssertEqual(trip.photoCount, 46)
        XCTAssertEqual(trip.endDate.timeIntervalSince(trip.startDate), 45 * 24 * 60 * 60, accuracy: 0.001)
    }

    func testHabitualPlaceAcrossEightWeeksAndNinetyDaysIsSuppressed() {
        let homeVisit = photos(prefix: "home", count: 15, hours: 20, coordinate: .singapore)
        let travelStart = origin.addingTimeInterval(4 * 24 * 60 * 60)
        let travel = photos(prefix: "travel", count: 15, hours: 20, coordinate: .tokyo, start: travelStart)
        let evidenceDays = [13, 26, 39, 52, 65, 78, 90]
        let homeEvidence = evidenceDays.map { day in
            photo(
                id: String(format: "home-evidence-%03d", day),
                date: origin.addingTimeInterval(Double(day) * 24 * 60 * 60),
                coordinate: .singapore
            )
        }

        let trips = TripDetector.detect(
            in: Array((homeVisit + travel + homeEvidence).reversed()),
            calendar: utcCalendar
        )

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].photos.map(\.id), travel.map(\.id))
    }

    func testContinuousHomeTravelHomeLibraryReturnsOnlyTravel() {
        let homeBefore = photos(
            prefix: "home-before",
            count: 45,
            hours: 44 * 24,
            coordinate: .singapore
        )
        let travelStart = origin.addingTimeInterval(45 * 24 * 60 * 60)
        let travel = photos(
            prefix: "travel",
            count: 15,
            hours: 7 * 24,
            coordinate: .tokyo,
            start: travelStart
        )
        let homeAfterStart = origin.addingTimeInterval(53 * 24 * 60 * 60)
        let homeAfter = photos(
            prefix: "home-after",
            count: 48,
            hours: 47 * 24,
            coordinate: .singapore,
            start: homeAfterStart
        )

        let trips = TripDetector.detect(
            in: homeBefore + travel + homeAfter,
            calendar: utcCalendar
        )

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].photos.map(\.id), travel.map(\.id))
    }

    func testSevenWeekEvidenceDoesNotInferHabitualPlace() {
        let homeVisit = photos(prefix: "home", count: 15, hours: 20, coordinate: .singapore)
        let evidenceDays = [15, 30, 45, 60, 75, 90]
        let homeEvidence = evidenceDays.map { day in
            photo(
                id: String(format: "home-evidence-%03d", day),
                date: origin.addingTimeInterval(Double(day) * 24 * 60 * 60),
                coordinate: .singapore
            )
        }

        let trips = TripDetector.detect(in: homeVisit + homeEvidence, calendar: utcCalendar)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].photos.map(\.id), homeVisit.map(\.id))
    }

    func testEightWeekEvidenceUnderNinetyDaysDoesNotInferHabitualPlace() {
        let homeVisit = photos(prefix: "home", count: 15, hours: 20, coordinate: .singapore)
        let evidenceDays = [12, 25, 38, 51, 64, 77, 89]
        let homeEvidence = evidenceDays.map { day in
            photo(
                id: String(format: "home-evidence-%03d", day),
                date: origin.addingTimeInterval(Double(day) * 24 * 60 * 60),
                coordinate: .singapore
            )
        }

        let trips = TripDetector.detect(in: homeVisit + homeEvidence, calendar: utcCalendar)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].photos.map(\.id), homeVisit.map(\.id))
    }

    func testNearbyDetectorFindsCompactOutingNearHabitualPlace() throws {
        let evidence = habitualEvidence()
        let outingStart = utcCalendar.startOfDay(for: origin)
            .addingTimeInterval((105 * 24 + 10) * 60 * 60)
        let outing = photos(
            prefix: "outing",
            count: 8,
            hours: 5,
            coordinate: PhotoCoordinate(latitude: 1.29, longitude: 103.85),
            start: outingStart
        )

        let event = try XCTUnwrap(
            NearbyEventDetector.detect(in: evidence + outing, calendar: utcCalendar).first
        )

        XCTAssertEqual(event.photos.map(\.id), outing.map(\.id))
        XCTAssertTrue(event.id.hasPrefix("nearby-"))
    }

    func testNearbyDetectorRejectsSmallFarAndScreenshotOnlyOutings() {
        let evidence = habitualEvidence()
        let outingStart = utcCalendar.startOfDay(for: origin)
            .addingTimeInterval((105 * 24 + 10) * 60 * 60)
        let tooSmall = photos(
            prefix: "small-outing",
            count: 5,
            hours: 3,
            coordinate: .singapore,
            start: outingStart
        )
        let far = photos(
            prefix: "far-outing",
            count: 8,
            hours: 3,
            coordinate: .tokyo,
            start: outingStart.addingTimeInterval(24 * 60 * 60)
        )
        let screenshots = photos(
            prefix: "screens",
            count: 12,
            hours: 3,
            coordinate: .singapore,
            start: outingStart.addingTimeInterval(2 * 24 * 60 * 60),
            isScreenshot: true
        )

        let events = NearbyEventDetector.detect(
            in: evidence + tooSmall + far + screenshots,
            calendar: utcCalendar
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testNearbyDetectorRequiresHabitualPlaceEvidence() {
        let outing = photos(prefix: "outing", count: 9, hours: 4, coordinate: .singapore)

        XCTAssertTrue(
            NearbyEventDetector.detect(in: outing, calendar: utcCalendar).isEmpty
        )
    }

    func testNearbyDetectorKeepsYishunHomePhotosOutOfMarinaBayOuting() throws {
        let evidence = [0, 14, 28, 42, 56, 70, 84, 91].map { day in
            photo(
                id: String(format: "yishun-evidence-%03d", day),
                date: origin.addingTimeInterval(Double(day) * 24 * 60 * 60),
                coordinate: .yishun
            )
        }
        let start = utcCalendar.startOfDay(for: origin)
            .addingTimeInterval((105 * 24 + 9) * 60 * 60)
        let homeBefore = photos(
            prefix: "home-before",
            count: 4,
            hours: 0.5,
            coordinate: .yishun,
            start: start
        )
        let marinaBay = photos(
            prefix: "marina",
            count: 9,
            hours: 2,
            coordinate: .marinaBay,
            start: start.addingTimeInterval(75 * 60)
        )
        let homeAfter = photos(
            prefix: "home-after",
            count: 4,
            hours: 0.5,
            coordinate: .yishun,
            start: start.addingTimeInterval(3.5 * 60 * 60)
        )

        let events = NearbyEventDetector.detect(
            in: evidence + homeBefore + marinaBay + homeAfter,
            calendar: utcCalendar
        )
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(Set(event.photos.map(\.id)), Set(marinaBay.map(\.id)))
        XCTAssertFalse(event.photos.contains { $0.id.hasPrefix("home-") })
        XCTAssertLessThan(
            TripDetector.distanceKilometers(try XCTUnwrap(event.centroid), .marinaBay),
            0.5
        )
    }

    func testNearbyDetectorDoesNotAttachUnlocatedHomeFramesOutsideTheOuting() throws {
        let evidence = [0, 14, 28, 42, 56, 70, 84, 91].map { day in
            photo(
                id: String(format: "yishun-evidence-%03d", day),
                date: origin.addingTimeInterval(Double(day) * 24 * 60 * 60),
                coordinate: .yishun
            )
        }
        let start = utcCalendar.startOfDay(for: origin)
            .addingTimeInterval((105 * 24 + 9) * 60 * 60)
        let unlocatedAtHome = photos(
            prefix: "unlocated-home",
            count: 5,
            hours: 0.5,
            coordinate: nil,
            start: start
        )
        let marinaBay = photos(
            prefix: "marina",
            count: 9,
            hours: 2,
            coordinate: .marinaBay,
            start: start.addingTimeInterval(75 * 60)
        )

        let event = try XCTUnwrap(
            NearbyEventDetector.detect(
                in: evidence + unlocatedAtHome + marinaBay,
                calendar: utcCalendar
            ).first
        )

        XCTAssertEqual(Set(event.photos.map(\.id)), Set(marinaBay.map(\.id)))
        XCTAssertFalse(event.photos.contains { $0.id.hasPrefix("unlocated-home") })
    }

    private func habitualEvidence() -> [PhotoMetadata] {
        [0, 14, 28, 42, 56, 70, 84, 91].map { day in
            photo(
                id: String(format: "habitual-%03d", day),
                date: origin.addingTimeInterval(Double(day) * 24 * 60 * 60),
                coordinate: .singapore
            )
        }
    }

    private func photos(
        prefix: String,
        count: Int,
        hours: Double,
        coordinate: PhotoCoordinate?,
        start: Date? = nil,
        isScreenshot: Bool = false
    ) -> [PhotoMetadata] {
        let start = start ?? origin
        return (0..<count).map { index in
            let fraction = count == 1 ? 0 : Double(index) / Double(count - 1)
            return photo(
                id: String(format: "%@-%03d", prefix, index),
                date: start.addingTimeInterval(fraction * hours * 60 * 60),
                coordinate: coordinate,
                isScreenshot: isScreenshot
            )
        }
    }

    private func photo(
        id: String,
        date: Date,
        coordinate: PhotoCoordinate?,
        isScreenshot: Bool = false
    ) -> PhotoMetadata {
        PhotoMetadata(
            id: id,
            creationDate: date,
            coordinate: coordinate,
            filename: "\(id).jpg",
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            isScreenshot: isScreenshot
        )
    }
}

final class VideoClipHeuristicsTests: XCTestCase {
    func testPeopleMomentGetsAReadableClipAroundTheBestFrame() throws {
        let descriptor = try XCTUnwrap(VideoClipHeuristics.choose(
            sourceDurationSeconds: 12,
            frames: [
                frame(time: 2, memory: 0.58, aesthetic: 0.56, people: 0, motion: 0.06),
                frame(time: 7, memory: 0.91, aesthetic: 0.86, people: 3, motion: 0.14),
                frame(time: 10, memory: 0.62, aesthetic: 0.60, people: 0, motion: 0.09),
            ],
            hasOriginalAudio: true
        ))

        XCTAssertEqual(descriptor.durationSeconds, 3.8, accuracy: 0.001)
        XCTAssertEqual(descriptor.startSeconds, 5.404, accuracy: 0.001)
        XCTAssertTrue(descriptor.hasOriginalAudio)
    }

    func testUsefulActionGetsAQuickerClipWhileViolentMotionIsPenalized() throws {
        let descriptor = try XCTUnwrap(VideoClipHeuristics.choose(
            sourceDurationSeconds: 9,
            frames: [
                frame(time: 2, memory: 0.62, aesthetic: 0.62, people: 0, motion: 0.82),
                frame(time: 5, memory: 0.78, aesthetic: 0.75, people: 0, motion: 0.26),
            ],
            hasOriginalAudio: false
        ))

        XCTAssertEqual(descriptor.durationSeconds, 2.8, accuracy: 0.001)
        XCTAssertEqual(descriptor.startSeconds, 3.824, accuracy: 0.001)
        XCTAssertEqual(descriptor.motionScore, 0.26, accuracy: 0.001)
    }

    func testTooShortVideoDoesNotEnterTheCut() {
        XCTAssertNil(VideoClipHeuristics.choose(
            sourceDurationSeconds: 0.6,
            frames: [frame(time: 0.3, memory: 0.9, aesthetic: 0.9, people: 1, motion: 0.1)],
            hasOriginalAudio: true
        ))
    }

    private func frame(
        time: Double,
        memory: Double,
        aesthetic: Double,
        people: Int,
        motion: Double
    ) -> VideoFrameEditorialScore {
        VideoFrameEditorialScore(
            timeSeconds: time,
            memoryScore: memory,
            aestheticScore: aesthetic,
            peopleCount: people,
            utilityProbability: 0.04,
            documentProbability: 0.02,
            motionFromPrevious: motion
        )
    }
}

private extension PhotoCoordinate {
    static let singapore = PhotoCoordinate(latitude: 1.3521, longitude: 103.8198)
    static let yishun = PhotoCoordinate(latitude: 1.4304, longitude: 103.8354)
    static let marinaBay = PhotoCoordinate(latitude: 1.2834, longitude: 103.8607)
    static let tokyo = PhotoCoordinate(latitude: 35.6762, longitude: 139.6503)
    static let paris = PhotoCoordinate(latitude: 48.8566, longitude: 2.3522)
}
