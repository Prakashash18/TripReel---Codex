import SwiftUI

@main
struct TripReelApp: App {
    @StateObject private var model = TripReelModel()
    @StateObject private var purchases = RevenueCatPurchaseService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(purchases)
                .preferredColorScheme(.dark)
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
