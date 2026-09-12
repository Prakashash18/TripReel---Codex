import AVFAudio
import AVFoundation
import ImageIO
import Photos
import SwiftUI
import UIKit

enum PhotoDisplayContentMode: Hashable, Sendable {
    case fill
    case fit
}

enum PhotoAssetLoadState: Equatable, Sendable {
    case loading(progress: Double?)
    case ready
    case failed

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum PhotoDisplaySizing {
    static func targetSize(
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        destinationPixelWidth: Int,
        destinationPixelHeight: Int,
        contentMode: PhotoDisplayContentMode,
        maximumPixelDimension: CGFloat = 4_096
    ) -> CGSize {
        let sourceWidth = CGFloat(max(1, sourcePixelWidth))
        let sourceHeight = CGFloat(max(1, sourcePixelHeight))
        let destinationWidth = CGFloat(max(1, destinationPixelWidth))
        let destinationHeight = CGFloat(max(1, destinationPixelHeight))
        let sourceAspect = sourceWidth / sourceHeight
        let destinationAspect = destinationWidth / destinationHeight

        var width: CGFloat
        var height: CGFloat
        switch contentMode {
        case .fill:
            if sourceAspect >= destinationAspect {
                height = destinationHeight
                width = height * sourceAspect
            } else {
                width = destinationWidth
                height = width / sourceAspect
            }
        case .fit:
            if sourceAspect >= destinationAspect {
                width = destinationWidth
                height = width / sourceAspect
            } else {
                height = destinationHeight
                width = height * sourceAspect
            }
        }

        let overscan: CGFloat = contentMode == .fill ? 1.14 : 1.03
        width *= overscan
        height *= overscan

        let downscale = min(
            1,
            sourceWidth / width,
            sourceHeight / height,
            maximumPixelDimension / max(width, height)
        )
        return CGSize(
            width: max(1, (width * downscale).rounded(.up)),
            height: max(1, (height * downscale).rounded(.up))
        )
    }
}

struct PhotoAssetView: View {
    let source: PhotoSource
    var label: String? = nil
    var dim = false
    var contentMode: PhotoDisplayContentMode = .fill
    var contentScale: CGFloat = 1
    var contentOffset: CGSize = .zero
    var samplingScale: CGFloat = 1
    var onLoadStateChange: ((PhotoAssetLoadState) -> Void)?

    init(
        source: PhotoSource,
        label: String? = nil,
        dim: Bool = false,
        contentMode: PhotoDisplayContentMode = .fill,
        contentScale: CGFloat = 1,
        contentOffset: CGSize = .zero,
        samplingScale: CGFloat? = nil,
        onLoadStateChange: ((PhotoAssetLoadState) -> Void)? = nil
    ) {
        self.source = source
        self.label = label
        self.dim = dim
        self.contentMode = contentMode
        self.contentScale = max(1, contentScale)
        self.contentOffset = contentOffset
        self.samplingScale = max(1, samplingScale ?? contentScale)
        self.onLoadStateChange = onLoadStateChange
    }

    init(imageName: String, label: String? = nil, dim: Bool = false) {
        self.init(source: .bundled(imageName), label: label, dim: dim)
    }

