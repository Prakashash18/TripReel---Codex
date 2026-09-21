import AuthenticationServices
import CryptoKit
import Foundation
import Security
import Supabase

struct SharedMemory: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let durationSeconds: Double
    let exportTier: String
    let shareToken: UUID
    let createdAt: Date
    let expiresAt: Date
    let savedToPhoneAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case durationSeconds = "duration_seconds"
        case exportTier = "export_tier"
        case shareToken = "share_token"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case savedToPhoneAt = "saved_to_phone_at"
    }

    var isPaid: Bool { exportTier == "story_pass" }
    var shareURL: URL? {
        URL(string: "https://getmemoriesapp.com/m/?token=\(shareToken.uuidString.lowercased())")
    }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0)
    }
}

struct MonthlyExportAllowance: Codable, Equatable, Sendable {
    let limit: Int
    let used: Int
    let remaining: Int

    static let unavailable = MonthlyExportAllowance(limit: 3, used: 0, remaining: 0)
}

private struct MonthlyExportClaim: Codable, Sendable {
    let allowed: Bool
    let remaining: Int
}

private struct MonthlyExportClaimParameters: Encodable {
    let storyID: String

    enum CodingKeys: String, CodingKey {
        case storyID = "p_story_id"
    }
}

private struct NewSharedMemory: Encodable {
    let ownerID: UUID
    let title: String
    let durationSeconds: Double
    let exportTier: String
    let storagePath: String
    let shareToken: UUID
    let savedToPhoneAt: Date?

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case title
        case durationSeconds = "duration_seconds"
        case exportTier = "export_tier"
        case storagePath = "storage_path"
        case shareToken = "share_token"
        case savedToPhoneAt = "saved_to_phone_at"
    }
}

private struct DownloadableMemory: Decodable {
    let storagePath: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case storagePath = "storage_path"
        case expiresAt = "expires_at"
    }
}

private struct AccountDeletionResponse: Decodable {
    let deleted: Bool
}

enum SharedMemoryPlaybackError: LocalizedError {
    case signedOut
    case expired

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "Sign in to watch this shared story."
        case .expired:
            return "This story has expired and is no longer available."
        }
    }
}

enum ShareLinkCreationPhase: Equatable, Sendable {
    case idle
    case preparing
    case uploading(Double)
    case publishing

    var statusText: String {
        switch self {
        case .idle: "Create share link"
        case .preparing: "Preparing upload…"
        case let .uploading(progress): "Uploading \(Int((progress * 100).rounded()))%"
        case .publishing: "Creating link…"
        }
    }
}

@MainActor
final class MemoryAccountService: ObservableObject {
    @Published private(set) var userID: UUID?
    @Published private(set) var userEmail: String?
    @Published private(set) var memories: [SharedMemory] = []
    @Published private(set) var monthlyExportAllowance = MonthlyExportAllowance.unavailable
    @Published private(set) var isLoadingMonthlyAllowance = false
    @Published private(set) var isBusy = false
    @Published private(set) var shareLinkCreationPhase: ShareLinkCreationPhase = .idle
    @Published private(set) var downloadingMemoryID: UUID?
    @Published var message: String?

    let isConfigured: Bool
    private let client: SupabaseClient?
    private let projectURL: URL?
    private let expiryNotificationScheduler = MemoryExpiryNotificationScheduler()
    private var authTask: Task<Void, Never>?
    private var memoryRefreshGeneration = 0

    init(bundle: Bundle = .main) {
        let urlString = Self.configurationValue(key: "SUPABASE_URL", bundle: bundle)
        let key = Self.configurationValue(key: "SUPABASE_PUBLISHABLE_KEY", bundle: bundle)
        if let urlString, let url = URL(string: urlString), let key {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
            projectURL = url
            isConfigured = true
        } else {
            client = nil
            projectURL = nil
            isConfigured = false
        }

        authTask = Task { [weak self] in
            guard let self, let client = self.client else { return }
            for await (_, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                self.apply(session: session)
                if session != nil {
                    async let memories: Void = self.refreshMemories()
                    async let allowance: Void = self.refreshMonthlyExportAllowance()
                    _ = await (memories, allowance)
                }
            }
        }
    }

