import SwiftUI

@main
struct TripReelApp: App {
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
            Task {
                await model.refreshPhotoLibraryIfAuthorized()
                await purchases.refresh()
            }
        }
    }
}
