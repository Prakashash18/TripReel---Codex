import CoreLocation
import Foundation
import Photos

protocol PhotoLibraryServing: AnyObject, Sendable {
    var onLibraryChange: (@Sendable () -> Void)? { get set }
    func fetchAllPhotos() async -> [PhotoMetadata]
    func fetchPhotos(withLocalIdentifiers identifiers: [String]) async -> [PhotoMetadata]
    func deletePhotos(withLocalIdentifiers identifiers: [String]) async throws -> Int
}

extension PhotoLibraryServing {
    func deletePhotos(withLocalIdentifiers identifiers: [String]) async throws -> Int {
        throw PhotoLibraryDeletionError.unsupported
    }
}

enum PhotoLibraryDeletionError: LocalizedError, Sendable {
    case unsupported
    case photosUnavailable(expected: Int, found: Int)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "These photos can't be deleted by TripReel."
        case let .photosUnavailable(expected, found):
            "Only \(found) of \(expected) selected photos are still available. Nothing was deleted."
        case let .rejected(message):
            message
        }
    }
}

/// Reads lightweight, value-only metadata from the part of the photo library the
/// user has made available to TripReel. Image bytes are requested separately by
/// the UI only when a thumbnail is actually needed.
final class PhotoLibraryService: NSObject, PhotoLibraryServing, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    typealias LibraryChangeHandler = @Sendable () -> Void

    private let photoLibrary: PHPhotoLibrary
    private let queue = DispatchQueue(label: "com.tripreel.photo-library-metadata", qos: .userInitiated)

    // Both values are confined to `queue`. Retaining the fetch result lets
    // PhotoKit produce incremental change details when the library changes.
    private var fullFetchResult: PHFetchResult<PHAsset>?
    private var libraryChangeHandler: LibraryChangeHandler?
    private var pendingChangeNotification: DispatchWorkItem?

    /// Called on the main queue after the set of accessible photo assets changes.
    var onLibraryChange: LibraryChangeHandler? {
        get { queue.sync { libraryChangeHandler } }
        set {
            queue.async { [weak self] in
                self?.libraryChangeHandler = newValue
            }
        }
    }

    init(photoLibrary: PHPhotoLibrary = .shared()) {
        self.photoLibrary = photoLibrary
        super.init()
        photoLibrary.register(self)
    }

    deinit {
        photoLibrary.unregisterChangeObserver(self)
    }

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Fetches every non-hidden image visible under the current full or
    /// limited-library authorization, including burst and synced sources.
    func fetchAllPhotos() async -> [PhotoMetadata] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }

                let result = PHAsset.fetchAssets(with: .image, options: Self.fetchOptions())
                self.fullFetchResult = result
                continuation.resume(returning: Self.metadata(from: result))
            }
        }
    }

    /// Fetches the accessible assets matching the supplied PhotoKit local
    /// identifiers. Missing or no-longer-authorized identifiers are ignored.
    func fetchPhotos(withLocalIdentifiers identifiers: [String]) async -> [PhotoMetadata] {
        guard !identifiers.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            queue.async {
                let uniqueIdentifiers = Array(Set(identifiers))
                let result = PHAsset.fetchAssets(
                    withLocalIdentifiers: uniqueIdentifiers,
                    options: Self.fetchOptions()
                )
                continuation.resume(returning: Self.metadata(from: result))
            }
        }
    }

    /// Requests one atomic deletion from Apple Photos. PhotoKit presents its own
    /// system confirmation before committing this change.
    func deletePhotos(withLocalIdentifiers identifiers: [String]) async throws -> Int {
        let uniqueIdentifiers = Array(Set(identifiers))
        guard !uniqueIdentifiers.isEmpty else { return 0 }

        let assets: [PHAsset] = await withCheckedContinuation { continuation in
            queue.async {
                let result = PHAsset.fetchAssets(
                    withLocalIdentifiers: uniqueIdentifiers,
                    options: nil
                )
                var values: [PHAsset] = []
                values.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in values.append(asset) }
                continuation.resume(returning: values)
            }
        }

        guard assets.count == uniqueIdentifiers.count else {
            throw PhotoLibraryDeletionError.photosUnavailable(
                expected: uniqueIdentifiers.count,
                found: assets.count
            )
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            photoLibrary.performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    let message = error?.localizedDescription
                        ?? "Apple Photos did not approve the deletion. Nothing was deleted."
                    continuation.resume(throwing: PhotoLibraryDeletionError.rejected(message))
                }
            }
        }
        return uniqueIdentifiers.count
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        queue.async { [weak self] in
            guard let self else { return }

            guard let currentResult = self.fullFetchResult,
                  let details = changeInstance.changeDetails(for: currentResult) else {
                return
            }
            self.fullFetchResult = details.fetchResultAfterChanges

            // iCloud and burst reconciliation can emit a short run of change
            // callbacks. Collapse them into one regroup request instead of
            // queueing a full-library scan for every callback.
            self.pendingChangeNotification?.cancel()
            let notification = DispatchWorkItem { [weak self] in
                guard let handler = self?.libraryChangeHandler else { return }
                DispatchQueue.main.async(execute: handler)
            }
            self.pendingChangeNotification = notification
            self.queue.asyncAfter(
                deadline: .now() + .milliseconds(450),
                execute: notification
            )
        }
    }

    private static func fetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = true
        options.includeAssetSourceTypes = [
            .typeUserLibrary,
            .typeCloudShared,
            .typeiTunesSynced
        ]
        options.wantsIncrementalChangeDetails = true
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return options
    }

    private static func metadata(from result: PHFetchResult<PHAsset>) -> [PhotoMetadata] {
        var photos: [PhotoMetadata] = []
        photos.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            let coordinate = validCoordinate(from: asset.location)
            photos.append(
                PhotoMetadata(
                    id: asset.localIdentifier,
                    creationDate: asset.creationDate,
                    coordinate: coordinate,
                    // Resolving PHAssetResource for every item makes a first
                    // scan of a large library much slower. The editor creates a
                    // stable display label and loads bytes only for visible IDs.
                    filename: "",
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot)
                )
            )
        }

        // PhotoKit applies the creation-date sort descriptor, and this second
        // value-type sort makes nil dates and ties deterministic for tests and
        // downstream grouping.
        return photos.sorted { lhs, rhs in
            switch (lhs.creationDate, rhs.creationDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.id < rhs.id
            }
        }
    }

    private static func validCoordinate(from location: CLLocation?) -> PhotoCoordinate? {
        guard let rawCoordinate = location?.coordinate,
              CLLocationCoordinate2DIsValid(rawCoordinate) else {
            return nil
        }

        return PhotoCoordinate(
            latitude: rawCoordinate.latitude,
            longitude: rawCoordinate.longitude
        )
    }

}

