import Foundation

enum SupabaseResumableUploadError: LocalizedError {
    case invalidProjectURL
    case invalidFile
    case invalidResponse
    case missingUploadLocation
    case server(status: Int, message: String)
    case stalled

    var errorDescription: String? {
        switch self {
        case .invalidProjectURL:
            "The private upload service is not configured correctly."
        case .invalidFile:
            "The finished video is no longer available on this iPhone."
        case .invalidResponse, .missingUploadLocation:
            "The private upload service returned an unexpected response."
        case let .server(status, message):
            message.isEmpty ? "The upload service returned error \(status)." : message
        case .stalled:
            "The upload stopped making progress."
        }
    }
}

/// Uploads exported movies in Supabase's required 6 MB TUS chunks. A finished
/// memory is commonly larger than the 6 MB limit recommended for standard
/// uploads, especially at 1080p, so this avoids building one large multipart
/// body in memory and can resume from the server's confirmed offset after a
/// transient mobile-network failure.
struct SupabaseResumableUploader: Sendable {
    static let chunkSize = 6 * 1024 * 1024

    private let endpoint: URL
    private let accessToken: String
    private let session: URLSession

    init(projectURL: URL, accessToken: String) throws {
        guard let projectReference = projectURL.host?.split(separator: ".").first,
              let endpoint = URL(
                string: "https://\(projectReference).storage.supabase.co/storage/v1/upload/resumable"
              ) else {
            throw SupabaseResumableUploadError.invalidProjectURL
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 5 * 60

        self.endpoint = endpoint
        self.accessToken = accessToken
        self.session = URLSession(configuration: configuration)
    }

    func upload(
        fileURL: URL,
        bucket: String,
        objectPath: String,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        guard fileURL.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value > 0 else {
            throw SupabaseResumableUploadError.invalidFile
        }

        let totalBytes = size.uint64Value
        let uploadURL = try await createUpload(
            byteCount: totalBytes,
            bucket: bucket,
            objectPath: objectPath
        )
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }

        var offset: UInt64 = 0
        await progress(0)

        while offset < totalBytes {
            try Task.checkCancellation()
            try file.seek(toOffset: offset)
            let requestedCount = Int(min(UInt64(Self.chunkSize), totalBytes - offset))
            guard let chunk = try file.read(upToCount: requestedCount), !chunk.isEmpty else {
                throw SupabaseResumableUploadError.invalidFile
            }

            do {
                offset = try await uploadChunk(chunk, to: uploadURL, at: offset)
            } catch {
                offset = try await resumeChunk(
                    chunk,
                    uploadURL: uploadURL,
                    expectedOffset: offset,
                    originalError: error
                )
            }

            await progress(min(1, Double(offset) / Double(totalBytes)))
        }
    }

    private func createUpload(
        byteCount: UInt64,
        bucket: String,
        objectPath: String
    ) async throws -> URL {
        var request = authorizedRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(byteCount), forHTTPHeaderField: "Upload-Length")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.setValue(
            uploadMetadata([
                "bucketName": bucket,
                "objectName": objectPath,
                "contentType": "video/mp4",
                "cacheControl": "3600"
            ]),
            forHTTPHeaderField: "Upload-Metadata"
        )

        let (data, response) = try await session.data(for: request)
        let http = try validatedHTTPResponse(response, data: data, allowed: [201])
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: endpoint)?.absoluteURL else {
            throw SupabaseResumableUploadError.missingUploadLocation
        }
        return url
    }

    private func uploadChunk(_ chunk: Data, to uploadURL: URL, at offset: UInt64) async throws -> UInt64 {
        var request = authorizedRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, from: chunk)
        let http = try validatedHTTPResponse(response, data: data, allowed: [204])
        guard let value = http.value(forHTTPHeaderField: "Upload-Offset"),
              let nextOffset = UInt64(value),
              nextOffset > offset else {
            throw SupabaseResumableUploadError.stalled
        }
        return nextOffset
    }

    private func resumeChunk(
        _ originalChunk: Data,
        uploadURL: URL,
        expectedOffset: UInt64,
        originalError: Error
    ) async throws -> UInt64 {
        var lastError = originalError

        for delay in [1, 3, 5] {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(delay))

            do {
                let serverOffset = try await fetchOffset(from: uploadURL)
                if serverOffset > expectedOffset { return serverOffset }
                guard serverOffset == expectedOffset else {
                    throw SupabaseResumableUploadError.stalled
                }
                return try await uploadChunk(originalChunk, to: uploadURL, at: serverOffset)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func fetchOffset(from uploadURL: URL) async throws -> UInt64 {
        var request = authorizedRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        let (data, response) = try await session.data(for: request)
        let http = try validatedHTTPResponse(response, data: data, allowed: [200, 204])
        guard let value = http.value(forHTTPHeaderField: "Upload-Offset"),
              let offset = UInt64(value) else {
            throw SupabaseResumableUploadError.invalidResponse
        }
        return offset
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validatedHTTPResponse(
        _ response: URLResponse,
        data: Data,
        allowed: Set<Int>
    ) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseResumableUploadError.invalidResponse
        }
        guard allowed.contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseResumableUploadError.server(status: http.statusCode, message: message)
        }
        return http
    }

    private func uploadMetadata(_ metadata: [String: String]) -> String {
        metadata
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key) \(Data(value.utf8).base64EncodedString())"
            }
            .joined(separator: ",")
    }
}
