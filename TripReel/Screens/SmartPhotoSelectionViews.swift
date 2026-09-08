import SwiftUI

struct PhotoAnalysisProgressOverlay: View {
    let progress: Double
    let status: String
    let usesCloud: Bool
    let currentAsset: TripAsset?
    let recentAssets: [TripAsset]
    let processedCount: Int
    let totalCount: Int
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    private var motionReduced: Bool {
        reduceMotion
    }

    private var backdropAsset: TripAsset? {
        currentAsset ?? recentAssets.last
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if let backdropAsset {
                    PhotoAssetView(source: backdropAsset.source)
                        .scaleEffect(1.18)
                        .blur(radius: 42)
                        .saturation(0.72)
                        .opacity(0.48)
                        .transition(.opacity)
                }

                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.035, blue: 0.018).opacity(0.90),
                        .black.opacity(0.80),
                        .black.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Circle()
                    .fill(TR.accent.opacity(glow ? 0.16 : 0.08))
                    .frame(width: 330, height: 330)
                    .blur(radius: 70)
                    .offset(y: -70)

                VStack(spacing: 0) {
                    HStack {
                        MetadataText(text: "TRIPREEL · FIRST CUT", color: .white.opacity(0.60))
                        Spacer()
                        Label(
                            usesCloud ? "ON-DEVICE + LUNA" : "ON THIS IPHONE",
                            systemImage: usesCloud ? "sparkles" : "lock.fill"
                        )
                        .font(TR.mono(9))
                        .tracking(0.7)
                        .foregroundStyle(usesCloud ? TR.accent : TR.keep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.28))
                        .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 44)

                    Spacer(minLength: 18)

                    AnalysisPhotoDeck(
                        currentAsset: currentAsset,
                        recentAssets: recentAssets,
                        width: min(
                            min(274, proxy.size.width * 0.68),
                            proxy.size.height * 0.32
                        ),
                        reduceMotion: motionReduced
                    )
                    .frame(height: min(358, proxy.size.height * 0.41))
                    .trEntrance(0, distance: 12)

                    VStack(spacing: 8) {
                        Text("Finding your story")
                            .font(TR.display(34))
                            .multilineTextAlignment(.center)
                        Text(status)
                            .font(TR.ui(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .contentTransition(.numericText())
                    }
                    .padding(.top, 20)
                    .trEntrance(1, distance: 8)

                    AnalysisContactStrip(assets: recentAssets)
                        .frame(height: 48)
                        .padding(.top, 18)

                    VStack(spacing: 9) {
                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [TR.accent.opacity(0.72), TR.accent],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: bar.size.width * max(0.015, min(1, progress)))
                                    .animation(motionReduced ? nil : TRMotion.progress, value: progress)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            MetadataText(
                                text: "\(processedCount) MOMENTS READ",
                                color: .white.opacity(0.48)
                            )
                            Spacer()
                            MetadataText(
                                text: totalCount > 0 ? "\(totalCount) TOTAL" : "PREPARING",
                                color: .white.opacity(0.48)
                            )
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 17)

                    Spacer(minLength: 16)

                    VStack(spacing: 12) {
                        Text(privacyNote)
                            .font(TR.ui(10))
                            .foregroundStyle(.white.opacity(0.38))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)

                        Button("Cancel", action: onCancel)
                            .font(TR.ui(13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.66))
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 10)
                }
                .padding(.bottom, 14)
            }
        }
        .ignoresSafeArea()
        .task(id: motionReduced) {
            glow = false
            guard !motionReduced else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            glow = true
        }
        .animation(
            motionReduced ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
            value: glow
        )
        .animation(
            motionReduced ? .easeInOut(duration: 0.16) : TRMotion.cardArrival,
            value: currentAsset?.id
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analyzing photos, \(Int(progress * 100)) percent")
        .accessibilityIdentifier("smart-photo-analysis-progress")
    }

    private var privacyNote: String {
        usesCloud
            ? "Most work stays here. Only consented, uncertain thumbnail copies may be reviewed by OpenAI's GPT-5.6 Luna."
            : "Faces, scenes, quality, and similar moments are compared privately on this iPhone."
    }
}

private struct AnalysisPhotoDeck: View {
    let currentAsset: TripAsset?
    let recentAssets: [TripAsset]
    let width: CGFloat
    let reduceMotion: Bool

    private var deckAssets: [TripAsset] {
        var assets = recentAssets
        if let currentAsset {
            assets.removeAll { $0.id == currentAsset.id }
            assets.append(currentAsset)
        }
        return Array(assets.suffix(3))
    }

    var body: some View {
        ZStack {
            if deckAssets.isEmpty {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.055))
                    .overlay {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.white.opacity(0.26))
                    }
                    .frame(width: width, height: width * 1.24)
            } else {
                ForEach(Array(deckAssets.enumerated()), id: \.element.id) { index, asset in
                    let depth = deckAssets.count - index - 1
                    ProcessingPhotoCard(asset: asset, active: depth == 0, reduceMotion: reduceMotion)
                        .frame(width: width, height: width * 1.24)
                        .scaleEffect(1 - CGFloat(depth) * 0.055)
                        .offset(
                            x: CGFloat(depth) * (index.isMultiple(of: 2) ? -13 : 13),
                            y: CGFloat(depth) * -13
                        )
                        .rotationEffect(.degrees(Double(depth) * (index.isMultiple(of: 2) ? -3.4 : 3.4)))
                        .zIndex(Double(index))
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.94))
                        )
                }
            }
        }
    }
}