enum TripPlaceLabelStyle: Hashable, Sendable {
    case destination
    case nearby
}

struct TripPlacemarkComponents: Sendable {
    let areasOfInterest: [String]
    let name: String?
    let thoroughfare: String?
    let subLocality: String?
    let locality: String?
    let subAdministrativeArea: String?
    let administrativeArea: String?
    let country: String?
    let isoCountryCode: String?
    let inlandWater: String?
    let ocean: String?

    init(
        areasOfInterest: [String] = [],
        name: String? = nil,
        thoroughfare: String? = nil,
        subLocality: String? = nil,
        locality: String? = nil,
        subAdministrativeArea: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        isoCountryCode: String? = nil,
        inlandWater: String? = nil,
        ocean: String? = nil
    ) {
        self.areasOfInterest = areasOfInterest
        self.name = name
        self.thoroughfare = thoroughfare
        self.subLocality = subLocality
        self.locality = locality
        self.subAdministrativeArea = subAdministrativeArea
        self.administrativeArea = administrativeArea
        self.country = country
        self.isoCountryCode = isoCountryCode
        self.inlandWater = inlandWater
        self.ocean = ocean
    }
}

enum TripPlaceLabelFormatter {
    static func displayName(
        for placemark: TripPlacemarkComponents,
        style: TripPlaceLabelStyle
    ) -> String? {
        switch style {
        case .destination:
            return destinationName(for: placemark)
        case .nearby:
            return nearbyName(for: placemark) ?? destinationName(for: placemark)
        }
    }

    private static func destinationName(for placemark: TripPlacemarkComponents) -> String? {
        let localName = firstNonempty(
            placemark.locality,
            placemark.subLocality,
            placemark.subAdministrativeArea
        )
        let administrativeName = firstNonempty(placemark.administrativeArea)
        let countryCode = placemark.isoCountryCode?.uppercased()
        // Apple commonly returns a ward in Vietnam and an administrative
        // district (for example “Mueang Chiang Mai District”) in Thailand.
        // For a trip-level label, the province/city is the name people expect.
        let locality: String? = {
            switch countryCode {
            case "TH", "VN":
                return simplifiedAdministrativeName(administrativeName)
                    ?? simplifiedAdministrativeName(localName)
            default:
                return simplifiedAdministrativeName(localName)
            }
        }()

        let region: String?
        switch countryCode {
        case "US", "CA", "AU":
            region = firstNonempty(placemark.administrativeArea, placemark.country)
        default:
            region = firstNonempty(placemark.country, placemark.administrativeArea)
        }

        if let locality, let region, !samePlace(locality, region) {
            return "\(locality), \(region)"
        }
        return locality
            ?? region
            ?? firstNonempty(placemark.name, placemark.inlandWater, placemark.ocean)
    }