    var body: some View {
        GeometryReader { proxy in
            PhotoSourceImage(
                source: source,
                size: proxy.size,
                contentMode: contentMode,
                samplingScale: samplingScale,
                onLoadStateChange: onLoadStateChange
            )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(contentScale)
                .offset(contentOffset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(dim ? 0.62 : 0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    if let label {
                        Text(label)
                            .font(TR.mono(10))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(18)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

enum MontagePlaybackBehavior: Hashable {
    case loop
    case playOnce
}

struct MontageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var photos: [ReelPhoto] = []
    var titleCards: [MontageTitleCard] = []
    var textOverlays: [MontageTextOverlay] = []
    var usesBundledFallback = false
    var dim = false
    var watermark = false
    var showLabels = true
    var look: MontageLook = .story
    var motionIntensity: MontageMotionIntensity = .gentle
    var secondsPerSlide = 2.2
    var playbackBehavior: MontagePlaybackBehavior = .loop
    var showsReplayControl = false
    var onPlaybackStarted: (() -> Void)?
    var onPlaybackEnded: (() -> Void)?
    @State private var currentIndex = 0
    @State private var motionPhase = false
    @State private var currentPhotoLoadState: PhotoAssetLoadState = .loading(progress: nil)
    @State private var lastReadySlide: MontageSlide?
    @State private var playbackGeneration = 0
    @State private var playbackComplete = false

    private var timeline: [MontageTimelineItem] {
        if !photos.isEmpty {
            return MontageTimelineBuilder.make(photos: photos, titleCards: titleCards)
        }
        guard usesBundledFallback else {
            return MontageTimelineBuilder.make(photos: [], titleCards: titleCards)
        }
        let fallbackPhotos = TripReelModel.assetNames.enumerated().map { index, imageName in
            ReelPhoto(
                id: "bundled-\(imageName)",
                source: .bundled(imageName),
                label: TripReelModel.photoLabels[index],
                time: "—",
                isSimilar: false,
                pixelWidth: 1_024,
                pixelHeight: 1_536,
                frameStyle: index % 3 == 1 ? .postcard : .portraitMatte,
                motionStyle: MontageMotionStyle.allCases[index % MontageMotionStyle.allCases.count]
            )
        }
        return MontageTimelineBuilder.make(photos: fallbackPhotos, titleCards: titleCards)
    }

    private var currentItem: MontageTimelineItem? {
        guard !timeline.isEmpty else { return nil }
        return timeline[min(currentIndex, timeline.count - 1)]
    }

    private var currentSlide: MontageSlide? {
        guard case let .photo(photo) = currentItem else { return nil }
        let photoIndex = photos.firstIndex(where: { $0.id == photo.id }) ?? currentIndex
        return MontageSlide(
            id: photo.id,
            source: photo.source,
            label: photo.label,
            aspectRatio: photo.aspectRatio,
            frameStyle: photo.isVideo ? .fullBleed : MontageFrameResolver.resolve(
                planned: photo.frameStyle,
                aspectRatio: photo.aspectRatio,
                index: photoIndex,
                isCustomized: photo.hasCustomFrameStyle,
                look: look,
                protectsPeople: photo.protectsPeople
            ),
            motionStyle: photo.motionStyle,
            usesAutomaticPeopleFraming: photo.usesAutomaticPeopleFraming,
            cropScale: photo.cropScale,
            cropOffsetX: photo.cropOffsetX,
            cropOffsetY: photo.cropOffsetY,
            mediaKind: photo.mediaKind,
            videoStartSeconds: photo.videoStartSeconds,
            videoDurationSeconds: photo.durationSeconds ?? secondsPerSlide,
            playsOriginalAudio: photo.hasOriginalAudio
        )
    }

    private var currentTextOverlay: MontageTextOverlay? {
        guard case let .photo(photo) = currentItem else { return nil }
        return textOverlays.first { $0.photoID == photo.id && !$0.text.isEmpty }
    }

    private var contentKey: MontageContentKey {
        MontageContentKey(
            itemIDs: timeline.map(\.id),
            itemDurationsMilliseconds: timeline.map {
                Int(($0.duration(defaultPhotoDuration: secondsPerSlide) * 1_000).rounded())
            }
        )
    }

    private var playbackKey: MontagePlaybackKey {
        MontagePlaybackKey(
            content: contentKey,
            behavior: playbackBehavior,
            generation: playbackGeneration
        )
    }

    private var currentMotionKey: MontageMotionPlaybackKey {
        MontageMotionPlaybackKey(
            itemID: currentItem?.id,
            look: look,
            intensity: motionIntensity,
            frameStyle: currentSlide?.frameStyle,
            motionStyle: currentSlide?.motionStyle,
            reduceMotion: motionReduced,
            generation: playbackGeneration
        )
    }

    private var motionReduced: Bool {
        reduceMotion
    }

    var body: some View {
        ZStack {
            if case let .title(card) = currentItem {
                MontageTitleArtwork(
                    card: card,
                    backgroundSource: photos.first?.source,
                    motionPhase: motionPhase,
                    reduceMotion: motionReduced
                )
                .id(card.id)
                .transition(
                    motionReduced
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 1.012))
                )
            } else if let slide = currentSlide {
                ZStack {
                    if !currentPhotoLoadState.isReady,
                       let lastReadySlide,
                       lastReadySlide.id != slide.id {
                        MontageSlideArtwork(
                            slide: lastReadySlide,
                            showLabel: showLabels,
                            motionPhase: motionPhase,
                            reduceMotion: motionReduced,
                            motionIntensity: motionIntensity
                        )
                    }

                    MontageSlideArtwork(
                        slide: slide,
                        showLabel: showLabels,
                        motionPhase: motionPhase,
                        reduceMotion: motionReduced,
                        motionIntensity: motionIntensity,
                        onLoadStateChange: { state in
                            handleLoadState(state, for: slide)
                        }
                    )
                    .opacity(currentPhotoLoadState.isReady ? 1 : 0.001)

                    if !currentPhotoLoadState.isReady, lastReadySlide == nil {
                        MontagePhotoWaitingArtwork(loadState: currentPhotoLoadState)
                    } else if !currentPhotoLoadState.isReady {
                        MontagePhotoWaitingBadge(loadState: currentPhotoLoadState)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 18)
                    }
                }
                .id("\(slide.id)-\(slide.frameStyle.rawValue)-\(playbackGeneration)")
                .transition(motionReduced ? .opacity : slide.motionStyle.transition)
            } else {
                ZStack {
                    Color.white.opacity(0.045)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.24))
                }
            }


            if dim {
                LinearGradient(
                    colors: [.black.opacity(0.70), .black.opacity(0.34), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            RadialGradient(
                colors: [.clear, .black.opacity(0.34)],
                center: .center,
                startRadius: 90,
                endRadius: 430
            )

            if let overlay = currentTextOverlay, currentPhotoLoadState.isReady {
                MontageTextOverlayArtwork(
                    overlay: overlay,
                    motionPhase: motionPhase,
                    reduceMotion: motionReduced
                )
                .id(overlay.id)
                .transition(.opacity)
            }

            if watermark {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TR.accent)
                    Text("Made with")
                        .font(TR.ui(10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(TR.appName)
                        .font(TR.ui(13, weight: .bold))
                        .foregroundStyle(TR.cream)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.black.opacity(0.74))
                .overlay(
                    Capsule()
                        .stroke(TR.accent.opacity(0.62), lineWidth: 1)
                )
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.48), radius: 10, y: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)
            }

            if showsReplayControl,
               playbackBehavior == .playOnce,
               playbackComplete {
                Button {
                    playbackComplete = false
                    playbackGeneration &+= 1
                } label: {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(TR.cream)
                        .padding(.horizontal, 17)
                        .frame(height: 44)
                        .background(.black.opacity(0.72))
                        .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.48), radius: 12, y: 6)
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
                .accessibilityHint("Plays this preview again from the beginning")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(Color(red: 0.051, green: 0.035, blue: 0.024))
        .accessibilityHidden(!showsReplayControl)
        .animation(
            motionReduced ? .easeInOut(duration: 0.18) : .easeInOut(duration: 0.46),
            value: currentIndex
        )
        .task(id: currentMotionKey) {
            motionPhase = false
            preheatUpcomingPhotos()
            guard !motionReduced else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            let duration = currentItem?.duration(defaultPhotoDuration: secondsPerSlide) ?? secondsPerSlide
            withAnimation(TRMotion.montageDrift(duration: duration)) {
                motionPhase = true
            }
        }
        .task(id: playbackKey) {
            playbackComplete = false
            currentIndex = 0
            lastReadySlide = nil
            prepareLoadStateForCurrentItem()
            guard !timeline.isEmpty else { return }
            var hasStarted = false
            while !Task.isCancelled {
                let itemID = currentItem?.id
                if case .photo = currentItem,
                   !(await waitForCurrentPhoto(itemID: itemID)) {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    guard advanceToNextItem() else {
                        finishPlayback()
                        return
                    }
                    continue
                }
                if !hasStarted {
                    hasStarted = true
                    onPlaybackStarted?()
                }
                let duration = currentItem?.duration(defaultPhotoDuration: secondsPerSlide) ?? secondsPerSlide
                let delay = UInt64(max(0.6, duration) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                guard advanceToNextItem() else {
                    finishPlayback()
                    return
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: playbackComplete)
    }

    private func preheatUpcomingPhotos() {
        guard !timeline.isEmpty else { return }
        let sources = (0..<min(7, timeline.count)).compactMap { offset -> PhotoSource? in
            let item = timeline[(currentIndex + offset) % timeline.count]
            guard case let .photo(photo) = item else { return nil }
            return photo.source
        }
        PhotoAssetImageLoader.preheat(sources: sources)
    }

    private func prepareLoadStateForCurrentItem() {
        guard case let .photo(photo) = currentItem else {
            currentPhotoLoadState = .ready
            return
        }
        if case .bundled = photo.source {
            currentPhotoLoadState = .ready
        } else {
            currentPhotoLoadState = .loading(progress: nil)
        }
    }

    @discardableResult
    private func advanceToNextItem() -> Bool {
        guard !timeline.isEmpty else { return false }
        if playbackBehavior == .playOnce, currentIndex >= timeline.count - 1 {
            return false
        }
        let nextIndex = (currentIndex + 1) % timeline.count
        if case let .photo(photo) = timeline[nextIndex], case .bundled = photo.source {
            currentPhotoLoadState = .ready
        } else if case .photo = timeline[nextIndex] {
            currentPhotoLoadState = .loading(progress: nil)
        } else {
            currentPhotoLoadState = .ready
        }
        currentIndex = nextIndex
        return true
    }

    private func finishPlayback() {
        guard !playbackComplete else { return }
        playbackComplete = true
        onPlaybackEnded?()
    }

    private func handleLoadState(_ state: PhotoAssetLoadState, for slide: MontageSlide) {
        guard currentSlide?.id == slide.id else { return }
        currentPhotoLoadState = state
        if state.isReady {
            lastReadySlide = slide
        }
    }

    private func waitForCurrentPhoto(itemID: String?) async -> Bool {
        // Preheating normally makes this immediate. A short grace period lets
        // iCloud finish without putting an empty frame into the montage; after
        // that, this pass skips the slide and can pick it up on the next loop.
        // Give the opening frame a little more time because there is nothing
        // honest to hold behind it. Once playback is under way, move on quickly
        // while the seven-frame preheater continues fetching in the background.
        let attempts = lastReadySlide == nil ? 80 : 12
        for _ in 0..<attempts {
            guard !Task.isCancelled, currentItem?.id == itemID else { return false }
            switch currentPhotoLoadState {
            case .ready:
                return true
            case .failed:
                return false
            case .loading:
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return false
    }

}

private struct MontageTextOverlayArtwork: View {
    let overlay: MontageTextOverlay
    let motionPhase: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack {
            if overlay.placement != .top { Spacer(minLength: 0) }
            Text(overlay.style == .bold ? overlay.text.uppercased() : overlay.text)
                .font(font)
                .foregroundStyle(TR.cream)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.66)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 12, y: 5)
                .opacity(reduceMotion ? 1 : (motionPhase ? 1 : 0))
                .offset(y: reduceMotion ? 0 : offset)
                .scaleEffect(reduceMotion ? 1 : scale)
                .animation(reduceMotion ? nil : animation, value: motionPhase)
            if overlay.placement != .bottom { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 52)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var font: Font {
        switch overlay.style {
        case .editorial: TR.display(35)
        case .clean: TR.ui(24, weight: .semibold)
        case .bold: TR.ui(25, weight: .black)
        }
    }

    private var offset: CGFloat {
        guard !motionPhase else { return 0 }
        return overlay.animation == .rise ? 18 : 0
    }

    private var scale: CGFloat {
        guard !motionPhase else { return 1 }
        return overlay.animation == .pop ? 0.86 : 1
    }

    private var animation: Animation {
        switch overlay.animation {
        case .fade: .easeOut(duration: 0.55)
        case .rise: .spring(response: 0.66, dampingFraction: 0.84)
        case .pop: .spring(response: 0.52, dampingFraction: 0.70)
        }
    }
}

private struct MontagePhotoWaitingBadge: View {
    let loadState: PhotoAssetLoadState

    var body: some View {
        HStack(spacing: 7) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(TR.accent)
            Text(detail)
                .font(TR.ui(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.black.opacity(0.64))
        .clipShape(Capsule())
        .transition(.opacity)
    }

    private var progress: Double? {
        guard case let .loading(progress) = loadState else { return nil }
        return progress
    }

    private var detail: String {
        guard let progress else { return "Preparing next moment" }
        return "iCloud \(Int(progress * 100))%"
    }
}

private struct MontageSlide {
    let id: String
    let source: PhotoSource
    let label: String
    let aspectRatio: Double
    let frameStyle: MontageFrameStyle
    let motionStyle: MontageMotionStyle
    let usesAutomaticPeopleFraming: Bool
    let cropScale: Double
    let cropOffsetX: Double
    let cropOffsetY: Double
    let mediaKind: LibraryMediaKind
    let videoStartSeconds: Double
    let videoDurationSeconds: Double
    let playsOriginalAudio: Bool

    var isVideo: Bool { mediaKind == .video }
}

private struct MontagePhotoWaitingArtwork: View {
    let loadState: PhotoAssetLoadState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.085, blue: 0.035),
                    Color(red: 0.045, green: 0.03, blue: 0.022),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .tint(TR.accent)
                Text("Preparing the next moment")
                    .font(TR.ui(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
                Text(detail)
                    .font(TR.ui(10))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private var progress: Double? {
        guard case let .loading(progress) = loadState else { return nil }
        return progress
    }

    private var detail: String {
        guard let progress else { return "Memories will skip it for now if it needs longer." }
        return "Downloading from iCloud · \(Int(progress * 100))%"
    }
}

struct MontageTitleArtwork: View {
    let card: MontageTitleCard
    let backgroundSource: PhotoSource?
    let motionPhase: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if let backgroundSource {
                PhotoAssetView(source: backgroundSource)
                    .scaleEffect(motionPhase && !reduceMotion ? 1.06 : 1.015)
                    .blur(radius: 18)
                    .saturation(0.55)
                    .opacity(0.36)
            }

            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.055, blue: 0.025).opacity(0.96),
                    Color(red: 0.035, green: 0.025, blue: 0.02).opacity(0.88),
                    .black.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(TR.accent.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 42)
                .offset(x: motionPhase && !reduceMotion ? 90 : 62, y: -170)

            VStack(spacing: card.style == .bold ? 10 : 13) {
                Text(displayTitle)
                    .font(titleFont)
                    .tracking(card.style == .editorial ? -0.6 : 0)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.62)
                    .foregroundStyle(TR.cream)
                    .trEntrance(0, distance: 10)
                Text(card.subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .trEntrance(1, distance: 8)
            }
            .padding(.horizontal, 30)
            .offset(y: motionPhase && !reduceMotion ? -5 : 5)
        }
    }

    private var displayTitle: String {
        card.style == .bold ? card.title.uppercased() : card.title
    }

    private var titleFont: Font {
        let size: CGFloat = card.kind == .opening ? 42 : 34
        switch card.style {
        case .editorial:
            return TR.display(size)
        case .clean:
            return TR.ui(size * 0.74, weight: .semibold)
        case .bold:
            return .system(size: size * 0.78, weight: .black, design: .rounded)
        }
    }

    private var subtitleFont: Font {
        switch card.style {
        case .editorial:
            return TR.ui(13, weight: .medium)
        case .clean:
            return TR.ui(12, weight: .regular)
        case .bold:
            return TR.mono(11, weight: .semibold)
        }
    }
}

private extension MontageMotionStyle {
    var transition: AnyTransition {
        switch self {
        case .panLeft:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 14, y: 0)),
                removal: .opacity.combined(with: .offset(x: -10, y: 0))
            )
        case .panRight:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: -14, y: 0)),
                removal: .opacity.combined(with: .offset(x: 10, y: 0))
            )
        case .rise:
            return .opacity.combined(with: .offset(x: 0, y: 12))
        case .settle:
            return .opacity.combined(with: .scale(scale: 1.025))
        case .zoomIn, .zoomOut:
            return .opacity.combined(with: .scale(scale: 0.985))
        }
    }
}

