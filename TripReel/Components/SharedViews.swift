import SwiftUI

struct PhotoAssetView: View {
    let imageName: String
    var label: String? = nil
    var dim = false

    var body: some View {
        GeometryReader { proxy in
            Image(imageName)
                .resizable()
                .scaledToFill()
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
    var dim = false
    var watermark = false
    var showLabels = true
    @State private var currentIndex = 0

    var body: some View {
        ZStack {
            ForEach(Array(TripReelModel.assetNames.enumerated()), id: \.offset) { index, imageName in
                PhotoAssetView(
                    imageName: imageName,
                    label: showLabels ? TripReelModel.photoLabels[index] : nil,
                    dim: false
                )
                .opacity(currentIndex == index ? 1 : 0)
                .scaleEffect(reduceMotion ? 1 : (currentIndex == index ? 1.08 : 1.015))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.72), value: currentIndex)
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
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled else { return }
                currentIndex = (currentIndex + 1) % TripReelModel.assetNames.count
            }
        }
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
