import SwiftUI

/// An explicit, reusable opt-in surface for TripReel's optional cloud photo analysis.
///
/// Present this view before starting any upload. Both the close button and
/// `Keep on device` invoke `onKeepOnDevice`, so dismissing the decision can never
/// be interpreted as consent.
struct CloudAnalysisConsentView: View {
    enum Context: Equatable {
        case firstUse
        case settings
    }

    let context: Context
    var cloudServiceAvailable = true
    let onUseCloudEnhancement: () -> Void
    let onKeepOnDevice: () -> Void

    @State private var showsDataDetails = false
    @State private var showsPrivacyPolicy = false

    init(
        context: Context = .firstUse,
        cloudServiceAvailable: Bool = true,
        onUseCloudEnhancement: @escaping () -> Void,
        onKeepOnDevice: @escaping () -> Void
    ) {
        self.context = context
        self.cloudServiceAvailable = cloudServiceAvailable
        self.onUseCloudEnhancement = onUseCloudEnhancement
        self.onKeepOnDevice = onKeepOnDevice
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .access)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    introduction
                    cloudReviewSummary
                    dataDetails
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
        .foregroundStyle(TR.cream)
        .accessibilityIdentifier("cloud-analysis-consent")
        .sheet(isPresented: $showsPrivacyPolicy) {
            TripReelPrivacyPolicyView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            MetadataText(text: context == .firstUse ? "Optional OpenAI review" : "Photo review settings")

            Spacer()

            Button(action: onKeepOnDevice) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.09))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close and keep photos on device")
            .accessibilityHint("Declines cloud photo analysis. No photo will be uploaded.")
            .accessibilityIdentifier("cloud-analysis-close")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(TR.accent.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(TR.accent)
            }
            .accessibilityHidden(true)

            Text(context == .firstUse ? "A second opinion for tricky photos" : "Choose how tricky photos are reviewed")
                .font(TR.display(36))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your iPhone makes the first cut. When it is unsure, OpenAI's image model, GPT-5.6 Luna, can look at a small thumbnail copy and help TripReel decide what belongs in your film.")
                .font(TR.ui(15))
                .foregroundStyle(.white.opacity(0.76))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Label("Optional · off by default", systemImage: "checkmark.shield")
                .font(TR.ui(13, weight: .semibold))
                .foregroundStyle(TR.keep)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(TR.keep.opacity(0.10))
                .overlay(Capsule().stroke(TR.keep.opacity(0.28), lineWidth: 1))
                .clipShape(Capsule())

            if !cloudServiceAvailable {
                Label(
                    "Cloud enhancement isn't configured in this build. On-device analysis is ready.",
                    systemImage: "wrench.and.screwdriver"
                )
                .font(TR.ui(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cloudReviewSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetadataText(text: "What happens", color: .white.opacity(0.52))

            VStack(spacing: 0) {
                reviewStep(
                    number: 1,
                    symbol: "iphone",
                    title: "Your iPhone checks first",
                    body: "Apple Vision analyzes every photo privately on the device."
                )

                stepDivider

                reviewStep(
                    number: 2,
                    symbol: "sparkles.rectangle.stack",
                    title: "OpenAI sees only the unsure ones",
                    body: "A thumbnail up to 512 pixels is sent without its filename, location, or other photo metadata. Your full-resolution original stays in Photos."
                )

                stepDivider

                reviewStep(
                    number: 3,
                    symbol: "trash.slash",
                    title: "TripReel uses the answer, not the copy",
                    body: "The result helps shape this film. TripReel discards its temporary thumbnail after review."
                )

                stepDivider

                reviewStep(
                    number: 4,
                    symbol: "hand.raised",
                    title: "You can keep everything local",
                    body: "Say no and Smart Selection still works entirely on your iPhone."
                )
            }
            .padding(.horizontal, 16)
            .glassCard(cornerRadius: 20)
            .accessibilityElement(children: .contain)

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Why use it")
                        .font(TR.ui(13, weight: .semibold))
                    Text("It can help with borderline screenshots, order or receipt photos, and low-quality shots while keeping travel and people moments in your hands.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(TR.accent.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TR.accent.opacity(0.24), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var dataDetails: some View {
        DisclosureGroup(isExpanded: $showsDataDetails) {
            VStack(alignment: .leading, spacing: 14) {
                handlingPoint(
                    title: "Default retention",
                    body: "OpenAI may retain API content for abuse monitoring for up to 30 days, or longer when legally or safety-required."
                )

                handlingPoint(
                    title: "Zero Data Retention",
                    body: "OpenAI-approved accounts can remove that default storage. Images flagged by OpenAI's child-safety classifier may still be retained for manual review."
                )

                handlingPoint(
                    title: "Model training",
                    body: "API data is not used to train OpenAI models by default."
                )

                Link(
                    "OpenAI API data controls",
                    destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!
                )
                .font(TR.ui(12, weight: .semibold))
                .foregroundStyle(TR.accent)
                .accessibilityHint("Opens OpenAI's API data controls documentation")

                Text("You can change this choice later from the OpenAI review card on the Trips screen.")
                    .font(TR.ui(12))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(.top, 12)
        } label: {
            Label("How OpenAI handles the thumbnail", systemImage: "lock.shield")
                .font(TR.ui(14, weight: .semibold))
                .foregroundStyle(TR.cream)
        }
        .tint(TR.accent)
        .padding(16)
        .background(.black.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("cloud-analysis-data-details")
    }

    private func handlingPoint(title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(TR.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TR.ui(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(body)
                    .font(TR.ui(12))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 13) {
            Button(
                cloudServiceAvailable ? "Use OpenAI for tricky photos" : "OpenAI review unavailable",
                action: onUseCloudEnhancement
            )
                .buttonStyle(CreamButtonStyle())
                .disabled(!cloudServiceAvailable)
                .opacity(cloudServiceAvailable ? 1 : 0.55)
                .accessibilityHint("Allows reduced-resolution thumbnail copies to be analyzed by GPT-5.6 Luna")
                .accessibilityIdentifier("cloud-analysis-accept")

            Button("Keep analysis on this iPhone", action: onKeepOnDevice)
                .font(TR.ui(15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .buttonStyle(.plain)
                .accessibilityHint("Declines cloud photo analysis. No photo will be uploaded.")
                .accessibilityIdentifier("cloud-analysis-decline")

            Button("Read TripReel privacy policy") {
                showsPrivacyPolicy = true
            }
            .font(TR.ui(12, weight: .medium))
            .foregroundStyle(TR.accent)
            .buttonStyle(.plain)
            .accessibilityIdentifier("tripreel-privacy-policy-link")
        }
    }

    private var stepDivider: some View {
        Divider()
            .overlay(.white.opacity(0.10))
            .padding(.leading, 58)
    }

    private func reviewStep(
        number: Int,
        symbol: String,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack(alignment: .topTrailing) {
                RoundedIcon(symbol: symbol, tint: TR.accent, size: 40)

                Text("\(number)")
                    .font(TR.mono(8, weight: .bold))
                    .foregroundStyle(TR.ink)
                    .frame(width: 17, height: 17)
                    .background(TR.accent)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TR.ui(14, weight: .semibold))
                Text(body)
                    .font(TR.ui(12))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }
}

/// A compact hook suitable for a future Settings screen. It deliberately owns no
/// preference storage; callers remain the source of truth and decide how to
/// present `CloudAnalysisConsentView` from `onReviewChoice`.
struct CloudAnalysisSettingsCard: View {
    let isEnabled: Bool
    var isAvailable = true
    let onReviewChoice: () -> Void

    var body: some View {
        Button(action: onReviewChoice) {
            HStack(spacing: 13) {
                RoundedIcon(symbol: "sparkles.rectangle.stack", tint: TR.accent, size: 42)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional OpenAI review")
                        .font(TR.ui(15, weight: .semibold))
                    Text(statusText)
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Text("Review")
                    .font(TR.ui(13, weight: .semibold))
                    .foregroundStyle(TR.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TR.accent.opacity(0.75))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(TR.cream)
            .padding(15)
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Optional OpenAI review, \(statusText)")
        .accessibilityHint("Review OpenAI photo analysis and privacy choices")
        .accessibilityIdentifier("cloud-analysis-settings-card")
    }

    private var statusText: String {
        if isEnabled, !isAvailable { return "On · service setup needed" }
        return isEnabled ? "On · OpenAI GPT-5.6 Luna" : "Off · On-device only"
    }
}

#if DEBUG
private struct CloudAnalysisConsentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CloudAnalysisConsentView(
                onUseCloudEnhancement: {},
                onKeepOnDevice: {}
            )
            .previewDisplayName("Cloud analysis consent")

            ZStack {
                WarmBackground(variant: .trips)
                CloudAnalysisSettingsCard(isEnabled: true, onReviewChoice: {})
                    .padding(24)
            }
            .previewDisplayName("Cloud analysis setting")
        }
    }
}
#endif
