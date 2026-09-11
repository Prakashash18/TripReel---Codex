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
                            "Photos and memory grouping",
                            "With your Photos permission, Memories reads accessible images, capture dates, and embedded locations to find meaningful moments and build a film. Detection and grouping happen on your device; Memories uses Apple's system geocoder to turn one representative coordinate into a place name. Originals remain in Apple Photos unless you explicitly select cut photos in Cleanup, accept Memories' warning, and confirm Apple's system deletion prompt. With iCloud Photos, that confirmed deletion can affect your other synced devices. Photos you pick without broad library access are copied temporarily into Memories' private on-device cache for the editing session."
                        )
                        section(
                            "On-device visual intelligence",
                            "Apple Vision analyzes small thumbnails on your iPhone for screenshots, document-like images, people, scenery, food, and visual quality. Recognized text itself is not retained. Photos left out of an automatic cut remain available under More Photos and can be restored."
                        )
                        section(
                            "AI Director",
                            "Your complete First Cut is created on-device without cloud AI. Only after you choose Improve with AI, select a creative direction, and explicitly continue may selected reduced-resolution JPEG previews pass through Memories' secure backend to OpenAI's GPT-5.6 Luna. To let AI compare rather than start blindly, Memories also sends the First Cut's title text, photo order, pacing, motion, soundtrack, and visual treatment, plus broad on-device cues such as relative day, orientation, scene category, people count, similarity group, and score bands. Memories re-encodes previews without EXIF, GPS, filenames, exact capture dates, recognized text, or stable Apple Photos identifiers. Known screenshots and sensitive or document-like images are blocked. OpenAI returns a structured editing plan; Memories validates and applies it locally without changing your originals."
                        )
                        section(
                            "AI video generation",
                            "AI video is a separate, optional feature. Apple Vision privately recommends a beginning and ending on your iPhone, and you can replace either. After you explicitly agree, Memories re-encodes up to two reduced JPEGs without EXIF, GPS, filenames, exact capture dates, or stable Apple Photos identifiers. Those copies pass through Memories' secure backend to OpenRouter, which routes them to ByteDance's Seedance 2.0 to create a six-second vertical story from the first frame to the last, or a four-second animation when only one usable moment is available. Seedance may invent motion or small visual details, so you should review the result. Memories adds the visible title locally after download. Your source photos and existing First Cut are never changed."
                        )
                        section(
                            "Storage and deletion",
                            "Memories' backend does not intentionally persist cloud previews, edit plans, or generated videos and discards in-memory request copies after use. OpenAI is called with store set to false. Under default API controls, OpenAI may retain API content for abuse monitoring for up to 30 days, or longer when legally or safety-required. Zero Data Retention removes default storage for eligible OpenAI requests, but images flagged by OpenAI's child-safety classifier may still be retained for manual review. OpenRouter video generation is not eligible for Zero Data Retention because its asynchronous provider must temporarily retain the input and generated output while the job is processed and retrieved."
                        )
                        section(
                            "Training, identity, and tracking",
                            "OpenAI states that API data is not used to train its models by default unless the API organization opts in. OpenRouter and the selected video provider have their own data terms. Memories sends temporary request or job identifiers instead of your Photos identifiers and does not use these images for advertising or cross-app tracking."
                        )
                        section(
                            "Your choices",
                            "You can finish, export, and manually edit using only the on-device First Cut. Every AI edit starts with an explicit OpenAI sharing decision, followed by photo and creative-direction choices. Nothing is prepared until you tap Create AI cut. The comparison screen shows the verified changes AI made, and you decide whether to use them or keep the First Cut. Declining or closing sends nothing and returns to First Cut. Revoking Photos access in iOS Settings stops further library access."
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Link(
                                "OpenAI API data controls",
                                destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!
                            )
                            Link(
                                "OpenRouter video data notice",
                                destination: URL(string: "https://openrouter.ai/docs/guides/overview/multimodal/video-generation#zero-data-retention")!
                            )
                            Link(
                                "Memories support",
                                destination: URL(string: "https://github.com/Prakashash18/TripReel---Codex/issues")!
                            )
                        }
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)

                        Text("Effective September 11, 2026")
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
            MetadataText(text: TR.appName)
            Text("Your memories stay yours.")
                .font(TR.display(34))
            Text("This policy explains the private on-device First Cut and what happens only if you explicitly request an AI edit.")
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
