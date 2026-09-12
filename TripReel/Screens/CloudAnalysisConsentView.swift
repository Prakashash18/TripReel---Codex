import SwiftUI

/// Explicit opt-in shown before the user chooses an AI direction or selects
/// upload candidates. Opening or dismissing this view never prepares a photo.
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

    private var isSettings: Bool {
        if case .settings = context { return true }
        return false
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .access)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    introduction
                    essentials
                    dataDetails
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
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
            MetadataText(text: "AI Director · no upload yet", color: TR.accent)
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
            .accessibilityLabel("Not now")
            .accessibilityHint("Closes without sharing any preview")
            .accessibilityIdentifier("cloud-analysis-close")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(TR.accent.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(TR.accent)
            }
            .accessibilityHidden(true)

            Text("Before AI sees your moments")
                .font(TR.display(36))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)

            Text("With your permission, Memories sends small photo previews or sampled video frames you choose to OpenAI’s GPT-5.6 Luna.")
                .font(TR.ui(15))
                .foregroundStyle(.white.opacity(0.76))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if !cloudServiceAvailable {
                Label(
                    "AI Director isn’t available in this build. Your First Cut is still ready.",
                    systemImage: "iphone.slash"
                )
                .font(TR.ui(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var essentials: some View {
        VStack(spacing: 0) {
            essentialRow(
                symbol: "checkmark.circle",
                title: "Choose the moments next",
                detail: "Nothing is selected or sent on this screen."
            )
            Divider().overlay(.white.opacity(0.10)).padding(.leading, 56)
            essentialRow(
                symbol: "photo.on.rectangle",
                title: "Previews, not originals",
                detail: "Full videos, sound, filenames, dates and locations stay private."
            )
            Divider().overlay(.white.opacity(0.10)).padding(.leading, 56)
            essentialRow(
                symbol: "timeline.selection",
                title: "AI compares your First Cut",
                detail: "It receives your order, titles and broad on-device scene and timing cues."
            )
            Divider().overlay(.white.opacity(0.10)).padding(.leading, 56)
            essentialRow(
                symbol: "checkmark.shield",
                title: "Your First Cut stays safe",
                detail: "You can keep it instead of the AI version."
            )
        }
        .padding(.horizontal, 15)
        .glassCard(cornerRadius: 20)
    }

    private func essentialRow(symbol: String, title: String, detail: String) -> some View {
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Memories also sends First Cut title text, order, pacing, motion, music and style, plus broad on-device cues such as relative day, orientation, scene category and score bands. It does not send GPS, exact dates, filenames, OCR text or stable Photos IDs. Memories’ Cloudflare service passes this request to OpenAI and does not intentionally store it. OpenAI API data is not used for training by default and may be retained for abuse monitoring for up to 30 days, or longer when legally or safety-required. Child-safety review exceptions may apply.")
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Link(
                    "OpenAI API data controls",
                    destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!
                )
                .font(TR.ui(12, weight: .semibold))
                .foregroundStyle(TR.accent)
            }
            .padding(.top, 11)
        } label: {
            Label("Privacy details", systemImage: "lock.shield")
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

    private var actions: some View {
        VStack(spacing: 10) {
            Button(
                cloudServiceAvailable
                    ? (isSettings ? "Allow cloud enhancement" : "Allow & choose moments")
                    : "AI Director unavailable",
                action: onUseCloudEnhancement
            )
            .buttonStyle(CreamButtonStyle())
            .disabled(!cloudServiceAvailable)
            .opacity(cloudServiceAvailable ? 1 : 0.55)
            .accessibilityHint("Gives permission, then lets you choose which photo previews or sampled video frames may be sent")
            .accessibilityIdentifier("cloud-analysis-accept")

            Button("Not now", action: onKeepOnDevice)
                .font(TR.ui(15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .buttonStyle(.plain)
                .accessibilityHint("Closes without sharing any preview")
                .accessibilityIdentifier("cloud-analysis-decline")

            Button("Memories privacy policy") { showsPrivacyPolicy = true }
                .font(TR.ui(12, weight: .medium))
                .foregroundStyle(TR.accent)
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripreel-privacy-policy-link")
        }
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
