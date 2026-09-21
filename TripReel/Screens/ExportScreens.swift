import RevenueCat
import AVKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MP4SharePayload: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

final class MP4ShareItemSource: NSObject, UIActivityItemSource {
    let videoURL: URL
    let title: String

    init(videoURL: URL, title: String) {
        self.videoURL = videoURL
        self.title = title
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        videoURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        // Return the finished file URL itself. UIKit brokers access to the
        // extension; Instagram and TikTok can then import the movie as a
        // normal file instead of interpreting a custom provider callback.
        videoURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.mpeg4Movie.identifier
    }
}

private struct MP4ShareController: UIViewControllerRepresentable {
    let payload: MP4SharePayload
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = MP4ShareItemSource(
            videoURL: payload.url,
            title: payload.title
        )
        let controller = UIActivityViewController(
            activityItems: [source],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                onComplete()
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct RenderedFilmPreview: View {
    let url: URL

    @State private var player = AVPlayer()
    @State private var didFinish = false

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .overlay {
                if didFinish {
                    Button {
                        replay()
                    } label: {
                        Label("Replay", systemImage: "arrow.counterclockwise")
                            .font(TR.ui(13, weight: .semibold))
                            .foregroundStyle(TR.cream)
                            .padding(.horizontal, 17)
                            .frame(height: 44)
                            .background(.black.opacity(0.74))
                            .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.48), radius: 12, y: 6)
                    }
                    .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
                    .accessibilityHint("Plays the exported video again from the beginning")
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .task(id: url) {
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                player.actionAtItemEnd = .pause
                didFinish = false
                player.play()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: AVPlayerItem.didPlayToEndTimeNotification
                )
            ) { notification in
                guard notification.object as AnyObject? === player.currentItem else { return }
                didFinish = true
            }
            .onDisappear {
                player.pause()
            }
            .animation(.easeInOut(duration: 0.22), value: didFinish)
    }

    private func replay() {
        didFinish = false
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished else { return }
            DispatchQueue.main.async {
                player.play()
            }
        }
    }
}

