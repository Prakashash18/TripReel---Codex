import SwiftUI

struct FirstWatchScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            MontageView(
                photos: model.photos,
                titleCards: model.montageTitleCards,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: 4.0 / 3.0
            )
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.60), .clear, .clear, .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    MetadataText(text: model.tripPlace, color: .white.opacity(0.82))
                    Text("\(model.tripDates) · \(model.excludedPhotos.isEmpty ? "the raw cut" : "smart first cut")")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.top, 4)
                .padding(.horizontal, 62)
                .trEntrance(0, distance: 7)

                Spacer()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        PlaybackProgressBar()
                        HStack {
                            MetadataText(text: "\(model.photos.count) photos", color: .white.opacity(0.65))
                            Spacer()
                            Text(model.rawDurationText)
                                .font(TR.mono(12))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    Text(model.excludedPhotos.isEmpty ? "Your film is ready to shape." : "Your smart first cut is ready.")
                        .font(TR.display(29))
                        .fixedSize(horizontal: false, vertical: true)

                    if let followUp = model.photoAnalysisFollowUp {
                        Button {
                            model.isSmartSelectionReviewPresented = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(TR.keep)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Preview ready")
                                        .font(TR.ui(12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.86))
                                    Text(followUp.previewMessage)
                                        .font(TR.ui(11))
                                        .foregroundStyle(.white.opacity(0.56))
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 8)

                                Text("View")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.30))
                            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityIdentifier("photo-analysis-follow-up-button")
                        .accessibilityLabel("Preview ready. \(followUp.previewMessage)")
                        .accessibilityHint("Shows optional ways to check more photos")
                    } else if let summary = model.smartSelectionSummary {
                        Button {
                            model.isSmartSelectionReviewPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text(summary)
                                Spacer()
                                Text("Review")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(TR.ui(12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.76))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(.black.opacity(0.30))
                            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityIdentifier("smart-selection-review-button")
                    }

                    VStack(spacing: 11) {
                        Button("Edit your film") {
                            model.go(.secondWatch)
                        }
                        .buttonStyle(CreamButtonStyle())
                        .accessibilityIdentifier("edit-film-button")

                        Button("Export this cut") {
                            model.openExport()
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .trEntrance(1, distance: 12)
            }
        }
        .accessibilityIdentifier("first-watch-screen")
    }
}