    /// Nearby cards should answer “where around here?” rather than repeating a
    /// city-state or country. Prefer a landmark, then neighborhood or street,
    /// with one concise piece of city context.
    private static func nearbyName(for placemark: TripPlacemarkComponents) -> String? {
        let city = firstNonempty(
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea
        )
        let neighborhood = firstNonempty(placemark.subLocality)
        let landmark = placemark.areasOfInterest
            .compactMap(cleaned)
            .first { candidate in
                !samePlace(candidate, neighborhood) && !samePlace(candidate, city)
            }
        let namedFallback = cleaned(placemark.name).flatMap { candidate in
            candidate.first?.isNumber == true ? nil : candidate
        }
        let primary = firstNonempty(
            landmark,
            neighborhood,
            placemark.thoroughfare,
            namedFallback
        )
        guard let primary else { return nil }

        let context: String?
        if landmark != nil {
            context = firstDistinct(neighborhood, city, from: primary)
        } else {
            context = firstDistinct(city, from: primary)
        }
        return context.map { "\(primary), \($0)" } ?? primary
    }

    private static func firstDistinct(
        _ values: String? ...,
        from reference: String
    ) -> String? {
        values.lazy.compactMap(cleaned).first { !samePlace($0, reference) }
    }

    private static func firstNonempty(_ values: String?...) -> String? {
        values.lazy.compactMap(cleaned).first
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func simplifiedAdministrativeName(_ value: String?) -> String? {
        guard var result = cleaned(value) else { return nil }
        if result.range(of: "Mueang ", options: [.anchored, .caseInsensitive]) != nil {
            result = String(result.dropFirst("Mueang ".count))
        }
        for suffix in [" Metropolitan District", " Municipality", " Province", " District"] {
            if result.range(of: suffix, options: [.anchored, .backwards, .caseInsensitive]) != nil {
                result = String(result.dropLast(suffix.count))
            }
        }
        return cleaned(result)
    }

    private static func samePlace(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = cleaned(lhs), let rhs = cleaned(rhs) else { return false }
        return lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            == rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

/// Serializes Core Location reverse-geocoding and caches nearby lookups. One
/// lookup per detected collection is sufficient; callers pass its centroid.
actor TripPlaceResolver {
    private struct CacheKey: Hashable {
        let latitudeUnits: Int
        let longitudeUnits: Int
        let style: TripPlaceLabelStyle

        init(_ coordinate: PhotoCoordinate, style: TripPlaceLabelStyle) {
            // Destination names can share a roughly 1 km cache cell. Nearby
            // landmarks and neighborhoods use a roughly 100 m cell.
            let scale = style == .nearby ? 1_000.0 : 100.0
            latitudeUnits = Int((coordinate.latitude * scale).rounded())
            longitudeUnits = Int((coordinate.longitude * scale).rounded())
            self.style = style
        }
    }

    private let geocoder = CLGeocoder()
    private var cache: [CacheKey: String] = [:]

    func placeName(
        for coordinate: PhotoCoordinate,
        style: TripPlaceLabelStyle = .destination
    ) async -> String? {
        let rawCoordinate = CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        guard CLLocationCoordinate2DIsValid(rawCoordinate) else { return nil }

        let key = CacheKey(coordinate, style: style)
        if let cachedName = cache[key] {
            return cachedName
        }

        do {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            guard let placemark = try await geocoder.reverseGeocodeLocation(location).first,
                  let name = TripPlaceLabelFormatter.displayName(
                    for: TripPlacemarkComponents(
                        areasOfInterest: placemark.areasOfInterest ?? [],
                        name: placemark.name,
                        thoroughfare: placemark.thoroughfare,
                        subLocality: placemark.subLocality,
                        locality: placemark.locality,
                        subAdministrativeArea: placemark.subAdministrativeArea,
                        administrativeArea: placemark.administrativeArea,
                        country: placemark.country,
                        isoCountryCode: placemark.isoCountryCode,
                        inlandWater: placemark.inlandWater,
                        ocean: placemark.ocean
                    ),
                    style: style
                  ) else {
                return nil
            }

            cache[key] = name
            return name
        } catch {
            // Connectivity and service errors are deliberately not cached so a
            // later refresh can resolve the same trip successfully.
            return nil
        }
    }

}
