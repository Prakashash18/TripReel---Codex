import SwiftUI

@main
struct TripReelApp: App {
    @StateObject private var model = TripReelModel()
    @StateObject private var purchases = RevenueCatPurchaseService()
    @StateObject private var rewardedExports = RewardedExportService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(purchases)
                .environmentObject(rewardedExports)
                .preferredColorScheme(.dark)
                .task { await rewardedExports.prepare() }
                .task { await purchases.refresh() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await model.refreshPhotoLibraryIfAuthorized()
                await purchases.refresh()
            }
        }
    }
}