struct CutScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGSize = .zero
    @State private var locked = false
    @State private var decisionFeedback = 0

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

                            Button("Done") {
                                model.finishPhotoSelection()
                            }
                            .font(TR.ui(13, weight: .semibold))
                            .foregroundStyle(TR.accent)
                            .buttonStyle(.plain)
                            .frame(width: 96, alignment: .trailing)
                            .disabled(locked)
                            .accessibilityIdentifier("finish-photo-selection-button")
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
                                withAnimation(
                                    motionReduced
                                        ? .easeInOut(duration: 0.14)
                                        : TRMotion.cardArrival
                                ) {
                                    model.undoLastDecision()
                                }
                                decisionFeedback += 1
                            }
                            .font(TR.ui(12, weight: .semibold))
                            .foregroundStyle(model.history.isEmpty ? .white.opacity(0.28) : .white.opacity(0.72))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(.white.opacity(0.06))
                            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                            .clipShape(Capsule())
                            .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
                            .disabled(model.history.isEmpty || locked)

                            CircleIconButton(symbol: "checkmark", tint: TR.keep, disabled: locked) {
                                sendCard(cut: false)
                            }
                        }

                        Text("Choose what stays in this film. Nothing is deleted.")
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
        .sensoryFeedback(.selection, trigger: decisionFeedback)
        .accessibilityIdentifier("cut-screen")
    }

    private var motionReduced: Bool {
        reduceMotion
    }

    private var photoCard: some View {
        ZStack {
            PhotoAssetView(source: model.currentPhoto.source)

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
        .id(model.currentPhoto.id)
        .transition(
            motionReduced
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.985))
        )
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
                        withAnimation(motionReduced ? nil : TRMotion.gestureReturn) {
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

        if motionReduced {
            decisionFeedback += 1
            withAnimation(.easeInOut(duration: 0.14)) {
                model.decidePhoto(id: photoID, cut: cut)
                dragOffset = .zero
                locked = false
            }
            return
        }

        decisionFeedback += 1
        withAnimation(TRMotion.cardDismiss, completionCriteria: .logicallyComplete) {
            dragOffset.width = cut ? -520 : 520
            dragOffset.height = 0
        } completion: {
            guard locked else { return }
            withAnimation(TRMotion.cardArrival) {
                model.decidePhoto(id: photoID, cut: cut)
                dragOffset = .zero
                locked = false
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .padding(.leading, 48)
                .padding(.top, 4)
                .trEntrance(0, distance: 10)

                VStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 12) {
                        MetadataText(text: "Live preview", color: .white.opacity(0.44))

                        GeometryReader { proxy in
                            HStack(spacing: 3) {
                                ForEach(Array(model.keptPhotos.prefix(8))) { photo in
                                    PhotoAssetView(source: photo.source)
                                        .frame(width: 22 + model.secondsPerPhoto * 21)
                                }
                            }
                            .frame(width: proxy.size.width, alignment: .leading)
                            .clipped()
                        }
                        .frame(height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .animation(reduceMotion ? nil : TRMotion.scrub, value: model.pace)

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
                .trEntrance(1, distance: 10)

                Spacer()

                VStack(spacing: 14) {
                    Button("Apply pace") {
                        model.navigateBack()
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
                .trEntrance(2, distance: 8)
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

                ForEach(Array(model.keptPhotos.prefix(4))) { photo in
                    HStack(spacing: 14) {
                        PhotoAssetView(source: photo.source)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTitles = false
    @State private var showMusic = false
    @State private var showStyle = false
    @State private var showPhotoEditor = false
    @State private var showFullPreview = false
    @StateObject private var soundtrack = LocalSoundtrackPlayer()

    var body: some View {
        ZStack {
            WarmBackground(variant: .cutting)

            ViewThatFits(in: .vertical) {
                studioContent(previewHeight: 458, compact: false)
                studioContent(previewHeight: 294, compact: true)
            }
        }
        .fullScreenCover(isPresented: $showTitles) {
            TitlesSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $showMusic) {
            MusicSheet()
                .environmentObject(model)
                .presentationDetents([.fraction(0.76)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
            .presentationBackground(TR.sheet)
        }
        .sheet(isPresented: $showStyle) {
            FilmStyleSheet()
                .environmentObject(model)
                .presentationDetents([.fraction(0.78)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .sheet(isPresented: $showPhotoEditor) {
            PhotoEditorSheet()
                .environmentObject(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .fullScreenCover(isPresented: $showFullPreview) {
            FullFilmPreview()
                .environmentObject(model)
        }
        .task(id: model.selectedTrackID) {
            soundtrack.play(track: model.selectedTrack)
        }
        .onChange(of: showFullPreview) { _, isShowing in
            if isShowing {
                soundtrack.stop()
            } else {
                soundtrack.play(track: model.selectedTrack)
            }
        }
        .onDisappear {
            soundtrack.stop()
        }
        .accessibilityIdentifier("second-watch-screen")
    }

    private func studioContent(previewHeight: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                MetadataText(text: "FILM STUDIO · \(model.tripShortPlace)", color: .white.opacity(0.82))
                Text("\(model.keptCount) photos · \(model.filmDurationText)\(trackSuffix)")
                    .font(TR.ui(12))
                    .foregroundStyle(.white.opacity(0.53))
            }
            .padding(.horizontal, 62)
            .padding(.top, 4)
            .trEntrance(0, distance: 7)

            Spacer(minLength: compact ? 5 : 12)

            ZStack {
                MontageView(
                    photos: model.keptPhotos,
                    titleCards: model.montageTitleCards,
                    showLabels: false,
                    look: model.montageLook,
                    motionIntensity: model.montageMotionIntensity,
                    secondsPerSlide: model.secondsPerPhoto
                )
                .frame(width: previewHeight * 9 / 16, height: previewHeight)
            }
            .frame(width: previewHeight * 9 / 16, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                    .stroke(.white.opacity(0.17), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.56), radius: 28, y: 20)
            .trEntrance(1, distance: 12)

            HStack(spacing: 9) {
                Button {
                    soundtrack.stop()
                    showFullPreview = true
                } label: {
                    Label("Preview full film", systemImage: "play.fill")
                        .font(TR.ui(11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
                .foregroundStyle(TR.cream)
                .background(.white.opacity(0.07))
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                .clipShape(Capsule())
                .accessibilityIdentifier("full-preview-button")

                Button {
                    soundtrack.toggle(track: model.selectedTrack)
                } label: {
                    Image(systemName: soundtrack.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TR.cream)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.07))
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                        .clipShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
                .disabled(model.selectedTrack == nil)
                .opacity(model.selectedTrack == nil ? 0.42 : 1)
                .accessibilityLabel(soundtrack.isPlaying ? "Pause soundtrack" : "Play soundtrack")
            }
            .frame(width: max(previewHeight * 9 / 16, 214))
            .padding(.top, compact ? 7 : 9)

            if let errorMessage = soundtrack.errorMessage {
                Text(errorMessage)
                    .font(TR.ui(10, weight: .medium))
                    .foregroundStyle(TR.accent)
                    .lineLimit(1)
                    .padding(.top, 6)
            }

            Spacer(minLength: compact ? 7 : 14)

            VStack(spacing: 10) {
                Menu {
                    Button {
                        model.editPhotoSelection()
                    } label: {
                        Label("Photos · \(model.keptCount) in", systemImage: "photo.stack")
                    }
                    .accessibilityIdentifier("studio-tool-photos")

                    Button {
                        showPhotoEditor = true
                    } label: {
                        Label("Framing · \(framingBadge)", systemImage: "crop.rotate")
                    }
                    .accessibilityIdentifier("studio-tool-framing")

                    Button {
                        showStyle = true
                    } label: {
                        Label("Style · \(model.montageLook.name)", systemImage: "wand.and.stars")
                    }
                    .accessibilityIdentifier("studio-tool-style")

                    Button {
                        showTitles = true
                    } label: {
                        Label("Titles · \(titleBadge.lowercased())", systemImage: "textformat")
                    }
                    .accessibilityIdentifier("studio-tool-titles")

                    Button {
                        showMusic = true
                    } label: {
                        Label("Music · \(model.selectedTrack?.name ?? "None")", systemImage: "music.note")
                    }
                    .accessibilityIdentifier("studio-tool-music")

                    Button {
                        model.go(.pace)
                    } label: {
                        Label("Pace · \(String(format: "%.1fs", model.secondsPerPhoto))", systemImage: "metronome")
                    }
                    .accessibilityIdentifier("studio-tool-pace")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TR.accent)
                            .frame(width: 34, height: 34)
                            .background(TR.accent.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit film")
                                .font(TR.ui(14, weight: .semibold))
                            Text("Photos, framing, look, titles, music and pace")
                                .font(TR.ui(10))
                                .foregroundStyle(.white.opacity(0.50))
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .foregroundStyle(TR.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCard(cornerRadius: 16)
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Edit film")
                .accessibilityHint("Choose photos, framing, style, titles, music or pace")
                .accessibilityIdentifier("studio-edit-menu")

                Button("Export film") {
                    model.openExport()
                }
                .buttonStyle(CreamButtonStyle())
                .accessibilityIdentifier("studio-export-button")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, compact ? 2 : 8)
            .trEntrance(2, distance: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackSuffix: String {
        guard let track = model.selectedTrack else { return "" }
        return " · \(track.name)"
    }

    private var titleBadge: String {
        model.titleCards.isEmpty ? "NONE" : "\(model.titleCards.count) ON"
    }

    private var framingBadge: String {
        model.customizedPhotoCount == 0 ? "Auto" : "\(model.customizedPhotoCount) edited"
    }
}

private struct FullFilmPreview: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var soundtrack = LocalSoundtrackPlayer()
    @State private var controlsVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MontageView(
                photos: model.keptPhotos,
                titleCards: model.montageTitleCards,
                showLabels: false,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.secondsPerPhoto
            )
            .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: motionReduced ? 0.14 : 0.22)) {
                        controlsVisible.toggle()
                    }
                }

            if controlsVisible {
                LinearGradient(
                    colors: [.black.opacity(0.66), .clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        previewControl(symbol: "xmark", label: "Close preview") {
                            dismiss()
                        }

                        Spacer()

                        previewControl(
                            symbol: soundtrack.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            label: soundtrack.isPlaying ? "Pause soundtrack" : "Play soundtrack"
                        ) {
                            soundtrack.toggle(track: model.selectedTrack)
                        }
                        .disabled(model.selectedTrack == nil)
                        .opacity(model.selectedTrack == nil ? 0.46 : 1)
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        MetadataText(text: "FULL FILM PREVIEW", color: .white.opacity(0.66))
                        Text("\(model.keptCount) photos · \(model.filmDurationText)\(trackSuffix)")
                            .font(TR.ui(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                        Text("Tap anywhere to hide controls")
                            .font(TR.ui(10))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .transition(.opacity)
            }
        }
        .task(id: model.selectedTrackID) {
            soundtrack.play(track: model.selectedTrack)
        }
        .task(id: controlsVisible) {
            guard controlsVisible, !voiceOverEnabled else { return }
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: motionReduced ? 0.14 : 0.3)) {
                controlsVisible = false
            }
        }
        .onDisappear { soundtrack.stop() }
        .statusBarHidden(true)
        .accessibilityIdentifier("full-film-preview")
    }

    private var trackSuffix: String {
        guard let track = model.selectedTrack else { return "" }
        return " · \(track.name)"
    }

    private var motionReduced: Bool {
        reduceMotion
    }

    private func previewControl(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TR.cream)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.46))
                .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
        .accessibilityLabel(label)
    }
}

private struct PhotoEditorSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var pinchStartScale: Double?
    @State private var dragStartX: Double?
    @State private var dragStartY: Double?
    @State private var editFeedback = 0

    private var selectedPhoto: ReelPhoto? {
        let photos = model.keptPhotos
        return photos.first(where: { $0.id == selectedID }) ?? photos.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                SheetHeader(title: "Framing & motion") { dismiss() }

                Text("TripReel starts with an on-device face and subject-aware crop. Pinch to zoom, drag to reframe, then fine-tune only the shots that need it.")
                    .font(TR.ui(12))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineSpacing(4)

                if let photo = selectedPhoto {
                    editorPreview(photo)
                    photoStrip
                    frameControls(photo)
                    motionControls(photo)
                    timingControls(photo)

                    Button("Reset this photo to Auto") {
                        withAnimation(reduceMotion ? nil : TRMotion.selection) {
                            model.resetPhotoEdit(id: photo.id)
                        }
                        editFeedback += 1
                    }
                    .font(TR.ui(13, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ContentUnavailableView(
                        "No photos in this cut",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Keep a photo to edit its framing and motion.")
                    )
                    .foregroundStyle(TR.cream)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 42)
        }
        .onAppear {
            if selectedID == nil { selectedID = model.keptPhotos.first?.id }
        }
        .sensoryFeedback(.selection, trigger: editFeedback)
        .accessibilityIdentifier("photo-editor-sheet")
    }

    private func editorPreview(_ photo: ReelPhoto) -> some View {
        GeometryReader { proxy in
            MontageView(
                photos: [photo],
                showLabels: false,
                look: .story,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.duration(for: photo)
            )
            .overlay(alignment: .topLeading) {
                if photo.usesAutomaticPeopleFraming {
                    Label("People-safe Auto", systemImage: "person.2.fill")
                        .font(TR.ui(10, weight: .semibold))
                        .foregroundStyle(TR.cream)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.62))
                        .overlay(Capsule().stroke(TR.keep.opacity(0.55), lineWidth: 1))
                        .clipShape(Capsule())
                        .padding(12)
                        .accessibilityLabel("Automatic framing keeps detected people visible")
                }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 7) {
                    Image(systemName: "hand.draw")
                    Text("Pinch to zoom · drag to move")
                }
                .font(TR.ui(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.black.opacity(0.54))
                .clipShape(Capsule())
                .padding(.bottom, 12)
            }
            .contentShape(Rectangle())
            .gesture(pinchGesture(for: photo))
            .simultaneousGesture(dragGesture(for: photo, size: proxy.size))
        }
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var photoStrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.keptPhotos) { photo in
                        Button {
                            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                                selectedID = photo.id
                                reader.scrollTo(photo.id, anchor: .center)
                            }
                            editFeedback += 1
                        } label: {
                            PhotoAssetView(source: photo.source)
                                .frame(width: 54, height: 54)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            selectedPhoto?.id == photo.id ? TR.accent : .white.opacity(0.12),
                                            lineWidth: selectedPhoto?.id == photo.id ? 2 : 1
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
                        .id(photo.id)
                        .accessibilityLabel("Edit \(photo.label)")
                    }
                }
            }
        }
    }

    private func frameControls(_ photo: ReelPhoto) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            MetadataText(text: "FRAME", color: .white.opacity(0.43))
            HStack(spacing: 7) {
                ForEach(MontageFrameStyle.allCases) { style in
                    editorChip(
                        title: style.name,
                        symbol: style.symbol,
                        selected: photo.frameStyle == style
                    ) {
                        withAnimation(reduceMotion ? nil : TRMotion.selection) {
                            model.setFrameStyle(style, forPhotoID: photo.id)
                        }
                        editFeedback += 1
                    }
                }
            }
        }
    }

    private func motionControls(_ photo: ReelPhoto) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            MetadataText(text: "MOTION", color: .white.opacity(0.43))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(MontageMotionStyle.allCases) { motion in
                        Button {
                            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                                model.setMotionStyle(motion, forPhotoID: photo.id)
                            }
                            editFeedback += 1
                        } label: {
                            Text(motion.name)
                                .font(TR.ui(11, weight: .semibold))
                                .foregroundStyle(photo.motionStyle == motion ? TR.ink : .white.opacity(0.65))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(photo.motionStyle == motion ? TR.cream : .white.opacity(0.055))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
                    }
                }
            }
        }
    }

    private func timingControls(_ photo: ReelPhoto) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MetadataText(text: "TIME ON SCREEN", color: .white.opacity(0.43))
                Spacer()
                Text(String(format: "%.1fs", model.duration(for: photo)))
                    .font(TR.mono(12))
                    .foregroundStyle(TR.accent)
            }
            Slider(
                value: Binding(
                    get: { model.duration(for: selectedPhoto ?? photo) },
                    set: { model.setPhotoDuration($0, forPhotoID: photo.id) }
                ),
                in: 0.6...4,
                step: 0.1
            )
            .tint(TR.accent)
        }
    }

    private func editorChip(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(TR.ui(10, weight: .semibold))
            }
            .foregroundStyle(selected ? TR.ink : .white.opacity(0.64))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? TR.cream : .white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
    }

    private func pinchGesture(for photo: ReelPhoto) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartScale ?? photo.cropScale
                if pinchStartScale == nil { pinchStartScale = start }
                model.setPhotoCrop(
                    scale: start * value.magnification,
                    offsetX: selectedPhoto?.cropOffsetX ?? photo.cropOffsetX,
                    offsetY: selectedPhoto?.cropOffsetY ?? photo.cropOffsetY,
                    forPhotoID: photo.id
                )
            }
            .onEnded { _ in pinchStartScale = nil }
    }

    private func dragGesture(for photo: ReelPhoto, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let startX = dragStartX ?? photo.cropOffsetX
                let startY = dragStartY ?? photo.cropOffsetY
                if dragStartX == nil {
                    dragStartX = startX
                    dragStartY = startY
                }
                model.setPhotoCrop(
                    scale: selectedPhoto?.cropScale ?? photo.cropScale,
                    offsetX: startX + Double(value.translation.width / max(1, size.width * 0.24)),
                    offsetY: startY + Double(value.translation.height / max(1, size.height * 0.24)),
                    forPhotoID: photo.id
                )
            }
            .onEnded { _ in
                dragStartX = nil
                dragStartY = nil
            }
    }
}

