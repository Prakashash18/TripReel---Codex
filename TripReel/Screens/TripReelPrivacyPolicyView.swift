import SwiftUI

struct TripReelPrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground(variant: .trips)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        policyHeader
                        section(
                            "Photos and trip detection",
                            "With your Photos permission, TripReel reads accessible images, capture dates, and embedded locations to find trips and build a film. Trip detection and grouping happen on your device; TripReel uses Apple's system geocoder to turn one representative coordinate into a place name. Originals remain in Apple Photos unless you explicitly select cut photos in Cleanup, accept TripReel's warning, and confirm Apple's system deletion prompt. With iCloud Photos, that confirmed deletion can affect your other synced devices. Photos you pick without broad library access are copied temporarily into TripReel's private on-device cache for the editing session."
                        )
                        section(
                            "On-device visual intelligence",
                            "Apple Vision analyzes small thumbnails on your iPhone for screenshots, document-like images, people, scenery, food, and visual quality. Recognized text itself is not retained. Photos left out of an automatic cut remain available under More Photos and can be restored."
                        )
                        section(
                            "Optional OpenAI analysis",
                            "Cloud enhancement is off until you explicitly enable it. When enabled, only uncertain reduced-resolution JPEG thumbnail copies may pass through TripReel's secure backend to OpenAI's GPT-5.6 Luna. TripReel re-encodes them without EXIF, GPS, filenames, or stable Apple Photos identifiers. Known screenshots and sensitive or document-like images are blocked from cloud review. The purpose is only to improve the automatic film selection."
                        )
                        section(
                            "Storage and deletion",
                            "TripReel's backend does not persist cloud thumbnails or classification results and discards its in-memory copies after the request. OpenAI is called with store set to false. Under default API controls, OpenAI may retain API content for abuse monitoring for up to 30 days, or longer when legally or safety-required. Zero Data Retention removes default storage for eligible accounts, but images flagged by OpenAI's child-safety classifier may still be retained for manual review."
                        )
                        section(
                            "Training, identity, and tracking",
                            "OpenAI states that API data is not used to train its models by default unless the API organization opts in. TripReel sends per-request placeholder IDs instead of your Photos identifiers and does not use these thumbnails for advertising or cross-app tracking."
                        )
                        section(
                            "Your choices",
                            "You can keep all analysis on-device or change the cloud choice from the Cloud photo intelligence card on the Trips screen. Turning it off prevents future uploads. Revoking Photos access in iOS Settings stops further library access."
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Link(
                                "OpenAI API data controls",
                                destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!
                            )
                            Link(
                                "TripReel support",
                                destination: URL(string: "https://github.com/Prakashash18/TripReel---Codex/issues")!
                            )
                        }
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)

                        Text("Effective September 5, 2026")
                            .font(TR.mono(10))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.38))
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .foregroundStyle(TR.cream)
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(TR.ui(14, weight: .semibold))
                }
            }
        }
        .tint(TR.accent)
        .accessibilityIdentifier("tripreel-privacy-policy")
    }

    private var policyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataText(text: "TripReel")
            Text("Your memories stay yours.")
                .font(TR.display(34))
            Text("This policy explains what TripReel processes on your iPhone and what happens only if you opt in to cloud enhancement.")
                .font(TR.ui(14))
                .foregroundStyle(.white.opacity(0.66))
                .lineSpacing(4)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(TR.ui(15, weight: .semibold))
            Text(body)
                .font(TR.ui(13))
                .foregroundStyle(.white.opacity(0.64))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