struct ExportScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @EnvironmentObject private var purchases: RevenueCatPurchaseService

    private var isFullStoryUnlocked: Bool {
        purchases.hasFullExportAccess(for: model.exportStoryID)
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            VStack(spacing: 0) {
                ScreenHeading(
                    eyebrow: "\(model.keptMediaSummary) · \(model.filmDurationText)",
                    title: "Export your film",
                    size: 38
                )
                .padding(.horizontal, 26)
                .padding(.leading, 48)
                .padding(.top, 4)
                .trEntrance(0, distance: 10)
                .accessibilityIdentifier("export-screen")

                Spacer(minLength: 20)

                VStack(spacing: 14) {
                    ExportOptionCard(
                        source: model.previewSource(at: 0),
                        title: "Free preview",
                        subtitle: "\(model.freeExportDurationText) · short video",
                        badge: "FREE · 720P · WATERMARK",
                        badgeColor: TR.keep,
                        watermark: true,
                        accessibilityID: "export-standard"
                    ) {
                        beginFreeExport()
                    }

                    ExportOptionCard(
                        source: model.fullStoryHighlightPhotos.first?.source
                            ?? model.previewSource(at: 2),
                        title: isFullStoryUnlocked ? "Full story · Unlocked" : "Full story",
                        subtitle: isFullStoryUnlocked
                            ? "Create your complete video again"
                            : "\(model.filmDurationText) · complete video",
                        badge: isFullStoryUnlocked
                            ? "YOUR STORY PASS · 1080P · NO WATERMARK"
                            : "PAID · 1080P · NO WATERMARK",
                        badgeColor: isFullStoryUnlocked ? TR.keep : TR.accent,
                        highlighted: true,
                        showsChevron: true,
                        accessibilityID: "export-hd"
                    ) {
                        model.requestExport(
                            .highDefinition,
                            isUnlocked: isFullStoryUnlocked
                        )
                    }

                    Text("Tap an option to see what’s included.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.54))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 26)
                .trEntrance(1, distance: 12)

                Spacer(minLength: 12)
            }
        }
        .alert(
            model.exportErrorTitle,
            isPresented: Binding(
                get: { model.exportErrorMessage != nil },
                set: { if !$0 { model.dismissExportMessage() } }
            )
        ) {
            if model.exportCanRetryPhotoDownload {
                Button("Retry download") { model.retryExportPhotoDownload() }
                Button("Not now", role: .cancel) { model.dismissExportMessage() }
            } else if model.exportCanRetryRender {
                Button("Try export again") { model.retryExportAfterFrameFailure() }
                Button("Not now", role: .cancel) { model.dismissExportMessage() }
            } else {
                Button("OK", role: .cancel) { model.dismissExportMessage() }
            }
        } message: {
            Text(model.exportErrorMessage ?? "Please try again.")
        }
    }

    private func beginFreeExport() {
        model.requestExport(.standard, isUnlocked: false)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack(alignment: .topTrailing) {
                        PhotoAssetView(source: source)
                        if watermark {
                            Text(TR.appName)
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
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TR.accent.opacity(0.72))
                    }
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

private struct FullStoryHighlightStrip: View {
    let photos: [ReelPhoto]
    let text: String

    var body: some View {
        HStack(spacing: 11) {
            HStack(spacing: 4) {
                ForEach(Array(photos.prefix(3))) { photo in
                    ZStack(alignment: .bottomTrailing) {
                        PhotoAssetView(source: photo.source)
                            .frame(width: 34, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        if photo.isVideo {
                            Image(systemName: "play.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.black.opacity(0.74), in: Circle())
                                .padding(3)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                MetadataText(text: "Full Story adds", color: TR.accent)
                Text(text)
                    .font(TR.ui(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TR.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Full Story adds \(text)")
        .accessibilityIdentifier("full-story-highlight")
    }
}

private struct ProjectFormatSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @EnvironmentObject private var purchases: RevenueCatPurchaseService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var projectURL: URL?
    @State private var projectError: String?
    @State private var selectionFeedback = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Continue editing")
                        .font(TR.display(28))
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(TR.ui(15, weight: .semibold))
                        .foregroundStyle(TR.accent)
                }

                Text("Choose a finished MP4 for mobile editors, or a timing file for a desktop editor.")
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineSpacing(4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedIcon(symbol: "scissors", tint: TR.accent, size: 38)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("CapCut Mobile")
                                .font(TR.ui(15, weight: .semibold))
                            Text("CapCut accepts Memories' MP4 as one editable video clip. Its mobile app doesn't import CSV, EDL or Final Cut timelines.")
                                .font(TR.ui(12))
                                .foregroundStyle(.white.opacity(0.66))
                                .lineSpacing(3)
                        }
                    }

                    Button {
                        dismiss()
                        model.requestExport(
                            .capCut,
                            isUnlocked: purchases.hasFullExportAccess(for: model.exportStoryID)
                        )
                    } label: {
                        Label("Render MP4 for CapCut", systemImage: "play.rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CreamButtonStyle())
                    .accessibilityIdentifier("render-capcut-video")

                    Text("If CapCut isn't offered in the share sheet, save the MP4 to Photos and import it from inside CapCut.")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineSpacing(3)
                }
                .padding(14)
                .background(TR.accent.opacity(0.09))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(TR.accent.opacity(0.26), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                MetadataText(text: "DESKTOP TIMELINE FILES", color: .white.opacity(0.43))

                VStack(spacing: 8) {
                    ForEach(model.formats) { format in
                        formatRow(format)
                    }
                }

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
                .appendingPathComponent("Memories-Projects", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safePlace = model.tripShortPlace
                .replacingOccurrences(of: "[^A-Za-z0-9-]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let url = directory.appendingPathComponent(
                "\(safePlace.isEmpty ? "Memories" : safePlace).\(format.fileExtension.lowercased())"
            )
            try projectText(formatID: format.id).write(to: url, atomically: true, encoding: .utf8)
            projectURL = url
            projectError = nil
        } catch {
            projectURL = nil
            projectError = "Memories couldn't prepare this timeline file."
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
              <library><event name="Memories"><project name="\(xmlEscaped(model.tripShortPlace))"><sequence duration="\(timecode(cursor))s"><spine>
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

enum ExportUnlockCelebration: String, Identifiable {
    case storyPass
    case monthlyGift

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .storyPass: "STORY PASS · UNLOCKED"
        case .monthlyGift: "A GIFT FROM MEMORIES"
        }
    }

    var title: String {
        switch self {
        case .storyPass: "This memory is yours."
        case .monthlyGift: "Your full story is ready."
        }
    }

    var detail: String {
        switch self {
        case .storyPass: "Every moment, in 1080p, without a watermark."
        case .monthlyGift: "One monthly free export used. Every moment is included."
        }
    }
}

struct ExportUnlockSuccessView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: ExportUnlockCelebration
    let remainingMonthlyExports: Int?
    let continueAction: () -> Void
    let laterAction: () -> Void
    @State private var revealed = false
    @State private var orbit = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            Circle()
                .fill(TR.accent.opacity(0.13))
                .frame(width: 330, height: 330)
                .blur(radius: 8)
                .scaleEffect(revealed ? 1 : 0.35)

            ForEach(0..<8, id: \.self) { index in
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 15 : 6, weight: .semibold))
                    .foregroundStyle(index.isMultiple(of: 3) ? TR.keep : TR.accent)
                    .offset(y: -128)
                    .rotationEffect(.degrees(Double(index) * 45 + (orbit ? 18 : 0)))
                    .opacity(revealed ? 0.9 : 0)
            }

            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(TR.accent.opacity(0.16))
                        .frame(width: 112, height: 112)
                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(TR.accent)
                }
                .scaleEffect(revealed ? 1 : 0.4)
                .opacity(revealed ? 1 : 0)

                VStack(spacing: 11) {
                    MetadataText(text: kind.eyebrow, color: TR.keep)
                    Text(kind.title)
                        .font(TR.display(42))
                        .tracking(-0.7)
                        .multilineTextAlignment(.center)
                    Text(kind.detail)
                        .font(TR.ui(15))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .offset(y: revealed ? 0 : 18)
                .opacity(revealed ? 1 : 0)

                HStack(spacing: 8) {
                    successCapsule("1080p")
                    successCapsule("Full story")
                    successCapsule("No watermark")
                }
                .opacity(revealed ? 1 : 0)

                if let remainingMonthlyExports {
                    Text("\(remainingMonthlyExports) free full export\(remainingMonthlyExports == 1 ? "" : "s") left this month")
                        .font(TR.ui(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Button("Create my full video", action: continueAction)
                    .buttonStyle(CreamButtonStyle())
                    .accessibilityIdentifier("continue-after-unlock")

                Button("Do this later", action: laterAction)
                    .font(TR.ui(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("finish-unlock-later")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 34)
        }
        .sensoryFeedback(.success, trigger: revealed)
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.72)) {
                    revealed = true
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    orbit = true
                }
            }
        }
        .accessibilityIdentifier("export-unlock-success")
    }

    private func successCapsule(_ title: String) -> some View {
        Text(title)
            .font(TR.ui(10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.74))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white.opacity(0.07), in: Capsule())
    }
}

struct PaywallScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @EnvironmentObject private var purchases: RevenueCatPurchaseService
    @EnvironmentObject private var account: MemoryAccountService
    @State private var showsPrivacyPolicy = false
    @State private var showsTermsOfUse = false
    @State private var didResumeExport = false
    @State private var celebration: ExportUnlockCelebration?
    @State private var showsAccount = false

    var body: some View {
        ZStack {
            MontageView(
                photos: model.keptPhotos,
                titleCards: model.montageTitleCards,
                textOverlays: model.textOverlays,
                dim: true,
                watermark: false,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.secondsPerPhoto
            )
                .ignoresSafeArea()

            LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.97)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer(minLength: 150)

                    VStack(alignment: .leading, spacing: 8) {
                        MetadataText(text: "FULL STORY · \(model.filmDurationText)", color: TR.accent)
                        Text("Choose your export")
                            .font(TR.display(38))
                            .tracking(-0.5)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The complete film in 1080p, without a watermark.")
                            .font(TR.ui(14))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    monthlyExportOption

                    if purchases.isConfigured {
                        if purchases.isLoading && purchases.packages.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView().tint(TR.accent)
                                Text("Loading export options…")
                                    .font(TR.ui(13))
                                    .foregroundStyle(.white.opacity(0.62))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                        } else {
                            purchaseOption
                        }
                    } else {
                        configurationNotice
                    }

                    if let message = purchases.message {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(message)
                                .font(TR.ui(12, weight: .medium))
                                .foregroundStyle(TR.cut.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)

                            if purchases.isConfigured && !purchases.isLoading {
                                Button("Try again") {
                                    Task { await purchases.refresh() }
                                }
                                .font(TR.ui(12, weight: .semibold))
                                .foregroundStyle(TR.accent)
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        beginFreeExport()
                    } label: {
                        Text("Or export a \(model.freeExportDurationText) preview with watermark")
                            .font(TR.ui(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(purchases.isPurchasing)
                    .accessibilityIdentifier("export-free-from-paywall")

                    VStack(spacing: 7) {
                        HStack(spacing: 18) {
                            Button("Privacy") { showsPrivacyPolicy = true }
                            Button("Terms") { showsTermsOfUse = true }
                        }
                        .font(TR.ui(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.54))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .task {
            await purchases.refresh()
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            TripReelPrivacyPolicyView()
        }
        .sheet(isPresented: $showsTermsOfUse) {
            MemoriesTermsOfUseView()
        }
        .sheet(isPresented: $showsAccount) {
            AccountCenterView(context: .sharing)
                .environmentObject(account)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .fullScreenCover(item: $celebration) { kind in
            ExportUnlockSuccessView(
                kind: kind,
                remainingMonthlyExports: kind == .monthlyGift
                    ? account.monthlyExportAllowance.remaining
                    : nil,
                continueAction: {
                    celebration = nil
                    resumeIfUnlockedByOffer()
                },
                laterAction: {
                    celebration = nil
                    model.keepEditingInsteadOfUpgrading()
                }
            )
        }
        .accessibilityIdentifier("paywall-screen")
    }

    @ViewBuilder
    private var monthlyExportOption: some View {
        if account.isSignedIn, account.monthlyExportAllowance.remaining > 0 {
            Button {
                claimMonthlyExport()
            } label: {
                VStack(spacing: 4) {
                    Text(account.isBusy ? "Preparing your export…" : "Use a free full export")
                        .font(TR.ui(17, weight: .semibold))
                    Text("\(account.monthlyExportAllowance.remaining) of 3 left this month")
                        .font(TR.ui(11, weight: .medium))
                        .opacity(0.7)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CreamButtonStyle())
            .disabled(account.isBusy || purchases.isPurchasing)
            .accessibilityIdentifier("use-monthly-free-export")
        } else if !account.isSignedIn {
            Button {
                showsAccount = true
            } label: {
                Text("Sign in for 3 free full exports each month")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CreamButtonStyle())
            .accessibilityIdentifier("sign-in-for-free-export")
        }
    }

    @ViewBuilder
    private var purchaseOption: some View {
        if let storyPass = purchases.storyPassPackage {
            Button {
                buySelectedPackage(storyPass)
            } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        if purchases.isPurchasing {
                            ProgressView().controlSize(.small).tint(TR.cream)
                        }
                        Text(purchases.isPurchasing ? "Connecting to App Store…" : "Buy Story Pass")
                        if let price = purchases.displayPrice(for: storyPass), !purchases.isPurchasing {
                            Text("· \(price)")
                        }
                    }
                    .font(TR.ui(16, weight: .semibold))
                    Text("One-time for this story · Apple confirms the price")
                        .font(TR.ui(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(purchases.isPurchasing)
            .accessibilityIdentifier("purchase-full-story")
        }
    }

    private var configurationNotice: some View {
        Label("Full export is temporarily unavailable", systemImage: "exclamationmark.circle")
            .font(TR.ui(12, weight: .medium))
            .foregroundStyle(.white.opacity(0.58))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func buySelectedPackage(_ package: Package) {
        Task {
            if await purchases.purchase(package, unlockingStoryID: model.exportStoryID) {
                guard purchases.hasFullExportAccess(for: model.exportStoryID) else { return }
                celebration = .storyPass
            }
        }
    }

    private func claimMonthlyExport() {
        Task {
            guard await account.claimMonthlyExport(storyID: model.exportStoryID) else { return }
            celebration = .monthlyGift
        }
    }

    private func beginFreeExport() {
        model.exportFreeVersionInsteadOfUpgrading()
    }

    private func resumeIfUnlocked() {
        guard purchases.hasFullExportAccess(for: model.exportStoryID), !didResumeExport else { return }
        didResumeExport = true
        model.resumePendingExportAfterPurchase()
    }

    private func resumeIfUnlockedByOffer() {
        guard !didResumeExport else { return }
        didResumeExport = true
        model.resumePendingExportAfterPurchase()
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
                    photos: model.activeExportPhotos,
                    titleCards: model.activeExportTitleCards,
                    textOverlays: model.activeExportTextOverlays,
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

                Text(model.exportProgressTitle)
                    .font(TR.display(32))
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                    .trEntrance(1, distance: 8)
                    .contentTransition(.opacity)

                Text(model.exportProgressDetail.uppercased())
                    .font(TR.mono(11, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 28)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : TRMotion.progress, value: model.exportProgressDetail)

                if case .preparingPhotos = model.exportProgressPhase {
                    Text("Memories retries iCloud automatically before it starts encoding.")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                        .padding(.top, 10)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(TR.accent).frame(width: proxy.size.width * model.renderProgress)
                    }
                }
                .frame(width: 236, height: 5)
                .padding(.top, 22)
                .animation(reduceMotion ? nil : TRMotion.progress, value: model.renderProgress)

                Text(model.exportCanFinishInBackground
                     ? "You can leave Memories while this finishes. We'll notify you when it's ready."
                     : "Keep Memories open while this video finishes.")
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.top, 18)

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
    @EnvironmentObject private var account: MemoryAccountService
    let createShareLinkRequest: Int
    @State private var readyFeedback = false
    @State private var sharePayload: MP4SharePayload?
    @State private var showsAccount = false
    @State private var shareLink: URL?
    @State private var isCreatingLink = false
    @State private var shareLinkError: String?
    @State private var showsLeaveWithoutSaving = false
    @State private var wantsLinkAfterSignIn = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    MetadataText(
                        text: "MEMORY READY",
                        color: TR.accent
                    )
                    .padding(.top, 16)
                    .accessibilityIdentifier("film-ready-save-status")

                    memoryCard

                    VStack(spacing: 4) {
                        Text(model.titleDraft(for: .opening).title)
                            .font(TR.display(31))
                            .tracking(-0.5)
                            .multilineTextAlignment(.center)
                        Text("\(model.tripDates.uppercased()) · \(model.activeExportMediaSummary.uppercased())")
                            .font(TR.mono(9))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.48))
                            .multilineTextAlignment(.center)
                    }

                    saveAndLinkStatus

                    Button {
                        saveToPhotos()
                    } label: {
                        Label(
                            model.exportSaveMessage == nil ? "Save video to Photos" : "Saved to Photos",
                            systemImage: model.exportSaveMessage == nil ? "square.and.arrow.down" : "checkmark.circle.fill"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CreamButtonStyle())
                    .disabled(model.exportedVideoURL == nil || model.isSavingExport || model.exportSaveMessage != nil)
                    .accessibilityIdentifier("save-film")

                    HStack(spacing: 10) {
                        Button {
                            shareFilm()
                        } label: {
                            Label("Share video", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle())
                        .accessibilityIdentifier("share-video-button")

                        Button {
                            createShareLink()
                        } label: {
                            HStack(spacing: 7) {
                                if isCreatingLink { ProgressView().controlSize(.small) }
                                Label(
                                    model.exportShareLinkURL == nil
                                        ? (isCreatingLink ? account.shareLinkCreationPhase.statusText : "Create share link")
                                        : "View share link",
                                    systemImage: "link"
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(isCreatingLink)
                        .accessibilityIdentifier("share-link-button")
                    }

                    Text("This on-device render expires after 24 hours. A link lasts 7 days; saving to Photos is permanent.")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.44))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)

                    Button {
                        if model.exportSaveMessage == nil &&
                            model.exportShareLinkURL == nil {
                            showsLeaveWithoutSaving = true
                        } else {
                            model.restart()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            PhotoAssetView(source: .bundled("hoi-an-lanes"))
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Another memory is ready")
                                    .font(TR.ui(13, weight: .semibold))
                                Text("Return to your memories")
                                    .font(TR.ui(11))
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.white.opacity(0.36))
                        }
                        .padding(13)
                        .glassCard(cornerRadius: 17)
                    }
                    .buttonStyle(TactileButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            readyFeedback.toggle()
        }
        .onChange(of: createShareLinkRequest) { _, _ in
            createShareLink()
        }
        .sensoryFeedback(.success, trigger: readyFeedback)
        .sheet(item: $sharePayload) { payload in
            MP4ShareController(payload: payload) {
                sharePayload = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsAccount, onDismiss: {
            if wantsLinkAfterSignIn && account.isSignedIn {
                wantsLinkAfterSignIn = false
                createShareLink()
            }
        }) {
            AccountCenterView(context: .sharing)
                .environmentObject(account)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(
            isPresented: Binding(
                get: { shareLink != nil },
                set: { if !$0 { shareLink = nil } }
            )
        ) {
            if let shareLink {
                MemoryLinkReadySheet(
                    title: model.titleDraft(for: .opening).title,
                    url: shareLink
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
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
        .alert(
            "Share link not created",
            isPresented: Binding(
                get: { shareLinkError != nil },
                set: { if !$0 { shareLinkError = nil } }
            )
        ) {
            Button("Try again") { createShareLink() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text(shareLinkError ?? "Please check your connection and try again.")
        }
        .confirmationDialog(
            "Keep this video?",
            isPresented: $showsLeaveWithoutSaving,
            titleVisibility: .visible
        ) {
            Button("Save video to Photos") { saveToPhotos() }
            Button("Create 7-day link") { createShareLink() }
            Button("Leave without keeping", role: .destructive) { model.restart() }
            Button("Stay here") { }
        } message: {
            Text("This render is temporary. Save a permanent copy, or create a seven-day link in your account before leaving.")
        }
        .accessibilityIdentifier("film-ready-screen")
    }

    private var saveAndLinkStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                model.exportSaveMessage != nil ? "KEPT ON YOUR IPHONE" :
                    model.exportShareLinkURL != nil ? "LINKED FOR SEVEN DAYS" : "NOT KEPT YET"
            )
            .font(TR.mono(10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(model.exportSaveMessage != nil || model.exportShareLinkURL != nil ? TR.keep : TR.accent)

            Label(
                model.exportSaveMessage == nil ? "Video not saved to Photos" : "Video saved to Photos",
                systemImage: model.exportSaveMessage == nil ? "exclamationmark.circle" : "checkmark.circle.fill"
            )
            .foregroundStyle(model.exportSaveMessage == nil ? TR.accent : TR.keep)
            .accessibilityIdentifier("film-ready-video-status")

            Label(
                model.exportShareLinkURL == nil ? "Share link not created" : "In your account · available for 7 days",
                systemImage: model.exportShareLinkURL == nil ? "link.badge.plus" : "checkmark.circle.fill"
            )
            .foregroundStyle(model.exportShareLinkURL == nil ? .white.opacity(0.72) : TR.keep)
            .accessibilityIdentifier("film-ready-link-status")
        }
        .font(TR.ui(12, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .glassCard(cornerRadius: 17)
    }

    private var memoryCard: some View {
        Group {
            if let url = model.exportedVideoURL {
                RenderedFilmPreview(url: url)
            } else {
                MontageView(
                    photos: model.activeExportPhotos,
                    titleCards: model.activeExportTitleCards,
                    textOverlays: model.activeExportTextOverlays,
                    watermark: model.exportQuality.includesWatermark,
                    showLabels: false,
                    look: model.montageLook,
                    motionIntensity: model.montageMotionIntensity,
                    secondsPerSlide: model.secondsPerPhoto,
                    playbackBehavior: .playOnce,
                    showsReplayControl: true
                )
            }
        }
        .frame(width: 224, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(TR.accent.opacity(0.35)))
        .shadow(color: .black.opacity(0.62), radius: 30, y: 22)
        .trEntrance(0, distance: 14)
    }

    private func shareFilm() {
        guard let url = model.exportedVideoURL else { return }
        sharePayload = MP4SharePayload(url: url, title: "\(model.tripShortPlace) · Memories")
    }

    private func saveToPhotos() {
        Task {
            let saved = await model.saveExportToPhotos()
            if saved, let shareURL = model.exportShareLinkURL {
                await account.markSavedToPhone(shareURL: shareURL)
            }
        }
    }

    private func createShareLink() {
        if let existingLink = model.exportShareLinkURL {
            shareLink = existingLink
            return
        }
        guard let videoURL = model.exportedVideoURL else { return }
        guard account.isSignedIn else {
            wantsLinkAfterSignIn = true
            showsAccount = true
            return
        }
        isCreatingLink = true
        shareLinkError = nil
        Task {
            let url = await account.createShareLink(
                videoURL: videoURL,
                title: model.titleDraft(for: .opening).title,
                durationSeconds: model.activeExportDurationSeconds,
                isPaid: model.exportQuality == .hd,
                wasSavedToPhone: model.exportSaveMessage != nil
            )
            isCreatingLink = false
            if let url {
                model.recordExportShareLink(url)
            } else {
                shareLinkError = account.message
                    ?? "The link couldn't be created. Your video is still safe on this iPhone."
            }
            shareLink = url
        }
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
    }

    private var cleanupOffer: some View {
        VStack(spacing: 18) {
            Spacer()
            MetadataText(text: "Saved to camera roll", color: .white.opacity(0.53))
                .accessibilityIdentifier("cleanup-screen")

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
        model.cleanupCandidatePhotos.count
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
        model.cleanupCandidatePhotos
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cut photos")
                    .font(TR.display(29))
                    .accessibilityIdentifier("cleanup-screen")
                Text(subtitle)
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))

                selectionToolbar
                    .padding(.top, 8)
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
                                model.toggleCleanupPhotoSelection(photo.id)
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
                    guard model.cleanupSelectedCount > 0 else { return }
                    activeAlert = .confirm(
                        model.cleanupSelectedCount,
                        includesEveryCutPhoto: model.areAllCleanupCandidatesSelected
                    )
                }
                .font(TR.ui(16, weight: .semibold))
                .foregroundStyle(model.cleanupSelectedCount == 0 ? .white.opacity(0.36) : Color(red: 0.10, green: 0.025, blue: 0.012))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(model.cleanupSelectedCount == 0 ? .white.opacity(0.08) : TR.cut)
                .clipShape(Capsule())
                .buttonStyle(TactileButtonStyle(pressedScale: 0.98))
                .disabled(model.cleanupSelectedCount == 0 || model.isDeletingPhotos)

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
            case let .confirm(count, includesEveryCutPhoto):
                let selectionWarning = includesEveryCutPhoto
                    ? "You selected every cut photo, including any thumbnail that is still loading here. "
                    : ""
                return Alert(
                    title: Text("Delete \(count) original photo\(count == 1 ? "" : "s")?"),
                    message: Text(selectionWarning + "This removes the selected originals from Apple Photos and devices synced with iCloud Photos. Memories cannot undo it. Apple Photos will ask you to confirm once more."),
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
                return Alert(
                    title: Text("Deleted from Photos"),
                    message: Text("\(count) photo\(count == 1 ? " was" : "s were") deleted after Apple Photos confirmed the change."),
                    dismissButton: .default(Text("Done")) { model.restart() }
                )
            case let .failure(message):
                return Alert(
                    title: Text("Photos weren't deleted"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var selectionToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                selectionCountLabel
                Spacer(minLength: 4)
                bulkSelectionButtons
            }

            VStack(alignment: .leading, spacing: 9) {
                selectionCountLabel
                bulkSelectionButtons
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var selectionCountLabel: some View {
        Text("\(model.cleanupSelectedCount) / \(candidatePhotos.count) selected")
            .font(TR.mono(11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.64))
            .contentTransition(.numericText())
            .accessibilityLabel("\(model.cleanupSelectedCount) of \(candidatePhotos.count) photos selected")
    }

    private var bulkSelectionButtons: some View {
        HStack(spacing: 8) {
            cleanupBulkButton(
                title: "Select all",
                symbol: "checkmark.circle",
                isEnabled: !candidatePhotos.isEmpty && !model.areAllCleanupCandidatesSelected,
                accessibilityID: "cleanup-select-all"
            ) {
                withAnimation(reduceMotion ? nil : TRMotion.selection) {
                    model.selectAllCleanupPhotos()
                }
            }

            cleanupBulkButton(
                title: "Clear all",
                symbol: "xmark.circle",
                isEnabled: model.cleanupSelectedCount > 0,
                accessibilityID: "cleanup-clear-all"
            ) {
                withAnimation(reduceMotion ? nil : TRMotion.selection) {
                    model.clearCleanupSelection()
                }
            }
        }
    }

    private func cleanupBulkButton(
        title: String,
        symbol: String,
        isEnabled: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(TR.ui(12, weight: .semibold))
                .foregroundStyle(isEnabled ? TR.cream : .white.opacity(0.34))
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.white.opacity(isEnabled ? 0.09 : 0.04))
                .overlay(Capsule().stroke(.white.opacity(isEnabled ? 0.16 : 0.07), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
        .disabled(!isEnabled || model.isDeletingPhotos)
        .accessibilityIdentifier(accessibilityID)
    }

    private var subtitle: String {
        if model.cleanupSelectedCount == 0 {
            return "Tap individual photos, or select the whole group at once."
        }
        return "\(model.cleanupSelectedCount) selected to delete. The rest stay in your library."
    }

    private var deleteLabel: String {
        if model.isDeletingPhotos { return "Deleting…" }
        let count = model.cleanupSelectedCount
        guard count > 0 else { return "Nothing selected" }
        return "Delete \(count) photo\(count == 1 ? "" : "s")"
    }

    private enum CleanupAlert: Identifiable {
        case confirm(Int, includesEveryCutPhoto: Bool)
        case success(Int)
        case failure(String)

        var id: String {
            switch self {
            case let .confirm(count, includesEveryCutPhoto):
                "confirm-\(count)-\(includesEveryCutPhoto)"
            case let .success(count): "success-\(count)"
            case let .failure(message): "failure-\(message)"
            }
        }
    }
}