private struct MontageSlideArtwork: View {
    let slide: MontageSlide
    let showLabel: Bool
    let motionPhase: Bool
    let reduceMotion: Bool
    let motionIntensity: MontageMotionIntensity
    var onLoadStateChange: ((PhotoAssetLoadState) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            switch slide.frameStyle {
            case .fullBleed:
                fullBleed(size: proxy.size)
            case .portraitMatte:
                portraitMatte(size: proxy.size)
            case .cinematic:
                cinematic(size: proxy.size)
            case .postcard:
                postcard(size: proxy.size)
            }
        }
    }

    private func fullBleed(size: CGSize) -> some View {
        Group {
            if slide.isVideo {
                VideoAssetClipView(
                    source: slide.source,
                    startSeconds: slide.videoStartSeconds,
                    durationSeconds: slide.videoDurationSeconds,
                    label: showLabel ? slide.label : nil,
                    contentScale: CGFloat(slide.cropScale),
                    contentOffset: cropOffset(in: size),
                    playsAudio: slide.playsOriginalAudio,
                    onLoadStateChange: onLoadStateChange
                )
            } else {
                PhotoAssetView(
                    source: slide.source,
                    label: showLabel ? slide.label : nil,
                    contentScale: fullBleedScale * CGFloat(slide.cropScale),
                    contentOffset: combinedOffset(in: size),
                    samplingScale: CGFloat(slide.cropScale) * (1 + 0.085 * amplitude),
                    onLoadStateChange: onLoadStateChange
                )
            }
        }
    }

    private func portraitMatte(size: CGSize) -> some View {
        let frameSize = portraitFrameSize(in: size)
        return ZStack {
            PhotoAssetView(source: slide.source)
                .scaleEffect(1.22)
                .blur(radius: 30)
                .saturation(0.82)
                .overlay(.black.opacity(0.34))

            LinearGradient(
                colors: [.black.opacity(0.22), .clear, .black.opacity(0.44)],
                startPoint: .top,
                endPoint: .bottom
            )

            PhotoAssetView(
                source: slide.source,
                label: showLabel ? slide.label : nil,
                contentMode: .fit,
                contentScale: CGFloat(slide.cropScale),
                contentOffset: cropOffset(in: frameSize),
                samplingScale: CGFloat(slide.cropScale) * (1 + 0.028 * amplitude),
                onLoadStateChange: onLoadStateChange
            )
            .frame(width: frameSize.width, height: frameSize.height)
            .background(.black.opacity(0.34))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .shadow(color: .black.opacity(0.62), radius: 26, y: 16)
            .scaleEffect(framedScale)
            .offset(framedOffset(in: size))
        }
    }

    private func cinematic(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.035, green: 0.027, blue: 0.021)
            PhotoAssetView(
                source: slide.source,
                contentMode: .fit,
                contentScale: CGFloat(slide.cropScale),
                contentOffset: cropOffset(
                    in: CGSize(width: size.width, height: size.height * 0.62)
                ),
                samplingScale: CGFloat(slide.cropScale) * (1 + 0.028 * amplitude),
                onLoadStateChange: onLoadStateChange
            )
                .frame(height: size.height * 0.62)
                .scaleEffect(framedScale)
                .offset(framedOffset(in: size))

            VStack {
                filmEdge
                Spacer()
                filmEdge
            }
            .padding(.vertical, 13)

            if showLabel {
                montageLabel
            }
        }
    }

    private func postcard(size: CGSize) -> some View {
        ZStack {
            PhotoAssetView(source: slide.source)
                .scaleEffect(1.14)
                .blur(radius: 24)
                .saturation(0.72)
                .overlay(.black.opacity(0.46))

            VStack(spacing: 0) {
                PhotoAssetView(
                    source: slide.source,
                    contentMode: .fit,
                    contentScale: CGFloat(slide.cropScale),
                    contentOffset: cropOffset(
                        in: CGSize(
                            width: max(1, size.width * 0.82 - 16),
                            height: size.height * 0.62
                        )
                    ),
                    samplingScale: CGFloat(slide.cropScale) * (1 + 0.028 * amplitude),
                    onLoadStateChange: onLoadStateChange
                )
                    .frame(height: size.height * 0.62)
                    .background(Color(red: 0.12, green: 0.09, blue: 0.07))

                HStack {
                    Text(showLabel ? slide.label : "TRIPREEL")
                        .font(TR.mono(9))
                        .tracking(1.1)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "sparkle")
                }
                .foregroundStyle(TR.ink.opacity(0.68))
                .padding(.horizontal, 13)
                .frame(height: 38)
            }
            .frame(width: size.width * 0.82)
            .padding(8)
            .background(TR.cream)
            .rotationEffect(.degrees(postcardRotation))
            .scaleEffect(framedScale)
            .offset(framedOffset(in: size))
            .shadow(color: .black.opacity(0.62), radius: 24, y: 17)
        }
    }

    private var amplitude: CGFloat {
        reduceMotion ? 0 : CGFloat(motionIntensity.amplitude)
    }

    private var fullBleedScale: CGFloat {
        let wide = 0.085 * amplitude
        let quiet = 0.018 * amplitude
        switch slide.motionStyle {
        case .zoomIn:
            return motionPhase ? 1 + wide : 1 + quiet
        case .zoomOut:
            return motionPhase ? 1 + quiet : 1 + wide
        case .panLeft, .panRight:
            return 1 + (0.075 * amplitude)
        case .rise:
            return motionPhase ? 1 + (0.065 * amplitude) : 1 + (0.025 * amplitude)
        case .settle:
            return motionPhase ? 1 + quiet : 1 + (0.065 * amplitude)
        }
    }

    private var framedScale: CGFloat {
        guard !slide.usesAutomaticPeopleFraming else { return 1 }
        let amount = 0.028 * amplitude
        switch slide.motionStyle {
        case .zoomOut, .settle:
            return motionPhase ? 1 : 1 + amount
        default:
            return motionPhase ? 1 + amount : 1
        }
    }

    private func motionOffset(in size: CGSize) -> CGSize {
        let horizontal = size.width * 0.038 * amplitude
        let vertical = size.height * 0.025 * amplitude
        switch slide.motionStyle {
        case .panLeft:
            return CGSize(width: motionPhase ? -horizontal : horizontal, height: 0)
        case .panRight:
            return CGSize(width: motionPhase ? horizontal : -horizontal, height: 0)
        case .rise:
            return CGSize(width: 0, height: motionPhase ? -vertical : vertical)
        case .settle:
            return CGSize(width: 0, height: motionPhase ? 0 : -vertical * 0.45)
        case .zoomIn:
            return CGSize(width: motionPhase ? -horizontal * 0.30 : horizontal * 0.20, height: 0)
        case .zoomOut:
            return CGSize(width: motionPhase ? 0 : -horizontal * 0.25, height: 0)
        }
    }

    private func framedOffset(in size: CGSize) -> CGSize {
        guard !slide.usesAutomaticPeopleFraming else { return .zero }
        let full = motionOffset(in: size)
        return CGSize(width: full.width * 0.30, height: full.height * 0.30)
    }

    private func cropOffset(in size: CGSize) -> CGSize {
        CGSize(
            width: size.width * 0.24 * CGFloat(slide.cropOffsetX),
            height: size.height * 0.24 * CGFloat(slide.cropOffsetY)
        )
    }

    private func portraitFrameSize(in size: CGSize) -> CGSize {
        let maximum = CGSize(width: size.width * 0.94, height: size.height * 0.88)
        let ratio = max(CGFloat(slide.aspectRatio), 0.1)
        if maximum.width / maximum.height > ratio {
            return CGSize(width: maximum.height * ratio, height: maximum.height)
        }
        return CGSize(width: maximum.width, height: maximum.width / ratio)
    }

    private func combinedOffset(in size: CGSize) -> CGSize {
        let motion = motionOffset(in: size)
        let crop = cropOffset(in: size)
        return CGSize(width: motion.width + crop.width, height: motion.height + crop.height)
    }

    private var postcardRotation: Double {
        let amount = Double(amplitude) * 1.5
        switch slide.motionStyle {
        case .panRight, .zoomOut, .settle:
            return motionPhase ? -0.35 : -0.35 - amount
        default:
            return motionPhase ? -0.35 + amount : -0.35
        }
    }

    private var filmEdge: some View {
        HStack(spacing: 7) {
            ForEach(0..<10, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.18))
                    .frame(width: 19, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var montageLabel: some View {
        Text(slide.label)
            .font(TR.mono(10))
            .tracking(1.3)
            .foregroundStyle(.white.opacity(0.56))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(18)
    }
}

private struct MontageContentKey: Hashable {
    let itemIDs: [String]
    let itemDurationsMilliseconds: [Int]
}

private struct MontagePlaybackKey: Hashable {
    let content: MontageContentKey
    let behavior: MontagePlaybackBehavior
    let generation: Int
}

private struct MontageMotionPlaybackKey: Hashable {
    let itemID: String?
    let look: MontageLook
    let intensity: MontageMotionIntensity
    let frameStyle: MontageFrameStyle?
    let motionStyle: MontageMotionStyle?
    let reduceMotion: Bool
    let generation: Int
}

private struct VideoAssetClipView: View {
    let source: PhotoSource
    let startSeconds: Double
    let durationSeconds: Double
    let label: String?
    let contentScale: CGFloat
    let contentOffset: CGSize
    let playsAudio: Bool
    let onLoadStateChange: ((PhotoAssetLoadState) -> Void)?

    @StateObject private var loader = MontageVideoClipLoader()

    private var requestKey: MontageVideoClipKey? {
        guard case .bundled = source else {
            return MontageVideoClipKey(
                source: source,
                startMilliseconds: Int((max(0, startSeconds) * 1_000).rounded()),
                durationMilliseconds: Int((max(0.8, durationSeconds) * 1_000).rounded()),
                playsAudio: playsAudio
            )
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let player = loader.player {
                MontagePlayerSurface(player: player)
                    .scaleEffect(max(1, contentScale))
                    .offset(contentOffset)
            } else {
                videoPlaceholder
            }

            if let label {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                    Text(label)
                }
                .font(TR.mono(9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.76))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.52))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(16)
            }
        }
        .clipped()
        .task(id: requestKey) {
            guard let requestKey else {
                loader.cancel()
                return
            }
            await loader.load(requestKey)
        }
        .onDisappear { loader.cancel() }
        .onChange(of: loader.loadState, initial: true) { _, state in
            onLoadStateChange?(state)
        }
        .accessibilityLabel(label.map { "Video clip, \($0)" } ?? "Video clip")
    }

    @ViewBuilder
    private var videoPlaceholder: some View {
        switch source {
        case .library:
            PhotoAssetView(source: source)
                .overlay(.black.opacity(0.12))
        case .imported, .bundled:
            ZStack {
                Color.black
                Image(systemName: "video.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }
}

private struct MontageVideoClipKey: Hashable, Sendable {
    let source: PhotoSource
    let startMilliseconds: Int
    let durationMilliseconds: Int
    let playsAudio: Bool
}

@MainActor
private final class MontageVideoClipLoader: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loadState: PhotoAssetLoadState = .loading(progress: nil)

    private static let manager = PHCachingImageManager()
    private var task: Task<Void, Never>?
    private var activeKey: MontageVideoClipKey?

    func load(_ key: MontageVideoClipKey) async {
        if activeKey == key, player != nil { return }
        cancel()
        activeKey = key
        loadState = .loading(progress: nil)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let asset = try await Self.requestAsset(
                    source: key.source,
                    progress: { [weak self] value in
                        Task { @MainActor [weak self] in
                            guard self?.activeKey == key else { return }
                            self?.loadState = .loading(progress: value)
                        }
                    }
                )
                try Task.checkCancellation()
                guard self.activeKey == key else { return }
                let item = AVPlayerItem(asset: asset)
                let start = CMTime(
                    seconds: Double(key.startMilliseconds) / 1_000,
                    preferredTimescale: 600
                )
                let duration = CMTime(
                    seconds: Double(key.durationMilliseconds) / 1_000,
                    preferredTimescale: 600
                )
                item.forwardPlaybackEndTime = CMTimeAdd(start, duration)
                let player = AVPlayer(playerItem: item)
                player.actionAtItemEnd = .pause
                player.volume = key.playsAudio ? 0.78 : 0
                await player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
                guard !Task.isCancelled, self.activeKey == key else { return }
                self.player = player
                self.loadState = .ready
                player.play()
            } catch is CancellationError {
                return
            } catch {
                guard self.activeKey == key else { return }
                self.player = nil
                self.loadState = .failed
            }
        }
        await task?.value
    }

    func cancel() {
        task?.cancel()
        task = nil
        player?.pause()
        player = nil
        activeKey = nil
        loadState = .loading(progress: nil)
    }

    private static func requestAsset(
        source: PhotoSource,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> AVAsset {
        switch source {
        case let .imported(path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw PhotoAnalysisThumbnailError.inaccessible
            }
            return AVURLAsset(url: url)
        case .bundled:
            throw PhotoAnalysisThumbnailError.inaccessible
        case let .library(identifier):
            return try await requestLibraryAsset(identifier: identifier, progress: progress)
        }
    }

    private static func requestLibraryAsset(
        identifier: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> AVAsset {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let photoAsset = result.firstObject, photoAsset.mediaType == .video else {
            throw PhotoAnalysisThumbnailError.inaccessible
        }
        let state = MontageVideoAssetRequestState(manager: manager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let options = PHVideoRequestOptions()
                options.deliveryMode = .automatic
                options.version = .current
                options.isNetworkAccessAllowed = true
                options.progressHandler = { value, _, _, _ in
                    progress(min(0.99, max(0, value)))
                }
                let requestID = manager.requestAVAsset(
                    forVideo: photoAsset,
                    options: options
                ) { asset, _, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        state.finish(.failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if let asset {
                        state.finish(.success(asset))
                    } else {
                        state.finish(.failure(PhotoAnalysisThumbnailError.unavailable))
                    }
                }
                state.install(requestID: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }
}

private struct MontagePlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> MontagePlayerView {
        let view = MontagePlayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: MontagePlayerView, context: Context) {
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: MontagePlayerView, coordinator: Void) {
        uiView.player = nil
    }
}

private final class MontagePlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
}

private final class MontageVideoAssetRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private let manager: PHImageManager
    private var continuation: CheckedContinuation<AVAsset, Error>?
    private var requestID = PHInvalidImageRequestID
    private var completed = false

    init(manager: PHImageManager) { self.manager = manager }

    func install(continuation: CheckedContinuation<AVAsset, Error>) {
        lock.lock()
        if completed {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(requestID: PHImageRequestID) {
        lock.lock()
        if completed {
            lock.unlock()
            manager.cancelImageRequest(requestID)
            return
        }
        self.requestID = requestID
        lock.unlock()
    }

    func finish(_ result: Result<AVAsset, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = continuation
        self.continuation = nil
        let requestID = requestID
        lock.unlock()
        if requestID != PHInvalidImageRequestID { manager.cancelImageRequest(requestID) }
        continuation?.resume(throwing: CancellationError())
    }
}

private struct PhotoSourceImage: View {
    let source: PhotoSource
    let size: CGSize
    let contentMode: PhotoDisplayContentMode
    let samplingScale: CGFloat
    let onLoadStateChange: ((PhotoAssetLoadState) -> Void)?
    @Environment(\.displayScale) private var displayScale
    @StateObject private var loader = PhotoAssetImageLoader()

    private var requestKey: PhotoImageRequestKey? {
        guard size.width > 1,
              size.height > 1 else { return nil }
        switch source {
        case .bundled:
            return nil
        case .library, .imported:
            break
        }
        return PhotoImageRequestKey(
            source: source,
            pixelWidth: max(
                80,
                Int((size.width * displayScale * samplingScale).rounded(.up))
            ),
            pixelHeight: max(
                80,
                Int((size.height * displayScale * samplingScale).rounded(.up))
            ),
            contentMode: contentMode
        )
    }

    var body: some View {
        Group {
            switch source {
            case let .bundled(imageName):
                if contentMode == .fit {
                    Image(imageName).resizable().scaledToFit()
                } else {
                    Image(imageName).resizable().scaledToFill()
                }
            case .library, .imported:
                if let image = loader.image {
                    if contentMode == .fit {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                } else {
                    ZStack {
                        Color.white.opacity(0.055)
                        if let progress = loader.downloadProgress {
                            VStack(spacing: 8) {
                                ProgressView(value: progress)
                                    .progressViewStyle(.circular)
                                    .tint(TR.accent)
                                if min(size.width, size.height) > 96 {
                                    Text("Downloading from iCloud \(Int(progress * 100))%")
                                        .font(TR.ui(10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.52))
                                }
                            }
                        } else {
                            VStack(spacing: 7) {
                                Image(systemName: loader.failed ? "photo.badge.exclamationmark" : "photo")
                                    .font(.system(size: min(size.width, size.height) * 0.23, weight: .light))
                                if loader.failed && min(size.width, size.height) > 96 {
                                    Text("Tap to try again")
                                        .font(TR.ui(10, weight: .medium))
                                }
                            }
                            .foregroundStyle(.white.opacity(0.28))
                        }
                    }
                }
            }
        }
        .animation(TRMotion.imageLoad, value: loader.image != nil)
        .onChange(of: requestKey, initial: true) { _, newValue in
            guard let newValue else {
                loader.cancel()
                return
            }
            loader.load(newValue)
        }
        .onAppear {
            if let requestKey {
                if loader.failed {
                    loader.retry(requestKey)
                } else {
                    loader.load(requestKey)
                }
            }
        }
        .onTapGesture {
            guard loader.failed, let requestKey else { return }
            loader.retry(requestKey)
        }
        .onDisappear { loader.cancel() }
        .onChange(of: reportedLoadState, initial: true) { _, state in
            onLoadStateChange?(state)
        }
        .accessibilityLabel(loader.failed ? "Photo unavailable. Tap to try again." : "Photo")
    }

    private var reportedLoadState: PhotoAssetLoadState {
        if case .bundled = source { return .ready }
        if loader.isPreviewReady { return .ready }
        if loader.failed { return .failed }
        return .loading(progress: loader.downloadProgress)
    }
}

private struct PhotoImageRequestKey: Hashable, Sendable {
    let source: PhotoSource
    let pixelWidth: Int
    let pixelHeight: Int
    let contentMode: PhotoDisplayContentMode
}

@MainActor
private final class PhotoAssetImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isPreviewReady = false
    @Published private(set) var failed = false
    @Published private(set) var downloadProgress: Double?

    private static let manager = PHCachingImageManager()
    private static let imageCache: NSCache<NSString, CachedPhotoImage> = {
        let cache = NSCache<NSString, CachedPhotoImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()
    private static let preheatPixelDimension: CGFloat = 2_560
    nonisolated private static let maximumDisplayPixelDimension: CGFloat = 4_096
    private static let minimumCachedQuality = 0.90
    private static var preheatInFlight = Set<String>()
    private var requestID = PHInvalidImageRequestID
    private var key: PhotoImageRequestKey?
    private var retryTask: Task<Void, Never>?
    private var fileTask: Task<Void, Never>?
    private var retryCount = 0
    private var usingDataFallback = false

    static func preheat(sources: [PhotoSource]) {
        let identifiers = sources.compactMap { source -> String? in
            guard case let .library(identifier) = source,
                  !preheatInFlight.contains(identifier) else { return nil }
            if let cached = imageCache.object(forKey: identifier as NSString),
               max(cached.pixelWidth, cached.pixelHeight) >= 2_200 {
                return nil
            }
            return identifier
        }
        guard !identifiers.isEmpty else { return }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        result.enumerateObjects { asset, _, _ in
            let identifier = asset.localIdentifier
            preheatInFlight.insert(identifier)
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImage(
                for: asset,
                targetSize: CGSize(
                    width: preheatPixelDimension,
                    height: preheatPixelDimension
                ),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                Task { @MainActor in
                    guard !cancelled else {
                        preheatInFlight.remove(identifier)
                        return
                    }
                    if let image, !degraded {
                        store(
                            image,
                            for: .library(identifier),
                            sourcePixelWidth: asset.pixelWidth,
                            sourcePixelHeight: asset.pixelHeight
                        )
                    }
                    if !degraded {
                        preheatInFlight.remove(identifier)
                    }
                }
            }
        }
    }

    func load(_ key: PhotoImageRequestKey) {
        guard self.key != key else { return }
        cancel()
        self.key = key
        isPreviewReady = false
        failed = false
        downloadProgress = nil
        if let cached = Self.cachedPhoto(for: key.source) {
            image = cached.image
            if Self.isSufficient(cached, for: key) {
                isPreviewReady = true
                return
            }
        }
        request(key)
    }

    func retry(_ key: PhotoImageRequestKey) {
        guard self.key == key else {
            load(key)
            return
        }
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
        isPreviewReady = false
        failed = false
        downloadProgress = nil
        usingDataFallback = false
        request(key)
    }

    private func request(_ key: PhotoImageRequestKey) {
        cancelImageRequest()

        switch key.source {
        case .bundled:
            failed = true
        case let .library(identifier):
            requestLibraryImage(identifier: identifier, key: key)
        case let .imported(path):
            requestImportedImage(path: path, key: key)
        }
    }

    private func requestLibraryImage(identifier: String, key: PhotoImageRequestKey) {

        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject else {
            failed = true
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] progress, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.key == key else { return }
                self.downloadProgress = min(0.99, max(0, progress))
                self.failed = false
            }
        }

        // Ask for enough source pixels to cover the rendered rectangle, not
        // merely its longest edge. A landscape image filling a portrait screen
        // needs substantially more width than the view bounds suggest.
        let targetSize = Self.displayTargetSize(
            sourcePixelWidth: asset.pixelWidth,
            sourcePixelHeight: asset.pixelHeight,
            key: key
        )

        requestID = Self.manager.requestImage(
            for: asset,
            targetSize: targetSize,
            // Request the uncropped thumbnail. SwiftUI applies fill/fit later,
            // so portrait frames can reuse the same pixels without PhotoKit
            // baking in a landscape crop.
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let error = info?[PHImageErrorKey] as? Error
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            Task { @MainActor [weak self] in
                guard let self, self.key == key, !cancelled else { return }
                if let image {
                    self.image = image
                    if !degraded {
                        Self.store(
                            image,
                            for: key.source,
                            sourcePixelWidth: asset.pixelWidth,
                            sourcePixelHeight: asset.pixelHeight
                        )
                        if Self.image(image, satisfies: targetSize) {
                            self.retryTask?.cancel()
                            self.retryTask = nil
                            self.failed = false
                            self.isPreviewReady = true
                            self.downloadProgress = nil
                            self.retryCount = 0
                            self.usingDataFallback = false
                        } else if !self.usingDataFallback {
                            // Keep the preview visible, but replace it with a
                            // source-data decode rather than freezing on a
                            // final callback that is still too small.
                            self.requestLibraryImageData(asset: asset, key: key)
                        }
                    }
                } else if error != nil || !degraded {
                    if self.retryCount >= 1 && !self.usingDataFallback {
                        self.requestLibraryImageData(asset: asset, key: key)
                    } else {
                        self.scheduleRetry(for: key)
                    }
                }
            }
        }
    }

    private func requestLibraryImageData(asset: PHAsset, key: PhotoImageRequestKey) {
        cancelImageRequest()
        usingDataFallback = true
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] progress, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.key == key else { return }
                self.downloadProgress = min(0.99, max(0, progress))
                self.failed = false
            }
        }

        requestID = Self.manager.requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { [weak self] data, _, _, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            guard !cancelled, let data else {
                Task { @MainActor [weak self] in
                    guard let self, self.key == key else { return }
                    self.usingDataFallback = false
                    self.scheduleRetry(for: key)
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self, self.key == key else { return }
                self.fileTask?.cancel()
                self.fileTask = Task { [weak self] in
                    let targetSize = Self.displayTargetSize(
                        sourcePixelWidth: asset.pixelWidth,
                        sourcePixelHeight: asset.pixelHeight,
                        key: key
                    )
                    let maximumPixelSize = Int(max(targetSize.width, targetSize.height).rounded(.up))
                    let decoded = await Task.detached(priority: .userInitiated) {
                        Self.thumbnail(from: data, maximumPixelSize: maximumPixelSize)
                    }.value
                    guard !Task.isCancelled, let self, self.key == key else { return }
                    self.usingDataFallback = false
                    if let decoded {
                        self.image = decoded
                        Self.store(
                            decoded,
                            for: key.source,
                            sourcePixelWidth: asset.pixelWidth,
                            sourcePixelHeight: asset.pixelHeight
                        )
                        self.downloadProgress = nil
                        self.failed = false
                        self.isPreviewReady = true
                        self.retryCount = 0
                    } else {
                        self.scheduleRetry(for: key)
                    }
                }
            }
        }
    }

    private func requestImportedImage(path: String, key: PhotoImageRequestKey) {
        fileTask?.cancel()
        fileTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return nil as DecodedPhotoImage? }
                let url = URL(fileURLWithPath: path)
                if let source = CGImageSourceCreateWithURL(
                    url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                ) {
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                    let sourceWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? key.pixelWidth
                    let sourceHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? key.pixelHeight
                    let target = Self.displayTargetSize(
                        sourcePixelWidth: sourceWidth,
                        sourcePixelHeight: sourceHeight,
                        key: key
                    )
                    if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCacheImmediately: true,
                            kCGImageSourceThumbnailMaxPixelSize: Int(max(target.width, target.height).rounded(.up))
                        ] as CFDictionary
                    ) {
                        return DecodedPhotoImage(
                            image: UIImage(cgImage: thumbnail),
                            sourcePixelWidth: sourceWidth,
                            sourcePixelHeight: sourceHeight
                        )
                    }
                }

                // A permission-free PhotosPicker video is an ordinary local
                // movie file. Extract one small poster on-device so every grid
                // can display it without a special video-only component.
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1_920, height: 1_920)
                guard let generated = try? await generator.image(
                    at: CMTime(seconds: 0.12, preferredTimescale: 600)
                ) else { return nil as DecodedPhotoImage? }
                return DecodedPhotoImage(
                    image: UIImage(cgImage: generated.image),
                    sourcePixelWidth: generated.image.width,
                    sourcePixelHeight: generated.image.height
                )
            }.value

            guard !Task.isCancelled, let self, self.key == key else { return }
            if let decoded {
                self.retryTask?.cancel()
                self.retryTask = nil
                self.image = decoded.image
                Self.store(
                    decoded.image,
                    for: key.source,
                    sourcePixelWidth: decoded.sourcePixelWidth,
                    sourcePixelHeight: decoded.sourcePixelHeight
                )
                self.failed = false
                self.isPreviewReady = true
                self.downloadProgress = nil
                self.retryCount = 0
            } else {
                self.failed = true
                self.scheduleRetry(for: key)
            }
        }
    }

    private func scheduleRetry(for key: PhotoImageRequestKey) {
        guard retryTask == nil else { return }
        guard retryCount < 4 else {
            failed = true
            downloadProgress = nil
            return
        }
        retryCount += 1
        let retryDelays: [UInt64] = [1, 2, 4, 7]
        let delay = retryDelays[retryCount - 1] * 1_000_000_000
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.key == key else { return }
            self.retryTask = nil
            self.failed = false
            self.isPreviewReady = false
            self.downloadProgress = nil
            self.request(key)
        }
    }

    private static func cachedPhoto(for source: PhotoSource) -> CachedPhotoImage? {
        guard let identifier = cacheIdentifier(for: source) else { return nil }
        return imageCache.object(forKey: identifier as NSString)
    }

    private static func isSufficient(
        _ cached: CachedPhotoImage,
        for key: PhotoImageRequestKey
    ) -> Bool {
        let target = displayTargetSize(
            sourcePixelWidth: cached.sourcePixelWidth,
            sourcePixelHeight: cached.sourcePixelHeight,
            key: key
        )
        return dimensions(
            width: cached.pixelWidth,
            height: cached.pixelHeight,
            satisfy: target
        )
    }

    private static func image(_ image: UIImage, satisfies target: CGSize) -> Bool {
        let width = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let height = image.cgImage?.height ?? Int(image.size.height * image.scale)
        return dimensions(width: width, height: height, satisfy: target)
    }

    private static func dimensions(width: Int, height: Int, satisfy target: CGSize) -> Bool {
        let requiredWidth = target.width * minimumCachedQuality
        let requiredHeight = target.height * minimumCachedQuality
        let direct = CGFloat(width) >= requiredWidth && CGFloat(height) >= requiredHeight
        let rotated = CGFloat(height) >= requiredWidth && CGFloat(width) >= requiredHeight
        return direct || rotated
    }

    private static func store(
        _ image: UIImage,
        for source: PhotoSource,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int
    ) {
        guard let identifier = cacheIdentifier(for: source) else { return }
        let pixelWidth = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let pixelHeight = image.cgImage?.height ?? Int(image.size.height * image.scale)
        if let existing = imageCache.object(forKey: identifier as NSString),
           existing.pixelWidth * existing.pixelHeight >= pixelWidth * pixelHeight { return }
        let value = CachedPhotoImage(
            image: image,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            sourcePixelWidth: max(sourcePixelWidth, pixelWidth),
            sourcePixelHeight: max(sourcePixelHeight, pixelHeight)
        )
        let cost = max(1, pixelWidth * pixelHeight * 4)
        imageCache.setObject(value, forKey: identifier as NSString, cost: cost)
    }

    /// Returns an uncropped source-sized request that is large enough for the
    /// destination rectangle and a small Ken Burns overscan. This avoids both
    /// oversized grid requests and undersized full-screen landscape crops.
    nonisolated private static func displayTargetSize(
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        key: PhotoImageRequestKey
    ) -> CGSize {
        PhotoDisplaySizing.targetSize(
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            destinationPixelWidth: key.pixelWidth,
            destinationPixelHeight: key.pixelHeight,
            contentMode: key.contentMode,
            maximumPixelDimension: maximumDisplayPixelDimension
        )
    }

    private static func cacheIdentifier(for source: PhotoSource) -> String? {
        switch source {
        case .bundled:
            nil
        case let .library(identifier):
            identifier
        case let .imported(path):
            "file:\(path)"
        }
    }

    nonisolated private static func thumbnail(from data: Data, maximumPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    private func cancelImageRequest() {
        if requestID != PHInvalidImageRequestID {
            Self.manager.cancelImageRequest(requestID)
        }
        requestID = PHInvalidImageRequestID
    }

    func cancel() {
        retryTask?.cancel()
        retryTask = nil
        fileTask?.cancel()
        fileTask = nil
        retryCount = 0
        usingDataFallback = false
        cancelImageRequest()
        key = nil
        image = nil
        isPreviewReady = false
        failed = false
        downloadProgress = nil
    }

    private final class CachedPhotoImage {
        let image: UIImage
        let pixelWidth: Int
        let pixelHeight: Int
        let sourcePixelWidth: Int
        let sourcePixelHeight: Int

        init(
            image: UIImage,
            pixelWidth: Int,
            pixelHeight: Int,
            sourcePixelWidth: Int,
            sourcePixelHeight: Int
        ) {
            self.image = image
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.sourcePixelWidth = sourcePixelWidth
            self.sourcePixelHeight = sourcePixelHeight
        }
    }

    private struct DecodedPhotoImage: @unchecked Sendable {
        let image: UIImage
        let sourcePixelWidth: Int
        let sourcePixelHeight: Int
    }
}

