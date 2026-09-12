import Foundation

struct PhotoCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

enum LibraryMediaKind: String, Hashable, Sendable {
    case photo
    case video
}

struct PhotoMetadata: Identifiable, Hashable, Sendable {
    let id: String
    let creationDate: Date?
    let coordinate: PhotoCoordinate?
    let filename: String
    let pixelWidth: Int
    let pixelHeight: Int
    let isScreenshot: Bool
    let mediaKind: LibraryMediaKind
    let durationSeconds: Double

    init(
        id: String,
        creationDate: Date?,
        coordinate: PhotoCoordinate?,
        filename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        isScreenshot: Bool,
        mediaKind: LibraryMediaKind = .photo,
        durationSeconds: Double = 0
    ) {
        self.id = id
        self.creationDate = creationDate
        self.coordinate = coordinate
        self.filename = filename
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
        self.isScreenshot = isScreenshot && mediaKind == .photo
        self.mediaKind = mediaKind
        self.durationSeconds = mediaKind == .video
            ? max(0, durationSeconds.isFinite ? durationSeconds : 0)
            : 0
    }
}

struct DetectedTrip: Identifiable, Hashable, Sendable {
    let id: String
    let photos: [PhotoMetadata]
    let startDate: Date
    let endDate: Date
    let centroid: PhotoCoordinate?
    let coverID: String

    var photoCount: Int { photos.count }
}

/// Groups photo-library metadata into stable, chronological destination visits.
///
/// The detector deliberately works only with metadata. Screenshots never make a
/// collection qualify as a trip, but screenshots captured during an already-
/// detected trip remain attached so Smart Selection can show (and restore) them.
/// Assets without a creation date cannot be grouped automatically.
enum TripDetector {
    private static let minimumPhotoCount = 15
    private static let minimumDuration: TimeInterval = 18 * 60 * 60
    private static let maximumDuration: TimeInterval = 45 * 24 * 60 * 60
    private static let minimumCalendarDays = 2
    private static let maximumInterPhotoGap: TimeInterval = 48 * 60 * 60
    private static let destinationRadiusKilometers = 120.0
    private static let habitualPlaceRadiusKilometers = 30.0
    private static let habitualPlaceMinimumWeeks = 8
    private static let habitualPlaceMinimumSpan: TimeInterval = 90 * 24 * 60 * 60

    static func detect(
        in photos: [PhotoMetadata],
        calendar: Calendar = .current,
        shouldCancel: @Sendable () -> Bool = { false }
    ) -> [DetectedTrip] {
        guard !shouldCancel() else { return [] }
        let normalized = normalizedUniquePhotos(photos)
            .filter { $0.creationDate != nil }
            .sorted(by: chronologicalOrder)

        guard !normalized.isEmpty, !shouldCancel() else { return [] }
        let screenshotPhotos = normalized.filter(\.isScreenshot)
        let groupingPhotos = normalized.filter { !$0.isScreenshot }
        guard !groupingPhotos.isEmpty else { return [] }

        let habitualPlaces = habitualPlaceCentroids(
            in: groupingPhotos,
            calendar: calendar,
            shouldCancel: shouldCancel
        )
        guard !shouldCancel() else { return [] }
        var trips: [DetectedTrip] = []
        for bucket in temporalBuckets(from: groupingPhotos) {
            guard !shouldCancel() else { return [] }
            trips.append(contentsOf: detectedTrips(
                in: bucket,
                calendar: calendar,
                shouldCancel: shouldCancel
            ))
        }

        let filteredTrips = trips
            .filter { trip in
                guard let centroid = trip.centroid else { return true }
                return !habitualPlaces.contains {
                    distanceKilometers(centroid, $0) <= habitualPlaceRadiusKilometers
                }
            }
            .sorted { lhs, rhs in
            if lhs.endDate != rhs.endDate { return lhs.endDate > rhs.endDate }
            if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
            return lhs.id < rhs.id
        }
        return attachScreenshots(screenshotPhotos, to: filteredTrips)
    }

