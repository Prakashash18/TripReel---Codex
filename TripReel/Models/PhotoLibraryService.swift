import CoreLocation
import Foundation
import Photos

protocol PhotoLibraryServing: AnyObject, Sendable {
    var onLibraryChange: (@Sendable () -> Void)? { get set }
    func fetchAllPhotos() async -> [PhotoMetadata]
    func fetchPhotos(withLocalIdentifiers identifiers: [String]) async -> [PhotoMetadata]
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

/// Serializes Core Location reverse-geocoding and caches nearby lookups. One
/// lookup per detected trip is sufficient; callers should pass the trip centroid.
actor TripPlaceResolver {
    private struct CacheKey: Hashable {
        let latitudeHundredths: Int
        let longitudeHundredths: Int

        init(_ coordinate: PhotoCoordinate) {
            latitudeHundredths = Int((coordinate.latitude * 100).rounded())
            longitudeHundredths = Int((coordinate.longitude * 100).rounded())
        }
    }

    private let geocoder = CLGeocoder()
    private var cache: [CacheKey: String] = [:]

    func placeName(for coordinate: PhotoCoordinate) async -> String? {
        let rawCoordinate = CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        guard CLLocationCoordinate2DIsValid(rawCoordinate) else { return nil }

        let key = CacheKey(coordinate)
        if let cachedName = cache[key] {
            return cachedName
        }

        do {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            guard let placemark = try await geocoder.reverseGeocodeLocation(location).first,
                  let name = Self.displayName(for: placemark) else {
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

    private static func displayName(for placemark: CLPlacemark) -> String? {
        let locality = firstNonempty(
            placemark.locality,
            placemark.subLocality,
            placemark.subAdministrativeArea
        )

        let region: String?
        switch placemark.isoCountryCode?.uppercased() {
        case "US", "CA", "AU":
            region = firstNonempty(placemark.administrativeArea, placemark.country)
        default:
            region = firstNonempty(placemark.country, placemark.administrativeArea)
        }

        if let locality, let region, locality.caseInsensitiveCompare(region) != .orderedSame {
            return "\(locality), \(region)"
        }

        return locality
            ?? region
            ?? firstNonempty(placemark.name, placemark.inlandWater, placemark.ocean)
    }

    private static func firstNonempty(_ values: String?...) -> String? {
        values.lazy
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .first
    }
}
