import SwiftUI

struct TripReelPrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsTermsOfUse = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground(variant: .trips)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        policyHeader
                        section(
                            "Photos, videos and memory grouping",
                            "With your Photos permission, Memories reads accessible photos and videos, capture dates, durations, and embedded locations to find meaningful moments and build a film. Detection and grouping happen on your device; Memories uses Apple's system geocoder to turn one representative coordinate into a place name. Originals remain in Apple Photos unless you explicitly select cut moments in Cleanup, accept Memories' warning, and confirm Apple's system deletion prompt. With iCloud Photos, that confirmed deletion can affect your other synced devices. Moments you pick without broad library access are copied temporarily into Memories' private on-device cache for the editing session."
                        )
                        section(
                            "On-device visual intelligence",
                            "Apple Vision analyzes small photo thumbnails and a bounded sample of video frames on your iPhone for screenshots, document-like images, people, scenery, food, and visual quality. For video, Memories also compares sampled frames to choose a useful 2–4 second window and avoid static or abrupt sections. Recognized text itself is not retained. Moments left out of an automatic cut remain available under More Moments and can be restored."
                        )
                        section(
                            "AI Director",
                            "Your complete First Cut is created on-device without cloud AI. Only after you choose Improve with AI, select a creative direction, and explicitly continue may selected reduced-resolution JPEG previews pass through Memories' secure backend to OpenAI's GPT-5.6 Luna. A selected video is represented by a small three-frame contact sheet plus coarse clip duration, motion, and whether sound is available; the video file and its audio are not uploaded. To let AI compare rather than start blindly, Memories also sends the First Cut's title text, moment order, pacing, motion, soundtrack, and visual treatment, plus broad on-device cues such as relative day, orientation, scene category, people count, similarity group, and score bands. Memories re-encodes previews without EXIF, GPS, filenames, exact capture dates, recognized text, or stable Apple Photos identifiers. Known screenshots and sensitive or document-like images are blocked. OpenAI returns a structured editing plan; Memories validates and applies it locally without changing your originals."
                        )
                        section(
                            "Storage and deletion",
                            "Memories' backend does not intentionally persist cloud previews or edit plans and discards in-memory request copies after use. OpenAI is called with store set to false. Under default API controls, OpenAI may retain API content for abuse monitoring for up to 30 days, or longer when legally or safety-required. Zero Data Retention removes default storage for eligible OpenAI requests, but images flagged by OpenAI's child-safety classifier may still be retained for manual review."
                        )
                        section(
                            "Training, identity, and tracking",
                            "OpenAI states that API data is not used to train its models by default unless the API organization opts in. Memories sends temporary request identifiers instead of your Photos identifiers and does not use these images for advertising or cross-app tracking."
                        )
                        section(
                            "Purchases",
                            "Apple processes payments. RevenueCat receives an anonymous app user identifier and purchase or subscription status so Memories can unlock full HD exports. RevenueCat never receives your photos, previews, films, titles, or location data. Pro subscriptions can be restored; a one-story pass is a consumable whose memory unlock is retained on the purchasing device."
                        )
                        section(
                            "Your choices",
                            "You can finish, export, and manually edit using only the on-device First Cut. Every AI edit starts with an explicit OpenAI sharing decision, followed by moment and creative-direction choices. Nothing is prepared until you tap Create AI cut. The comparison screen shows the verified changes AI made, and you decide whether to use them or keep the First Cut. Declining or closing sends nothing and returns to First Cut. Revoking Photos access in iOS Settings stops further library access."
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Button("Memories Terms of Use") { showsTermsOfUse = true }
                            Link(
                                "OpenAI API data controls",
                                destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!
                            )
                            Link("RevenueCat privacy policy", destination: URL(string: "https://www.revenuecat.com/privacy")!)
                            Link(
                                "Memories support",
                                destination: URL(string: "https://github.com/Prakashash18/TripReel---Codex/issues")!
                            )
                        }
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)

                        Text("Effective September 13, 2026")
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
        .sheet(isPresented: $showsTermsOfUse) {
            MemoriesTermsOfUseView()
        }
        .accessibilityIdentifier("tripreel-privacy-policy")
    }

    private var policyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataText(text: TR.appStoreName)
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

struct MemoriesTermsOfUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground(variant: .trips)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            MetadataText(text: TR.appStoreName)
                            Text("Your content. Your responsibility.")
                                .font(TR.display(34))
                            Text("These terms explain the permission Memories needs to turn media you choose into a story.")
                                .font(TR.ui(14))
                                .foregroundStyle(.white.opacity(0.66))
                                .lineSpacing(4)
                        }

                        termsSection(
                            "Your rights to imported content",
                            "You may import a photo, video, audio recording, caption, or other material only if you own it or have all permissions needed to use it. This includes copyright and, where applicable, permission from people shown or heard. Do not use Memories to infringe another person's intellectual-property, privacy, publicity, or other rights."
                        )
                        termsSection(
                            "Permission to create your story",
                            "You keep ownership of your content. You give Memories a limited, non-exclusive permission to access, copy, analyze, edit, render, and export only the content you choose, solely to provide the features you request. This permission ends when processing and any disclosed service-provider security or legal retention are complete."
                        )
                        termsSection(
                            "Optional AI Director",
                            "Nothing is sent to OpenAI unless you explicitly approve an AI edit. When you do, the limited permission above also allows Memories and its service providers to process the disclosed reduced previews and editorial information for that request. The original photo and video files remain on your device as described in the Privacy Policy."
                        )
                        termsSection(
                            "Exports and sharing",
                            "You are responsible for reviewing your finished story and confirming that you have the rights and permissions required before saving, publishing, or sharing it. AI-generated titles and edits can be inaccurate and should be checked before use."
                        )
                        termsSection(
                            "Music and app assets",
                            "Music, fonts, graphics, and other assets supplied by Memories remain owned by their respective licensors. You may use them only as incorporated into stories created and exported through Memories. When sharing an export that includes bundled music, preserve or provide the attribution shown in Music Credits."
                        )
                        termsSection(
                            "Purchases",
                            "Purchases are processed by Apple. Subscription billing, renewal, cancellation, and refunds are governed by Apple's terms and the purchase information shown before confirmation."
                        )

                        Link(
                            "Apple Standard EULA",
                            destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                        )
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)

                        Text("Effective September 13, 2026")
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
            .navigationTitle("Terms of Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(TR.ui(14, weight: .semibold))
                }
            }
        }
        .tint(TR.accent)
        .accessibilityIdentifier("memories-terms-of-use")
    }

    private func termsSection(_ title: String, _ body: String) -> some View {
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
