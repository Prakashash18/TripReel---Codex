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
        .alert(
            "Photo Library",
            isPresented: Binding(
                get: { model.libraryErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { model.dismissLibraryMessage() }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.dismissLibraryMessage()
            }
        } message: {
            Text(model.libraryErrorMessage ?? "")
        }
        .sheet(isPresented: $model.isCloudAnalysisConsentPresented) {
            CloudAnalysisConsentView(
                context: model.cloudConsentIsSettings ? .settings : .firstUse,
                cloudServiceAvailable: model.cloudAnalysisIsConfigured,
                onUseCloudEnhancement: {
                    model.useCloudEnhancement()
                },
                onKeepOnDevice: {
                    model.keepAnalysisOnDevice()
                }
            )
            .interactiveDismissDisabled()
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(26)
            .presentationBackground(TR.sheet)
        }
        .sheet(isPresented: $model.isSmartSelectionReviewPresented) {
            SmartSelectionReviewView()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .overlay {
            if model.isAnalyzingPhotos {
                PhotoAnalysisProgressOverlay(
                    progress: model.photoAnalysisProgress,
                    status: model.photoAnalysisStatus,
                    usesCloud: model.cloudAnalysisIsEnabled && model.cloudAnalysisIsConfigured,
                    currentAsset: model.photoAnalysisCurrentAsset,
                    recentAssets: model.photoAnalysisRecentAssets,
                    processedCount: model.photoAnalysisProcessedCount,
                    totalCount: model.photoAnalysisTotalCount,
                    onCancel: model.cancelPhotoAnalysis
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isAnalyzingPhotos)
    }
}
