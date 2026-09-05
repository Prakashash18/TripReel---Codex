import SwiftUI

struct FirstWatchScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            MontageView()
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.60), .clear, .clear, .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    MetadataText(text: "Da Nang, Vietnam", color: .white.opacity(0.82))
                    Text("Aug 2 – Aug 9, 2026 · the raw cut")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.top, 4)

                Spacer()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        PlaybackProgressBar()
                        HStack {
                            MetadataText(text: "84 photos", color: .white.opacity(0.65))
                            Spacer()
                            Text("1:52")
                                .font(TR.mono(12))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    Text("Here's the whole trip, uncut.")
                        .font(TR.display(29))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 11) {
                        Button("Refine it") {
                            model.go(.cut)
                        }
                        .buttonStyle(CreamButtonStyle())

                        Button("Looks good, export") {
                            model.go(.export)
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .accessibilityIdentifier("first-watch-screen")
    }
}

struct CutScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var dragOffset: CGSize = .zero
    @State private var locked = false

    private var dragStrength: Double {
        min(abs(dragOffset.width) / 105, 1)
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .cutting)

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("\(model.cutPhotoIDs.count) CUT")
                                .font(TR.mono(12))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.57))
                                .frame(width: 82, alignment: .leading)

                            Spacer()

                            Text("\(model.currentPhotoIndex + 1) of \(model.photos.count)")
                                .font(TR.ui(14, weight: .semibold))

                            Spacer()

                            Button("Done cutting") {
                                model.go(.pace)
                            }
                            .font(TR.ui(13, weight: .semibold))
                            .foregroundStyle(TR.accent)
                            .buttonStyle(.plain)
                            .frame(width: 96, alignment: .trailing)
                            .disabled(locked)
                        }

                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12))
                                Capsule()
                                    .fill(TR.accent)
                                    .frame(width: bar.size.width * CGFloat(model.currentPhotoIndex + 1) / CGFloat(model.photos.count))
                            }
                        }
                        .frame(height: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 0)

                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.white.opacity(0.045))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)

                        photoCard
                            .padding(.horizontal, 22)
                            .padding(.vertical, 20)
                    }
                    .frame(height: max(400, proxy.size.height - 230))

                    VStack(spacing: 16) {
                        HStack(spacing: 34) {
                            CircleIconButton(symbol: "xmark", tint: TR.cut, disabled: locked) {
                                sendCard(cut: true)
                            }

                            Button("Undo") {
                                model.undoLastDecision()
                            }
                            .font(TR.ui(12, weight: .semibold))
                            .foregroundStyle(model.history.isEmpty ? .white.opacity(0.28) : .white.opacity(0.72))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(.white.opacity(0.06))
                            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                            .disabled(model.history.isEmpty || locked)

                            CircleIconButton(symbol: "checkmark", tint: TR.keep, disabled: locked) {
                                sendCard(cut: false)
                            }
                        }

                        Text("Cutting only removes it from the film.")
                            .font(TR.ui(12))
                            .foregroundStyle(.white.opacity(0.43))
                    }
                    .padding(.bottom, 12)
                }
            }

            if model.showCutHint {
                CutHintOverlay {
                    withAnimation(.easeOut(duration: 0.25)) {
                        model.showCutHint = false
                    }
                }
                .transition(.opacity)
            }
        }
        .onDisappear {
            locked = false
            dragOffset = .zero
        }
        .accessibilityIdentifier("cut-screen")
    }

    private var photoCard: some View {
        ZStack {
            PhotoAssetView(imageName: model.currentPhoto.imageName)

            LinearGradient(colors: [.clear, .black.opacity(0.64)], startPoint: .center, endPoint: .bottom)

            HStack(alignment: .bottom) {
                Text(model.currentPhoto.label)
                Spacer()
                Text(model.currentPhoto.time)
            }
            .font(TR.mono(10))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(18)

            if model.currentPhoto.isSimilar {
                HStack(spacing: 7) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 10, weight: .medium))
                    Text("Similar to last shot")
                        .font(TR.ui(11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.black.opacity(0.57))
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            }

            Text("CUT")
                .font(TR.ui(20, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(TR.cut)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.black.opacity(0.36))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TR.cut, lineWidth: 2))
                .rotationEffect(.degrees(-11))
                .opacity(dragOffset.width < 0 ? dragStrength : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18)
                .padding(.top, 60)

            Text("KEEP")
                .font(TR.ui(20, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(TR.keep)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.black.opacity(0.36))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TR.keep, lineWidth: 2))
                .rotationEffect(.degrees(11))
                .opacity(dragOffset.width > 0 ? dragStrength : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 18)
                .padding(.top, 60)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.60), radius: 30, y: 24)
        .offset(x: dragOffset.width, y: dragOffset.height * 0.15)
        .rotationEffect(.degrees(dragOffset.width / 24))
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard !locked else { return }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    guard !locked else { return }
                    if abs(value.translation.width) > 92 {
                        sendCard(cut: value.translation.width < 0)
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .accessibilityLabel("Photo \(model.currentPhotoIndex + 1) of \(model.photos.count)")
        .accessibilityHint("Swipe left to cut or right to keep")
    }

    private func sendCard(cut: Bool) {
        guard !locked else { return }
        let photoID = model.currentPhoto.id
        locked = true
        withAnimation(.easeOut(duration: 0.24)) {
            dragOffset.width = cut ? -520 : 520
            dragOffset.height = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard locked else { return }
            model.decidePhoto(id: photoID, cut: cut)
            dragOffset = .zero
            locked = false
        }
    }
}

