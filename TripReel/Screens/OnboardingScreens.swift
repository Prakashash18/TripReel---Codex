import Photos
import PhotosUI
import SwiftUI
import UIKit

struct WelcomeScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 720

            ZStack {
                WarmBackground(variant: .access)

                LinearGradient(
                    colors: [.black.opacity(0.06), .clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: compact ? 15 : 22) {
                    MemoriesEntranceArtwork(reduceMotion: reduceMotion)
                        .frame(height: compact ? 285 : min(410, proxy.size.height * 0.47))
                        .frame(maxWidth: .infinity)
                        .trEntrance(0, distance: 8)

                    VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                        MetadataText(text: TR.appName, color: TR.accent.opacity(0.88))

                        Text(TR.tagline)
                            .font(TR.display(compact ? 37 : 44))
                            .tracking(-0.65)
                            .foregroundStyle(TR.cream)
                            .lineSpacing(compact ? -5 : -7)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .trEntrance(1, distance: 12)

                    Spacer(minLength: compact ? 2 : 8)

                    Button("Get started") {
                        model.continueFromWelcome()
                    }
                    .buttonStyle(CreamButtonStyle())
                    .trEntrance(2, distance: 10)
                    .accessibilityHint("Continues to the one-time Photos setup")
                    .accessibilityIdentifier("welcome-continue-button")
                }
                .padding(.horizontal, 28)
                .padding(.top, compact ? 2 : 10)
                .safeAreaPadding(.vertical, compact ? 8 : 12)
            }
        }
        .accessibilityIdentifier("welcome-screen")
    }
}

private struct MemoriesEntranceArtwork: View {
    let reduceMotion: Bool
    @State private var startDate = Date()

