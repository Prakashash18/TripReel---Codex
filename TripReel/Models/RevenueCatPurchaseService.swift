import Foundation
import RevenueCat
import StoreKit

struct ExportPremiumRequirement: Equatable, Sendable {
    let photoCount: Int
    let durationSeconds: Double
    let freePhotoLimit: Int
    let freeDurationLimit: Double
    let requiresHighDefinition: Bool

    var exceedsPhotoLimit: Bool { photoCount > freePhotoLimit }
    var exceedsDurationLimit: Bool { durationSeconds > freeDurationLimit }

    var reasonText: String {
        switch (exceedsPhotoLimit, exceedsDurationLimit, requiresHighDefinition) {
        case (true, true, _):
            "This film is longer and includes more moments than a free export."
        case (true, false, _):
            "This film includes more moments than a free export."
        case (false, true, _):
            "This film is longer than a free export."
        case (false, false, true):
            "HD export is included with a Story Pass."
        case (false, false, false):
            "This export is included with a Story Pass."
        }
    }
}

enum ExportAccessPolicy {
    static func premiumRequirement(
        photoCount: Int,
        durationSeconds: Double,
        freePhotoCount: Int? = nil,
        freeDurationSeconds: Double? = nil,
        quality: ExportQuality
    ) -> ExportPremiumRequirement? {
        let safePhotoCount = max(photoCount, 0)
        let safeDuration = max(durationSeconds.isFinite ? durationSeconds : 0, 0)
        let safeFreePhotoCount = min(
            safePhotoCount,
            max(0, freePhotoCount ?? safePhotoCount)
        )
        let suppliedFreeDuration = freeDurationSeconds ?? safeDuration
        let safeFreeDuration = min(
            safeDuration,
            max(suppliedFreeDuration.isFinite ? suppliedFreeDuration : 0, 0)
        )
        let requiresHighDefinition = quality == .hd

        // Standard always has a usable free path. The model turns a longer
        // film into a complete short cut within the free limits at render time.
        guard requiresHighDefinition else { return nil }
        return ExportPremiumRequirement(
            photoCount: safePhotoCount,
            durationSeconds: safeDuration,
            freePhotoLimit: safeFreePhotoCount,
            freeDurationLimit: safeFreeDuration,
            requiresHighDefinition: requiresHighDefinition
        )
    }
}

@MainActor
final class RevenueCatPurchaseService: NSObject, ObservableObject {
    static let defaultStoryPassPackageIdentifier = "story_pass"

    @Published private(set) var isConfigured = false
    @Published private(set) var packages: [Package] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?
    @Published private(set) var storefrontCurrencyCode: String?

    let storyPassPackageIdentifier: String

    private let apiKey: String?
    private let defaults: UserDefaults
    private let grantsQAFullExportAccess: Bool
    private let unlockedStoriesKey = "memories.unlocked-export-story-ids"

    override convenience init() {
        self.init(bundle: .main)
    }