private struct FilmStyleSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionFeedback = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Film style") { dismiss() }

                Text("Choose the mood, not every tiny transition. TripReel still adapts portrait and landscape photos automatically.")
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineSpacing(4)

                stylePreview

                VStack(spacing: 9) {
                    ForEach(MontageLook.allCases) { look in
                        lookRow(look)
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    MetadataText(text: "MOTION", color: .white.opacity(0.43))

                    HStack(spacing: 7) {
                        ForEach(MontageMotionIntensity.allCases) { intensity in
                            Button {
                                withAnimation(reduceMotion ? nil : TRMotion.selection) {
                                    model.montageMotionIntensity = intensity
                                }
                                selectionFeedback += 1
                            } label: {
                                Text(intensity.name)
                                    .font(TR.ui(12, weight: .semibold))
                                    .foregroundStyle(
                                        model.montageMotionIntensity == intensity
                                            ? TR.ink
                                            : .white.opacity(0.64)
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(
                                        model.montageMotionIntensity == intensity
                                            ? TR.cream
                                            : .white.opacity(0.055)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
                            .accessibilityValue(
                                model.montageMotionIntensity == intensity ? "Selected" : "Not selected"
                            )
                        }
                    }

                    Text("Reduce Motion in iOS Settings always overrides this choice.")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.40))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 34)
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .accessibilityIdentifier("film-style-sheet")
    }

    private var stylePreview: some View {
        HStack(spacing: 17) {
            MontageView(
                photos: previewPhotos,
                showLabels: false,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: max(1.15, model.secondsPerPhoto)
            )
            .frame(width: 126, height: 224)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.46), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 9) {
                MetadataText(text: "LIVE PREVIEW", color: TR.accent)
                Text(model.montageLook.name)
                    .font(TR.display(28))
                    .foregroundStyle(TR.cream)
                Text(model.montageLook.detail)
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineSpacing(3)
                Spacer(minLength: 4)
                Label("Updates with every tap", systemImage: "play.circle.fill")
                    .font(TR.ui(10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .glassCard(cornerRadius: 20)
        .animation(reduceMotion ? nil : TRMotion.selection, value: model.montageLook)
        .animation(reduceMotion ? nil : TRMotion.selection, value: model.montageMotionIntensity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live \(model.montageLook.name) film preview")
        .accessibilityIdentifier("film-style-live-preview")
    }

    private var previewPhotos: [ReelPhoto] {
        let photos = model.keptPhotos
        guard !photos.isEmpty else { return [] }
        let unprotected = photos.filter { !$0.protectsPeople }
        let candidates = unprotected.isEmpty ? photos : unprotected
        var selected: [ReelPhoto] = []
        let landscape = candidates.first(where: { $0.aspectRatio >= 0.88 })
        let portrait = candidates.first(where: { $0.aspectRatio < 0.88 })
        if model.montageLook == .story {
            // Story is the mixed editorial treatment; lead with its portrait
            // matte when available so it cannot look identical to Clean.
            selected.append(portrait ?? candidates[0])
            if let landscape { selected.append(landscape) }
        } else {
            // Cinema, Journal, and Clean resolve the same landscape into three
            // deliberately different frames on the first preview beat.
            selected.append(landscape ?? candidates[0])
            if let portrait { selected.append(portrait) }
        }
        selected.append(contentsOf: photos.filter { candidate in
            !selected.contains(where: { $0.id == candidate.id })
        })
        return Array(selected.prefix(4))
    }

    private func lookRow(_ look: MontageLook) -> some View {
        let selected = model.montageLook == look
        return Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                model.montageLook = look
            }
            selectionFeedback += 1
        } label: {
            HStack(spacing: 13) {
                Image(systemName: look.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? TR.accent : .white.opacity(0.58))
                    .frame(width: 34, height: 34)
                    .background(selected ? TR.accent.opacity(0.12) : .white.opacity(0.045))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(look.name)
                        .font(TR.ui(14, weight: .semibold))
                    Text(look.detail)
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.50))
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? TR.keep : .white.opacity(0.24))
            }
            .foregroundStyle(TR.cream)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? TR.accent.opacity(0.07) : .white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? TR.accent.opacity(0.40) : .white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("film-look-\(look.rawValue)")
    }
}

