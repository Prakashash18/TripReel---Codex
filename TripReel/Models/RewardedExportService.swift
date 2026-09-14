import Foundation
@preconcurrency import GoogleMobileAds
import UserMessagingPlatform

/// Owns the voluntary rewarded-ad exchange for extended previews. The short
/// preview never requires an ad. Rewarded access is stored against the exact
/// edit, so a failed render or re-share never asks for the same ad twice.
@MainActor
final class RewardedExportService: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var privacyOptionsRequired = false

    private let defaults: UserDefaults
    private let appID: String?
    private let rewardedAdUnitID: String?
    private let unlockedVersionsKey = "memories.rewarded-export.unlocked-version-ids"
    private let isUITesting: Bool
    private let forcesRewardPromptInUITests: Bool

    private var rewardedAd: RewardedAd?
    private var didInitializeAds = false
    private var didRequestConsent = false
    private var didEarnCurrentReward = false
    private var pendingVersionID: String?
    private var presentationCompletion: ((Bool) -> Void)?

    override convenience init() {
        self.init(bundle: .main)
    }

    init(bundle: Bundle, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appID = Self.configurationValue(key: "GADApplicationIdentifier", bundle: bundle)
        rewardedAdUnitID = Self.configurationValue(key: "ADMOB_REWARDED_AD_UNIT_ID", bundle: bundle)
        let arguments = ProcessInfo.processInfo.arguments
        isUITesting = arguments.contains("-qaScreen")
        forcesRewardPromptInUITests = arguments.contains("-qaRewardedExportPrompt")
        super.init()
    }

    var isConfigured: Bool {
        appID != nil && rewardedAdUnitID != nil
    }

    func hasUnlockedExtendedPreview(versionID: String) -> Bool {
        unlockedVersionIDs.contains(versionID)
    }

    func prepare() async {
        guard isConfigured, !isUITesting, !didRequestConsent else { return }
        didRequestConsent = true
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            updatePrivacyOptionsRequirement()
            if ConsentInformation.shared.canRequestAds {
                startAdsIfNeeded()
                await loadRewardedAdIfNeeded()
            }
        } catch {
            // Consent can be gathered when the user explicitly chooses the ad.
        }
    }

    func watchAdAndUnlock(versionID: String) async -> Bool {
        if hasUnlockedExtendedPreview(versionID: versionID) { return true }
        if isUITesting && !forcesRewardPromptInUITests {
            unlock(versionID: versionID)
            return true
        }
        guard isConfigured else {
            message = "Free ad-supported exports are not configured in this build yet."
            return false
        }
        guard presentationCompletion == nil else { return false }

        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            if !didRequestConsent {
                didRequestConsent = true
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            }
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
            updatePrivacyOptionsRequirement()
            guard ConsentInformation.shared.canRequestAds else {
                message = "Choose an advertising privacy option to use the free export."
                return false
            }

            startAdsIfNeeded()
            await loadRewardedAdIfNeeded()
            guard let rewardedAd else {
                message = "An ad is not available right now. Please try again in a moment."
                return false
            }

            self.rewardedAd = nil
            pendingVersionID = versionID
            didEarnCurrentReward = false
            return await withCheckedContinuation { continuation in
                presentationCompletion = { continuation.resume(returning: $0) }
                rewardedAd.present(from: nil) { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.didEarnCurrentReward = true
                        if let pendingVersionID = self.pendingVersionID {
                            // Store the earned reward immediately, before render
                            // or any later lifecycle interruption can occur.
                            self.unlock(versionID: pendingVersionID)
                        }
                    }
                }
            }
        } catch {
            message = "The ad could not be prepared. Check your connection and try again."
            return false
        }
    }

    func clearMessage() {
        message = nil
    }

    func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            updatePrivacyOptionsRequirement()
        } catch {
            message = "Advertising privacy choices could not be opened. Please try again."
        }
    }

    private func startAdsIfNeeded() {
        guard !didInitializeAds else { return }
        didInitializeAds = true
        MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
        MobileAds.shared.start()
    }

    private func updatePrivacyOptionsRequirement() {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func loadRewardedAdIfNeeded() async {
        guard rewardedAd == nil, let rewardedAdUnitID else { return }
        do {
            let ad = try await RewardedAd.load(with: rewardedAdUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
        } catch {
            rewardedAd = nil
        }
    }

    private func finishPresentation(granted: Bool, fallbackMessage: String? = nil) {
        guard let completion = presentationCompletion else { return }
        if granted, let pendingVersionID {
            unlock(versionID: pendingVersionID)
        } else if let fallbackMessage {
            message = fallbackMessage
        }
        presentationCompletion = nil
        pendingVersionID = nil
        didEarnCurrentReward = false
        completion(granted)
        Task { await loadRewardedAdIfNeeded() }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.finishPresentation(
                granted: self.didEarnCurrentReward,
                fallbackMessage: "Finish the ad to unlock this free export."
            )
        }
    }

    nonisolated func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.finishPresentation(
                granted: false,
                fallbackMessage: "The ad could not open. Please try again."
            )
        }
    }

    private var unlockedVersionIDs: Set<String> {
        Set(defaults.stringArray(forKey: unlockedVersionsKey) ?? [])
    }

    private func unlock(versionID: String) {
        var unlocked = unlockedVersionIDs
        unlocked.insert(versionID)
        // Keep the preference compact while retaining recent edit unlocks.
        defaults.set(Array(Array(unlocked).sorted().suffix(40)), forKey: unlockedVersionsKey)
    }

    private static func configurationValue(key: String, bundle: Bundle) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
