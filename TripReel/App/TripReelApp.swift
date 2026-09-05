import SwiftUI

@main
struct TripReelApp: App {
    @StateObject private var model = TripReelModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await model.refreshPhotoLibraryIfAuthorized()
            }
        }
    }
}
