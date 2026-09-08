import SwiftUI

/// Explicit opt-in shown only after the user chooses an AI creative direction.
/// Entering or dismissing this view never starts thumbnail preparation or a request.
struct CloudAnalysisConsentView: View {
    enum Context: Equatable {
        case aiRemix(AICutDirection)
        case settings
    }

    let context: Context
    var cloudServiceAvailable = true
    let onUseCloudEnhancement: () -> Void
    let onKeepOnDevice: () -> Void

    @State private var showsDataDetails = false
    @State private var showsPrivacyPolicy = false

    private var direction: AICutDirection? {
        guard case let .aiRemix(direction) = context else { return nil }
        return direction
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .access)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    introduction
                    permissions
                    privacySummary
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
        HStack {
            MetadataText(text: "AI Remix · your choice", color: TR.accent)
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
            .accessibilityLabel("Close and keep First Cut")
            .accessibilityHint("No photo preview will be uploaded")
            .accessibilityIdentifier("cloud-analysis-close")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack {
                Circle()
                    .fill(TR.accent.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: direction?.symbol ?? "sparkles.rectangle.stack")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(TR.accent)
            }
            .accessibilityHidden(true)

            Text(direction.map { "Create “\($0.title)”" } ?? "Optional AI Remix")
                .font(TR.display(36))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)

            Text("To direct another version, TripReel will send selected reduced photo previews through TripReel's secure service to OpenAI’s GPT-5.6 Luna. Nothing leaves this iPhone until you continue.")
                .font(TR.ui(15))
                .foregroundStyle(.white.opacity(0.76))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Label("Your First Cut always stays available", systemImage: "checkmark.shield")
                .font(TR.ui(13, weight: .semibold))
                .foregroundStyle(TR.keep)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(TR.keep.opacity(0.10))
                .overlay(Capsule().stroke(TR.keep.opacity(0.28), lineWidth: 1))
                .clipShape(Capsule())

            if !cloudServiceAvailable {
                Label(
                    "AI Remix isn't available in this build. Your on-device First Cut is ready.",
                    systemImage: "iphone.slash"
                )
                .font(TR.ui(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissions: some View {
        HStack(alignment: .top, spacing: 12) {
            consentColumn(
                title: "AI can",
                symbol: "checkmark",
                tint: TR.keep,
                items: [
                    "Shape the story and moments",
                    "Write editable title hooks",
                    "Pick bundled music and a look"
                ]
            )

            consentColumn(
                title: "AI can't",
                symbol: "xmark",
                tint: TR.cut,
                items: [
                    "Change originals",
                    "Identify people or places",
                    "Invent photos or external music"
                ]
            )
        }
    }

    private func consentColumn(
        title: String,
        symbol: String,
        tint: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(TR.ui(14, weight: .semibold))
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 15, height: 15)
                    Text(item)
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .glassCard(cornerRadius: 18)
    }

    private var privacySummary: some View {
        VStack(spacing: 0) {
            summaryRow(
                symbol: "photo.stack",
                title: "Reduced previews only",
                detail: "No originals, filenames, dates, locations or Photos identifiers."
            )
            Divider().overlay(.white.opacity(0.10)).padding(.leading, 56)
            summaryRow(
                symbol: "wand.and.stars",
                title: "Editable recommendations return",
                detail: "Story, titles, bundled music, look and photo decisions are applied locally."
            )
            Divider().overlay(.white.opacity(0.10)).padding(.leading, 56)
            summaryRow(
                symbol: "externaldrive.badge.xmark",
                title: "No intentional storage by TripReel",
                detail: "The service processes the request without saving your previews."
            )
        }
        .padding(.horizontal, 15)
        .glassCard(cornerRadius: 20)
    }

    private func summaryRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedIcon(symbol: symbol, tint: TR.accent, size: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(TR.ui(13, weight: .semibold))
                Text(detail)
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    private var dataDetails: some View {
        DisclosureGroup(isExpanded: $showsDataDetails) {
            VStack(alignment: .leading, spacing: 12) {
                detailPoint(
                    title: "External processor",
                    body: "Selected previews are sent to OpenAI’s GPT-5.6 Luna through TripReel's Cloudflare service."
                )
                detailPoint(
                    title: "OpenAI retention",
                    body: "OpenAI may retain API content for abuse monitoring for up to 30 days, or longer when legally or safety-required. Approved Zero Data Retention accounts can remove default storage; child-safety review exceptions may still apply."
                )
                detailPoint(
                    title: "Model training",
                    body: "OpenAI API data is not used to train its models by default."
                )
                Link(
                    "OpenAI API data controls",
                    destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!
                )
                .font(TR.ui(12, weight: .semibold))
                .foregroundStyle(TR.accent)
            }
            .padding(.top, 12)
        } label: {
            Label("How the selected previews are handled", systemImage: "lock.shield")
                .font(TR.ui(14, weight: .semibold))
                .foregroundStyle(TR.cream)
        }
        .tint(TR.accent)
        .padding(16)
        .background(.black.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("cloud-analysis-data-details")
    }

    private func detailPoint(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(TR.ui(12, weight: .semibold))
            Text(body)
                .font(TR.ui(11))
                .foregroundStyle(.white.opacity(0.60))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(
                cloudServiceAvailable ? "Continue with AI" : "AI Remix unavailable",
                action: onUseCloudEnhancement
            )
            .buttonStyle(CreamButtonStyle())
            .disabled(!cloudServiceAvailable)
            .opacity(cloudServiceAvailable ? 1 : 0.55)
            .accessibilityHint("Consents to preparing and sending selected reduced previews")
            .accessibilityIdentifier("cloud-analysis-accept")

            Button("Keep it on-device", action: onKeepOnDevice)
                .font(TR.ui(15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .buttonStyle(.plain)
                .accessibilityHint("Returns to First Cut without uploading any preview")
                .accessibilityIdentifier("cloud-analysis-decline")

            Button("Read TripReel privacy policy") { showsPrivacyPolicy = true }
                .font(TR.ui(12, weight: .medium))
                .foregroundStyle(TR.accent)
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripreel-privacy-policy-link")
        }
    }
}

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
                    Text("Optional AI Remix")
                        .font(TR.ui(15, weight: .semibold))
                    Text(isAvailable ? "First Cut stays on-device · review privacy" : "Unavailable · First Cut still works")
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
        .accessibilityLabel("Optional AI Remix privacy")
        .accessibilityHint("Reviews how selected previews are handled")
        .accessibilityIdentifier("cloud-analysis-settings-card")
    }
}

#if DEBUG
private struct CloudAnalysisConsentView_Previews: PreviewProvider {
    static var previews: some View {
        CloudAnalysisConsentView(
            context: .aiRemix(.betterStory),
            onUseCloudEnhancement: {},
            onKeepOnDevice: {}
        )
    }
}
#endif
