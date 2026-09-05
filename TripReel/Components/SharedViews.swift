import AVFAudio
import ImageIO
import Photos
import SwiftUI
import UIKit

enum PhotoDisplayContentMode: Hashable {
    case fill
    case fit
}

struct PhotoAssetView: View {
    let source: PhotoSource
    var label: String? = nil
    var dim = false
    var contentMode: PhotoDisplayContentMode = .fill

    init(
        source: PhotoSource,
        label: String? = nil,
        dim: Bool = false,
        contentMode: PhotoDisplayContentMode = .fill
    ) {
        self.source = source
        self.label = label
        self.dim = dim
        self.contentMode = contentMode
    }

    init(imageName: String, label: String? = nil, dim: Bool = false) {
        self.init(source: .bundled(imageName), label: label, dim: dim)
    }

    var body: some View {
        GeometryReader { proxy in
            PhotoSourceImage(source: source, size: proxy.size, contentMode: contentMode)
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

struct MontageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var photos: [ReelPhoto] = []
    var usesBundledFallback = false
    var dim = false
    var watermark = false
    var showLabels = true
    var look: MontageLook = .story
    var motionIntensity: MontageMotionIntensity = .gentle
    var secondsPerSlide = 2.2
    @State private var currentIndex = 0
    @State private var motionPhase = false

    private var slideCount: Int {
        if !photos.isEmpty { return photos.count }
        return usesBundledFallback ? TripReelModel.assetNames.count : 0
    }

    private var currentSlide: MontageSlide? {
        guard slideCount > 0 else { return nil }
        let index = min(currentIndex, slideCount - 1)
        if !photos.isEmpty {
            let photo = photos[index]
            return MontageSlide(
                id: photo.id,
                source: photo.source,
                label: photo.label,
                aspectRatio: photo.aspectRatio,
                frameStyle: resolvedFrameStyle(
                    planned: photo.frameStyle,
                    aspectRatio: photo.aspectRatio,
                    index: index
                ),
                motionStyle: photo.motionStyle
            )
        }

        let imageName = TripReelModel.assetNames[index]
        return MontageSlide(
            id: "bundled-\(imageName)",
            source: .bundled(imageName),
            label: TripReelModel.photoLabels[index],
            aspectRatio: 2.0 / 3.0,
            frameStyle: index % 3 == 1 ? .postcard : .portraitMatte,
            motionStyle: MontageMotionStyle.allCases[index % MontageMotionStyle.allCases.count]
        )
    }

    private var contentKey: MontageContentKey {
        MontageContentKey(
            count: slideCount,
            firstID: photos.first?.id ?? (usesBundledFallback ? TripReelModel.assetNames.first : nil),
            lastID: photos.last?.id ?? (usesBundledFallback ? TripReelModel.assetNames.last : nil),
            look: look,
            motionIntensity: motionIntensity
        )
    }

    var body: some View {
        ZStack {
            if let slide = currentSlide {
                MontageSlideArtwork(
                    slide: slide,
                    showLabel: showLabels,
                    motionPhase: motionPhase,
                    reduceMotion: reduceMotion,
                    motionIntensity: motionIntensity
                )
                .id(slide.id)
                .transition(slide.motionStyle.transition)
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

            if watermark {
                Text("TripReel")
                    .font(TR.ui(11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(14)
            }
        }
        .background(Color(red: 0.051, green: 0.035, blue: 0.024))
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.58), value: currentIndex)
        .onChange(of: currentIndex, initial: true) { _, _ in
            motionPhase = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: max(0.7, secondsPerSlide * 0.92))) {
                motionPhase = true
            }
        }
        .task(id: contentKey) {
            currentIndex = 0
            guard !reduceMotion, slideCount > 0 else { return }
            while !Task.isCancelled {
                let delay = UInt64(max(0.6, secondsPerSlide) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                currentIndex = (currentIndex + 1) % slideCount
            }
        }
    }

    private func resolvedFrameStyle(
        planned: MontageFrameStyle,
        aspectRatio: Double,
        index: Int
    ) -> MontageFrameStyle {
        switch look {
        case .story:
            return planned
        case .cinema:
            return aspectRatio < 0.88 ? .portraitMatte : .cinematic
        case .journal:
            return index.isMultiple(of: 3) && aspectRatio >= 0.88 ? .fullBleed : .postcard
        case .clean:
            return aspectRatio < 0.88 ? .portraitMatte : .fullBleed
        }
    }
}

private struct MontageSlide {
    let id: String
    let source: PhotoSource
    let label: String
    let aspectRatio: Double
    let frameStyle: MontageFrameStyle
    let motionStyle: MontageMotionStyle
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
        PhotoAssetView(source: slide.source, label: showLabel ? slide.label : nil)
            .scaleEffect(fullBleedScale)
            .offset(motionOffset(in: size))
    }

    private func portraitMatte(size: CGSize) -> some View {
        ZStack {
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
                contentMode: .fit
            )
            .frame(width: size.width * 0.76, height: size.height * 0.86)
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
            PhotoAssetView(source: slide.source, contentMode: .fit)
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
                PhotoAssetView(source: slide.source, contentMode: .fit)
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
        let full = motionOffset(in: size)
        return CGSize(width: full.width * 0.30, height: full.height * 0.30)
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
    let count: Int
    let firstID: String?
    let lastID: String?
    let look: MontageLook
    let motionIntensity: MontageMotionIntensity
}

private struct PhotoSourceImage: View {
    let source: PhotoSource
    let size: CGSize
    let contentMode: PhotoDisplayContentMode
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
            pixelWidth: max(80, Int((size.width * displayScale).rounded(.up))),
            pixelHeight: max(80, Int((size.height * displayScale).rounded(.up))),
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
                        Image(systemName: loader.failed ? "icloud.slash" : "photo")
                            .font(.system(size: min(size.width, size.height) * 0.23, weight: .light))
                            .foregroundStyle(.white.opacity(0.28))
                    }
                }
            }
        }
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
        .onDisappear { loader.cancel() }
    }
}

