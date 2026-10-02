import SwiftUI
import FirebaseCore
import FirebaseAnalytics

final class MemoriesAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MemoriesAnalytics.configure()
        return true
    }
}

@MainActor
enum MemoriesAnalytics {
    static let preferenceKey = "memories.analytics.enabled"

    static func configure() {
        // Tests and ordinary debug sessions must not inflate production installs.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-FIRDebugEnabled") else { return }
        #endif
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        applyPreference(UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true)
    }

    static func applyPreference(_ enabled: Bool) {
        guard FirebaseApp.app() != nil else { return }
        // No account ID or user content is attached to automatic SDK events.
        Analytics.setUserProperty("false", forName: AnalyticsUserPropertyAllowAdPersonalizationSignals)
        Analytics.setAnalyticsCollectionEnabled(enabled)
        MemoriesEngagement.shared.applyPreference(enabled)
        if !enabled { Analytics.resetAnalyticsData() }
    }
}

@main
struct TripReelApp: App {
    @UIApplicationDelegateAdaptor(MemoriesAppDelegate.self) private var appDelegate
    @StateObject private var model = TripReelModel()
    @StateObject private var purchases = RevenueCatPurchaseService()
    @StateObject private var account = MemoryAccountService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(purchases)
                .environmentObject(account)
                .preferredColorScheme(.dark)
                .task {
                    await purchases.refresh()
                    await account.restoreSession()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            model.resumeInterruptedExportIfNeeded()
            model.refreshMyExports()
            Task {
                await model.refreshPhotoLibraryIfAuthorized()
                await purchases.refresh()
            }
        }
    }
}
