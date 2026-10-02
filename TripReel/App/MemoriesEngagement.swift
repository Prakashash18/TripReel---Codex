import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseInAppMessaging
import FirebaseRemoteConfig

/// Only fixed event names and categorical values cross the analytics boundary.
/// Never pass story titles, media identifiers, URLs, errors, or account information.
enum MemoryEvent: String {
    case firstCutStarted = "first_cut_started", firstCutCompleted = "first_cut_completed"
    case aiStarted = "ai_director_started", aiCompleted = "ai_director_completed"
    case aiFailed = "ai_director_failed", aiCancelled = "ai_director_cancelled"
    case aiVideoStarted = "ai_video_started", aiVideoCompleted = "ai_video_completed"
    case aiVideoFailed = "ai_video_failed", aiVideoCancelled = "ai_video_cancelled"
    case aiAccepted = "ai_director_accepted", aiRejected = "ai_director_rejected"
    case exportStarted = "export_started", exportCompleted = "export_completed"
    case exportFailed = "export_failed", exportCancelled = "export_cancelled"
    case saveCompleted = "save_completed", saveFailed = "save_failed"
    case shareOpened = "share_sheet_opened", shareLinkCreated = "share_link_created"
    case paywallViewed = "story_pass_viewed", purchaseStarted = "story_pass_started"
    case purchaseCompleted = "story_pass_completed", purchaseCancelled = "story_pass_cancelled"
    case purchaseFailed = "story_pass_failed"
    case tipViewed = "help_tip_viewed", tipDismissed = "help_tip_dismissed"
    case reviewRequested = "review_requested"
}

enum MemoryFeature: String, CaseIterable {
    case music, atmosphere, title, titleStyle = "title_style", selection, reorder, frame, motion, crop, duration, videoTrim = "video_trim"
}

enum HelpTipVariant: String, CaseIterable {
    case save, music, none
    init(remoteValue: String) { self = Self(rawValue: remoteValue) ?? .save }
    var text: String {
        switch self {
        case .save: "Keep your film: export it, then choose Save to Photos. Copies in Memories are temporary."
        case .music: "Make it feel like your memory: try a different soundtrack before exporting your film."
        case .none: ""
        }
    }
}

/// Local-only eligibility state. Export IDs are never sent to Firebase.
struct EngagementHistory {
    let defaults: UserDefaults
    func recordSave(id: String) -> Bool {
        var ids = defaults.stringArray(forKey: "engagement.savedExports") ?? []
        guard !ids.contains(id) else { return false }
        ids.append(id)
        defaults.set(Array(ids.suffix(200)), forKey: "engagement.savedExports")
        defaults.set(defaults.integer(forKey: "engagement.saveCount") + 1, forKey: "engagement.saveCount")
        return true
    }
    func reviewEligible(version: String, now: Date) -> Bool {
        guard defaults.integer(forKey: "engagement.saveCount") >= 2,
              defaults.string(forKey: "engagement.reviewVersion") != version else { return false }
        guard let last = defaults.object(forKey: "engagement.reviewDate") as? Date else { return true }
        return now.timeIntervalSince(last) >= 120 * 86400
    }
    func markReviewRequested(version: String, now: Date) {
        defaults.set(version, forKey: "engagement.reviewVersion")
        defaults.set(now, forKey: "engagement.reviewDate")
    }
    func tipEligible(now: Date) -> Bool {
        guard let last = defaults.object(forKey: "engagement.tipDate") as? Date else { return true }
        return now.timeIntervalSince(last) >= 86400
    }
    func markTipShown(now: Date) { defaults.set(now, forKey: "engagement.tipDate") }
}

@MainActor
final class MemoriesEngagement: ObservableObject {
    static let shared = MemoriesEngagement()
    @Published private(set) var tip: HelpTipVariant?
    @Published private(set) var saveRevision = 0
    private let history = EngagementHistory(defaults: .standard)
    private var editedFeatures: Set<MemoryFeature> = []
    private var config: RemoteConfig?
    private var refreshing = false
    private var activeScreen: AppScreen = .welcome
    private var safeToMessage = false
    private var tipExposure: HelpTipVariant?
    private var tipsEnabled = true
    private var reviewsEnabled = true
    private var variant = HelpTipVariant.save

