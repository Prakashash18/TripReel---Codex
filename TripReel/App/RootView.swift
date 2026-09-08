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
            case .firstCutOptions:
                FirstCutOptionsScreen()
            case .aiDirection:
                AICutDirectionScreen()
            case .aiProcessing:
                AICutProcessingScreen()
            case .aiComparison:
                AICutComparisonScreen()
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
        .transition(
            TRMotion.screenTransition(
                direction: model.navigationDirection,
                prefersCrossFade: reduceMotion
            )
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : TRMotion.navigation,
            value: model.screen
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .global)
                .onEnded { value in
                    guard model.canNavigateBack,
                          value.startLocation.x <= 24,
                          value.translation.width >= 72,
                          abs(value.translation.height) < 54 else { return }
                    model.navigateBack()
                }
        )
        .accessibilityAction(.escape) {
            if model.canNavigateBack { model.navigateBack() }
        }
        .background(Color.black)
        .foregroundStyle(TR.cream)
        .tint(TR.accent)
        .overlay(alignment: .topLeading) {
            if model.canNavigateBack {
                Button {
                    model.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TR.cream)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.58))
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
                .padding(.leading, 16)
                .safeAreaPadding(.top, 7)
                .accessibilityLabel("Back")
                .accessibilityHint("Returns to the previous step")
                .accessibilityIdentifier("app-back-button")
                .zIndex(10)
            }
        }
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
                context: model.cloudConsentIsSettings
                    ? .settings
                    : .aiRemix(model.selectedAICutDirection ?? .betterStory),
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
                    usesCloud: false,
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
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : TRMotion.overlay, value: model.isAnalyzingPhotos)
    }
}
