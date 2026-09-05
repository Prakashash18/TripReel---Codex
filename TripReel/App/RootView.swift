import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.screen {
            case .welcome:
                WelcomeScreen()
            case .access:
                PhotoAccessScreen()
            case .limited:
                LimitedAccessScreen()
            case .trips:
                TripsScreen()
            case .empty:
                EmptyTripsScreen()
            case .building:
                BuildingScreen()
            case .firstWatch:
                FirstWatchScreen()
            case .cut:
                CutScreen()
            case .pace:
                PaceScreen()
            case .secondWatch:
                SecondWatchScreen()
            case .export:
                ExportScreen()
            case .paywall:
                PaywallScreen()
            case .rendering:
                RenderingScreen()
            case .done:
                FilmReadyScreen()
            case .cleanup:
                CleanupScreen()
            }
        }
        .id(model.screen.rawValue)
        .transition(.opacity.combined(with: .scale(scale: 1.008)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: model.screen)
        .background(Color.black)
        .foregroundStyle(TR.cream)
        .tint(TR.accent)
    }
}