    static var collectionAllowed: Bool {
        FirebaseApp.app() != nil && (UserDefaults.standard.object(forKey: MemoriesAnalytics.preferenceKey) as? Bool ?? true)
    }

    func applyPreference(_ enabled: Bool) {
        guard FirebaseApp.app() != nil else { return }
        InAppMessaging.inAppMessaging().automaticDataCollectionEnabled = enabled
        InAppMessaging.inAppMessaging().messageDisplaySuppressed = true
        if enabled {
            refreshConfiguration()
        } else {
            tip = nil
            tipExposure = nil
            config = nil
            variant = .save
            tipsEnabled = true
            reviewsEnabled = true
        }
    }

    private func refreshConfiguration() {
        guard Self.collectionAllowed, !refreshing else { return }
        refreshing = true
        let remote = RemoteConfig.remoteConfig()
        remote.setDefaults([
            "memories_help_tip_variant": "save" as NSString,
            "memories_help_tips_enabled": true as NSNumber,
            "memories_review_requests_enabled": true as NSNumber
        ])
        config = remote
        Task {
            defer { refreshing = false }
            // Fetch respects the SDK cache. Keep bundled defaults if offline.
            _ = try? await remote.fetchAndActivate()
            guard Self.collectionAllowed else { return }
            variant = HelpTipVariant(remoteValue: remote["memories_help_tip_variant"].stringValue)
            tipsEnabled = remote["memories_help_tips_enabled"].boolValue
            reviewsEnabled = remote["memories_review_requests_enabled"].boolValue
            if !tipsEnabled { tip = nil }
        }
    }

    func record(_ event: MemoryEvent) {
        guard Self.collectionAllowed else { return }
        let parameters: [String: Any]? = tipExposure.map { ["tip_variant": $0.rawValue] }
        Analytics.logEvent(event.rawValue, parameters: parameters)
    }

    func beginStory() {
        editedFeatures.removeAll()
        tipExposure = nil
        record(.firstCutStarted)
    }

    func used(_ feature: MemoryFeature) {
        guard Self.collectionAllowed, editedFeatures.insert(feature).inserted else { return }
        // Count distinct feature adoption per editing journey, not each keystroke/slider tick.
        Analytics.logEvent("feature_used", parameters: ["feature": feature.rawValue])
    }

    func screenChanged(_ screen: AppScreen) {
        activeScreen = screen
        tip = nil
        guard Self.collectionAllowed else { return }
        Analytics.logEvent("screen_view", parameters: ["screen_name": screen.rawValue, "screen_class": "Memories"])
        if screen == .paywall { record(.paywallViewed) }
    }

    func updateMessageSafety(screen: AppScreen, isActive: Bool, blocked: Bool) {
        activeScreen = screen
        safeToMessage = isActive && !blocked
        guard Self.collectionAllowed else { tip = nil; return }
        // Console campaigns are allowed only on the library screen, never during a film,
        // permission request, purchase, edit, or render. Campaigns must use this trigger.
        let allowCampaign = safeToMessage && screen == .trips
        InAppMessaging.inAppMessaging().messageDisplaySuppressed = !allowCampaign
        if allowCampaign { InAppMessaging.inAppMessaging().triggerEvent("memories_library_ready") }
        if !safeToMessage { tip = nil }
    }

    func offerTip() {
        guard Self.collectionAllowed, safeToMessage, activeScreen == .firstCutOptions,
              tipsEnabled, variant != .none, tip == nil, history.tipEligible(now: Date()) else { return }
        tip = variant
        tipExposure = variant
        history.markTipShown(now: Date())
        record(.tipViewed)
    }

    func dismissTip() { record(.tipDismissed); tip = nil }

    func savedExport(id: String) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard history.recordSave(id: id) else { return }
        record(.saveCompleted)
        saveRevision += 1
    }

    func requestReviewIfEligible(_ request: () -> Void) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let hasPresentedController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
        guard !hasPresentedController, safeToMessage, activeScreen == .done, reviewsEnabled,
              history.reviewEligible(version: version, now: Date()) else { return }
        history.markReviewRequested(version: version, now: Date())
        record(.reviewRequested) // Request only: StoreKit does not expose display or rating completion.
        request()
    }
}