    init(bundle: Bundle, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        let grantsQAFullExportAccess = ProcessInfo.processInfo.arguments.contains("-qaPremium")
        #else
        let grantsQAFullExportAccess = false
        #endif
        self.grantsQAFullExportAccess = grantsQAFullExportAccess

        if grantsQAFullExportAccess {
            apiKey = nil
            storyPassPackageIdentifier = Self.defaultStoryPassPackageIdentifier
            super.init()
            return
        }

        let configuredKey = Self.configurationValue(
            key: "REVENUECAT_PUBLIC_SDK_KEY",
            bundle: bundle
        )
        apiKey = configuredKey
        storyPassPackageIdentifier = Self.configurationValue(
            key: "REVENUECAT_STORY_PASS_PACKAGE_ID",
            bundle: bundle
        ) ?? Self.defaultStoryPassPackageIdentifier
        super.init()

        guard let configuredKey else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: configuredKey)
        }
        isConfigured = true
    }

    func refresh() async {
        guard isConfigured, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            storefrontCurrencyCode = await Storefront.current?.currency?.identifier
            let offerings = try await Purchases.shared.offerings()
            packages = Self.sortedPackages(from: offerings.current)
                .filter(isStoryPass)
            message = packages.isEmpty
                ? "Story Pass isn't available for this build yet."
                : nil
        } catch {
            message = Self.userFacingMessage(for: error, action: .loading)
        }
    }

    @discardableResult
    func purchase(_ package: Package, unlockingStoryID storyID: String? = nil) async -> Bool {
        guard isConfigured, !isPurchasing else { return false }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return false }
            if isStoryPass(package), let storyID {
                unlockStory(storyID)
                return true
            }
            message = "The Story Pass purchase completed, but this story could not be unlocked. Please contact support."
            return false
        } catch {
            message = Self.userFacingMessage(for: error, action: .purchasing)
            return false
        }
    }

    func clearMessage() {
        message = nil
    }

    var storyPassPackage: Package? {
        packages.first(where: isStoryPass)
    }

    /// Sandbox product metadata may disagree with Apple's final payment sheet.
    /// Never show a number when its storefront currency cannot be verified.
    func displayPrice(for package: Package) -> String? {
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return nil
        }
        guard let storefrontCurrencyCode,
              let productCurrencyCode = package.storeProduct.currencyCode,
              storefrontCurrencyCode.caseInsensitiveCompare(productCurrencyCode) == .orderedSame else {
            return nil
        }
        return package.localizedPriceString
    }

    func hasFullExportAccess(for storyID: String) -> Bool {
        grantsQAFullExportAccess || unlockedStoryIDs.contains(storyID)
    }

    func isStoryPass(_ package: Package) -> Bool {
        if package.identifier == storyPassPackageIdentifier { return true }
        let productID = package.storeProduct.productIdentifier.lowercased()
        return package.packageType == .custom
            && productID.contains("story")
            && (productID.contains("pass") || productID.contains("export"))
    }

    private var unlockedStoryIDs: Set<String> {
        Set(defaults.stringArray(forKey: unlockedStoriesKey) ?? [])
    }

    private func unlockStory(_ storyID: String) {
        var unlocked = unlockedStoryIDs
        unlocked.insert(storyID)
        defaults.set(Array(unlocked).sorted(), forKey: unlockedStoriesKey)
    }

    private static func configurationValue(key: String, bundle: Bundle) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    enum PurchaseAction {
        case loading
        case purchasing
    }

    private static func userFacingMessage(for error: Error, action: PurchaseAction) -> String {
        let code = ErrorCode(rawValue: (error as NSError).code)

        switch code {
        case .purchaseCancelledError:
            return "Purchase cancelled. Nothing was charged."
        case .networkError, .offlineConnectionError, .productRequestTimedOut:
            return "The App Store couldn't be reached. Check your connection and try again."
        case .purchaseNotAllowedError, .insufficientPermissionsError:
            return "Purchases aren't allowed on this device. Check Screen Time or Apple ID settings."
        case .paymentPendingError:
            return "This purchase is waiting for approval. Full access will unlock when Apple confirms it."
        case .productNotAvailableForPurchaseError:
            return "This option isn't available in the App Store right now. Please try again later."
        case .productAlreadyPurchasedError:
            return "This Story Pass was already recorded. Return to the story and try exporting again."
        case .storeProblemError:
            return "The App Store couldn't complete the request. Please wait a moment and try again."
        case .invalidCredentialsError, .configurationError, .invalidAppleSubscriptionKeyError:
            return "Purchases are temporarily unavailable while we update the store configuration."
        default:
            switch action {
            case .loading:
                return "Export options couldn't be loaded. Check your connection and try again."
            case .purchasing:
                return "The purchase couldn't be completed. Nothing was charged. Please try again."
            }
        }
    }

    private static func sortedPackages(from offering: Offering?) -> [Package] {
        guard let offering else { return [] }
        return offering.availablePackages.sorted { $0.identifier < $1.identifier }
    }
}