private struct TitlesSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: TitleField?
    @State private var selectedKind: TitleCardKind = .opening
    @State private var selectionFeedback = 0

    var body: some View {
        ZStack {
            WarmBackground(variant: .cutting)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    SheetHeader(title: "Titles & text") { dismiss() }

                    Text("Edit every title on one timeline. Tap a clip, change its text below, and watch the live canvas update without closing the editor.")
                        .font(TR.ui(13))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineSpacing(4)

                    titlePreview

                    VStack(alignment: .leading, spacing: 9) {
                        MetadataText(text: "TITLE TIMELINE", color: .white.opacity(0.43))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 9) {
                                ForEach(Array(TitleCardKind.allCases.enumerated()), id: \.element.id) { index, kind in
                                    timelineClip(kind, index: index)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    titleControls
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 38)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Previous") { moveSelection(by: -1) }
                Button("Next") { moveSelection(by: 1) }
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .accessibilityIdentifier("title-editor-screen")
    }

    private var titlePreview: some View {
        let active = model.titleCards.contains(selectedKind)
        let previewHeight: CGFloat = UIScreen.main.bounds.height < 760 ? 230 : 300
        return HStack {
            Spacer(minLength: 0)
            MontageTitleArtwork(
                card: selectedCard,
                backgroundSource: model.previewSource(at: selectedIndex),
                motionPhase: false,
                reduceMotion: true
            )
            .frame(width: previewHeight * 9 / 16, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(active ? TR.accent.opacity(0.62) : .white.opacity(0.15), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Text(active ? "IN FILM" : "NOT IN FILM")
                    .font(TR.mono(8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(active ? TR.keep : .white.opacity(0.58))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.70))
                    .clipShape(Capsule())
                    .padding(9)
            }
            .shadow(color: .black.opacity(0.50), radius: 22, y: 14)
            .animation(reduceMotion ? nil : TRMotion.selection, value: selectedCard)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Live preview for \(selectedKind.name)")
            .accessibilityValue(active ? "Included in film" : "Not included in film")
            .accessibilityIdentifier("title-live-preview")
            Spacer(minLength: 0)
        }
    }

    private var titleControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedKind.name)
                        .font(TR.ui(16, weight: .semibold))
                    Text(selectedKind.placement)
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.49))
                }
                Spacer()
                Toggle(
                    "Show in film",
                    isOn: Binding(
                        get: { model.titleCards.contains(selectedKind) },
                        set: { model.setTitleCardEnabled($0, for: selectedKind) }
                    )
                )
                .labelsHidden()
                .tint(TR.keep)
                .accessibilityLabel("Show \(selectedKind.name) in film")
                .accessibilityIdentifier("title-enabled-toggle")
            }

            VStack(spacing: 9) {
                TextField("Title", text: titleBinding, axis: .vertical)
                    .font(TR.ui(17, weight: .semibold))
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .subtitle }
                    .accessibilityIdentifier("title-main-text")

                Divider().overlay(.white.opacity(0.10))

                TextField("Supporting text", text: subtitleBinding, axis: .vertical)
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1...2)
                    .focused($focusedField, equals: .subtitle)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("title-subtitle-text")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(.white.opacity(0.055))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.14), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                MetadataText(text: "TEXT STYLE", color: .white.opacity(0.43))
                HStack(spacing: 8) {
                    ForEach(MontageTitleStyle.allCases) { style in
                        styleButton(style)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MetadataText(text: "ON SCREEN", color: .white.opacity(0.43))
                    Spacer()
                    Text(String(format: "%.1fs", selectedCard.duration))
                        .font(TR.mono(11, weight: .semibold))
                        .foregroundStyle(TR.accent)
                }
                Slider(value: durationBinding, in: 1...4, step: 0.1)
                    .tint(TR.accent)
                    .accessibilityIdentifier("title-duration-slider")
            }
        }
        .padding(15)
        .glassCard(cornerRadius: 20)
    }

    private func timelineClip(_ kind: TitleCardKind, index: Int) -> some View {
        let active = model.titleCards.contains(kind)
        let selected = selectedKind == kind
        let card = model.montageTitleCard(for: kind)

        return Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                selectedKind = kind
                if !active { model.setTitleCardEnabled(true, for: kind) }
            }
            selectionFeedback += 1
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    PhotoAssetView(source: model.previewSource(at: index))
                    Color.black.opacity(0.46)
                    Text(card.title)
                        .font(TR.display(13))
                        .foregroundStyle(TR.cream)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.65), radius: 4, y: 1)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .padding(7)
                }
                .frame(width: 108, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                HStack(spacing: 5) {
                    Text(kind.name.replacingOccurrences(of: " title", with: ""))
                        .font(TR.ui(11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(active ? String(format: "%.1fs", card.duration) : "ADD")
                        .font(TR.mono(8, weight: .semibold))
                        .foregroundStyle(active ? TR.keep : TR.accent)
                }
            }
            .frame(width: 108)
            .foregroundStyle(TR.cream)
            .padding(7)
            .background(selected ? TR.accent.opacity(0.13) : .white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? TR.accent.opacity(0.72) : .white.opacity(0.11), lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel(kind.name)
        .accessibilityValue(active ? "In film, \(String(format: "%.1f seconds", card.duration))" : "Not in film")
        .accessibilityIdentifier("title-timeline-\(kind.rawValue)")
    }

    private func styleButton(_ style: MontageTitleStyle) -> some View {
        let selected = selectedCard.style == style
        return Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                model.setTitleStyle(style, for: selectedKind)
            }
            selectionFeedback += 1
        } label: {
            Text(style.name)
                .font(style == .editorial ? TR.display(16) : TR.ui(12, weight: style == .bold ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? TR.ink : TR.cream)
                .background(selected ? TR.cream : .white.opacity(0.055))
                .clipShape(Capsule())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("title-style-\(style.rawValue)")
    }

    private var selectedCard: MontageTitleCard {
        model.montageTitleCard(for: selectedKind)
    }

    private var selectedIndex: Int {
        TitleCardKind.allCases.firstIndex(of: selectedKind) ?? 0
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { model.titleDraft(for: selectedKind).title },
            set: { model.setTitleText($0, for: selectedKind) }
        )
    }

    private var subtitleBinding: Binding<String> {
        Binding(
            get: { model.titleDraft(for: selectedKind).subtitle },
            set: { model.setTitleSubtitle($0, for: selectedKind) }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { model.titleDraft(for: selectedKind).duration },
            set: { model.setTitleDuration($0, for: selectedKind) }
        )
    }

    private func moveSelection(by offset: Int) {
        let all = TitleCardKind.allCases
        guard let current = all.firstIndex(of: selectedKind) else { return }
        let destination = min(max(current + offset, 0), all.count - 1)
        withAnimation(reduceMotion ? nil : TRMotion.selection) {
            selectedKind = all[destination]
            model.setTitleCardEnabled(true, for: selectedKind)
        }
        selectionFeedback += 1
    }

    private enum TitleField: Hashable {
        case title
        case subtitle
    }
}

