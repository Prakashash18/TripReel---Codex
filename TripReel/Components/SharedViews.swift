import ImageIO
import Photos
import SwiftUI
import UIKit

struct PhotoAssetView: View {
    let source: PhotoSource
    var label: String? = nil
    var dim = false

    init(source: PhotoSource, label: String? = nil, dim: Bool = false) {
        self.source = source
        self.label = label
        self.dim = dim
    }

    init(imageName: String, label: String? = nil, dim: Bool = false) {
        self.init(source: .bundled(imageName), label: label, dim: dim)
    }

    var body: some View {
        GeometryReader { proxy in
            PhotoSourceImage(source: source, size: proxy.size)
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
    @State private var currentIndex = 0

    private var slideCount: Int {
        if !photos.isEmpty { return photos.count }
        return usesBundledFallback ? TripReelModel.assetNames.count : 0
    }

    private var currentSlide: MontageSlide? {
        guard slideCount > 0 else { return nil }
        let index = min(currentIndex, slideCount - 1)
        if !photos.isEmpty {
            let photo = photos[index]
            return MontageSlide(id: photo.id, source: photo.source, label: photo.label)
        }

        let imageName = TripReelModel.assetNames[index]
        return MontageSlide(
            id: "bundled-\(imageName)",
            source: .bundled(imageName),
            label: TripReelModel.photoLabels[index]
        )
    }

    private var contentKey: MontageContentKey {
        MontageContentKey(
            count: slideCount,
            firstID: photos.first?.id ?? (usesBundledFallback ? TripReelModel.assetNames.first : nil),
            lastID: photos.last?.id ?? (usesBundledFallback ? TripReelModel.assetNames.last : nil)
        )
    }

    var body: some View {
        ZStack {
            if let slide = currentSlide {
                PhotoAssetView(
                    source: slide.source,
                    label: showLabels ? slide.label : nil,
                    dim: false
                )
                .id(slide.id)
                .transition(.opacity)
                .scaleEffect(reduceMotion ? 1 : 1.08)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.72), value: currentIndex)
        .task(id: contentKey) {
            currentIndex = 0
            guard !reduceMotion, slideCount > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled else { return }
                currentIndex = (currentIndex + 1) % slideCount
            }
        }
    }
}

private struct MontageSlide {
    let id: String
    let source: PhotoSource
    let label: String
}

private struct MontageContentKey: Hashable {
    let count: Int
    let firstID: String?
    let lastID: String?
}

private struct PhotoSourceImage: View {
    let source: PhotoSource
    let size: CGSize
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
            pixelHeight: max(80, Int((size.height * displayScale).rounded(.up)))
        )
    }

    var body: some View {
        Group {
            switch source {
            case let .bundled(imageName):
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            case .library, .imported:
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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

        requestID = Self.manager.requestImage(
            for: asset,
            targetSize: CGSize(width: key.pixelWidth, height: key.pixelHeight),
            contentMode: .aspectFill,
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