private struct CutHintOverlay: View {
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    Label("Cut", systemImage: "arrow.left")
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: 16)
                    Label("Keep", systemImage: "arrow.right")
                }
                .font(TR.ui(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.76))

                Text("Swipe left to cut it from the film. Right to keep.")
                    .font(TR.display(30))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Nothing is deleted from your phone.")
                    .font(TR.ui(14))
                    .foregroundStyle(.white.opacity(0.61))

                Text("Tap to start")
                    .font(TR.ui(13, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.84))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cutting instructions. Tap to start.")
    }
}

struct PaceScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .pace)

            VStack(spacing: 0) {
                ScreenHeading(
                    eyebrow: "\(model.keptCount) photos in the cut",
                    title: "Set the pace"
                )
                .padding(.horizontal, 26)
                .padding(.top, 4)

                VStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 12) {
                        MetadataText(text: "Live preview", color: .white.opacity(0.44))

                        GeometryReader { proxy in
                            HStack(spacing: 3) {
                                ForEach(Array(model.photos.prefix(8))) { photo in
                                    PhotoAssetView(imageName: photo.imageName)
                                        .frame(width: 22 + model.secondsPerPhoto * 21)
                                }
                            }
                            .frame(width: proxy.size.width, alignment: .leading)
                            .clipped()
                        }
                        .frame(height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HStack(alignment: .firstTextBaseline) {
                            Text(String(format: "%.1fs per photo", model.secondsPerPhoto))
                                .font(TR.ui(13))
                                .foregroundStyle(.white.opacity(0.57))
                            Spacer()
                            Text(model.durationText)
                                .font(TR.display(34))
                                .contentTransition(.numericText())
                        }
                    }

                    VStack(spacing: 14) {
                        Slider(value: $model.pace, in: 0...1)
                            .tint(TR.accent)
                            .accessibilityLabel("Film pace")

                        HStack {
                            Text("Slow and cinematic")
                            Spacer()
                            Text("Fast and punchy")
                        }
                        .font(TR.ui(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)

                Spacer()

                VStack(spacing: 14) {
                    Button("Watch it") {
                        model.go(.secondWatch)
                    }
                    .buttonStyle(CreamButtonStyle())

                    Button("Advanced · per-photo timing") {
                        showAdvanced = true
                    }
                    .font(TR.ui(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.47))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 7)
            }
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedTimingSheet()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .accessibilityIdentifier("pace-screen")
    }
}

private struct AdvancedTimingSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "Per-photo timing") { dismiss() }

                ForEach(Array(model.photos.prefix(4))) { photo in
                    HStack(spacing: 14) {
                        PhotoAssetView(imageName: photo.imageName)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(photo.label)
                            .font(TR.mono(13))
                            .foregroundStyle(.white.opacity(0.61))
                        Spacer()
                        Text(String(format: "%.1fs", model.secondsPerPhoto))
                            .font(TR.mono(13))
                    }
                }

                Text("Most people never need this. The pace slider sets everything at once.")
                    .font(TR.ui(12))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

