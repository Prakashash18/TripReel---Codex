import AuthenticationServices
import AVKit
import SwiftUI
import UIKit

enum AccountPresentationContext {
    case account
    case sharing
}

struct AccountCenterView: View {
    @EnvironmentObject private var account: MemoryAccountService
    @Environment(\.dismiss) private var dismiss
    let context: AccountPresentationContext
    @State private var nonce: String?
    @State private var showsAccountDeletion = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground(variant: .trips)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        accountHero
                        if account.isSignedIn { signedInContent } else { signedOutContent }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 36)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(TR.cream)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task { await account.restoreSession() }
        .alert(
            "Memories account",
            isPresented: Binding(
                get: { account.message != nil },
                set: { if !$0 { account.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { account.message = nil }
        } message: {
            Text(account.message ?? "Please try again.")
        }
        .sheet(isPresented: $showsAccountDeletion) {
            AccountDeletionSheet()
                .environmentObject(account)
        }
    }

    private var accountHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataText(
                text: account.isSignedIn ? "YOUR MEMORIES ACCOUNT" : "SHARE FROM MEMORIES",
                color: TR.accent
            )
            Text(account.isSignedIn ? "Your shared stories" : "A link your people can open")
                .font(TR.display(39))
                .tracking(-0.6)
            Text(account.isSignedIn
                 ? "Share or save a linked video again before it expires in seven days."
                 : "Sign in to create a private share link for Messages or social media. Local saving never needs an account.")
                .font(TR.ui(15))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(3)
        }
        .padding(.top, 18)
    }

    private var signedOutContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                accountBenefit("link", "Share one simple link")
                Divider().overlay(.white.opacity(0.1))
                accountBenefit("clock", "Automatic seven-day expiry")
                Divider().overlay(.white.opacity(0.1))
                accountBenefit("lock.shield", "Private originals stay on iPhone")
            }
            .padding(.horizontal, 18)
            .glassCard(cornerRadius: 24, highlighted: true)

            if account.isConfigured {
                SignInWithAppleButton(.continue) { request in
                    let newNonce = AppleSignInNonce.random()
                    nonce = newNonce
                    request.requestedScopes = [.email]
                    request.nonce = AppleSignInNonce.sha256(newNonce)
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(Capsule())
                .disabled(account.isBusy)
            } else {
                Label("Account setup is not connected in this build", systemImage: "wrench.and.screwdriver")
                    .font(TR.ui(13, weight: .medium))
                    .foregroundStyle(TR.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassCard(cornerRadius: 18)
            }

            Text("Apple shares only the account details you approve. Memories never uploads your photo library.")
                .font(TR.ui(11))
                .foregroundStyle(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(account.userEmail ?? "Signed in with Apple", systemImage: "person.crop.circle.fill")
                    .font(TR.ui(13, weight: .semibold))
                Spacer()
                Button("Sign out") { Task { await account.signOut() } }
                    .font(TR.ui(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(16)
            .glassCard(cornerRadius: 18)

            HStack(spacing: 13) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TR.keep)
                    .frame(width: 38, height: 38)
                    .background(TR.keep.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Monthly full exports")
                        .font(TR.ui(14, weight: .semibold))
                    Text("\(account.monthlyExportAllowance.remaining) of 3 remaining")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
            }
            .padding(16)
            .glassCard(cornerRadius: 18, highlighted: account.monthlyExportAllowance.remaining > 0)

            if account.memories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(TR.accent)
                    Text(context == .sharing ? "You’re ready to create this link" : "No shared stories yet")
                        .font(TR.display(24))
                    Text(context == .sharing
                         ? "Close this screen, then tap Create share link again."
                         : "Create a link from the final screen of any memory.")
                        .font(TR.ui(13))
                        .foregroundStyle(.white.opacity(0.52))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else {
                Text("ACTIVE LINKS")
                    .font(TR.mono(10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(TR.accent)

                ForEach(account.memories) { memory in
                    SharedMemoryRow(memory: memory)
                        .environmentObject(account)
                }
            }

            accountDeletionSection
        }
    }

    private var accountDeletionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCOUNT & PRIVACY")
                .font(TR.mono(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.46))
            Text("You can permanently remove your account and every video and link stored by Memories.")
                .font(TR.ui(12))
                .foregroundStyle(.white.opacity(0.5))
                .lineSpacing(2)
            Button(role: .destructive) {
                showsAccountDeletion = true
            } label: {
                Label("Delete account and cloud data", systemImage: "person.crop.circle.badge.minus")
                    .font(TR.ui(13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .accessibilityIdentifier("delete-account-button")
        }
        .padding(17)
        .glassCard(cornerRadius: 20)
        .padding(.top, 12)
    }

    private func accountBenefit(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(TR.ui(14, weight: .semibold))
            .foregroundStyle(TR.cream)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        guard case let .success(authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let nonce else {
            account.message = "Sign in was cancelled or Apple didn’t return a valid identity."
            return
        }
        Task { await account.signInWithApple(idToken: token, nonce: nonce) }
    }
}

private struct AccountDeletionSheet: View {
    @EnvironmentObject private var account: MemoryAccountService
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var showsFinalConfirmation = false
    @State private var isDeleting = false

    private var isConfirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground(variant: .export)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.86))
                            .padding(.top, 12)

                        VStack(alignment: .leading, spacing: 10) {
                            MetadataText(text: "PERMANENT ACTION", color: .red.opacity(0.86))
                            Text("Delete your Memories account?")
                                .font(TR.display(39))
                                .tracking(-0.6)
                            Text("This cannot be undone. Before continuing, make sure you have saved every video you want to keep.")
                                .font(TR.ui(15))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineSpacing(3)
                        }

                        VStack(spacing: 0) {
                            deletionWarning("play.rectangle", "All cloud videos will be deleted")
                            Divider().overlay(.white.opacity(0.1))
                            deletionWarning("link", "Every shared link will stop working")
                            Divider().overlay(.white.opacity(0.1))
                            deletionWarning("person.crop.circle", "Your account and export history will be removed")
                            Divider().overlay(.white.opacity(0.1))
                            deletionWarning("photo", "Videos already saved in Photos stay on your iPhone")
                        }
                        .padding(.horizontal, 17)
                        .glassCard(cornerRadius: 22, highlighted: true)

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Type DELETE to continue")
                                .font(TR.ui(13, weight: .semibold))
                            TextField("DELETE", text: $confirmation)
                                .font(TR.ui(17, weight: .semibold))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(16)
                                .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 15))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                }
                                .accessibilityIdentifier("delete-account-confirmation-field")
                        }

                        Button(role: .destructive) {
                            showsFinalConfirmation = true
                        } label: {
                            Group {
                                if isDeleting {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Permanently delete account", systemImage: "trash")
                                }
                            }
                            .font(TR.ui(14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(.red.opacity(isConfirmed ? 0.82 : 0.28), in: Capsule())
                        }
                        .foregroundStyle(.white)
                        .disabled(!isConfirmed || isDeleting)
                        .accessibilityIdentifier("delete-account-permanently-button")
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 38)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(TR.cream)
                        .disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
            .alert("Delete everything?", isPresented: $showsFinalConfirmation) {
                Button("Delete account", role: .destructive) {
                    Task {
                        isDeleting = true
                        let deleted = await account.deleteAccount()
                        isDeleting = false
                        if deleted { dismiss() }
                    }
                }
                Button("Keep my account", role: .cancel) {}
            } message: {
                Text("This is your final confirmation. All cloud videos, links, and account data will be permanently deleted.")
            }
        }
    }

    private func deletionWarning(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(TR.ui(13, weight: .semibold))
            .foregroundStyle(TR.cream)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 15)
    }
}

