import SwiftUI

struct PhotoAnalysisProgressOverlay: View {
    let progress: Double
    let status: String
    let usesCloud: Bool
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, progress)))
                        .stroke(TR.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(TR.accent)
                }
                .frame(width: 76, height: 76)

                VStack(spacing: 8) {
                    Text("Finding the best moments")
                        .font(TR.display(29))
                    Text(status)
                        .font(TR.ui(13))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                    if usesCloud {
                        Text("Consented thumbnail copies may be reviewed by GPT-5.6 Luna")
                            .font(TR.ui(11))
                            .foregroundStyle(.white.opacity(0.43))
                            .multilineTextAlignment(.center)
                    }
                }

                Button("Cancel", action: onCancel)
                    .font(TR.ui(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 330)
            .glassCard(cornerRadius: 24)
            .padding(.horizontal, 30)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analyzing photos, \(Int(progress * 100)) percent")
        .accessibilityIdentifier("smart-photo-analysis-progress")
    }
}

struct SmartSelectionReviewView: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss

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

                if model.excludedPhotos.isEmpty {
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
                            ForEach(model.excludedPhotos) { excluded in
                                excludedRow(excluded)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .foregroundStyle(TR.cream)
        .accessibilityIdentifier("smart-selection-review")
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

            Button("Include") {
                model.includeExcludedPhoto(id: excluded.id)
            }
            .font(TR.ui(12, weight: .semibold))
            .foregroundStyle(TR.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(TR.cream)
            .clipShape(Capsule())
            .buttonStyle(.plain)
            .accessibilityLabel("Include \(excluded.asset.filename.isEmpty ? "photo" : excluded.asset.filename)")
        }
        .padding(10)
        .glassCard(cornerRadius: 17)
    }
}