struct MetadataText: View {
    let text: String
    var color: Color = .white.opacity(0.53)

    var body: some View {
        Text(text.uppercased())
            .font(TR.mono(11))
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

struct ScreenHeading: View {
    let eyebrow: String?
    let title: String
    var size: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                MetadataText(text: eyebrow)
            }
            Text(title)
                .font(TR.display(size))
                .tracking(-0.5)
                .foregroundStyle(TR.cream)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CircleIconButton: View {
    let symbol: String
    let tint: Color
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 66, height: 66)
                .background(tint.opacity(0.12))
                .overlay(Circle().stroke(tint.opacity(0.46), lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(symbol == "xmark" ? "Cut photo" : "Keep photo")
    }
}

struct PlaybackProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var duration: Double = 13.2
    var playbackRun = 0
    var isComplete = false
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(TR.cream)
                    .frame(width: proxy.size.width * progress)
                Circle()
                    .fill(TR.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: TR.accent.opacity(0.75), radius: 6)
                    .offset(x: max(0, proxy.size.width * progress - 3))
            }
        }
        .frame(height: 2)
        .task(id: PlaybackProgressKey(reduceMotion: reduceMotion, playbackRun: playbackRun)) {
            if reduceMotion {
                progress = isComplete ? 1 : 0
            } else {
                progress = 0
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: max(0.6, duration))) {
                    progress = 1
                }
            }
        }
        .onChange(of: isComplete) { _, complete in
            guard complete else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.16)) {
                progress = 1
            }
        }
    }
}

