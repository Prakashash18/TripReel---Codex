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
                        title: "Memory Preview",
                        subtitle: "9:16 · 720p · \(model.freeExportDurationText)",
                        badge: model.freeExportEndingBadge,
                        badgeColor: TR.keep,
                        watermark: true,
                        accessibilityID: "export-standard"
                    ) {
                        model.requestExport(
                            .standard,
                            isPremium: purchases.hasFullExportAccess(for: model.exportStoryID)
                        )
                    }

                    ExportOptionCard(
                        source: model.fullStoryHighlightPhotos.first?.source
                            ?? model.previewSource(at: 2),
                        title: "Full Story",
                        subtitle: "9:16 · 1080p · \(model.filmDurationText) complete",
                        badge: "FULL LENGTH · NO WATERMARK",
                        badgeColor: TR.accent,
                        highlighted: true,
                        showsChevron: true,
                        highlightPhotos: model.fullStoryHighlightPhotos,
                        highlightText: fullStoryTeaserText,
                        accessibilityID: "export-hd"
                    ) {
                        model.requestExport(
                            .highDefinition,
                            isPremium: purchases.hasFullExportAccess(for: model.exportStoryID)
                        )
                    }

                    Text("Both export as vertical videos ready for Instagram, TikTok or Photos.")
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
            } else {
                Button("OK", role: .cancel) { model.dismissExportMessage() }
            }
        } message: {
            Text(model.exportErrorMessage ?? "Please try again.")
        }
    }

    private var fullStoryTeaserText: String {
        let count = model.fullStoryExclusiveMomentCount
        if count > 0 {
            return "\(count) more moment\(count == 1 ? "" : "s") · +\(model.fullStoryExtraDurationText)"
        }
        if model.fullStoryExtraDurationSeconds > 0.01 {
            return "Full pacing restored · +\(model.fullStoryExtraDurationText)"
        }
        return "Every moment in 1080p, without the watermark"
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
    var highlightPhotos: [ReelPhoto] = []
    var highlightText: String? = nil
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

                if let highlightText, !highlightPhotos.isEmpty {
                    Divider()
                        .overlay(.white.opacity(0.10))
                    FullStoryHighlightStrip(
                        photos: highlightPhotos,
                        text: highlightText
                    )
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
                            isPremium: purchases.hasFullExportAccess(for: model.exportStoryID)
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

struct PaywallScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @EnvironmentObject private var purchases: RevenueCatPurchaseService
    @State private var selectedPackageID: String?
    @State private var showsPrivacyPolicy = false
    @State private var didResumeExport = false

    private var selectedPackage: Package? {
        purchases.packages.first { $0.identifier == selectedPackageID }
            ?? purchases.packages.first
    }

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
                VStack(alignment: .leading, spacing: 14) {
                    Spacer(minLength: 150)

                    VStack(alignment: .leading, spacing: 8) {
                        MetadataText(
                            text: "FULL STORY · \(model.keptMediaSummary.uppercased()) · \(model.filmDurationText)",
                            color: TR.accent
                        )
                        Text("Keep every moment")
                            .font(TR.display(38))
                            .tracking(-0.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !model.fullStoryHighlightPhotos.isEmpty,
                       model.fullStoryExtraDurationSeconds > 0.01 {
                        FullStoryHighlightStrip(
                            photos: model.fullStoryHighlightPhotos,
                            text: fullStoryTeaserText
                        )
                        .padding(14)
                        .background(.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(TR.accent.opacity(0.28), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }

                    Label("1080p · No watermark", systemImage: "sparkles.rectangle.stack")
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.accent)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("paywall-free-summary")

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
                            purchaseOptions
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

                    if selectedPackage != nil {
                        Button {
                            buySelectedPackage()
                        } label: {
                            HStack(spacing: 9) {
                                if purchases.isPurchasing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(TR.ink)
                                }
                                Text(purchases.isPurchasing ? "Connecting to App Store…" : purchaseButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(CreamButtonStyle())
                        .disabled(purchases.isPurchasing)
                        .accessibilityIdentifier("purchase-full-story")
                    }

                    Button {
                        model.exportFreeVersionInsteadOfUpgrading()
                    } label: {
                        VStack(spacing: 3) {
                            Text("Export free preview")
                            Text("\(model.freeExportDurationText) · Watermarked")
                                .font(TR.ui(11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(purchases.isPurchasing)
                    .accessibilityIdentifier("export-free-from-paywall")

                    if purchases.isConfigured {
                        Button("Restore Pro") {
                            restorePurchases()
                        }
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .disabled(purchases.isPurchasing)
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 7) {
                        if selectedPackage != nil {
                            Text(purchaseTermsText)
                                .font(TR.ui(10))
                                .foregroundStyle(.white.opacity(0.38))
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }

                        HStack(spacing: 18) {
                            Button("Privacy") { showsPrivacyPolicy = true }
                            Link(
                                "Terms",
                                destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                            )
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
            selectDefaultPackageIfNeeded()
            resumeIfPremium()
        }
        .onChange(of: purchases.packages.map(\.identifier)) { _, _ in
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: purchases.isPremium) { _, isPremium in
            if isPremium { resumeIfPremium() }
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            TripReelPrivacyPolicyView()
        }
        .accessibilityIdentifier("paywall-screen")
    }

    private func packageRow(_ package: Package) -> some View {
        let isSelected = selectedPackage?.identifier == package.identifier
        let isStoryPass = purchases.isStoryPass(package)
        return Button {
            withAnimation(TRMotion.selection) {
                selectedPackageID = package.identifier
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isStoryPass ? "Export this story" : "Memories Pro · \(package.memoriesDisplayName)")
                        .font(TR.ui(16, weight: .semibold))
                    Text(isStoryPass
                        ? "One full export · \(package.localizedPriceString)"
                        : "Unlimited full exports · \(package.memoriesPriceDetail)")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? TR.accent : .white.opacity(0.28))
            }
            .foregroundStyle(TR.cream)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(isSelected ? TR.accent.opacity(0.14) : .white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? TR.accent.opacity(0.62) : .white.opacity(0.14), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private var purchaseOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let storyPass = purchases.storyPassPackage {
                packageRow(storyPass)
            }

            if let annual = purchases.proPackages.first(where: { $0.packageType == .annual })
                ?? purchases.proPackages.first {
                packageRow(annual)
            }

        }
    }

    private var configurationNotice: some View {
        Label("Full export is temporarily unavailable", systemImage: "exclamationmark.circle")
            .font(TR.ui(12, weight: .medium))
            .foregroundStyle(.white.opacity(0.58))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var fullStoryTeaserText: String {
        let count = model.fullStoryExclusiveMomentCount
        if count > 0 {
            return "\(count) more moment\(count == 1 ? "" : "s") · +\(model.fullStoryExtraDurationText)"
        }
        return "Full pacing restored · +\(model.fullStoryExtraDurationText)"
    }

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackageID == nil || !purchases.packages.contains(where: { $0.identifier == selectedPackageID }) else {
            return
        }
        selectedPackageID = purchases.storyPassPackage?.identifier
            ?? purchases.proPackages.first(where: { $0.packageType == .annual })?.identifier
            ?? purchases.packages.first?.identifier
    }

    private var purchaseButtonTitle: String {
        guard let selectedPackage else { return "Choose an option" }
        return purchases.isStoryPass(selectedPackage)
            ? "Export this story"
            : "Start Memories Pro"
    }

    private var purchaseTermsText: String {
        guard let selectedPackage, !purchases.isStoryPass(selectedPackage) else {
            return "The story pass is a one-time purchase for this memory."
        }
        return "Subscriptions renew automatically unless cancelled at least 24 hours before the current period ends. Manage or cancel in your Apple ID settings."
    }

    private func buySelectedPackage() {
        guard let package = selectedPackage else { return }
        Task {
            if await purchases.purchase(package, unlockingStoryID: model.exportStoryID) {
                resumeIfUnlocked()
            }
        }
    }

    private func restorePurchases() {
        Task {
            if await purchases.restorePurchases() {
                resumeIfPremium()
            }
        }
    }

    private func resumeIfPremium() {
        resumeIfUnlocked()
    }

    private func resumeIfUnlocked() {
        guard purchases.hasFullExportAccess(for: model.exportStoryID), !didResumeExport else { return }
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
    @State private var sharePayload: MP4SharePayload?

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
        .sheet(item: $sharePayload) { payload in
            MP4ShareController(payload: payload) {
                sharePayload = nil
            }
            .ignoresSafeArea()
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
        .accessibilityIdentifier("film-ready-screen")
    }

    private func readyContent(previewWidth: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: compact ? 4 : 10)

            MetadataText(text: "\(model.activeExportMediaSummary) · \(model.activeExportDurationText)", color: .white.opacity(0.57))
                .padding(.horizontal, 62)
                .padding(.bottom, compact ? 10 : 20)
                .trEntrance(0, distance: 6)

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
                .frame(width: previewWidth, height: previewWidth * 14 / 9)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                .shadow(color: .black.opacity(0.58), radius: 30, y: 22)
                .trEntrance(1, distance: 12)

            Text("Ready to share")
                .font(TR.display(compact ? 27 : 30))
                .multilineTextAlignment(.center)
                .padding(.top, compact ? 12 : 20)
                .trEntrance(2, distance: 8)

            Spacer(minLength: compact ? 4 : 14)

            VStack(spacing: compact ? 8 : 11) {
                if let url = model.exportedVideoURL {
                    Button {
                        sharePayload = MP4SharePayload(
                            url: url,
                            title: "\(model.tripShortPlace) · Memories reel"
                        )
                    } label: {
                        Label("Share Reel", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CreamButtonStyle())
                    .accessibilityIdentifier("share-film")
                } else {
                    Button("Share Reel") { }
                        .buttonStyle(CreamButtonStyle())
                        .disabled(true)
                        .accessibilityIdentifier("share-film")
                }

                Text("Instagram or TikTok not shown? Save Video, then upload it from the app.")
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.center)

                Button {
                    saveFilm()
                } label: {
                    HStack(spacing: 8) {
                        if model.isSavingExport {
                            ProgressView()
                                .controlSize(.small)
                                .tint(TR.cream)
                        }
                        Label(model.isSavingExport ? "Saving…" : "Save Video", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(model.isSavingExport)
                .accessibilityIdentifier("save-film")

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

    private func saveFilm() {
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
