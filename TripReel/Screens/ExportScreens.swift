import SwiftUI

struct ExportScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var showProjectSheet = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            VStack(spacing: 0) {
                ScreenHeading(
                    eyebrow: "\(model.keptCount) photos · \(model.filmDurationText)",
                    title: "Export your film",
                    size: 38
                )
                .padding(.horizontal, 26)
                .padding(.top, 4)
                .trEntrance(0, distance: 10)

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
                    .buttonStyle(TactileButtonStyle())
                    .accessibilityIdentifier("export-project")

                    Text("The watermark sits in the top-right corner, as shown.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.43))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 26)
                .trEntrance(1, distance: 12)

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
        .alert(
            "Export couldn't finish",
            isPresented: Binding(
                get: { model.exportErrorMessage != nil },
                set: { if !$0 { model.dismissExportMessage() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissExportMessage() }
        } message: {
            Text(model.exportErrorMessage ?? "Please try again.")
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
        .buttonStyle(TactileButtonStyle())
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}

private struct ProjectFormatSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var projectURL: URL?
    @State private var projectError: String?
    @State private var selectionFeedback = 0

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

                Text("Your cut, order, framing, motion and timing travel in a small timeline file you can share with another editor.")
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
                    Text("CapCut can't read timeline files. Choose the CSV timing sheet to see the photo order, cut times, framing and motion settings.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.73))
                        .lineSpacing(3)
                }
                .padding(14)
                .background(TR.accent.opacity(0.09))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(TR.accent.opacity(0.26), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let projectURL {
                    ShareLink(item: projectURL) {
                        Text("Share \(model.selectedFormat.fileExtension)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CreamButtonStyle())
                    .accessibilityIdentifier("share-project-file")
                } else {
                    Button("Prepare \(model.selectedFormat.fileExtension)") {
                        prepareProjectFile()
                    }
                    .buttonStyle(CreamButtonStyle())
                }

                if let projectError {
                    Text(projectError)
                        .font(TR.ui(11, weight: .medium))
                        .foregroundStyle(TR.cut)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 38)
        }
        .onAppear { prepareProjectFile() }
        .onChange(of: model.selectedFormatID) { _, _ in prepareProjectFile() }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
    }

    private func formatRow(_ format: ProjectFormat) -> some View {
        let active = model.selectedFormatID == format.id
        return Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                model.selectedFormatID = format.id
            }
            selectionFeedback += 1
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
        .buttonStyle(TactileButtonStyle())
        .accessibilityValue(active ? "Selected" : "Not selected")
    }

    private func prepareProjectFile() {
        do {
            let format = model.selectedFormat
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TripReel-Projects", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safePlace = model.tripShortPlace
                .replacingOccurrences(of: "[^A-Za-z0-9-]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let url = directory.appendingPathComponent(
                "\(safePlace.isEmpty ? "TripReel" : safePlace).\(format.fileExtension.lowercased())"
            )
            try projectText(formatID: format.id).write(to: url, atomically: true, encoding: .utf8)
            projectURL = url
            projectError = nil
        } catch {
            projectURL = nil
            projectError = "TripReel couldn't prepare this timeline file."
        }
    }

    private func projectText(formatID: String) -> String {
        var cursor = 0.0
        let rows = model.keptPhotos.enumerated().map { index, photo -> ProjectRow in
            let duration = model.duration(for: photo)
            defer { cursor += duration }
            return ProjectRow(index: index + 1, photo: photo, start: cursor, duration: duration)
        }

        switch formatID {
        case "fcpxml":
            let clips = rows.map { row in
                "        <asset-clip name=\"\(xmlEscaped(row.photo.label))\" offset=\"\(timecode(row.start))s\" duration=\"\(timecode(row.duration))s\" note=\"frame=\(row.photo.frameStyle.rawValue); motion=\(row.photo.motionStyle.rawValue)\"/>"
            }.joined(separator: "\n")
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <fcpxml version="1.11">
              <library><event name="TripReel"><project name="\(xmlEscaped(model.tripShortPlace))"><sequence duration="\(timecode(cursor))s"><spine>
            \(clips)
              </spine></sequence></project></event></library>
            </fcpxml>
            """
        case "edl":
            let body = rows.map { row in
                String(format: "%03d  AX       V     C        %@ %@ %@ %@\n* FROM CLIP NAME: %@\n* FRAME: %@  MOTION: %@",
                       row.index,
                       edlTime(row.start), edlTime(row.start + row.duration), edlTime(row.start), edlTime(row.start + row.duration),
                       row.photo.label, row.photo.frameStyle.rawValue, row.photo.motionStyle.rawValue)
            }.joined(separator: "\n")
            return "TITLE: \(model.tripShortPlace)\nFCM: NON-DROP FRAME\n\n\(body)\n"
        default:
            let header = "order,photo,start_seconds,duration_seconds,frame,motion,zoom,offset_x,offset_y"
            let body = rows.map { row in
                "\(row.index),\(csvEscaped(row.photo.label)),\(timecode(row.start)),\(timecode(row.duration)),\(row.photo.frameStyle.rawValue),\(row.photo.motionStyle.rawValue),\(timecode(row.photo.cropScale)),\(timecode(row.photo.cropOffsetX)),\(timecode(row.photo.cropOffsetY))"
            }.joined(separator: "\n")
            return "\(header)\n\(body)\n"
        }
    }

    private func timecode(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }

    private func edlTime(_ seconds: Double) -> String {
        let totalFrames = max(0, Int((seconds * 30).rounded()))
        let frames = totalFrames % 30
        let totalSeconds = totalFrames / 30
        return String(
            format: "%02d:%02d:%02d:%02d",
            totalSeconds / 3_600,
            (totalSeconds / 60) % 60,
            totalSeconds % 60,
            frames
        )
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private struct ProjectRow {
        let index: Int
        let photo: ReelPhoto
        let start: Double
        let duration: Double
    }
}

struct PaywallScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            MontageView(
                photos: model.keptPhotos,
                titleCards: model.montageTitleCards,
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
            .trEntrance(0, distance: 14)
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
        .buttonStyle(TactileButtonStyle())
    }
}

struct RenderingScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .rendering)

            VStack(spacing: 0) {
                MontageView(
                    photos: model.keptPhotos,
                    titleCards: model.montageTitleCards,
                    showLabels: false,
                    look: model.montageLook,
                    motionIntensity: model.montageMotionIntensity,
                    secondsPerSlide: model.secondsPerPhoto
                )
                    .frame(width: 172, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.56), radius: 26, y: 20)
                    .overlay {
                        if motionAllowed {
                            GeometryReader { proxy in
                                LinearGradient(
                                    colors: [.clear, TR.accent.opacity(0.34), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 46)
                                .blur(radius: 5)
                                .offset(y: sweep ? proxy.size.height + 24 : -70)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .allowsHitTesting(false)
                        }
                    }
                    .trEntrance(0, distance: 12)

                Text("Rendering")
                    .font(TR.display(32))
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                    .trEntrance(1, distance: 8)

                MetadataText(
                    text: "\(Int(model.renderProgress * 100))% · full-resolution video",
                    color: .white.opacity(0.62)
                )
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : TRMotion.progress, value: model.renderProgress)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(TR.accent).frame(width: proxy.size.width * model.renderProgress)
                    }
                }
                .frame(width: 236, height: 5)
                .padding(.top, 22)
                .animation(reduceMotion ? nil : TRMotion.progress, value: model.renderProgress)

                Button("Cancel") {
                    model.cancelRender()
                }
                .font(TR.ui(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
        }
        .task(id: reduceMotion) {
            sweep = false
            guard motionAllowed else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
        .accessibilityIdentifier("rendering-screen")
    }

    private var motionAllowed: Bool {
        !reduceMotion
    }
}

struct FilmReadyScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var readyFeedback = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            ViewThatFits(in: .vertical) {
                readyContent(previewWidth: 350, compact: false)
                readyContent(previewWidth: 236, compact: true)
            }
        }
        .onAppear { readyFeedback.toggle() }
        .sensoryFeedback(.success, trigger: readyFeedback)
        .alert(
            "Couldn't save the film",
            isPresented: Binding(
                get: { model.exportErrorMessage != nil },
                set: { if !$0 { model.dismissExportMessage() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissExportMessage() }
        } message: {
            Text(model.exportErrorMessage ?? "Please try again.")
        }
        .accessibilityIdentifier("film-ready-screen")
    }

    private func readyContent(previewWidth: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: compact ? 4 : 10)

            MetadataText(text: "\(model.tripShortPlace) · \(model.filmDurationText)", color: .white.opacity(0.57))
                .padding(.bottom, compact ? 10 : 20)
                .trEntrance(0, distance: 6)

            MontageView(
                photos: model.keptPhotos,
                titleCards: model.montageTitleCards,
                watermark: model.exportQuality.includesWatermark,
                showLabels: false,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.secondsPerPhoto
            )
                .frame(width: previewWidth, height: previewWidth * 14 / 9)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                .shadow(color: .black.opacity(0.58), radius: 30, y: 22)
                .trEntrance(1, distance: 12)

            Text("Your film is ready")
                .font(TR.display(compact ? 27 : 30))
                .multilineTextAlignment(.center)
                .padding(.top, compact ? 12 : 20)
                .trEntrance(2, distance: 8)

            Spacer(minLength: compact ? 4 : 14)

            VStack(spacing: compact ? 8 : 11) {
                HStack(spacing: 10) {
                    Button {
                        if model.usesDemoData {
                            model.cleanupShowsGrid = false
                            model.go(.cleanup)
                        } else {
                            Task {
                                if await model.saveExportToPhotos() {
                                    model.cleanupShowsGrid = false
                                    model.go(.cleanup)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isSavingExport {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(TR.ink)
                            }
                            Text(model.isSavingExport ? "Saving…" : "Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(CreamButtonStyle())
                    .disabled(model.isSavingExport)
                    .accessibilityIdentifier("save-film")

                    if let url = model.exportedVideoURL {
                        ShareLink(item: url) {
                            Text("Share")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle())
                        .accessibilityIdentifier("share-film")
                    } else {
                        Button("Share") { }
                            .buttonStyle(GlassButtonStyle())
                            .disabled(true)
                    }
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
            .trEntrance(3, distance: 10)
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

            Text("They're still in your library. You decide whether any originals are deleted.")
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
        .trEntrance(0, distance: 12)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeAlert: CleanupAlert?
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
                            guard !model.isDeletingPhotos else { return }
                            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                                if model.cleanupSelection.contains(photo.id) {
                                    model.cleanupSelection.remove(photo.id)
                                } else {
                                    model.cleanupSelection.insert(photo.id)
                                }
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
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .frame(width: 23, height: 23)
                                .padding(6)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
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
                    activeAlert = .confirm(model.cleanupSelection.count)
                }
                .font(TR.ui(16, weight: .semibold))
                .foregroundStyle(model.cleanupSelection.isEmpty ? .white.opacity(0.36) : Color(red: 0.10, green: 0.025, blue: 0.012))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(model.cleanupSelection.isEmpty ? .white.opacity(0.08) : TR.cut)
                .clipShape(Capsule())
                .buttonStyle(TactileButtonStyle(pressedScale: 0.98))
                .disabled(model.cleanupSelection.isEmpty || model.isDeletingPhotos)

                Button("Keep them all") {
                    model.restart()
                }
                .font(TR.ui(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.53))
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .disabled(model.isDeletingPhotos)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(.black.opacity(0.22))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        }
        .safeAreaPadding(.vertical)
        .sensoryFeedback(.selection, trigger: model.cleanupSelection.count)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case let .confirm(count):
                Alert(
                    title: Text("Delete \(count) original photo\(count == 1 ? "" : "s")?"),
                    message: Text("This removes the selected originals from Apple Photos and devices synced with iCloud Photos. TripReel cannot undo it. Apple Photos will ask you to confirm once more."),
                    primaryButton: .destructive(Text("Delete from Photos")) {
                        Task {
                            if let deletedCount = await model.deleteCleanupSelection() {
                                activeAlert = .success(deletedCount)
                            } else {
                                activeAlert = .failure(
                                    model.cleanupDeletionErrorMessage
                                        ?? "Nothing was deleted."
                                )
                            }
                        }
                    },
                    secondaryButton: .cancel()
                )
            case let .success(count):
                Alert(
                    title: Text("Deleted from Photos"),
                    message: Text("\(count) photo\(count == 1 ? " was" : "s were") deleted after Apple Photos confirmed the change."),
                    dismissButton: .default(Text("Done")) { model.restart() }
                )
            case let .failure(message):
                Alert(
                    title: Text("Photos weren't deleted"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var subtitle: String {
        if model.cleanupSelection.isEmpty {
            return "Nothing is selected. Pick only what you want gone."
        }
        return "\(model.cleanupSelection.count) selected to delete. The rest stay in your library."
    }

    private var deleteLabel: String {
        if model.isDeletingPhotos { return "Deleting…" }
        let count = model.cleanupSelection.count
        guard count > 0 else { return "Nothing selected" }
        return "Delete \(count) photo\(count == 1 ? "" : "s")"
    }

    private enum CleanupAlert: Identifiable {
        case confirm(Int)
        case success(Int)
        case failure(String)

        var id: String {
            switch self {
            case let .confirm(count): "confirm-\(count)"
            case let .success(count): "success-\(count)"
            case let .failure(message): "failure-\(message)"
            }
        }
    }
}
