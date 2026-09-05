import SwiftUI

@main
struct TripReelApp: App {
    @StateObject private var model = TripReelModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}