private struct PhotoImageRequestKey: Hashable {
    let source: PhotoSource
    let pixelWidth: Int
    let pixelHeight: Int
    let contentMode: PhotoDisplayContentMode
}

@MainActor
private final class PhotoAssetImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var failed = false

    private static let manager = PHCachingImageManager()
    private var requestID = PHInvalidImageRequestID
    private var key: PhotoImageRequestKey?
    private var retryTask: Task<Void, Never>?
    private var fileTask: Task<Void, Never>?
    private var retryCount = 0

    func load(_ key: PhotoImageRequestKey) {
        guard self.key != key else { return }
        cancel()
        self.key = key
        failed = false
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
        failed = false
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
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        // A full-screen @3x request can otherwise make PhotoKit fetch a much
        // larger iCloud original. Start screen-sized but bounded, then retry at
        // progressively smaller thumbnail sizes so the film rarely lands on a
        // blank cloud frame on a slow connection.
        let requestedLongestSide = max(key.pixelWidth, key.pixelHeight)
        let retryBound = max(480, 1_600 / max(1, 1 << retryCount))
        let scale = min(1, CGFloat(retryBound) / CGFloat(max(1, requestedLongestSide)))
        let targetSize = CGSize(
            width: max(160, CGFloat(key.pixelWidth) * scale),
            height: max(160, CGFloat(key.pixelHeight) * scale)
        )

        requestID = Self.manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: key.contentMode == .fit ? .aspectFit : .aspectFill,
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
                        self.retryTask?.cancel()
                        self.retryTask = nil
                        self.failed = false
                        self.retryCount = 0
                    }
                } else if error != nil || !degraded {
                    self.failed = true
                    self.scheduleRetry(for: key)
                }
            }
        }
    }

    private func requestImportedImage(path: String, key: PhotoImageRequestKey) {
        fileTask?.cancel()
        fileTask = Task { [weak self] in
            let maximumPixelSize = max(key.pixelWidth, key.pixelHeight)
            let image = await Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled,
                      let source = CGImageSourceCreateWithURL(
                        URL(fileURLWithPath: path) as CFURL,
                        [kCGImageSourceShouldCache: false] as CFDictionary
                      ),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCacheImmediately: true,
                            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
                        ] as CFDictionary
                      ) else {
                    return nil as UIImage?
                }
                return UIImage(cgImage: thumbnail)
            }.value

            guard !Task.isCancelled, let self, self.key == key else { return }
            if let image {
                self.retryTask?.cancel()
                self.retryTask = nil
                self.image = image
                self.failed = false
                self.retryCount = 0
            } else {
                self.failed = true
                self.scheduleRetry(for: key)
            }
        }
    }

    private func scheduleRetry(for key: PhotoImageRequestKey) {
        guard retryCount < 2, retryTask == nil else { return }
        retryCount += 1
        let delay = UInt64(retryCount) * 1_000_000_000
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.key == key else { return }
            self.retryTask = nil
            self.failed = false
            self.request(key)
        }
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
        cancelImageRequest()
        key = nil
        image = nil
        failed = false
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
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(symbol == "xmark" ? "Cut photo" : "Keep photo")
    }
}

struct PlaybackProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(TR.cream)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 2)
        .onAppear {
            if reduceMotion {
                progress = 0.35
            } else {
                progress = 0
                withAnimation(.linear(duration: 13.2).repeatForever(autoreverses: false)) {
                    progress = 1
                }
            }
        }
    }
}

enum LocalSoundtrackStyle: String, Hashable, Sendable {
    case drift
    case coast
    case market
    case pulse
}