private struct ProcessingPhotoCard: View {
    let asset: TripAsset
    let active: Bool
    let reduceMotion: Bool
    @State private var scanning = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PhotoAssetView(source: asset.source)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.08), .black.opacity(0.60)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if active {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, TR.accent.opacity(0.82), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1.5)
                        .shadow(color: TR.accent.opacity(0.8), radius: 8)
                        .offset(y: scanning ? proxy.size.height * 0.43 : -proxy.size.height * 0.43)

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("READING MOMENT")
                    }
                    .font(TR.mono(9))
                    .tracking(0.8)
                    .foregroundStyle(TR.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.46))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(active ? TR.accent.opacity(0.34) : .white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.64), radius: 28, y: 20)
        }
        .task(id: AnalysisCardMotionKey(assetID: asset.id, reduceMotion: reduceMotion)) {
            scanning = false
            guard active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                scanning = true
            }
        }
    }
}

private struct AnalysisCardMotionKey: Hashable {
    let assetID: String
    let reduceMotion: Bool
}

private struct AnalysisContactStrip: View {
    let assets: [TripAsset]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(assets.suffix(5))) { asset in
                ZStack(alignment: .bottomTrailing) {
                    PhotoAssetView(source: asset.source)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(TR.ink)
                        .frame(width: 14, height: 14)
                        .background(TR.keep)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.black.opacity(0.28), lineWidth: 1))
                        .offset(x: 3, y: 3)
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.82))
                )
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : TRMotion.cardArrival,
            value: assets.map(\.id)
        )
    }
}

struct SmartSelectionReviewView: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var includeFeedback = 0

    var body: some View {
        ZStack {
            WarmBackground(variant: .cleanup)

            VStack(spacing: 0) {
                SheetHeader(title: "More Photos") { dismiss() }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                Text("TripReel kept these photos out of the automatic cut. Nothing was deleted. Add back anything that matters to you.")
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(4)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                if let followUp = model.photoAnalysisFollowUp {
                    photoAnalysisFollowUpCard(followUp)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }

                if model.visibleExcludedPhotos.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(TR.keep)
                        Text("Everything is in your film")
                            .font(TR.display(24))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(model.visibleExcludedPhotos) { excluded in
                                excludedRow(excluded)
                                    .transition(
                                        reduceMotion
                                            ? .opacity
                                            : .opacity.combined(with: .offset(x: 18))
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .foregroundStyle(TR.cream)
        .sensoryFeedback(.selection, trigger: includeFeedback)
        .accessibilityIdentifier("smart-selection-review")
    }

    private func photoAnalysisFollowUpCard(_ followUp: PhotoAnalysisFollowUp) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .frame(width: 30, height: 30)
                    .background(TR.accent.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Your preview is ready")
                        .font(TR.ui(15, weight: .semibold))
                    Text("Enjoy it now. TripReel can check a few more moments whenever you choose.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineSpacing(3)
                }
            }

            VStack(spacing: 9) {
                if followUp.syncingFromPhotosCount > 0 {
                    followUpRow(
                        "Still syncing from Photos",
                        count: followUp.syncingFromPhotosCount,
                        symbol: "icloud.and.arrow.down"
                    )
                }
                if followUp.anotherLookCount > 0 {
                    followUpRow(
                        "Ready for another look",
                        count: followUp.anotherLookCount,
                        symbol: "magnifyingglass"
                    )
                }
                if followUp.accessNeededCount > 0 {
                    followUpRow(
                        "May need Photos access",
                        count: followUp.accessNeededCount,
                        symbol: "photo.on.rectangle"
                    )
                }
            }

            Button {
                model.retryPhotoAnalysisFollowUp()
                dismiss()
            } label: {
                Label("Check again now", systemImage: "arrow.clockwise")
                    .font(TR.ui(13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(TR.ink)
                    .background(TR.cream)
                    .clipShape(Capsule())
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityIdentifier("photo-analysis-retry-button")
            .accessibilityHint("Checks the source trip again and refreshes the preview")
        }
        .padding(15)
        .glassCard(cornerRadius: 18)
    }

    private func followUpRow(
        _ title: String,
        count: Int? = nil,
        detail: String? = nil,
        symbol: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .frame(width: 18)
            Text(title)
                .font(TR.ui(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            if let count {
                Text("\(count)")
                    .font(TR.mono(11))
                    .foregroundStyle(.white.opacity(0.52))
            } else if let detail {
                Text(detail)
                    .font(TR.ui(10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private func excludedRow(_ excluded: SmartExcludedPhoto) -> some View {
        HStack(spacing: 13) {
            PhotoAssetView(source: excluded.asset.source)
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Label(excluded.reason.title, systemImage: excluded.reason.symbol)
                    .font(TR.ui(13, weight: .semibold))
                    .foregroundStyle(TR.accent)
                Text(excluded.detail)
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(2)
                Text(excluded.origin.title)
                    .font(TR.mono(9))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.36))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if excluded.reason == .waitingForPhotos {
                Text("Check later")
                    .font(TR.ui(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.07))
                    .clipShape(Capsule())
                    .accessibilityLabel("Photo is not ready yet")
            } else {
                Button("Include") {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : TRMotion.cardDismiss) {
                        model.includeExcludedPhoto(id: excluded.id)
                    }
                    includeFeedback += 1
                }
                .font(TR.ui(12, weight: .semibold))
                .foregroundStyle(TR.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(TR.cream)
                .clipShape(Capsule())
                .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
                .accessibilityLabel("Include \(excluded.asset.filename.isEmpty ? "photo" : excluded.asset.filename)")
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 17)
    }
}
