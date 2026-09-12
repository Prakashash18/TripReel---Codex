import Foundation
import RevenueCat

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
            "HD export is included with Memories Pro."
        case (false, false, false):
            "This export is included with Memories Pro."
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
final class RevenueCatPurchaseService: NSObject, ObservableObject, PurchasesDelegate {
    static let defaultEntitlementIdentifier = "memories_pro"
    static let defaultStoryPassPackageIdentifier = "story_pass"

    @Published private(set) var isConfigured = false
    @Published private(set) var isPremium = false
    @Published private(set) var packages: [Package] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?

    let entitlementIdentifier: String
    let storyPassPackageIdentifier: String

    private let apiKey: String?
    private let defaults: UserDefaults
    private let unlockedStoriesKey = "memories.unlocked-export-story-ids"

    override convenience init() {
        self.init(bundle: .main)
    }

    init(bundle: Bundle, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-qaPremium") {
            apiKey = nil
            entitlementIdentifier = Self.defaultEntitlementIdentifier
            storyPassPackageIdentifier = Self.defaultStoryPassPackageIdentifier
            super.init()
            isPremium = true
            return
        }
        #endif

        let configuredKey = Self.configurationValue(
            key: "REVENUECAT_PUBLIC_SDK_KEY",
            bundle: bundle
        )
        apiKey = configuredKey
        entitlementIdentifier = Self.defaultEntitlementIdentifier
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
        Purchases.shared.delegate = self
        isConfigured = true

        if let cached = Purchases.shared.cachedCustomerInfo {
            apply(cached)
        }
    }

    func refresh() async {
        guard isConfigured, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let customerInfo = Purchases.shared.customerInfo()
            async let offerings = Purchases.shared.offerings()
            let (resolvedCustomerInfo, resolvedOfferings) = try await (customerInfo, offerings)
            apply(resolvedCustomerInfo)
            packages = Self.sortedPackages(from: resolvedOfferings.current)
            message = packages.isEmpty
                ? "No export options are available for this build yet."
                : nil
        } catch {
            message = "Export options couldn't be loaded. Check your connection and try again."
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
            apply(result.customerInfo)
            if result.userCancelled { return false }
            if isStoryPass(package), let storyID {
                unlockStory(storyID)
                return true
            }
            if !isPremium {
                message = "The purchase completed, but Memories Pro is not active yet. Try Restore Purchases."
            }
            return isPremium
        } catch {
            message = "The purchase couldn't be completed. Please try again."
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        guard isConfigured, !isPurchasing else { return false }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            apply(customerInfo)
            if !isPremium {
                message = "No active Memories Pro purchase was found for this Apple ID."
            }
            return isPremium
        } catch {
            message = "Purchases couldn't be restored. Please try again."
            return false
        }
    }

    func clearMessage() {
        message = nil
    }

    var storyPassPackage: Package? {
        packages.first(where: isStoryPass)
    }

    var proPackages: [Package] {
        packages.filter { !isStoryPass($0) }
    }

    func hasFullExportAccess(for storyID: String) -> Bool {
        isPremium || unlockedStoryIDs.contains(storyID)
    }

    func isStoryPass(_ package: Package) -> Bool {
        if package.identifier == storyPassPackageIdentifier { return true }
        let productID = package.storeProduct.productIdentifier.lowercased()
        return package.packageType == .custom
            && productID.contains("story")
            && (productID.contains("pass") || productID.contains("export"))
    }

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.apply(customerInfo)
        }
    }

    private func apply(_ customerInfo: CustomerInfo) {
        isPremium = customerInfo.entitlements.active[entitlementIdentifier]?.isActive == true
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

    private static func sortedPackages(from offering: Offering?) -> [Package] {
        guard let offering else { return [] }
        return offering.availablePackages.sorted { lhs, rhs in
            let left = packageRank(lhs.packageType)
            let right = packageRank(rhs.packageType)
            if left != right { return left < right }
            return lhs.identifier < rhs.identifier
        }
    }

    private static func packageRank(_ type: PackageType) -> Int {
        switch type {
        case .annual: 0
        case .monthly: 1
        case .lifetime: 2
        case .sixMonth: 3
        case .threeMonth: 4
        case .twoMonth: 5
        case .weekly: 6
        case .custom: 7
        case .unknown: 8
        @unknown default: 9
        }
    }
}

extension Package {
    var memoriesDisplayName: String {
        switch packageType {
        case .annual: "Yearly"
        case .monthly: "Monthly"
        case .lifetime: "Lifetime"
        case .sixMonth: "Six months"
        case .threeMonth: "Three months"
        case .twoMonth: "Two months"
        case .weekly: "Weekly"
        case .custom, .unknown: storeProduct.localizedTitle.isEmpty ? "Memories Pro" : storeProduct.localizedTitle
        @unknown default: "Memories Pro"
        }
    }

    var memoriesPriceDetail: String {
        switch packageType {
        case .annual: "\(localizedPriceString) per year"
        case .monthly: "\(localizedPriceString) per month"
        case .sixMonth: "\(localizedPriceString) every six months"
        case .threeMonth: "\(localizedPriceString) every three months"
        case .twoMonth: "\(localizedPriceString) every two months"
        case .weekly: "\(localizedPriceString) per week"
        case .lifetime: "\(localizedPriceString) once"
        case .custom, .unknown: localizedPriceString
        @unknown default: localizedPriceString
        }
    }
}