/// Plays small original instrumental loops synthesized entirely on the device.
/// This makes music previews real without a network dependency or licensed
/// catalog audio. A future renderer can schedule the same samples into export.
@MainActor
final class LocalSoundtrackPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var preparationTask: Task<Void, Never>?
    private var activeTrackID: String?

    init() {
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(track: MusicTrack?) {
        guard let track, let profile = track.soundProfile else {
            stop()
            return
        }
        if activeTrackID == track.id, isPlaying { return }

        stop(deactivateSession: false)
        activeTrackID = track.id
        errorMessage = nil
        preparationTask = Task { [weak self] in
            let samples = await Task.detached(priority: .userInitiated) {
                LocalSoundtrackSynthesizer.render(profile: profile, bpm: track.bpmValue)
            }.value
            guard !Task.isCancelled, let self, self.activeTrackID == track.id else { return }
            self.start(samples: samples)
        }
    }

    func toggle(track: MusicTrack?) {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else if activeTrackID == track?.id, engine.isRunning {
            player.play()
            isPlaying = true
        } else {
            play(track: track)
        }
    }

    func stop() {
        stop(deactivateSession: true)
    }

    private func start(samples: [Float]) {
        let frameCount = AVAudioFrameCount(samples.count)
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            errorMessage = "Audio preview couldn't be prepared."
            activeTrackID = nil
            return
        }

        buffer.frameLength = frameCount
        for index in samples.indices {
            channels[0][index] = samples[index]
            channels[1][index] = samples[index]
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            isPlaying = true
        } catch {
            errorMessage = "Audio preview is unavailable on the current output."
            isPlaying = false
            activeTrackID = nil
        }
    }

    private func stop(deactivateSession: Bool) {
        preparationTask?.cancel()
        preparationTask = nil
        player.stop()
        engine.pause()
        isPlaying = false
        activeTrackID = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }
}

private enum LocalSoundtrackSynthesizer {
    static func render(profile: LocalSoundtrackStyle, bpm: Double) -> [Float] {
        let sampleRate = 44_100.0
        let beats = 16.0
        let seconds = beats * 60.0 / max(60, bpm)
        let sampleCount = max(1, Int(seconds * sampleRate))
        let roots = [48, 53, 45, 50]
        var output = [Float](repeating: 0, count: sampleCount)

        for frame in 0..<sampleCount {
            let time = Double(frame) / sampleRate
            let beatPosition = time * bpm / 60.0
            let beatPhase = beatPosition.truncatingRemainder(dividingBy: 1)
            let barPosition = beatPosition / 4
            let bar = min(3, Int(barPosition) % 4)
            let barPhase = barPosition.truncatingRemainder(dividingBy: 1)
            let chordEnvelope = min(1, min(barPhase * 7, (1 - barPhase) * 9))
            let root = roots[bar]

            let rootTone = sine(midi: root, time: time)
            let third = sine(midi: root + (bar == 2 ? 3 : 4), time: time)
            let fifth = sine(midi: root + 7, time: time)
            var sample = (rootTone * 0.42 + third * 0.28 + fifth * 0.24)
                * chordEnvelope * 0.20

            switch profile {
            case .drift:
                sample += sine(midi: root + 12, time: time) * 0.055
                    * (0.5 + 0.5 * sin(time * 0.7))
            case .coast:
                let pluck = exp(-beatPhase * 7.5)
                sample += sine(midi: root + 12 + Int(beatPosition) % 5, time: time)
                    * pluck * 0.16
            case .market:
                let mallet = exp(-beatPhase * 11)
                sample += sine(midi: root + 19 + (Int(beatPosition) % 3) * 2, time: time)
                    * mallet * 0.18
                if Int(beatPosition * 2) % 2 == 1 {
                    sample += deterministicNoise(frame) * exp(-(beatPhase * 2).truncatingRemainder(dividingBy: 1) * 18) * 0.035
                }
            case .pulse:
                let bass = sine(midi: root - 12, time: time) * 0.15
                sample += bass * (beatPhase < 0.56 ? 1 : 0.24)
                sample += sin(2 * .pi * (58 - beatPhase * 30) * time)
                    * exp(-beatPhase * 12) * 0.16
            }

            let edgeFade = min(1, min(time / 0.06, (seconds - time) / 0.06))
            output[frame] = Float(max(-0.86, min(0.86, sample * max(0, edgeFade))))
        }
        return output
    }

    private static func sine(midi: Int, time: Double) -> Double {
        let frequency = 440 * pow(2, Double(midi - 69) / 12)
        return sin(2 * .pi * frequency * time)
    }

    private static func deterministicNoise(_ value: Int) -> Double {
        let raw = sin(Double(value) * 12.9898) * 43_758.5453
        return ((raw - floor(raw)) * 2) - 1
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
        .buttonStyle(.plain)
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
