import SwiftUI

struct ExportScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var showProjectSheet = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            VStack(spacing: 0) {
                ScreenHeading(
                    eyebrow: "\(model.keptCount) photos · \(model.durationText)",
                    title: "Export your film",
                    size: 38
                )
                .padding(.horizontal, 26)
                .padding(.top, 4)

                Spacer(minLength: 20)

                VStack(spacing: 14) {
                    ExportOptionCard(
                        source: model.previewSource(at: 0),
                        title: "Standard",
                        subtitle: "720p · watermarked",
                        badge: "FREE",
                        badgeColor: TR.keep,
                        watermark: true,
                        accessibilityID: "export-standard"
                    ) {
                        model.startRender()
                    }

                    ExportOptionCard(
                        source: model.previewSource(at: 2),
                        title: "HD",
                        subtitle: "1080p · no watermark",
                        badge: "PRO",
                        badgeColor: TR.accent,
                        highlighted: true,
                        showsChevron: true,
                        accessibilityID: "export-hd"
                    ) {
                        model.go(.paywall)
                    }

                    Button {
                        showProjectSheet = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "rectangle.stack.badge.play")
                                .font(.system(size: 25, weight: .light))
                                .foregroundStyle(.white.opacity(0.67))
                                .frame(width: 74, height: 96)
                                .background(.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Project file")
                                    .font(TR.ui(18, weight: .semibold))
                                Text("Keep editing in CapCut, Premiere or Final Cut")
                                    .font(TR.ui(13))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineSpacing(2)
                                MetadataText(text: "Free", color: TR.keep)
                            }

                            Spacer(minLength: 4)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.34))
                        }
                        .foregroundStyle(TR.cream)
                        .padding(14)
                        .glassCard(cornerRadius: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("export-project")

                    Text("The watermark sits in the top-right corner, as shown.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.43))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 26)

                Spacer(minLength: 16)

                Button("Back") {
                    model.go(.secondWatch)
                }
                .font(TR.ui(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.53))
                .buttonStyle(.plain)
                .padding(.bottom, 7)
            }
        }
        .sheet(isPresented: $showProjectSheet) {
            ProjectFormatSheet()
                .environmentObject(model)
                .presentationDetents([.fraction(0.74)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .accessibilityIdentifier("export-screen")
    }
}

private struct ExportOptionCard: View {
    let source: PhotoSource
    let title: String
    let subtitle: String
    let badge: String
    let badgeColor: Color
    var watermark = false
    var highlighted = false
    var showsChevron = false
    var accessibilityID: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    PhotoAssetView(source: source)
                    if watermark {
                        Text("TripReel")
                            .font(TR.ui(6, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(4)
                            .background(.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(5)
                    }
                }
                .frame(width: 74, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(TR.ui(18, weight: .semibold))
                    Text(subtitle)
                        .font(TR.ui(13))
                        .foregroundStyle(.white.opacity(0.63))
                    MetadataText(text: badge, color: badgeColor)
                }

                Spacer()

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TR.accent.opacity(0.72))
                }
            }
            .foregroundStyle(TR.cream)
            .padding(14)
            .glassCard(cornerRadius: 20, highlighted: highlighted)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}