private struct SharedMemoryRow: View {
    @EnvironmentObject private var account: MemoryAccountService
    let memory: SharedMemory
    @State private var copyConfirmation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            NavigationLink {
                SharedMemoryDetailView(memory: memory)
                    .environmentObject(account)
            } label: {
                HStack(alignment: .center, spacing: 13) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(memory.isPaid ? TR.accent : TR.keep, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(memory.title)
                            .font(TR.ui(16, weight: .semibold))
                            .lineLimit(2)
                        Text("\(memory.isPaid ? "FULL STORY" : "FREE PREVIEW") · \(durationText)")
                            .font(TR.mono(9, weight: .semibold))
                            .tracking(0.9)
                            .foregroundStyle(memory.isPaid ? TR.accent : TR.keep)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(memory.daysRemaining == 0 ? "Expires today" : "\(memory.daysRemaining)d left")
                            .font(TR.ui(10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watch \(memory.title)")
            .accessibilityHint("Opens the video with save and share options")
            .accessibilityIdentifier("account-watch-video-\(memory.id.uuidString)")

            HStack(spacing: 16) {
                Button {
                    Task { await account.downloadToPhotos(memory) }
                } label: {
                    if account.downloadingMemoryID == memory.id {
                        ProgressView()
                            .tint(TR.cream)
                            .accessibilityLabel("Downloading video")
                    } else {
                        Label(
                            memory.savedToPhoneAt == nil ? "Save video" : "Download again",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                }
                .disabled(account.downloadingMemoryID != nil)
                .accessibilityIdentifier("account-download-video-\(memory.id.uuidString)")

                Spacer(minLength: 0)

                if let url = memory.shareURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Menu {
                        Button("Copy link", systemImage: "link") {
                            UIPasteboard.general.url = url
                            copyConfirmation = "Link copied"
                        }
                        Button("Copy invitation", systemImage: "text.quote") {
                            UIPasteboard.general.string = MemoryShareCopy.invitation(
                                title: memory.title,
                                url: url,
                                expiry: memory.daysRemaining == 0 ? "today" : "in \(memory.daysRemaining) day\(memory.daysRemaining == 1 ? "" : "s")"
                            )
                            copyConfirmation = "Invitation copied"
                        }
                        Divider()
                        Button("Remove link", systemImage: "trash", role: .destructive) {
                            Task { await account.revoke(memory) }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .font(TR.ui(12, weight: .semibold))
            if let copyConfirmation {
                Text(copyConfirmation)
                    .font(TR.ui(11, weight: .semibold))
                    .foregroundStyle(TR.keep)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .foregroundStyle(TR.cream)
        .padding(17)
        .glassCard(cornerRadius: 20, highlighted: memory.isPaid)
    }

    private var durationText: String {
        let seconds = max(0, Int(memory.durationSeconds.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SharedMemoryDetailView: View {
    @EnvironmentObject private var account: MemoryAccountService
    @Environment(\.dismiss) private var dismiss
    let memory: SharedMemory

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var playbackError: String?
    @State private var copyConfirmation: String?
    @State private var confirmsRemoval = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    video

                    VStack(alignment: .leading, spacing: 8) {
                        MetadataText(
                            text: "\(memory.isPaid ? "FULL STORY" : "FREE PREVIEW") · \(durationText)",
                            color: memory.isPaid ? TR.accent : TR.keep
                        )
                        Text(memory.title)
                            .font(TR.display(36))
                            .tracking(-0.5)
                        Text(expiryText)
                            .font(TR.ui(13))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Button {
                        Task { await account.downloadToPhotos(memory) }
                    } label: {
                        Group {
                            if account.downloadingMemoryID == memory.id {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Label(
                                    memory.savedToPhoneAt == nil ? "Save video to Photos" : "Download again",
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CreamButtonStyle())
                    .disabled(account.downloadingMemoryID != nil)
                    .accessibilityIdentifier("memory-detail-save-video")

                    if let url = memory.shareURL {
                        ShareLink(
                            item: url,
                            subject: Text("A memory from Memories"),
                            message: Text(MemoryShareCopy.invitation(
                                title: memory.title,
                                url: url,
                                expiry: shareExpiryText
                            ))
                        ) {
                            Label("Share private link", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle())
                        .accessibilityIdentifier("memory-detail-share-link")

                        HStack(spacing: 22) {
                            Button("Copy link", systemImage: "link") {
                                UIPasteboard.general.url = url
                                copyConfirmation = "Link copied"
                            }
                            Button("More", systemImage: "ellipsis.circle") {
                                confirmsRemoval = true
                            }
                        }
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)
                        .frame(maxWidth: .infinity)
                    }

                    if let copyConfirmation {
                        Text(copyConfirmation)
                            .font(TR.ui(12, weight: .semibold))
                            .foregroundStyle(TR.keep)
                            .frame(maxWidth: .infinity)
                    }

                    Text("The video and private link expire automatically. Save it to Photos if you want to keep it.")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.44))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Watch memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: memory.id) { await loadVideo() }
        .onDisappear { player?.pause() }
        .confirmationDialog(
            "More options",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            if let url = memory.shareURL {
                Button("Copy invitation") {
                    UIPasteboard.general.string = MemoryShareCopy.invitation(
                        title: memory.title,
                        url: url,
                        expiry: shareExpiryText
                    )
                    copyConfirmation = "Invitation copied"
                }
            }
            Button("Delete video and link", role: .destructive) {
                Task {
                    await account.revoke(memory)
                    if !account.memories.contains(memory) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting removes the stored video and makes its link stop working.")
        }
    }

    @ViewBuilder
    private var video: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.78))

            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityLabel("\(memory.title) video player")
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(TR.accent)
                    Text("Preparing your memory…")
                        .font(TR.ui(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(TR.accent)
                    Text(playbackError ?? "This video couldn’t be opened.")
                        .font(TR.ui(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await loadVideo() } }
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)
                }
                .padding(24)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(maxHeight: 520)
        .padding(.top, 12)
    }

    private func loadVideo() async {
        player?.pause()
        player = nil
        playbackError = nil
        isLoading = true
        do {
            let url = try await account.playbackURL(for: memory)
            guard !Task.isCancelled else { return }
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            isLoading = false
            newPlayer.play()
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            playbackError = (error as? LocalizedError)?.errorDescription
                ?? "This video couldn’t be opened. Check your connection and try again."
        }
    }

    private var durationText: String {
        let seconds = max(0, Int(memory.durationSeconds.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var expiryText: String {
        memory.daysRemaining == 0
            ? "This private video expires today."
            : "This private video expires in \(memory.daysRemaining) day\(memory.daysRemaining == 1 ? "" : "s")."
    }

    private var shareExpiryText: String {
        memory.daysRemaining == 0
            ? "today"
            : "in \(memory.daysRemaining) day\(memory.daysRemaining == 1 ? "" : "s")"
    }
}

struct MemoryLinkReadySheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let url: URL
    @State private var copyConfirmation: String?

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(TR.accent)
                    .symbolEffect(.bounce, value: url)
                MetadataText(text: "LINK READY · 7 DAYS", color: TR.keep)
                Text("Send the memory, not the file")
                    .font(TR.display(37))
                    .multilineTextAlignment(.center)
                Text("Anyone with this link can watch “\(title)” until it expires.")
                    .font(TR.ui(14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                Spacer()
                ShareLink(item: url) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CreamButtonStyle())
                HStack(spacing: 18) {
                    Button("Copy link") {
                        UIPasteboard.general.url = url
                        copyConfirmation = "Link copied"
                    }
                    Button("Copy invitation") {
                        UIPasteboard.general.string = MemoryShareCopy.invitation(
                            title: title,
                            url: url,
                            expiry: "in 7 days"
                        )
                        copyConfirmation = "Invitation copied"
                    }
                }
                .font(TR.ui(13, weight: .semibold))
                .foregroundStyle(TR.accent)
                Text(copyConfirmation ?? "For Facebook posts, copy the link and paste it into your caption.")
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                Button("Done") { dismiss() }
                    .font(TR.ui(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(24)
        }
    }

}

private enum MemoryShareCopy {
    static func invitation(title: String, url: URL, expiry: String) -> String {
        "I made “\(title)” with Memories. Watch it before this private link expires \(expiry):\n\(url.absoluteString)"
    }
}
