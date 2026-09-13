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
    @State private var previewTravels = false
    @State private var sparklePulses = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    previewFlow
                    safetySummary
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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: false)) {
                previewTravels = true
            }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                sparklePulses = true
            }
        }
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

            Text("Let AI shape the story")
                .font(TR.display(36))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)

            Text("You choose the moments. Memories sends small previews to OpenAI’s GPT-5.6 Luna.")
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

    private var previewFlow: some View {
        HStack(spacing: 12) {
            flowEndpoint(symbol: "iphone", label: "Your iPhone")

            ZStack {
                Capsule()
                    .fill(.white.opacity(0.13))
                    .frame(height: 2)
                Image(systemName: "photo.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .frame(width: 34, height: 42)
                    .background(TR.sheet)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(TR.accent.opacity(0.45)))
                    .offset(x: reduceMotion ? 0 : (previewTravels ? 32 : -32))
                    .opacity(reduceMotion ? 1 : (previewTravels ? 0.35 : 1))
            }
            .frame(maxWidth: .infinity)

            flowEndpoint(symbol: "sparkles", label: "AI Director")
                .scaleEffect(sparklePulses && !reduceMotion ? 1.06 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reduced previews move securely from this iPhone to OpenAI")
    }

    private func flowEndpoint(symbol: String, label: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TR.accent)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.24))
                .clipShape(Circle())
            Text(label)
                .font(TR.ui(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var safetySummary: some View {
        HStack(spacing: 8) {
            compactSafetyLabel("Originals stay here", symbol: "iphone")
            compactSafetyLabel("First Cut stays safe", symbol: "checkmark.shield")
        }
    }

    private func compactSafetyLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(TR.ui(10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.70))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06))
            .clipShape(Capsule())
    }

    private var dataDetails: some View {
        DisclosureGroup(isExpanded: $showsDataDetails) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Memories also sends First Cut title text, order, pacing, motion, music and style, plus broad on-device cues such as relative day, orientation, scene category and score bands. A preview can contain text visible in the image, but Memories does not send extracted OCR text, GPS, exact dates, filenames or stable Photos IDs. Memories’ Cloudflare service passes this request to OpenAI and does not intentionally store it. OpenAI API data is not used for training by default and may be retained for abuse monitoring for up to 30 days, or longer when legally or safety-required. Child-safety review exceptions may apply.")
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
                    ? (isSettings ? "Allow AI Director" : "Allow & continue")
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
