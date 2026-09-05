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
        let singapore = photos(prefix: "sg", count: 14, hours: 20, coordinate: .singapore)
        let tokyoStart = singapore.last!.creationDate!.addingTimeInterval(2 * 60 * 60)
        let tokyo = photos(prefix: "jp", count: 14, hours: 20, coordinate: .tokyo, start: tokyoStart)
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

private extension PhotoCoordinate {
    static let singapore = PhotoCoordinate(latitude: 1.3521, longitude: 103.8198)
    static let tokyo = PhotoCoordinate(latitude: 35.6762, longitude: 139.6503)
    static let paris = PhotoCoordinate(latitude: 48.8566, longitude: 2.3522)
}