private struct ProjectFormatSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Project file")
                        .font(TR.display(28))
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(TR.ui(15, weight: .semibold))
                        .foregroundStyle(TR.accent)
                }

                Text("Your cut, order and timing travel with the file. Full-resolution photos come along — nothing is re-compressed.")
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineSpacing(4)

                VStack(spacing: 8) {
                    ForEach(model.formats) { format in
                        formatRow(format)
                    }
                }

                HStack(alignment: .top, spacing: 11) {
                    Text("CapCut")
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)
                    Text("CapCut can't read timeline files. Choose the photo sequence — it imports in order, and the timing sheet tells you where the cuts go.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.73))
                        .lineSpacing(3)
                }
                .padding(14)
                .background(TR.accent.opacity(0.09))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(TR.accent.opacity(0.26), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Export \(model.selectedFormat.fileExtension)") {
                    dismiss()
                }
                .buttonStyle(CreamButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 38)
        }
    }

    private func formatRow(_ format: ProjectFormat) -> some View {
        let active = model.selectedFormatID == format.id
        return Button {
            model.selectedFormatID = format.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(format.name)
                        .font(TR.ui(15, weight: .semibold))
                    Text(format.apps)
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
                Text(format.fileExtension)
                    .font(TR.mono(10))
                    .tracking(0.8)
                    .foregroundStyle(active ? TR.accent : .white.opacity(0.42))
            }
            .foregroundStyle(TR.cream)
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .background(active ? TR.accent.opacity(0.10) : .white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(active ? TR.accent.opacity(0.46) : .white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(active ? "Selected" : "Not selected")
    }
}

struct PaywallScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            MontageView(
                photos: model.keptPhotos,
                dim: true,
                watermark: true,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.secondsPerPhoto
            )
                .ignoresSafeArea()

            LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    MetadataText(text: "TripReel Pro", color: .white.opacity(0.64))
                    Text("Lose the watermark on this film")
                        .font(TR.display(36))
                        .tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Free is 1 film a month, watermarked, 720p. Pro is unlimited films, 1080p, no watermark, and the full music library.")
                        .font(TR.ui(14))
                        .foregroundStyle(.white.opacity(0.69))
                        .lineSpacing(5)
                }

                VStack(spacing: 10) {
                    purchaseRow(title: "Yearly", subtitle: "$24.99/yr · 2 months free", badge: "BEST VALUE", highlighted: true)
                    purchaseRow(title: "Monthly", subtitle: "$2.99/mo", badge: nil, highlighted: false)

                    Button("Keep the watermark, export free") {
                        model.startRender()
                    }
                    .font(TR.ui(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .safeAreaPadding(.bottom)
        }
        .accessibilityIdentifier("paywall-screen")
    }

    private func purchaseRow(title: String, subtitle: String, badge: String?, highlighted: Bool) -> some View {
        Button {
            model.startRender(hd: true)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(TR.ui(16, weight: .semibold))
                    Text(subtitle)
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                if let badge {
                    MetadataText(text: badge, color: TR.accent)
                }
            }
            .foregroundStyle(TR.cream)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(highlighted ? TR.accent.opacity(0.14) : .white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(highlighted ? TR.accent.opacity(0.56) : .white.opacity(0.16), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct RenderingScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            WarmBackground(variant: .rendering)

            VStack(spacing: 0) {
                MontageView(
                    photos: model.keptPhotos,
                    showLabels: false,
                    look: model.montageLook,
                    motionIntensity: model.montageMotionIntensity,
                    secondsPerSlide: model.secondsPerPhoto
                )
                    .frame(width: 172, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.56), radius: 26, y: 20)

                Text("Rendering")
                    .font(TR.display(32))
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                MetadataText(
                    text: "\(Int(model.renderProgress * 100))% · \(max(1, Int((1 - model.renderProgress) * 34)))s left",
                    color: .white.opacity(0.62)
                )
                .contentTransition(.numericText())

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(TR.accent).frame(width: proxy.size.width * model.renderProgress)
                    }
                }
                .frame(width: 236, height: 5)
                .padding(.top, 22)

                Button("Cancel") {
                    model.go(.export)
                }
                .font(TR.ui(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
        }
        .accessibilityIdentifier("rendering-screen")
    }
}

struct FilmReadyScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            ViewThatFits(in: .vertical) {
                readyContent(previewWidth: 350, compact: false)
                readyContent(previewWidth: 236, compact: true)
            }
        }
        .accessibilityIdentifier("film-ready-screen")
    }

    private func readyContent(previewWidth: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: compact ? 4 : 10)

            MetadataText(text: "\(model.tripShortPlace) · \(model.durationText)", color: .white.opacity(0.57))
                .padding(.bottom, compact ? 10 : 20)

            MontageView(
                photos: model.keptPhotos,
                watermark: model.exportQuality.includesWatermark,
                showLabels: false,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.secondsPerPhoto
            )
                .frame(width: previewWidth, height: previewWidth * 14 / 9)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                .shadow(color: .black.opacity(0.58), radius: 30, y: 22)

            Text("Your film is ready")
                .font(TR.display(compact ? 27 : 30))
                .multilineTextAlignment(.center)
                .padding(.top, compact ? 12 : 20)

            Spacer(minLength: compact ? 4 : 14)

            VStack(spacing: compact ? 8 : 11) {
                HStack(spacing: 10) {
                    Button("Save") {
                        model.cleanupShowsGrid = false
                        model.go(.cleanup)
                    }
                    .buttonStyle(CreamButtonStyle())

                    Button("Share") {
                        model.cleanupShowsGrid = false
                        model.go(.cleanup)
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                Button("Make another") {
                    model.restart()
                }
                .font(TR.ui(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
                .buttonStyle(.plain)
                .padding(.vertical, compact ? 3 : 6)
            }
            .padding(.horizontal, 26)
        }
        .padding(.bottom, compact ? 0 : 12)
    }
}

struct CleanupScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            WarmBackground(variant: .cleanup)

            if model.cleanupShowsGrid {
                CleanupGrid()
            } else {
                cleanupOffer
            }
        }
        .accessibilityIdentifier("cleanup-screen")
    }

    private var cleanupOffer: some View {
        VStack(spacing: 18) {
            Spacer()
            MetadataText(text: "Saved to camera roll", color: .white.opacity(0.53))

            Text(cleanupQuestion)
                .font(TR.display(32))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("They're still in your library. Nothing has been deleted.")
                .font(TR.ui(14))
                .foregroundStyle(.white.opacity(0.61))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(spacing: 11) {
                if cleanupCount > 0 {
                    Button("Review cut photos") {
                        model.cleanupShowsGrid = true
                    }
                    .buttonStyle(GlassButtonStyle())
                } else {
                    Button("Done") {
                        model.restart()
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                Button("Not now") {
                    model.restart()
                }
                .font(TR.ui(15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .buttonStyle(.plain)
                .padding(.vertical, 10)
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 30)
        .safeAreaPadding(.vertical)
        .offset(y: -8)
    }

    private var cleanupCount: Int {
        if model.usesDemoData && model.cutPhotoIDs.isEmpty {
            return min(24, model.photos.count)
        }
        return model.cutPhotoIDs.count
    }

    private var cleanupQuestion: String {
        guard cleanupCount > 0 else {
            return "Your film is saved, and every original photo is still in your library."
        }
        return "You cut \(cleanupCount) photos from this film. Want to clear them off your phone too?"
    }
}

private struct CleanupGrid: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var showDeletedConfirmation = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var candidatePhotos: [ReelPhoto] {
        let explicit = model.photos.filter { model.cutPhotoIDs.contains($0.id) }
        if model.usesDemoData && explicit.isEmpty {
            return Array(model.photos.prefix(24))
        }
        return explicit
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cut photos")
                    .font(TR.display(29))
                Text(subtitle)
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(candidatePhotos) { photo in
                        Button {
                            if model.cleanupSelection.contains(photo.id) {
                                model.cleanupSelection.remove(photo.id)
                            } else {
                                model.cleanupSelection.insert(photo.id)
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                PhotoAssetView(source: photo.source)
                                    .frame(height: 112)

                                ZStack {
                                    Circle()
                                        .fill(model.cleanupSelection.contains(photo.id) ? TR.cream : .black.opacity(0.3))
                                    Circle().stroke(.white.opacity(0.88), lineWidth: 1.5)
                                    if model.cleanupSelection.contains(photo.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(TR.ink)
                                    }
                                }
                                .frame(width: 23, height: 23)
                                .padding(6)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            model.cleanupSelection.contains(photo.id)
                                ? "Deselect \(photo.label) from deletion"
                                : "Select \(photo.label) for deletion"
                        )
                        .accessibilityValue(model.cleanupSelection.contains(photo.id) ? "Selected" : "Not selected")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            VStack(spacing: 10) {
                Button(deleteLabel) {
                    guard !model.cleanupSelection.isEmpty else { return }
                    showDeletedConfirmation = true
                }
                .font(TR.ui(16, weight: .semibold))
                .foregroundStyle(model.cleanupSelection.isEmpty ? .white.opacity(0.36) : Color(red: 0.10, green: 0.025, blue: 0.012))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(model.cleanupSelection.isEmpty ? .white.opacity(0.08) : TR.cut)
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .disabled(model.cleanupSelection.isEmpty)

                Button("Keep them all") {
                    model.restart()
                }
                .font(TR.ui(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.53))
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(.black.opacity(0.22))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        }
        .safeAreaPadding(.vertical)
        .alert("Demo cleanup", isPresented: $showDeletedConfirmation) {
            Button("Done") { model.restart() }
        } message: {
            Text("TripReel would ask Photos for permission before deleting \(model.cleanupSelection.count) selected photos. This prototype leaves your library untouched.")
        }
    }

    private var subtitle: String {
        if model.cleanupSelection.isEmpty {
            return "Nothing is selected. Pick only what you want gone."
        }
        return "\(model.cleanupSelection.count) selected to delete. The rest stay in your library."
    }

    private var deleteLabel: String {
        let count = model.cleanupSelection.count
        guard count > 0 else { return "Nothing selected" }
        return "Delete \(count) photo\(count == 1 ? "" : "s")"
    }
}