private struct MusicSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionFeedback = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "Music") { dismiss() }

                Text("Matched to your \(String(format: "%.1fs", model.secondsPerPhoto)) pace. Picking a track re-cuts the film to its beats.")
                    .font(TR.ui(13))
                    .foregroundStyle(.white.opacity(0.57))
                    .lineSpacing(4)

                Link(destination: URL(string: "https://www.scottbuckley.com.au/library/using-this-music/")!) {
                    Label("Music by Scott Buckley · CC BY 4.0", systemImage: "checkmark.seal")
                        .font(TR.ui(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }

                VStack(spacing: 8) {
                    ForEach(model.tracks) { track in
                        trackRow(track)
                    }
                }

                Text("Music previews are 90-second excerpts, trimmed, loudness-normalized, faded, and transcoded to AAC for TripReel.")
                    .font(TR.ui(10))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineSpacing(3)

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
        .sensoryFeedback(.selection, trigger: selectionFeedback)
    }

    private var beatNote: String {
        guard model.selectedTrackID != nil else { return "Pick a track first" }
        return model.cutToBeat ? "Photos land on the downbeat" : "Photos keep your pace"
    }

    private func trackRow(_ track: MusicTrack) -> some View {
        let active = track.id == "none" ? model.selectedTrackID == nil : model.selectedTrackID == track.id

        return Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                model.selectTrack(track)
            }
            selectionFeedback += 1
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

                MusicLevelBars(
                    heights: track.bars,
                    tint: active ? track.tint : .white.opacity(0.23),
                    animated: active && track.resourceName != nil
                )

                Text(track.tag)
                    .font(TR.mono(10))
                    .foregroundStyle(.white.opacity(0.43))
                    .frame(width: 48, alignment: .trailing)
            }
            .foregroundStyle(TR.cream)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(active ? TR.accent.opacity(0.10) : .white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(active ? TR.accent.opacity(0.46) : .white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityValue(active ? "Selected" : "Not selected")
    }
}

private struct MusicLevelBars: View {
    let heights: [CGFloat]
    let tint: Color
    let animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(tint)
                    .frame(
                        width: 2,
                        height: animated && !reduceMotion
                            ? height * (lifted ? highScale(for: index) : lowScale(for: index))
                            : height
                    )
                    .animation(
                        animated && !reduceMotion
                            ? .easeInOut(duration: 0.46 + Double(index) * 0.06)
                                .repeatForever(autoreverses: true)
                            : nil,
                        value: lifted
                    )
            }
        }
        .frame(height: 29)
        .task(id: MusicBarsMotionKey(animated: animated, reduceMotion: reduceMotion)) {
            lifted = false
            guard animated, !reduceMotion else { return }
            await Task.yield()
            lifted = true
        }
    }

    private func lowScale(for index: Int) -> CGFloat {
        index.isMultiple(of: 2) ? 0.42 : 0.76
    }

    private func highScale(for index: Int) -> CGFloat {
        index.isMultiple(of: 2) ? 1 : 0.55
    }
}

private struct MusicBarsMotionKey: Hashable {
    let animated: Bool
    let reduceMotion: Bool
}