    private static func attachScreenshots(
        _ screenshots: [PhotoMetadata],
        to trips: [DetectedTrip]
    ) -> [DetectedTrip] {
        guard !screenshots.isEmpty, !trips.isEmpty else { return trips }
        var attachments = Array(repeating: [PhotoMetadata](), count: trips.count)

        for screenshot in screenshots {
            guard let date = screenshot.creationDate else { continue }
            let candidate = trips.enumerated()
                .compactMap { index, trip -> (index: Int, distance: TimeInterval)? in
                    let lowerBound = trip.startDate.addingTimeInterval(-maximumInterPhotoGap)
                    let upperBound = trip.endDate.addingTimeInterval(maximumInterPhotoGap)
                    guard (lowerBound...upperBound).contains(date) else { return nil }
                    let distance: TimeInterval
                    if date < trip.startDate {
                        distance = trip.startDate.timeIntervalSince(date)
                    } else if date > trip.endDate {
                        distance = date.timeIntervalSince(trip.endDate)
                    } else {
                        distance = 0
                    }
                    return (index, distance)
                }
                .min {
                    if $0.distance != $1.distance { return $0.distance < $1.distance }
                    if trips[$0.index].startDate != trips[$1.index].startDate {
                        return trips[$0.index].startDate < trips[$1.index].startDate
                    }
                    return trips[$0.index].id < trips[$1.index].id
                }

            if let candidate {
                attachments[candidate.index].append(screenshot)
            }
        }

        return trips.enumerated().map { index, trip in
            guard !attachments[index].isEmpty else { return trip }
            return DetectedTrip(
                id: trip.id,
                photos: (trip.photos + attachments[index]).sorted(by: chronologicalOrder),
                startDate: trip.startDate,
                endDate: trip.endDate,
                centroid: trip.centroid,
                coverID: trip.coverID
            )
        }
    }

    static func normalizedUniquePhotos(_ photos: [PhotoMetadata]) -> [PhotoMetadata] {
        let canonical = photos
            .map(sanitized)
            .sorted(by: canonicalOrder)

        var seen = Set<String>()
        return canonical.filter { seen.insert($0.id).inserted }
    }

    private static func sanitized(_ photo: PhotoMetadata) -> PhotoMetadata {
        PhotoMetadata(
            id: photo.id,
            creationDate: photo.creationDate,
            coordinate: validated(photo.coordinate),
            filename: photo.filename,
            pixelWidth: photo.pixelWidth,
            pixelHeight: photo.pixelHeight,
            isScreenshot: photo.isScreenshot,
            mediaKind: photo.mediaKind,
            durationSeconds: photo.durationSeconds
        )
    }

