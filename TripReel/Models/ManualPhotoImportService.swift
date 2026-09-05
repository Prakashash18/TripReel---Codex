import CoreTransferable
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A photo copied out of the system Photos picker. Unlike a `PHAsset` local
/// identifier, the file remains readable without photo-library permission.
struct ManualImportedPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let filePath: String
    let creationDate: Date?
    let coordinate: PhotoCoordinate?
    let filename: String
    let pixelWidth: Int
    let pixelHeight: Int

    var fileURL: URL { URL(fileURLWithPath: filePath) }
}

struct ManualPhotoImportResult: Hashable, Sendable {
    let photos: [ManualImportedPhoto]
    let failureCount: Int

    var requestedCount: Int { photos.count + failureCount }
}

/// Imports picker selections one at a time so selecting many full-resolution
/// images never requires all of their bytes to be resident in memory together.
/// Each provider file is copied while the `FileRepresentation` receive closure
/// owns it; the temporary provider URL is not valid after that closure returns.
actor ManualPhotoImportService {
    func importItems(_ items: [PhotosPickerItem]) async -> ManualPhotoImportResult {
        // The app does not persist an in-progress manual edit across launches.
        // Do this work on the actor when importing rather than on the main
        // actor during model/app initialization.
        try? ManualPhotoImportStorage.prepareCurrentSession()

        var imported: [ManualImportedPhoto] = []
        imported.reserveCapacity(items.count)
        var failureCount = 0

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                failureCount += items.count - index
                break
            }

            do {
                guard let transferred = try await item.loadTransferable(
                    type: PickerTransferredImage.self
                ) else {
                    failureCount += 1
                    continue
                }

                do {
                    let photo = try Self.makePhoto(
                        from: transferred,
                        pickerIdentifier: item.itemIdentifier
                    )
                    imported.append(photo)
                } catch {
                    try? FileManager.default.removeItem(at: transferred.fileURL)
                    failureCount += 1
                }
            } catch {
                // A provider can fail independently (for example, if its iCloud
                // download is unavailable). Preserve successful selections and
                // report this item through the aggregate failure count.
                failureCount += 1
            }
        }

        return ManualPhotoImportResult(
            photos: imported,
            failureCount: failureCount
        )
    }

    /// Call when a successful manual selection is replaced or discarded.
    /// Only files directly inside TripReel's private import cache are removed.
    func removeImportedFiles(for photos: [ManualImportedPhoto]) {
        for photo in photos {
            try? ManualPhotoImportStorage.removeFileIfOwned(URL(fileURLWithPath: photo.filePath))
        }
    }

    private static func makePhoto(
        from transferred: PickerTransferredImage,
        pickerIdentifier: String?
    ) throws -> ManualImportedPhoto {
        guard let source = CGImageSourceCreateWithURL(
            transferred.fileURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
        let rawProperties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) as? [CFString: Any] else {
            throw ImportError.unreadableImage
        }

        let width = integerValue(rawProperties[kCGImagePropertyPixelWidth])
        let height = integerValue(rawProperties[kCGImagePropertyPixelHeight])
        guard width > 0, height > 0 else {
            throw ImportError.invalidDimensions
        }

        let stableID: String
        if let pickerIdentifier = nonempty(pickerIdentifier) {
            stableID = "picker:\(pickerIdentifier)"
        } else {
            // The copied file owns this UUID for its lifetime, so the record ID
            // remains stable without hashing a potentially multi-gigabyte RAW.
            stableID = "manual:\(transferred.storageIdentifier)"
        }

        return ManualImportedPhoto(
            id: stableID,
            filePath: transferred.fileURL.path,
            creationDate: creationDate(in: rawProperties),
            coordinate: coordinate(in: rawProperties),
            filename: transferred.originalFilename,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    private static func creationDate(in properties: [CFString: Any]) -> Date? {
        let exif = dictionary(properties[kCGImagePropertyExifDictionary])
        let tiff = dictionary(properties[kCGImagePropertyTIFFDictionary])

        let candidates: [(String?, String?)] = [
            (
                stringValue(exif?[kCGImagePropertyExifDateTimeOriginal]),
                stringValue(exif?[kCGImagePropertyExifOffsetTimeOriginal])
            ),
            (
                stringValue(exif?[kCGImagePropertyExifDateTimeDigitized]),
                stringValue(exif?[kCGImagePropertyExifOffsetTimeDigitized])
            ),
            (stringValue(tiff?[kCGImagePropertyTIFFDateTime]), nil)
        ]

        for (dateString, offsetString) in candidates {
            guard let dateString = nonempty(dateString) else { continue }
            if let date = parseExifDate(dateString, offset: offsetString) {
                return date
            }
        }
        return nil
    }

    private static func parseExifDate(_ value: String, offset: String?) -> Date? {
        let locale = Locale(identifier: "en_US_POSIX")
        let calendar = Calendar(identifier: .gregorian)

        if let offset = normalizedOffset(offset) {
            for format in [
                "yyyy:MM:dd HH:mm:ss.SSSSSSXXXXX",
                "yyyy:MM:dd HH:mm:ss.SSSXXXXX",
                "yyyy:MM:dd HH:mm:ssXXXXX"
            ] {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.calendar = calendar
                formatter.dateFormat = format
                if let date = formatter.date(from: value + offset) {
                    return date
                }
            }
        }

        for format in [
            "yyyy:MM:dd HH:mm:ss.SSSSSS",
            "yyyy:MM:dd HH:mm:ss.SSS",
            "yyyy:MM:dd HH:mm:ss"
        ] {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            // EXIF timestamps without an offset describe local wall time. The
            // device zone is the least surprising fallback available here.
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func normalizedOffset(_ value: String?) -> String? {
        guard var value = nonempty(value) else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.range(of: #"^[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            return value
        }
        if value.range(of: #"^[+-]\d{4}$"#, options: .regularExpression) != nil {
            let insertion = value.index(value.endIndex, offsetBy: -2)
            value.insert(":", at: insertion)
            return value
        }
        return nil
    }

    private static func coordinate(in properties: [CFString: Any]) -> PhotoCoordinate? {
        guard let gps = dictionary(properties[kCGImagePropertyGPSDictionary]),
              var latitude = doubleValue(gps[kCGImagePropertyGPSLatitude]),
              var longitude = doubleValue(gps[kCGImagePropertyGPSLongitude]) else {
            return nil
        }

        let latitudeReference = stringValue(gps[kCGImagePropertyGPSLatitudeRef])?.uppercased()
        let longitudeReference = stringValue(gps[kCGImagePropertyGPSLongitudeRef])?.uppercased()
        latitude = signedMagnitude(latitude, negativeReference: "S", reference: latitudeReference)
        longitude = signedMagnitude(longitude, negativeReference: "W", reference: longitudeReference)

        guard latitude.isFinite,
              longitude.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else {
            return nil
        }
        return PhotoCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func signedMagnitude(
        _ value: Double,
        negativeReference: String,
        reference: String?
    ) -> Double {
        guard let reference else { return value }
        return reference == negativeReference ? -abs(value) : abs(value)
    }

    private static func dictionary(_ value: Any?) -> [CFString: Any]? {
        if let dictionary = value as? [CFString: Any] {
            return dictionary
        }
        if let dictionary = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key as CFString, $0.value) })
        }
        return nil
    }

    private static func integerValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        return (value as? NSString).map(String.init)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

}