struct SecondWatchScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var showTitles = false
    @State private var showMusic = false

    var body: some View {
        ZStack {
            MontageView()
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.56), .clear, .clear, .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    MetadataText(text: "Your cut · Da Nang", color: .white.opacity(0.82))
                    Text("\(model.keptCount) photos · \(model.durationText)\(trackSuffix)")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.53))
                }
                .padding(.top, 4)

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    PlaybackProgressBar()

                    Text(model.cutPhotoIDs.isEmpty ? "Nothing cut. This is the film." : "You cut \(model.cutPhotoIDs.count). This is the film.")
                        .font(TR.display(29))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        EditOptionButton(symbol: "textformat", label: "Titles", badge: titleBadge, badgeColor: model.titleCards.isEmpty ? .white.opacity(0.46) : TR.keep) {
                            showTitles = true
                        }
                        EditOptionButton(symbol: "music.note", label: "Music", badge: model.selectedTrack?.name.uppercased() ?? "NONE", badgeColor: model.selectedTrack == nil ? .white.opacity(0.46) : TR.keep) {
                            showMusic = true
                        }
                        EditOptionButton(symbol: "metronome", label: "Pace", badge: String(format: "%.1FS", model.secondsPerPhoto), badgeColor: .white.opacity(0.48)) {
                            model.go(.pace)
                        }
                    }

                    VStack(spacing: 11) {
                        Button("Export") {
                            model.go(.export)
                        }
                        .buttonStyle(CreamButtonStyle())

                        Button("Back to cutting") {
                            model.go(.cut)
                        }
                        .font(TR.ui(14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.53))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showTitles) {
            TitlesSheet()
                .environmentObject(model)
                .presentationDetents([.fraction(0.76)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .sheet(isPresented: $showMusic) {
            MusicSheet()
                .environmentObject(model)
                .presentationDetents([.fraction(0.76)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .accessibilityIdentifier("second-watch-screen")
    }

    private var trackSuffix: String {
        guard let track = model.selectedTrack else { return "" }
        return " · \(track.name)"
    }

    private var titleBadge: String {
        model.titleCards.isEmpty ? "NONE" : "\(model.titleCards.count) ON"
    }
}

private struct EditOptionButton: View {
    let symbol: String
    let label: String
    let badge: String
    let badgeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                Text(label)
                    .font(TR.ui(11, weight: .semibold))
                Text(badge)
                    .font(TR.mono(9))
                    .tracking(0.7)
                    .foregroundStyle(badgeColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(TR.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

private struct TitlesSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Titles") { dismiss() }

                Text("Three cards, filled in from your photos. Tap one to add or remove it.")
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineSpacing(4)

                VStack(spacing: 11) {
                    ForEach(Array(TitleCardKind.allCases.enumerated()), id: \.element.id) { index, card in
                        titleCardRow(card, index: index)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    MetadataText(text: "Opening title text", color: .white.opacity(0.42))

                    TextField("Da Nang", text: $model.titleText)
                        .font(TR.display(21))
                        .foregroundStyle(TR.cream)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    Text("Type is set by the film. No font or colour to pick.")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 38)
        }
    }

    private func titleCardRow(_ card: TitleCardKind, index: Int) -> some View {
        let active = model.titleCards.contains(card)
        let text: String = {
            switch card {
            case .opening: model.titleText
            case .place: "Hoi An"
            case .ending: "Aug 2026"
            }
        }()

        return Button {
            if active {
                model.titleCards.remove(card)
            } else {
                model.titleCards.insert(card)
            }
        } label: {
            HStack(spacing: 0) {
                ZStack {
                    PhotoAssetView(imageName: TripReelModel.assetNames[index])
                    Text(text)
                        .font(TR.display(card == .opening ? 17 : 14))
                        .foregroundStyle(TR.cream)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.65), radius: 4, y: 1)
                        .padding(8)
                }
                .frame(width: 96, height: 80)

                VStack(alignment: .leading, spacing: 5) {
                    Text(card.name)
                        .font(TR.ui(15, weight: .semibold))
                    Text(card.placement)
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.56))
                    Text(active ? "IN THE FILM" : "TAP TO ADD")
                        .font(TR.mono(10))
                        .tracking(1)
                        .foregroundStyle(active ? TR.keep : .white.opacity(0.42))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
            }
            .foregroundStyle(TR.cream)
            .background(active ? TR.keep.opacity(0.07) : .white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(active ? TR.keep.opacity(0.42) : .white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(active ? "Selected" : "Not selected")
    }
}

private struct MusicSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "Music") { dismiss() }

                Text("Matched to your \(String(format: "%.1fs", model.secondsPerPhoto)) pace. Picking a track re-cuts the film to its beats.")
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineSpacing(4)

                VStack(spacing: 8) {
                    ForEach(model.tracks) { track in
                        trackRow(track)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cut to the beat")
                            .font(TR.ui(14, weight: .semibold))
                        Text(beatNote)
                            .font(TR.ui(12))
                            .foregroundStyle(.white.opacity(0.51))
                    }
                    Spacer()
                    Toggle("Cut to the beat", isOn: $model.cutToBeat)
                        .labelsHidden()
                        .tint(TR.accent)
                        .disabled(model.selectedTrackID == nil)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 38)
        }
    }

    private var beatNote: String {
        guard model.selectedTrackID != nil else { return "Pick a track first" }
        return model.cutToBeat ? "Photos land on the downbeat" : "Photos keep your pace"
    }

    private func trackRow(_ track: MusicTrack) -> some View {
        let active = track.id == "none" ? model.selectedTrackID == nil : model.selectedTrackID == track.id

        return Button {
            model.selectTrack(track)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: track.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TR.ink)
                    .frame(width: 36, height: 36)
                    .background(track.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(TR.ui(15, weight: .semibold))
                    Text(track.mood)
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer()

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(track.bars.enumerated()), id: \.offset) { _, height in
                        Capsule()
                            .fill(active ? track.tint : .white.opacity(0.23))
                            .frame(width: 2, height: height)
                    }
                }
                .frame(height: 29)

                Text(track.bpm)
                    .font(TR.mono(10))
                    .foregroundStyle(.white.opacity(0.43))
                    .frame(width: 34, alignment: .trailing)
            }
            .foregroundStyle(TR.cream)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(active ? TR.accent.opacity(0.10) : .white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(active ? TR.accent.opacity(0.46) : .white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(active ? "Selected" : "Not selected")
    }
}