    private static func validated(_ coordinate: PhotoCoordinate?) -> PhotoCoordinate? {
        guard let coordinate,
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90.0...90.0).contains(coordinate.latitude),
              (-180.0...180.0).contains(coordinate.longitude) else {
            return nil
        }
        return coordinate
    }

    /// Total ordering used only to select a deterministic value if duplicate IDs
    /// are supplied. PHAsset local identifiers are unique in normal operation.
    private static func canonicalOrder(_ lhs: PhotoMetadata, _ rhs: PhotoMetadata) -> Bool {
        if lhs.id != rhs.id { return lhs.id < rhs.id }

        switch (lhs.creationDate, rhs.creationDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }

        switch (lhs.coordinate, rhs.coordinate) {
        case let (left?, right?):
            if left.latitude != right.latitude { return left.latitude < right.latitude }
            if left.longitude != right.longitude { return left.longitude < right.longitude }
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }

        if lhs.filename != rhs.filename { return lhs.filename < rhs.filename }
        if lhs.pixelWidth != rhs.pixelWidth { return lhs.pixelWidth < rhs.pixelWidth }
        if lhs.pixelHeight != rhs.pixelHeight { return lhs.pixelHeight < rhs.pixelHeight }
        if lhs.mediaKind != rhs.mediaKind { return lhs.mediaKind.rawValue < rhs.mediaKind.rawValue }
        if lhs.durationSeconds != rhs.durationSeconds { return lhs.durationSeconds < rhs.durationSeconds }
        return lhs.isScreenshot == false && rhs.isScreenshot == true
    }

    static func chronologicalOrder(_ lhs: PhotoMetadata, _ rhs: PhotoMetadata) -> Bool {
        guard let leftDate = lhs.creationDate, let rightDate = rhs.creationDate else {
            return lhs.creationDate != nil
        }
        if leftDate != rightDate { return leftDate < rightDate }
        return lhs.id < rhs.id
    }

    private static func temporalBuckets(from photos: [PhotoMetadata]) -> [[PhotoMetadata]] {
        guard let first = photos.first else { return [] }

        var result: [[PhotoMetadata]] = []
        var current = [first]

        for photo in photos.dropFirst() {
            let previousDate = current[current.count - 1].creationDate!
            let date = photo.creationDate!
            if date.timeIntervalSince(previousDate) > maximumInterPhotoGap {
                result.append(current)
                current = [photo]
            } else {
                current.append(photo)
            }
        }
        result.append(current)
        return result
    }

    private static func detectedTrips(
        in bucket: [PhotoMetadata],
        calendar: Calendar,
        shouldCancel: @Sendable () -> Bool
    ) -> [DetectedTrip] {
        guard !shouldCancel() else { return [] }
        let located = bucket.filter { $0.coordinate != nil }
        guard !located.isEmpty else {
            return makeTrip(from: bucket, reliableCoordinates: [], calendar: calendar).map { [$0] } ?? []
        }

        let anchorSegments = destinationSegments(from: located)
        let anchorTimeline = anchorSegments.enumerated()
            .flatMap { segmentIndex, segment in
                segment.anchors.compactMap { anchor in
                    anchor.creationDate.map {
                        DatedAnchor(date: $0, segmentIndex: segmentIndex)
                    }
                }
            }
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.segmentIndex < $1.segmentIndex
            }
        var assignments = Array(repeating: [PhotoMetadata](), count: anchorSegments.count)
        var directlyAssigned = Set<String>()

        for (segmentIndex, segment) in anchorSegments.enumerated() {
            assignments[segmentIndex].append(contentsOf: segment.anchors)
            directlyAssigned.formUnion(segment.anchors.map(\.id))
        }

        var unattached: [PhotoMetadata] = []
        for (offset, photo) in bucket.enumerated() where !directlyAssigned.contains(photo.id) {
            if offset.isMultiple(of: 256), shouldCancel() { return [] }
            guard let date = photo.creationDate,
                  let segmentIndex = nearestSegment(
                    to: date,
                    in: anchorTimeline
                  ) else {
                unattached.append(photo)
                continue
            }
            assignments[segmentIndex].append(photo)
        }

        var result: [DetectedTrip] = []
        for (index, photos) in assignments.enumerated() {
            let reliableIDs = Set(anchorSegments[index].anchors.map(\.id))
            let reliable = photos.filter { reliableIDs.contains($0.id) }
            if let trip = makeTrip(from: photos, reliableCoordinates: reliable, calendar: calendar) {
                result.append(trip)
            }
        }

        // A long, unlocated run that cannot be attached safely is still useful as
        // a time-only trip. It is never merged across the 48-hour temporal break.
        for unlocatedBucket in temporalBuckets(from: unattached.sorted(by: chronologicalOrder)) {
            if let trip = makeTrip(from: unlocatedBucket, reliableCoordinates: [], calendar: calendar) {
                result.append(trip)
            }
        }

        return result
    }

    private struct AnchorSegment {
        var anchors: [PhotoMetadata]
        private var x: Double
        private var y: Double
        private var z: Double

        init(_ anchor: PhotoMetadata) {
            anchors = [anchor]
            let vector = unitVector(for: anchor.coordinate!)
            x = vector.x
            y = vector.y
            z = vector.z
        }

        init(_ anchors: [PhotoMetadata]) {
            self.init(anchors[0])
            for anchor in anchors.dropFirst() {
                add(anchor)
            }
        }

        mutating func add(_ anchor: PhotoMetadata) {
            anchors.append(anchor)
            let vector = TripDetector.unitVector(for: anchor.coordinate!)
            x += vector.x
            y += vector.y
            z += vector.z
        }

        var centroid: PhotoCoordinate {
            TripDetector.coordinate(x: x, y: y, z: z) ?? anchors[0].coordinate!
        }
    }

    /// A far-away point becomes a destination only after a second nearby anchor.
    /// This prevents a single corrupt GPS value from splitting an otherwise sound trip.
    private static func destinationSegments(from anchors: [PhotoMetadata]) -> [AnchorSegment] {
        guard let first = anchors.first else { return [] }

        var completed: [AnchorSegment] = []
        var active = AnchorSegment(first)
        var pending: PhotoMetadata?

        for anchor in anchors.dropFirst() {
            if distanceKilometers(active.centroid, anchor.coordinate!) <= destinationRadiusKilometers {
                pending = nil
                active.add(anchor)
                continue
            }

            if let pendingAnchor = pending,
               distanceKilometers(pendingAnchor.coordinate!, anchor.coordinate!) <= destinationRadiusKilometers {
                completed.append(active)
                active = AnchorSegment([pendingAnchor, anchor])
                pending = nil
            } else {
                pending = anchor
            }
        }

        completed.append(active)
        return completed
    }

    private struct DatedAnchor {
        let date: Date
        let segmentIndex: Int
    }

    private static func nearestSegment(to date: Date, in anchors: [DatedAnchor]) -> Int? {
        guard !anchors.isEmpty else { return nil }
        var low = 0
        var high = anchors.count
        while low < high {
            let middle = (low + high) / 2
            if anchors[middle].date < date {
                low = middle + 1
            } else {
                high = middle
            }
        }

        var candidates: [DatedAnchor] = []
        if low < anchors.count {
            candidates.append(anchors[low])
        }
        if low > 0 {
            candidates.append(anchors[low - 1])
        }

        return candidates.min { lhs, rhs in
            let leftDistance = abs(lhs.date.timeIntervalSince(date))
            let rightDistance = abs(rhs.date.timeIntervalSince(date))
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return lhs.segmentIndex < rhs.segmentIndex
        }?.segmentIndex
    }

    private static func makeTrip(
        from input: [PhotoMetadata],
        reliableCoordinates: [PhotoMetadata],
        calendar: Calendar
    ) -> DetectedTrip? {
        let photos = input.sorted(by: chronologicalOrder)
        guard photos.count >= minimumPhotoCount,
              let startDate = photos.first?.creationDate,
              let endDate = photos.last?.creationDate,
              endDate.timeIntervalSince(startDate) >= minimumDuration,
              endDate.timeIntervalSince(startDate) <= maximumDuration else {
            return nil
        }

        let distinctDays = Set(photos.compactMap { photo in
            photo.creationDate.map(calendar.startOfDay(for:))
        })
        guard distinctDays.count >= minimumCalendarDays else { return nil }

        let centroid = sphericalCentroid(of: reliableCoordinates)
        let coverID: String
        if let centroid {
            coverID = reliableCoordinates.min { lhs, rhs in
                let leftDistance = distanceKilometers(lhs.coordinate!, centroid)
                let rightDistance = distanceKilometers(rhs.coordinate!, centroid)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return chronologicalOrder(lhs, rhs)
            }?.id ?? photos[(photos.count - 1) / 2].id
        } else {
            coverID = photos[(photos.count - 1) / 2].id
        }

        return DetectedTrip(
            id: photos[0].id,
            photos: photos,
            startDate: startDate,
            endDate: endDate,
            centroid: centroid,
            coverID: coverID
        )
    }

    private struct HabitualPlaceCluster {
        private(set) var earliestDate: Date
        private(set) var latestDate: Date
        private(set) var weekStarts: Set<Date>
        private var x: Double
        private var y: Double
        private var z: Double

        init(photo: PhotoMetadata, weekStart: Date) {
            let vector = TripDetector.unitVector(for: photo.coordinate!)
            earliestDate = photo.creationDate!
            latestDate = photo.creationDate!
            weekStarts = [weekStart]
            x = vector.x
            y = vector.y
            z = vector.z
        }

        mutating func add(_ photo: PhotoMetadata, weekStart: Date) {
            let date = photo.creationDate!
            earliestDate = min(earliestDate, date)
            latestDate = max(latestDate, date)
            weekStarts.insert(weekStart)

            let vector = TripDetector.unitVector(for: photo.coordinate!)
            x += vector.x
            y += vector.y
            z += vector.z
        }

        var centroid: PhotoCoordinate? {
            TripDetector.coordinate(x: x, y: y, z: z)
        }
    }

    private struct SpatialCell: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }

    /// Learns habitual places from recurrence, not photo volume. This is kept
    /// deliberately conservative: a place must recur in eight calendar weeks
    /// over at least ninety days before it can suppress a trip candidate.
    static func habitualPlaceCentroids(
        in photos: [PhotoMetadata],
        calendar: Calendar,
        shouldCancel: @Sendable () -> Bool
    ) -> [PhotoCoordinate] {
        var clusters: [HabitualPlaceCluster] = []
        var clusterIndexesByCell: [SpatialCell: [Int]] = [:]

        for (offset, photo) in photos.enumerated() {
            if offset.isMultiple(of: 256), shouldCancel() { return [] }
            guard let coordinate = photo.coordinate,
                  let date = photo.creationDate else { continue }
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)

            let photoCell = habitualCell(for: coordinate)
            var candidateIndexes = Set<Int>()
            for xOffset in -1...1 {
                for yOffset in -1...1 {
                    for zOffset in -1...1 {
                        let nearbyCell = SpatialCell(
                            x: photoCell.x + xOffset,
                            y: photoCell.y + yOffset,
                            z: photoCell.z + zOffset
                        )
                        candidateIndexes.formUnion(clusterIndexesByCell[nearbyCell] ?? [])
                    }
                }
            }

            var closestIndex: Int?
            var closestDistance = Double.greatestFiniteMagnitude
            for index in candidateIndexes.sorted() {
                let cluster = clusters[index]
                guard let centroid = cluster.centroid else { continue }
                let distance = distanceKilometers(coordinate, centroid)
                if distance <= habitualPlaceRadiusKilometers,
                   distance < closestDistance {
                    closestIndex = index
                    closestDistance = distance
                }
                // Equal distances keep the cluster created first. Input order is
                // normalized by date and asset identifier, so this remains stable.
            }

            if let closestIndex {
                let oldCell = clusters[closestIndex].centroid.map(habitualCell)
                clusters[closestIndex].add(photo, weekStart: weekStart)
                let newCell = clusters[closestIndex].centroid.map(habitualCell)
                if oldCell != newCell {
                    if let oldCell {
                        clusterIndexesByCell[oldCell]?.removeAll { $0 == closestIndex }
                    }
                    if let newCell {
                        clusterIndexesByCell[newCell, default: []].append(closestIndex)
                    }
                }
            } else {
                clusters.append(HabitualPlaceCluster(photo: photo, weekStart: weekStart))
                clusterIndexesByCell[photoCell, default: []].append(clusters.count - 1)
            }
        }

        return clusters.compactMap { cluster in
            guard cluster.weekStarts.count >= habitualPlaceMinimumWeeks,
                  cluster.latestDate.timeIntervalSince(cluster.earliestDate) >= habitualPlaceMinimumSpan else {
                return nil
            }
            return cluster.centroid
        }
        .sorted {
            if $0.latitude != $1.latitude { return $0.latitude < $1.latitude }
            return $0.longitude < $1.longitude
        }
    }

    private static func habitualCell(for coordinate: PhotoCoordinate) -> SpatialCell {
        let vector = unitVector(for: coordinate)
        let angularRadius = habitualPlaceRadiusKilometers / 6_371.0088
        let chordSize = 2 * sin(angularRadius / 2)
        return SpatialCell(
            x: Int(floor(vector.x / chordSize)),
            y: Int(floor(vector.y / chordSize)),
            z: Int(floor(vector.z / chordSize))
        )
    }

    static func sphericalCentroid(of photos: [PhotoMetadata]) -> PhotoCoordinate? {
        let located = photos.filter { $0.coordinate != nil }
        guard !located.isEmpty else { return nil }

        var x = 0.0
        var y = 0.0
        var z = 0.0
        for photo in located {
            let vector = unitVector(for: photo.coordinate!)
            x += vector.x
            y += vector.y
            z += vector.z
        }

        if let mean = coordinate(x: x, y: y, z: z) {
            return mean
        }

        // Exact antipodal inputs have no spherical mean. A deterministic medoid
        // is a useful fallback and is also a real photo coordinate.
        return located.min { lhs, rhs in
            let leftTotal = located.reduce(0.0) {
                $0 + distanceKilometers(lhs.coordinate!, $1.coordinate!)
            }
            let rightTotal = located.reduce(0.0) {
                $0 + distanceKilometers(rhs.coordinate!, $1.coordinate!)
            }
            if leftTotal != rightTotal { return leftTotal < rightTotal }
            return lhs.id < rhs.id
        }?.coordinate
    }

    static func unitVector(for coordinate: PhotoCoordinate) -> (x: Double, y: Double, z: Double) {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        return (
            cos(latitude) * cos(longitude),
            cos(latitude) * sin(longitude),
            sin(latitude)
        )
    }

    static func coordinate(x: Double, y: Double, z: Double) -> PhotoCoordinate? {
        let magnitude = sqrt((x * x) + (y * y) + (z * z))
        guard magnitude > 1e-12 else { return nil }
        return PhotoCoordinate(
            latitude: atan2(z, sqrt((x * x) + (y * y))) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    static func distanceKilometers(_ lhs: PhotoCoordinate, _ rhs: PhotoCoordinate) -> Double {
        let leftLatitude = lhs.latitude * .pi / 180
        let rightLatitude = rhs.latitude * .pi / 180
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = pow(sin(latitudeDelta / 2), 2)
            + cos(leftLatitude) * cos(rightLatitude) * pow(sin(longitudeDelta / 2), 2)
        let centralAngle = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return 6_371.0088 * centralAngle
    }
}

/// Finds compact, one-day photo outings near a place the library shows is
/// habitual. These complement multi-day travel without flooding the main trip
/// list with every ordinary day at home.
enum NearbyEventDetector {
    private static let minimumPhotoCount = 6
    private static let minimumLocatedPhotoCount = 3
    private static let maximumSessionGap: TimeInterval = 4 * 60 * 60
    private static let maximumDuration: TimeInterval = 18 * 60 * 60
    private static let maximumDistanceFromHabitualPlace = 150.0
    // Nearby cards represent one walkable place, not a whole city. Yishun and
    // Marina Bay are roughly twenty kilometres apart, so the former 25 km
    // radius could blend home photos into a city outing.
    private static let eventRadiusKilometers = 5.0
    private static let habitualBoundaryRadiusKilometers = 4.0
    private static let localHabitualRadiusKilometers = 3.0
    private static let habitualMinimumWeeks = 8
    private static let habitualMinimumSpan: TimeInterval = 90 * 24 * 60 * 60
    private static let unlocatedEdgeAllowance: TimeInterval = 30 * 60
    private static let maximumResults = 20

    static func detect(
        in photos: [PhotoMetadata],
        calendar: Calendar = .current,
        shouldCancel: @Sendable () -> Bool = { false }
    ) -> [DetectedTrip] {
        guard !shouldCancel() else { return [] }
        let candidates = TripDetector.normalizedUniquePhotos(photos)
            .filter { $0.creationDate != nil && !$0.isScreenshot }
            .sorted(by: TripDetector.chronologicalOrder)
        guard !candidates.isEmpty else { return [] }

        let habitualPlaces = localHabitualPlaceCentroids(
            in: candidates,
            calendar: calendar,
            shouldCancel: shouldCancel
        )
        guard !habitualPlaces.isEmpty, !shouldCancel() else { return [] }

        var events: [DetectedTrip] = []
        for session in sessions(from: candidates, calendar: calendar) {
            guard !shouldCancel() else { return [] }
            let localEvents = spatialEvents(
                from: session,
                habitualPlaces: habitualPlaces,
                shouldCancel: shouldCancel
            )
            events.append(contentsOf: localEvents)
        }

        return Array(events.sorted {
            if $0.endDate != $1.endDate { return $0.endDate > $1.endDate }
            return $0.id < $1.id
        }.prefix(maximumResults))
    }

    private static func sessions(
        from photos: [PhotoMetadata],
        calendar: Calendar
    ) -> [[PhotoMetadata]] {
        guard let first = photos.first else { return [] }
        var sessions: [[PhotoMetadata]] = []
        var current = [first]

        for photo in photos.dropFirst() {
            let previous = current[current.count - 1]
            let previousDate = previous.creationDate!
            let date = photo.creationDate!
            if !calendar.isDate(previousDate, inSameDayAs: date)
                || date.timeIntervalSince(previousDate) > maximumSessionGap {
                sessions.append(current)
                current = [photo]
            } else {
                current.append(photo)
            }
        }
        sessions.append(current)
        return sessions
    }

    private struct EventCluster {
        var anchors: [PhotoMetadata]

        var centroid: PhotoCoordinate {
            TripDetector.sphericalCentroid(of: anchors) ?? anchors[0].coordinate!
        }

        mutating func add(_ photo: PhotoMetadata) {
            anchors.append(photo)
        }
    }

    private struct HabitualCluster {
        private(set) var earliestDate: Date
        private(set) var latestDate: Date
        private(set) var weekStarts: Set<Date>
        private var x: Double
        private var y: Double
        private var z: Double

        init(photo: PhotoMetadata, weekStart: Date) {
            let vector = TripDetector.unitVector(for: photo.coordinate!)
            earliestDate = photo.creationDate!
            latestDate = photo.creationDate!
            weekStarts = [weekStart]
            x = vector.x
            y = vector.y
            z = vector.z
        }

        mutating func add(_ photo: PhotoMetadata, weekStart: Date) {
            let vector = TripDetector.unitVector(for: photo.coordinate!)
            earliestDate = min(earliestDate, photo.creationDate!)
            latestDate = max(latestDate, photo.creationDate!)
            weekStarts.insert(weekStart)
            x += vector.x
            y += vector.y
            z += vector.z
        }

        var centroid: PhotoCoordinate {
            TripDetector.coordinate(x: x, y: y, z: z)!
        }
    }

    private struct HabitualCell: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }

    /// The multi-day trip detector intentionally learns "home region" at city
    /// scale. Nearby needs a separate neighbourhood-scale signal; otherwise a
    /// compact country/city such as Singapore collapses Yishun and Marina Bay
    /// into the same habitual centroid.
    private static func localHabitualPlaceCentroids(
        in photos: [PhotoMetadata],
        calendar: Calendar,
        shouldCancel: @Sendable () -> Bool
    ) -> [PhotoCoordinate] {
        var clusters: [HabitualCluster] = []
        var indexesByCell: [HabitualCell: [Int]] = [:]

        for (offset, photo) in photos.enumerated() {
            if offset.isMultiple(of: 256), shouldCancel() { return [] }
            guard let coordinate = photo.coordinate, let date = photo.creationDate else { continue }
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
            let cell = habitualCell(for: coordinate)
            var candidateIndexes = Set<Int>()
            for x in -1...1 {
                for y in -1...1 {
                    for z in -1...1 {
                        candidateIndexes.formUnion(indexesByCell[
                            HabitualCell(x: cell.x + x, y: cell.y + y, z: cell.z + z)
                        ] ?? [])
                    }
                }
            }

            let nearest = candidateIndexes
                .map { index in
                    (index, TripDetector.distanceKilometers(coordinate, clusters[index].centroid))
                }
                .filter { $0.1 <= localHabitualRadiusKilometers }
                .min {
                    if $0.1 != $1.1 { return $0.1 < $1.1 }
                    return $0.0 < $1.0
                }
            if let nearest {
                let oldCell = habitualCell(for: clusters[nearest.0].centroid)
                clusters[nearest.0].add(photo, weekStart: weekStart)
                let newCell = habitualCell(for: clusters[nearest.0].centroid)
                if oldCell != newCell {
                    indexesByCell[oldCell]?.removeAll { $0 == nearest.0 }
                    indexesByCell[newCell, default: []].append(nearest.0)
                }
            } else {
                clusters.append(HabitualCluster(photo: photo, weekStart: weekStart))
                indexesByCell[cell, default: []].append(clusters.count - 1)
            }
        }

        return clusters.compactMap { cluster in
            guard cluster.weekStarts.count >= habitualMinimumWeeks,
                  cluster.latestDate.timeIntervalSince(cluster.earliestDate) >= habitualMinimumSpan else {
                return nil
            }
            return cluster.centroid
        }
    }

    private static func habitualCell(for coordinate: PhotoCoordinate) -> HabitualCell {
        let vector = TripDetector.unitVector(for: coordinate)
        let angularRadius = localHabitualRadiusKilometers / 6_371.0088
        let chord = 2 * sin(angularRadius / 2)
        return HabitualCell(
            x: Int(floor(vector.x / chord)),
            y: Int(floor(vector.y / chord)),
            z: Int(floor(vector.z / chord))
        )
    }

    /// Splits a time session by actual place before adding unlocated frames.
    /// A reliable home anchor is a hard boundary; photos without GPS are only
    /// attached within the observed outing's time range (plus a small edge), so
    /// an unlocated frame taken at home does not bridge two distant places.
    private static func spatialEvents(
        from photos: [PhotoMetadata],
        habitualPlaces: [PhotoCoordinate],
        shouldCancel: @Sendable () -> Bool
    ) -> [DetectedTrip] {
        let located = photos.filter { $0.coordinate != nil }
        guard !located.isEmpty else { return [] }

        var clusters: [EventCluster] = []
        var anchorCluster: [String: Int] = [:]
        var homeAnchorDates: [Date] = []

        for (offset, photo) in located.enumerated() {
            if offset.isMultiple(of: 128), shouldCancel() { return [] }
            let coordinate = photo.coordinate!
            if habitualPlaces.contains(where: {
                TripDetector.distanceKilometers(coordinate, $0) <= habitualBoundaryRadiusKilometers
            }) {
                if let date = photo.creationDate { homeAnchorDates.append(date) }
                continue
            }

            let nearest = clusters.indices
                .map { index in
                    (index, TripDetector.distanceKilometers(coordinate, clusters[index].centroid))
                }
                .filter { $0.1 <= eventRadiusKilometers }
                .min {
                    if $0.1 != $1.1 { return $0.1 < $1.1 }
                    return $0.0 < $1.0
                }

            let clusterIndex: Int
            if let nearest {
                clusterIndex = nearest.0
                clusters[clusterIndex].add(photo)
            } else {
                clusterIndex = clusters.count
                clusters.append(EventCluster(anchors: [photo]))
            }
            anchorCluster[photo.id] = clusterIndex
        }

        guard !clusters.isEmpty else { return [] }
        var unlocatedCluster: [String: Int] = [:]
        for photo in photos where photo.coordinate == nil {
            guard let date = photo.creationDate else { continue }
            let nearestHomeDistance = homeAnchorDates.map {
                abs($0.timeIntervalSince(date))
            }.min()
            let nearest = clusters.enumerated().compactMap { index, cluster -> (Int, TimeInterval)? in
                guard let first = cluster.anchors.compactMap(\.creationDate).min(),
                      let last = cluster.anchors.compactMap(\.creationDate).max() else { return nil }
                let window = ClosedRange(
                    uncheckedBounds: (
                        lower: first.addingTimeInterval(-unlocatedEdgeAllowance),
                        upper: last.addingTimeInterval(unlocatedEdgeAllowance)
                    )
                )
                guard window.contains(date) else { return nil }
                let distance = cluster.anchors.compactMap(\.creationDate).map {
                    abs($0.timeIntervalSince(date))
                }.min() ?? .greatestFiniteMagnitude
                return (index, distance)
            }.min {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                return $0.0 < $1.0
            }
            guard let nearest,
                  nearestHomeDistance.map({ nearest.1 < $0 }) ?? true else { continue }
            unlocatedCluster[photo.id] = nearest.0
        }

        return clusters.enumerated().compactMap { index, cluster in
            guard cluster.anchors.count >= minimumLocatedPhotoCount,
                  cluster.anchors.contains(where: { $0.creationDate != nil }) else {
                return nil
            }
            let clusterIDs = Set(cluster.anchors.map(\.id))
            let members = photos.filter { photo in
                if let assigned = anchorCluster[photo.id] {
                    return assigned == index
                }
                return unlocatedCluster[photo.id] == index
            }

            return makeEvent(
                from: members,
                reliableCoordinates: cluster.anchors,
                habitualPlaces: habitualPlaces,
                preferredID: clusterIDs.sorted().first
            )
        }
    }

    private static func makeEvent(
        from photos: [PhotoMetadata],
        reliableCoordinates: [PhotoMetadata],
        habitualPlaces: [PhotoCoordinate],
        preferredID: String?
    ) -> DetectedTrip? {
        let photos = photos.sorted(by: TripDetector.chronologicalOrder)
        guard photos.count >= minimumPhotoCount,
              let startDate = photos.first?.creationDate,
              let endDate = photos.last?.creationDate,
              endDate.timeIntervalSince(startDate) <= maximumDuration else { return nil }

        guard reliableCoordinates.count >= minimumLocatedPhotoCount,
              let centroid = TripDetector.sphericalCentroid(of: reliableCoordinates),
              habitualPlaces.contains(where: {
                  TripDetector.distanceKilometers(centroid, $0) <= maximumDistanceFromHabitualPlace
              }) else { return nil }

        let cover = reliableCoordinates.min { lhs, rhs in
            let left = TripDetector.distanceKilometers(lhs.coordinate!, centroid)
            let right = TripDetector.distanceKilometers(rhs.coordinate!, centroid)
            if left != right { return left < right }
            return TripDetector.chronologicalOrder(lhs, rhs)
        } ?? photos[(photos.count - 1) / 2]

        return DetectedTrip(
            id: "nearby-\(preferredID ?? photos[0].id)",
            photos: photos,
            startDate: startDate,
            endDate: endDate,
            centroid: centroid,
            coverID: cover.id
        )
    }
}