    private let imageNames = Array(TripReelModel.assetNames.prefix(5))
    private let cardRotations: [Double] = [-11, -5.5, 0, 5.5, 11]
    private let cardOffsets: [CGFloat] = [-0.34, -0.17, 0, 0.17, 0.34]
    private let cardVerticalOffsets: [CGFloat] = [0.035, -0.01, -0.035, -0.005, 0.04]

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                artwork(in: proxy.size, progress: 0.78)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    artwork(
                        in: proxy.size,
                        progress: cycleProgress(at: timeline.date)
                    )
                }
            }
        }
        .task {
            startDate = Date()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Several photos gather and become one animated story")
        .accessibilityIdentifier("memories-entrance-artwork")
    }

    private func artwork(in size: CGSize, progress: Double) -> some View {
        let width = max(240, size.width)
        let height = max(250, size.height)
        let centerX = width / 2
        let centerY = height * 0.47
        let reveal = eased(progress, from: 0.02, to: 0.22)
        let gather = eased(progress, from: 0.29, to: 0.57)
        let convert = eased(progress, from: 0.52, to: 0.68)
        let storyProgress = eased(progress, from: 0.66, to: 0.93)
        let cycleOpacity = 1 - eased(progress, from: 0.95, to: 1)
        let cardWidth = min(104, width * 0.29)
        let cardHeight = cardWidth * 1.28
        let reelWidth = min(178, width * 0.47)
        let reelHeight = min(height * 0.76, reelWidth * 1.48)

        return ZStack {
            Circle()
                .fill(TR.accent.opacity(0.17 + (convert * 0.09)))
                .frame(width: reelWidth * 1.6, height: reelWidth * 1.6)
                .blur(radius: 34)
                .scaleEffect(0.82 + (convert * 0.22))
                .position(x: centerX, y: centerY)

            storyFrame(
                width: reelWidth,
                height: reelHeight,
                storyProgress: storyProgress
            )
            .opacity(convert)
            .scaleEffect(0.82 + (convert * 0.18))
            .rotation3DEffect(
                .degrees((1 - convert) * 8),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.62
            )
            .position(x: centerX, y: centerY)

            ForEach(Array(imageNames.enumerated()), id: \.offset) { index, imageName in
                let xStart = centerX + (cardOffsets[index] * width)
                let yStart = centerY + (cardVerticalOffsets[index] * height)
                let xEnd = centerX + (CGFloat(index - 2) * 2.5)
                let yEnd = centerY + (CGFloat(abs(index - 2)) * 2)
                let individualReveal = eased(
                    reveal,
                    from: Double(index) * 0.08,
                    to: min(1, 0.56 + (Double(index) * 0.08))
                )

                entranceCard(imageName)
                    .frame(width: cardWidth, height: cardHeight)
                    .rotationEffect(.degrees(cardRotations[index] * (1 - gather)))
                    .scaleEffect((0.72 + (individualReveal * 0.28)) * (1 - (convert * 0.28)))
                    .opacity(individualReveal * (1 - convert))
                    .position(
                        x: interpolate(xStart, xEnd, gather),
                        y: interpolate(yStart + 24, yEnd, gather)
                    )
                    .zIndex(Double(index + 1))
            }

            HStack(spacing: 10) {
                Text(convert < 0.52 ? "5 MOMENTS" : "1 STORY")
                    .contentTransition(.numericText())
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 42, height: 1)
                    .overlay(alignment: convert < 0.52 ? .leading : .trailing) {
                        Circle()
                            .fill(TR.accent)
                            .frame(width: 5, height: 5)
                    }
                Image(systemName: convert < 0.52 ? "photo.on.rectangle.angled" : "play.rectangle.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(TR.mono(9, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.56))
            .position(x: centerX, y: height - 12)
        }
        .opacity(cycleOpacity)
    }

    private func entranceCard(_ imageName: String) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.12), .clear, .black.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(TR.cream.opacity(0.72), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.48), radius: 14, y: 9)
    }

    private func storyFrame(
        width: CGFloat,
        height: CGFloat,
        storyProgress: Double
    ) -> some View {
        let imagePosition = storyProgress * Double(max(1, imageNames.count - 1))

        return ZStack {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.black.opacity(0.72))

            ForEach(Array(imageNames.enumerated()), id: \.offset) { index, imageName in
                let distance = abs(imagePosition - Double(index))
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width - 12, height: height - 12)
                    .scaleEffect(1.015 + (CGFloat(storyProgress) * 0.055))
                    .opacity(max(0, 1 - distance))
            }
            .frame(width: width - 12, height: height - 12)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.05), .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(6)

            VStack {
                HStack(spacing: 4) {
                    ForEach(imageNames.indices, id: \.self) { index in
                        Capsule()
                            .fill(Double(index) <= imagePosition ? TR.cream : .white.opacity(0.24))
                            .frame(height: 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(TR.accent)
                    Text("YOUR STORY")
                }
                .font(TR.mono(8, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(TR.cream.opacity(0.86))
                .padding(.bottom, 14)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(TR.cream.opacity(0.72), lineWidth: 2)
        }
        .shadow(color: TR.accent.opacity(0.20), radius: 24)
        .shadow(color: .black.opacity(0.56), radius: 22, y: 14)
    }

    private func cycleProgress(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(startDate))
        return elapsed.truncatingRemainder(dividingBy: 7.6) / 7.6
    }

    private func eased(_ value: Double, from start: Double, to end: Double) -> Double {
        guard end > start else { return value >= end ? 1 : 0 }
        let unit = min(1, max(0, (value - start) / (end - start)))
        return unit * unit * (3 - (2 * unit))
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: Double) -> CGFloat {
        start + ((end - start) * CGFloat(progress))
    }
}

struct PhotoAccessScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.openURL) private var openURL
    @State private var requestingAccess = false
    @State private var showPicker = false
    @State private var showAccessDenied = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack {
            WarmBackground(variant: .access)

            accessContent(compact: UIScreen.main.bounds.height < 720)
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            requestingAccess = true
            Task {
                let loaded = await model.loadManualSelection(items: newItems)
                requestingAccess = false
                if loaded { pickerItems = [] }
            }
        }
        .alert("Photo access is off", isPresented: $showAccessDenied) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow Memories to read your photos in Settings, or choose photos manually instead.")
        }
        .accessibilityIdentifier("photo-access-screen")
    }

    private func accessContent(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: compact ? 8 : 42)

            VStack(spacing: compact ? 14 : 24) {
                VStack(spacing: compact ? 7 : 10) {
                    Label("One-time setup", systemImage: "checkmark.shield")
                        .font(TR.mono(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(TR.keep.opacity(0.88))

                    Text("Choose the photos that matter")
                        .font(TR.display(compact ? 32 : 38))
                        .tracking(-0.38)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                MontageView(usesBundledFallback: true, showLabels: false)
                    .frame(width: compact ? 134 : 184, height: compact ? 169 : 232)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 26, y: 18)

                Text("Set this up once. Memories uses dates and locations on this iPhone to group your photos into stories. You stay in control.")
                    .font(TR.ui(compact ? 13 : 15))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(compact ? 2 : 5)
                    .frame(maxWidth: 300)
            }
            .trEntrance(0, distance: compact ? 8 : 14)

            Spacer(minLength: compact ? 8 : 28)

            VStack(spacing: compact ? 10 : 16) {
                Button {
                    requestAccess()
                } label: {
                    HStack(spacing: 9) {
                        if requestingAccess {
                            ProgressView()
                                .tint(TR.ink)
                        }
                        Text(requestingAccess ? "Finding your stories…" : "Allow Photos")
                    }
                }
                .buttonStyle(CreamButtonStyle())
                .disabled(requestingAccess)

                Button("Select photos instead") {
                    showPicker = true
                }
                .font(TR.ui(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .buttonStyle(.plain)
                .photosPicker(
                    isPresented: $showPicker,
                    selection: $pickerItems,
                    maxSelectionCount: 0,
                    matching: .images,
                    preferredItemEncoding: .current,
                    photoLibrary: .shared()
                )
            }
            .trEntrance(1, distance: 10)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, compact ? 0 : 20)
        .safeAreaPadding(.vertical)
        .offset(y: compact ? 0 : 24)
    }

    private func requestAccess() {
        requestingAccess = true
        Task {
            let status = await model.requestPhotoLibraryAuthorization()
            switch status {
            case .authorized:
                await model.scanPhotoLibrary(navigateToResults: true)
            case .limited:
                await model.scanPhotoLibrary(navigateToResults: false)
                model.go(.limited)
            case .denied, .restricted, .notDetermined:
                showAccessDenied = true
            @unknown default:
                showAccessDenied = true
            }
            requestingAccess = false
        }
    }
}

struct LimitedAccessScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.openURL) private var openURL
    private let columns = Array(repeating: GridItem(.fixed(58), spacing: 7), count: 3)

    var body: some View {
        ZStack {
            WarmBackground(variant: .access)

            VStack(spacing: 0) {
                Spacer(minLength: 70)

                VStack(spacing: 24) {
                    Text("Limited access")
                        .font(TR.ui(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.63))

                    Text("You'll only see the photos you picked")
                        .font(TR.display(36))
                        .tracking(-0.4)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: columns, spacing: 7) {
                        ForEach(0..<6, id: \.self) { index in
                            Group {
                                if model.libraryPreviewPhotos.indices.contains(index) {
                                    PhotoAssetView(source: model.libraryPreviewPhotos[index].source)
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(.white.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                }
                            }
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Text("Memories can only build stories from the photos you selected. You can expand access at any time.")
                        .font(TR.ui(15))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 300)
                }
                .trEntrance(0, distance: 12)

                Spacer(minLength: 48)

                VStack(spacing: 16) {
                    Button("Expand access") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                    .buttonStyle(CreamButtonStyle())

                    Button("Continue with \(model.selectedPhotoCount) photos") {
                        model.showTripResults()
                    }
                    .font(TR.ui(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.57))
                    .buttonStyle(.plain)
                }
                .trEntrance(1, distance: 9)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
            .safeAreaPadding(.vertical)
        }
        .accessibilityIdentifier("limited-access-screen")
    }
}