/// The value loaded by PhotosPicker. The copy must happen in this transfer
/// representation because `received.file` is provider-owned and short-lived.
private struct PickerTransferredImage: Transferable, Sendable {
    let fileURL: URL
    let originalFilename: String
    let storageIdentifier: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let fileManager = FileManager.default
            let importDirectory = try ManualPhotoImportStorage.directory()

            let originalFilename = safeFilename(from: received.file)
            let fileExtension = safeExtension(from: received.file)
            let storageIdentifier = UUID().uuidString.lowercased()
            let destination = importDirectory
                .appendingPathComponent(storageIdentifier)
                .appendingPathExtension(fileExtension)
            do {
                try fileManager.copyItem(at: received.file, to: destination)
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDestination = destination
            try? mutableDestination.setResourceValues(values)

            return PickerTransferredImage(
                fileURL: destination,
                originalFilename: originalFilename,
                storageIdentifier: storageIdentifier
            )
        }
    }

    private static func safeFilename(from url: URL) -> String {
        let candidate = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate != ".", candidate != ".." else {
            return "photo.\(safeExtension(from: url))"
        }
        return String(candidate.prefix(255))
    }

    private static func safeExtension(from url: URL) -> String {
        let candidate = url.pathExtension.lowercased()
        let allowed = CharacterSet.alphanumerics
        if !candidate.isEmpty,
           candidate.unicodeScalars.allSatisfy({ allowed.contains($0) }),
           candidate.count <= 12 {
            return candidate
        }
        return "img"
    }
}

private enum ManualPhotoImportStorage {
    private static let sessionIdentifier = UUID().uuidString.lowercased()

    static func directory() throws -> URL {
        let directory = try rootDirectory()
            .appendingPathComponent(sessionIdentifier, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    static func prepareCurrentSession() throws {
        let root = try rootDirectory()
        let current = try directory().standardizedFileURL
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for entry in entries where entry.standardizedFileURL != current {
            // `root` is an app-private cache dedicated to these imports. Direct
            // children are files or directories left by an older app process.
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func rootDirectory() throws -> URL {
        let fileManager = FileManager.default
        let cacheRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cacheRoot
            .appendingPathComponent("TripReel", isDirectory: true)
            .appendingPathComponent("ManualPhotoImports", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    static func removeFileIfOwned(_ fileURL: URL) throws {
        let root = try directory().standardizedFileURL
        let candidate = fileURL.standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else { return }
        try FileManager.default.removeItem(at: candidate)
    }
}

private enum ImportError: Error {
    case unreadableImage
    case invalidDimensions
}