private struct PlaybackProgressKey: Hashable {
    let reduceMotion: Bool
    let playbackRun: Int
}

/// Plays bundled, attributed CC BY 4.0 music without a network connection.
@MainActor
final class LocalSoundtrackPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var activeTrackID: String?
    private var finishTask: Task<Void, Never>?

    func play(track: MusicTrack?, volume: Float = 0.82, restart: Bool = false) {
        guard let track, let resourceName = track.resourceName else {
            stop()
            return
        }
        finishTask?.cancel()
        finishTask = nil
        let safeVolume = min(1, max(0, volume))
        if activeTrackID == track.id, isPlaying, !restart {
            player?.volume = safeVolume
            return
        }

        stop(deactivateSession: false)
        errorMessage = nil
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "m4a")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "m4a", subdirectory: "Music") else {
            errorMessage = "This music preview is missing from the app."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = safeVolume
            player.prepareToPlay()
            guard player.play() else { throw SoundtrackError.couldNotStart }
            self.player = player
            activeTrackID = track.id
            isPlaying = player.isPlaying
        } catch {
            errorMessage = "Audio preview is unavailable on the current output."
            isPlaying = false
            activeTrackID = nil
        }
    }

    func finishNaturally(fadeDuration: TimeInterval = 0.9) {
        guard let player, player.isPlaying else {
            stop()
            return
        }
        finishTask?.cancel()
        let duration = max(0.15, fadeDuration)
        player.setVolume(0, fadeDuration: duration)
        finishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func toggle(track: MusicTrack?, volume: Float = 0.82) {
        if let player, isPlaying {
            player.pause()
            isPlaying = false
        } else if let player, activeTrackID == track?.id {
            player.volume = min(1, max(0, volume))
            player.play()
            isPlaying = player.isPlaying
        } else {
            play(track: track, volume: volume)
        }
    }

    func stop() {
        stop(deactivateSession: true)
    }

    private func stop(deactivateSession: Bool) {
        finishTask?.cancel()
        finishTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        activeTrackID = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    private enum SoundtrackError: Error {
        case couldNotStart
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.09))
                .clipShape(Circle())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
        .accessibilityLabel("Close")
    }
}

struct SheetHeader: View {
    let title: String
    let done: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TR.display(28))
                .foregroundStyle(TR.cream)
            Spacer()
            Button("Done", action: done)
                .font(TR.ui(15, weight: .semibold))
                .foregroundStyle(TR.accent)
        }
    }
}

struct RoundedIcon: View {
    let symbol: String
    var tint: Color = TR.cream
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.40, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}