    deinit { authTask?.cancel() }

    var isSignedIn: Bool { userID != nil }

    func restoreSession() async {
        guard let client else { return }
        guard client.auth.currentSession != nil else { return }
        guard let session = try? await client.auth.session else {
            apply(session: nil)
            return
        }
        apply(session: session)
        async let memories: Void = refreshMemories()
        async let allowance: Void = refreshMonthlyExportAllowance()
        _ = await (memories, allowance)
    }

    func signInWithApple(idToken: String, nonce: String) async {
        guard let client else {
            message = "Accounts are not connected yet. Add the Supabase project details to this build."
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            apply(session: session)
            async let memories: Void = refreshMemories()
            async let allowance: Void = refreshMonthlyExportAllowance()
            _ = await (memories, allowance)
        } catch {
            message = "Sign in didn’t finish. Nothing was uploaded. Please try again."
        }
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
            userID = nil
            userEmail = nil
            memories = []
            monthlyExportAllowance = .unavailable
            await expiryNotificationScheduler.cancelAll()
        } catch {
            message = "Couldn’t sign out. Check your connection and try again."
        }
    }

    /// Permanently removes every cloud video and share link before deleting
    /// the authenticated account. The privileged deletion itself lives in an
    /// authenticated Edge Function; the service-role key never reaches iOS.
    func deleteAccount() async -> Bool {
        guard let client, userID != nil else {
            message = "Sign in before deleting your account."
            return false
        }

        isBusy = true
        message = nil
        defer { isBusy = false }

        do {
            let response: AccountDeletionResponse = try await client.functions
                .invoke("delete-account")
            guard response.deleted else {
                message = "Your account wasn’t deleted. Please try again."
                return false
            }

            // deleteUser invalidates refresh tokens server-side. signOut also
            // clears the already-issued session from this iPhone immediately.
            try await client.auth.signOut()
            apply(session: nil)
            await expiryNotificationScheduler.cancelAll()
            message = "Your account, videos, and share links were deleted."
            return true
        } catch {
            message = "Your account couldn’t be deleted. Nothing else was removed. Please try again."
            return false
        }
    }

    func refreshMonthlyExportAllowance() async {
        guard let client, userID != nil else {
            monthlyExportAllowance = .unavailable
            return
        }

        isLoadingMonthlyAllowance = true
        defer { isLoadingMonthlyAllowance = false }
        do {
            let rows: [MonthlyExportAllowance] = try await client
                .rpc("monthly_export_allowance")
                .execute()
                .value
            if let allowance = rows.first {
                monthlyExportAllowance = allowance
            }
        } catch {
            // Older builds can run before the allowance migration is applied.
            // Keep Story Pass available and avoid presenting an unusable free claim.
            monthlyExportAllowance = .unavailable
        }
    }

    /// Atomically reserves one of this account's three monthly full exports.
    /// Repeating the same story ID is idempotent and never spends a second credit.
    func claimMonthlyExport(storyID: String) async -> Bool {
        guard let client, userID != nil else {
            message = "Sign in to use your monthly free exports."
            return false
        }

        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let rows: [MonthlyExportClaim] = try await client
                .rpc(
                    "claim_monthly_export",
                    params: MonthlyExportClaimParameters(storyID: storyID)
                )
                .execute()
                .value
            guard let claim = rows.first else { return false }
            monthlyExportAllowance = MonthlyExportAllowance(
                limit: monthlyExportAllowance.limit,
                used: max(0, monthlyExportAllowance.limit - claim.remaining),
                remaining: claim.remaining
            )
            if !claim.allowed {
                message = "You’ve used this month’s three free full exports. Story Pass is still available for this memory."
            }
            return claim.allowed
        } catch {
            message = "Your free export couldn’t be reserved. Please check your connection and try again."
            return false
        }
    }

    func refreshMemories() async {
        guard let client, userID != nil else {
            memories = []
            return
        }

        memoryRefreshGeneration &+= 1
        let refreshGeneration = memoryRefreshGeneration

        do {
            let rows = try await fetchMemories(using: client)
            guard refreshGeneration == memoryRefreshGeneration else { return }
            memories = sortedActiveMemories(rows)
            await expiryNotificationScheduler.synchronize(memories: memories)
            message = nil
        } catch {
            // A newly-created Supabase session can emit its signed-in event at
            // the same time as the account screen and app lifecycle request a
            // refresh. Give the session store one brief chance to settle before
            // surfacing a real backend or network failure to the user.
            try? await Task.sleep(for: .milliseconds(350))
            guard refreshGeneration == memoryRefreshGeneration else { return }

            do {
                let rows = try await fetchMemories(using: client)
                guard refreshGeneration == memoryRefreshGeneration else { return }
                memories = sortedActiveMemories(rows)
                await expiryNotificationScheduler.synchronize(memories: memories)
                message = nil
            } catch {
                guard refreshGeneration == memoryRefreshGeneration else { return }
                message = "You’re signed in, but your shared stories couldn’t load yet. Please try again."
            }
        }
    }

    func createShareLink(
        videoURL: URL,
        title: String,
        durationSeconds: Double,
        isPaid: Bool,
        wasSavedToPhone: Bool
    ) async -> URL? {
        guard let client, let projectURL, let userID else {
            message = "Create an account first to make a share link. Your video stays on this iPhone until then."
            return nil
        }

        isBusy = true
        shareLinkCreationPhase = .preparing
        message = nil
        defer {
            isBusy = false
            shareLinkCreationPhase = .idle
        }

        let memoryID = UUID()
        let shareToken = UUID()
        let storagePath = "\(userID.uuidString.lowercased())/\(memoryID.uuidString.lowercased()).mp4"

        do {
            let session = try await client.auth.session
            let uploader = try SupabaseResumableUploader(
                projectURL: projectURL,
                accessToken: session.accessToken
            )
            try await uploader.upload(
                fileURL: videoURL,
                bucket: "memory-exports",
                objectPath: storagePath
            ) { progress in
                await self.updateShareLinkUploadProgress(progress)
            }

            shareLinkCreationPhase = .publishing
            let inserted: SharedMemory = try await client
                .from("memories")
                .insert(
                    NewSharedMemory(
                        ownerID: userID,
                        title: title,
                        durationSeconds: max(0, durationSeconds),
                        exportTier: isPaid ? "story_pass" : "free",
                        storagePath: storagePath,
                        shareToken: shareToken,
                        savedToPhoneAt: wasSavedToPhone ? Date() : nil
                    )
                )
                .select("id,title,duration_seconds,export_tier,share_token,created_at,expires_at,saved_to_phone_at")
                .single()
                .execute()
                .value

            memories = sortedActiveMemories(memories + [inserted])
            await expiryNotificationScheduler.synchronize(
                memories: memories,
                requestAuthorizationIfNeeded: true
            )
            return inserted.shareURL
        } catch {
            _ = try? await client.storage.from("memory-exports").remove(paths: [storagePath])
            if let description = (error as? LocalizedError)?.errorDescription,
               !description.isEmpty {
                message = "\(description) Your video is still safe on this iPhone. Please try again."
            } else {
                message = "The share link couldn’t be created. Your video is still safe on this iPhone. Please try again."
            }
            return nil
        }
    }

    func markSavedToPhone(memoryID: UUID) async {
        guard let client else { return }
        expiryNotificationScheduler.cancel(memoryID: memoryID)
        struct SavedMarker: Encodable {
            let savedToPhoneAt: Date

            enum CodingKeys: String, CodingKey {
                case savedToPhoneAt = "saved_to_phone_at"
            }
        }
        do {
            try await client
                .from("memories")
                .update(SavedMarker(savedToPhoneAt: Date()))
                .eq("id", value: memoryID)
                .execute()
            await refreshMemories()
        } catch {
            // Saving to Photos succeeded. A cloud status refresh is optional
            // and must never turn that local success into an error.
        }
    }

    func markSavedToPhone(shareURL: URL) async {
        guard let memory = memories.first(where: { $0.shareURL == shareURL }) else { return }
        await markSavedToPhone(memoryID: memory.id)
    }

    /// A link is the only opt-in upload path. Its owner may save that same
    /// private MP4 back to Photos while the seven-day record is still active.
    func downloadToPhotos(_ memory: SharedMemory) async {
        guard userID != nil else {
            message = "Sign in to download this shared story."
            return
        }
        guard memory.expiresAt > Date() else {
            message = "This story has expired and can no longer be downloaded."
            await refreshMemories()
            return
        }
        guard downloadingMemoryID == nil else { return }

        downloadingMemoryID = memory.id
        message = nil
        defer { downloadingMemoryID = nil }

        do {
            let signedURL = try await playbackURL(for: memory, expiresIn: 300)
            let (temporaryURL, response) = try await URLSession.shared.download(from: signedURL)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200 else {
                message = "The story couldn't be downloaded. Please try again."
                return
            }

            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Memories-Download-\(UUID().uuidString).mp4")
            try FileManager.default.moveItem(at: temporaryURL, to: localURL)
            defer { try? FileManager.default.removeItem(at: localURL) }

            try await TripReelVideoExporter().saveToPhotoLibrary(localURL)
            await markSavedToPhone(memoryID: memory.id)
            message = "Saved to Photos. This copy is yours to keep."
        } catch {
            message = "Couldn't save this story. Check your connection and Photos access, then try again."
        }
    }

    /// Returns a short-lived URL for the signed-in owner to stream a linked
    /// story. The storage object remains private and the URL expires quickly.
    func playbackURL(for memory: SharedMemory, expiresIn: Int = 3_600) async throws -> URL {
        guard let client, let ownerID = userID else {
            throw SharedMemoryPlaybackError.signedOut
        }
        guard memory.expiresAt > Date() else {
            throw SharedMemoryPlaybackError.expired
        }

        let stored: DownloadableMemory = try await client
            .from("memories")
            .select("storage_path,expires_at")
            .eq("id", value: memory.id)
            .eq("owner_id", value: ownerID)
            .single()
            .execute()
            .value

        guard stored.expiresAt > Date() else {
            throw SharedMemoryPlaybackError.expired
        }

        return try await client.storage
            .from("memory-exports")
            .createSignedURL(path: stored.storagePath, expiresIn: expiresIn)
    }

    func revoke(_ memory: SharedMemory) async {
        guard let client, let ownerID = userID else {
            message = "Sign in to delete this shared story."
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let stored: DownloadableMemory = try await client
                .from("memories")
                .select("storage_path,expires_at")
                .eq("id", value: memory.id)
                .eq("owner_id", value: ownerID)
                .single()
                .execute()
                .value

            try await client.storage
                .from("memory-exports")
                .remove(paths: [stored.storagePath])
            try await client
                .from("memories")
                .delete()
                .eq("id", value: memory.id)
                .eq("owner_id", value: ownerID)
                .execute()
            memories.removeAll { $0.id == memory.id }
            expiryNotificationScheduler.cancel(memoryID: memory.id)
        } catch {
            message = "That video and link couldn’t be deleted. Please try again."
        }
    }

    private func apply(session: Session?) {
        userID = session?.user.id
        userEmail = session?.user.email
        if session == nil {
            memories = []
            monthlyExportAllowance = .unavailable
            Task { await expiryNotificationScheduler.cancelAll() }
        }
    }

    private func fetchMemories(using client: SupabaseClient) async throws -> [SharedMemory] {
        // `currentUser` can outlive an expired token. Asking Auth for `session`
        // first guarantees the following Data API request has a valid JWT.
        _ = try await client.auth.session
        return try await client
            .from("memories")
            .select("id,title,duration_seconds,export_tier,share_token,created_at,expires_at,saved_to_phone_at")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    private func sortedActiveMemories(_ rows: [SharedMemory]) -> [SharedMemory] {
        rows
            .filter { $0.expiresAt > Date() }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString > rhs.id.uuidString }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func updateShareLinkUploadProgress(_ progress: Double) {
        shareLinkCreationPhase = .uploading(progress)
    }

    private static func configurationValue(key: String, bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}

enum AppleSignInNonce {
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            for byte in bytes where remaining > 0 {
                guard byte < characters.count else { continue }
                result.append(characters[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
