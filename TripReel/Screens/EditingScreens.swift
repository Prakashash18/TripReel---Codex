import AVKit
import SwiftUI

struct FirstWatchScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @StateObject private var soundtrack = LocalSoundtrackPlayer()
    @State private var playbackRun = 0
    @State private var playbackComplete = false

    private var firstCut: TripEditSnapshot? {
        model.firstCutSnapshot
    }

    private var firstCutTrack: MusicTrack? {
        model.musicTrack(withID: firstCut?.selectedTrackID)
    }

    private var firstCutMediaSummary: String {
        let moments = firstCut?.keptPhotos ?? model.keptPhotos
        let videoCount = moments.filter(\.isVideo).count
        return Trip.mediaCountText(
            photoCount: moments.count - videoCount,
            videoCount: videoCount
        )
    }

    private var soundtrackVolume: Float {
        (firstCut?.keptPhotos ?? model.keptPhotos).contains(where: \.isVideo) ? 0.42 : 0.82
    }

    private var firstCutDurationSeconds: Double {
        firstCut?.durationSeconds ?? model.filmDurationSeconds
    }

    var body: some View {
        ZStack {
            MontageView(
                photos: firstCut?.keptPhotos ?? model.keptPhotos,
                titleCards: firstCut?.montageTitleCards ?? model.montageTitleCards,
                textOverlays: firstCut?.textOverlays ?? model.textOverlays,
                look: firstCut?.montageLook ?? model.montageLook,
                motionIntensity: firstCut?.motionIntensity ?? model.montageMotionIntensity,
                secondsPerSlide: firstCut.map { 1.85 - ($0.pace * 1.25) } ?? model.secondsPerPhoto,
                playbackBehavior: .playOnce,
                showsReplayControl: true,
                onPlaybackStarted: {
                    playbackComplete = false
                    playbackRun &+= 1
                    soundtrack.play(
                        track: firstCutTrack,
                        volume: soundtrackVolume,
                        restart: true
                    )
                },
                onPlaybackEnded: {
                    playbackComplete = true
                    soundtrack.finishNaturally()
                }
            )
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.54), .clear, .clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    MetadataText(text: "First Cut · On-device", color: .white.opacity(0.82))
                    Text("\(model.tripPlace) · \(model.tripDates)")
                        .font(TR.ui(12))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.top, 4)
                .padding(.horizontal, 62)
                .trEntrance(0, distance: 7)
                .accessibilityIdentifier("first-watch-screen")

                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    VStack(spacing: 12) {
                        PlaybackProgressBar(
                            duration: firstCutDurationSeconds,
                            playbackRun: playbackRun,
                            isComplete: playbackComplete
                        )
                        HStack {
                            MetadataText(
                                text: firstCutMediaSummary,
                                color: .white.opacity(0.65)
                            )
                            Spacer()
                            Text(model.firstCutDurationText)
                                .font(TR.mono(12))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    Button("Continue") {
                        model.continueFromFirstWatch()
                    }
                    .buttonStyle(CreamButtonStyle())
                    .accessibilityHint("Choose whether to improve this cut with AI or edit it yourself")
                    .accessibilityIdentifier("first-cut-continue-button")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .trEntrance(1, distance: 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                soundtrack.toggle(track: firstCutTrack, volume: soundtrackVolume)
            } label: {
                Image(systemName: soundtrack.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TR.cream)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.58))
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
            .padding(.trailing, 16)
            .safeAreaPadding(.top, 7)
            .disabled(firstCutTrack == nil)
            .opacity(firstCutTrack == nil ? 0.42 : 1)
            .accessibilityLabel(soundtrack.isPlaying ? "Pause soundtrack" : "Play soundtrack")
            .accessibilityHint(firstCutTrack.map { "Soundtrack: \($0.name)" } ?? "No soundtrack selected")
            .accessibilityIdentifier("first-watch-audio")
        }
        .onDisappear {
            soundtrack.stop()
        }
    }
}

struct FirstCutOptionsScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            VStack(alignment: .leading, spacing: 0) {
                ScreenHeading(
                    eyebrow: "First Cut · created on-device",
                    title: "Where to next?"
                )
                .padding(.leading, 48)
                .trEntrance(0, distance: 8)
                .accessibilityIdentifier("first-cut-options-screen")

                Text("Your original First Cut stays safe whichever route you choose.")
                    .font(TR.ui(14))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(4)
                    .padding(.top, 14)
                    .trEntrance(1, distance: 8)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        model.openAICutDirections()
                    } label: {
                        VStack(spacing: 3) {
                            Label("Improve with AI", systemImage: "sparkles")
                            Text("Let AI reconsider safe moments and direct another cut")
                                .font(TR.ui(10))
                                .foregroundStyle(TR.ink.opacity(0.58))
                        }
                    }
                    .buttonStyle(CreamButtonStyle())
                    .accessibilityHint("Choose a direction for an optional alternative cut")
                    .accessibilityIdentifier("improve-with-ai-button")

                    Button {
                        model.editCut(
                            model.selectedCutSource == .working ? .working : .firstCut
                        )
                    } label: {
                        VStack(spacing: 3) {
                            Text("Edit Myself")
                            Text("Change moments, framing, titles, music and pace")
                                .font(TR.ui(10))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .accessibilityIdentifier("edit-film-button")

                    Button {
                        model.keepFirstCutForExport()
                    } label: {
                        Label("Export This", systemImage: "checkmark.circle.fill")
                            .font(TR.ui(14, weight: .semibold))
                            .foregroundStyle(TR.cream.opacity(0.84))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                            .background(.white.opacity(0.055))
                            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(TactileButtonStyle(pressedScale: 0.97))
                    .accessibilityHint("Skips editing and opens export with the First Cut")
                    .accessibilityIdentifier("export-first-cut-button")
                }
                .trEntrance(2, distance: 12)

                Label("Created privately on your iPhone", systemImage: "checkmark.shield")
                    .font(TR.ui(11, weight: .medium))
                    .foregroundStyle(TR.keep.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }
}

struct AICutDirectionScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPhotoSelection = false
    @State private var recipesExpanded = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeading(
                        eyebrow: "AI Director · permission granted",
                        title: "Edit moments & direction"
                    )
                    .padding(.leading, 48)
                    .trEntrance(0, distance: 8)

                    AICutPhotoSelectionCard {
                        showsPhotoSelection = true
                    }
                        .trEntrance(1, distance: 8)

                    storyContextEditor
                        .trEntrance(2, distance: 8)

                    recipePicker

                    Button("Create AI cut") {
                        model.continueWithAICutDirection()
                    }
                    .buttonStyle(CreamButtonStyle())
                    .disabled(!model.aiCutCanCreate)
                    .opacity(model.aiCutCanCreate ? 1 : 0.48)
                    .accessibilityHint("Sends the selected reduced previews and current edit recipe to OpenAI, then creates a comparison cut")
                    .accessibilityIdentifier("ai-direction-continue")

                    Text(sharingSummary)
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
        }
        .sheet(isPresented: $showsPhotoSelection) {
            AICutPhotoSelectionSheet()
                .environmentObject(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(26)
                .presentationBackground(TR.sheet)
        }
        .accessibilityIdentifier("ai-direction-screen")
    }

    private var activeDirection: AICutDirection {
        model.selectedAICutDirection ?? model.recommendedAICutDirection
    }

    @ViewBuilder
    private var recipePicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                MetadataText(text: "Reel recipe", color: .white.opacity(0.52))
                Spacer()
                if recipesExpanded {
                    Button("Collapse") {
                        withAnimation(reduceMotion ? nil : TRMotion.selection) {
                            recipesExpanded = false
                        }
                    }
                    .font(TR.ui(11, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai-direction-collapse")
                }
            }

            if recipesExpanded {
                LazyVStack(spacing: 11) {
                    ForEach(AICutDirection.allCases) { direction in
                        AICutDirectionCard(
                            direction: direction,
                            selected: model.selectedAICutDirection == direction,
                            recommended: model.recommendedAICutDirection == direction
                        ) {
                            model.selectAICutDirection(direction)
                            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                                recipesExpanded = false
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                AICutDirectionCard(
                    direction: activeDirection,
                    selected: true,
                    recommended: model.recommendedAICutDirection == activeDirection,
                    actionLabel: "Change"
                ) {
                    withAnimation(reduceMotion ? nil : TRMotion.selection) {
                        recipesExpanded = true
                    }
                }
                .accessibilityIdentifier("ai-direction-expand")
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }

    private var storyContextEditor: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What is this reel about?")
                        .font(TR.ui(15, weight: .semibold))
                    Text("Optional · one clue helps AI find the meaning")
                        .font(TR.ui(10))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                Text("\(model.aiCutStoryContext.count)/\(CloudPhotoAnalysisClient.maximumStoryContextCharacters)")
                    .font(TR.mono(9))
                    .foregroundStyle(.white.opacity(0.34))
            }

            TextField(
                "e.g. Our students’ competition day",
                text: $model.aiCutStoryContext,
                axis: .vertical
            )
            .font(TR.ui(13))
            .lineLimit(2...3)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(.black.opacity(0.20))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .onChange(of: model.aiCutStoryContext) { _, value in
                if value.count > CloudPhotoAnalysisClient.maximumStoryContextCharacters {
                    model.aiCutStoryContext = String(
                        value.prefix(CloudPhotoAnalysisClient.maximumStoryContextCharacters)
                    )
                }
            }
            .accessibilityIdentifier("ai-story-context")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(model.aiCutStoryContextSuggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            withAnimation(TRMotion.selection) {
                                model.aiCutStoryContext = suggestion
                            }
                        }
                        .font(TR.ui(10, weight: .semibold))
                        .foregroundStyle(
                            model.aiCutStoryContext == suggestion ? TR.ink : .white.opacity(0.64)
                        )
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            model.aiCutStoryContext == suggestion ? TR.accent : .white.opacity(0.055)
                        )
                        .clipShape(Capsule())
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
                    }
                }
            }
        }
        .foregroundStyle(TR.cream)
        .padding(15)
        .glassCard(cornerRadius: 18)
    }

    private var sharingSummary: String {
        let context = model.aiCutStoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty
            ? "OpenAI’s GPT-5.6 Luna receives \(model.aiCutSelectedPhotoCount) small previews and your current edit recipe."
            : "OpenAI’s GPT-5.6 Luna receives \(model.aiCutSelectedPhotoCount) small previews, your edit recipe and story hint."
    }
}

private struct AICutPhotoSelectionCard: View {
    @EnvironmentObject private var model: TripReelModel
    let action: () -> Void

    private var selectedPhotos: [ReelPhoto] {
        model.aiCutPhotoOptions
            .filter { model.selectedAICutPhotoIDs.contains($0.id) }
            .prefix(3)
            .map(\.photo)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    ForEach(Array(selectedPhotos.enumerated()), id: \.element.id) { index, photo in
                        PhotoAssetView(source: photo.source)
                            .frame(width: 46, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(.white.opacity(0.22), lineWidth: 1)
                            )
                            .rotationEffect(.degrees(Double(index - 1) * 5))
                            .offset(x: CGFloat(index - 1) * 14)
                            .zIndex(Double(index))
                    }
                }
                .frame(width: 72, height: 62)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Moments for AI")
                        .font(TR.ui(15, weight: .semibold))
                    Text(selectionSummary)
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.56))
                    Text("Ranked on device for quality & relevance")
                        .font(TR.ui(10, weight: .medium))
                        .foregroundStyle(TR.keep.opacity(0.82))
                }

                Spacer(minLength: 4)

                Text("Edit moments")
                    .font(TR.ui(12, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TR.accent.opacity(0.75))
            }
            .foregroundStyle(TR.cream)
            .padding(14)
            .glassCard(cornerRadius: 18, highlighted: true)
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel("Moments for AI, \(model.aiCutSelectedPhotoCount) selected")
        .accessibilityHint("Edit which reduced photo previews or sampled video frames may be sent")
        .accessibilityIdentifier("ai-photo-selection-card")
    }

    private var selectionSummary: String {
        if model.aiCutAvailablePhotoCount > model.aiCutPhotoSelectionLimit {
            return "\(model.aiCutSelectedPhotoCount) selected · max \(model.aiCutPhotoSelectionLimit)"
        }
        return "\(model.aiCutSelectedPhotoCount) selected · \(model.aiCutAvailablePhotoCount) available"
    }
}

private struct AICutPhotoSelectionSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    private var selectionIsFull: Bool {
        model.aiCutSelectedPhotoCount >= model.aiCutPhotoSelectionLimit
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .cleanup)

            VStack(spacing: 0) {
                SheetHeader(title: "Edit moments") { dismiss() }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text(selectionSummary)
                        .font(TR.ui(12, weight: .semibold))
                        .foregroundStyle(selectionIsFull ? TR.accent : .white.opacity(0.64))

                    HStack(spacing: 8) {
                        selectionAction("Best moments", identifier: "ai-photos-suggested") {
                            model.selectSuggestedAICutPhotos()
                        }

                        selectionAction(selectAllTitle, identifier: "ai-photos-select-all") {
                            model.selectAllAICutPhotos()
                        }

                        selectionAction("Clear", identifier: "ai-photos-clear") {
                            model.clearAICutPhotoSelection()
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 13)
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.aiCutPhotoOptions) { option in
                            photoCell(option)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 118)
                }
            }
        }
        .foregroundStyle(TR.cream)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if selectionIsFull {
                    Text("Deselect one moment to choose another")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.52))
                } else {
                    Text("Chosen on this iPhone for quality, relevance & variety")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Button("Done") { dismiss() }
                    .buttonStyle(CreamButtonStyle())
                    .disabled(model.aiCutSelectedPhotoCount == 0)
                    .opacity(model.aiCutSelectedPhotoCount == 0 ? 0.48 : 1)
                    .accessibilityIdentifier("ai-photos-done")
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .background(TR.sheet.opacity(0.94))
        }
        .accessibilityIdentifier("ai-photo-selection-sheet")
    }

    private func photoCell(_ option: AICutPhotoOption) -> some View {
        let selected = model.selectedAICutPhotoIDs.contains(option.id)
        let canSelect = selected || !selectionIsFull

        return Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                if selected {
                    model.toggleAICutPhotoSelection(option.id)
                } else if !canSelect {
                    return
                } else {
                    model.toggleAICutPhotoSelection(option.id)
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                PhotoAssetView(source: option.photo.source)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? TR.accent.opacity(0.10) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                selected ? TR.accent : .white.opacity(0.10),
                                lineWidth: selected ? 2 : 1
                            )
                    }

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        selected ? TR.ink : .white,
                        selected ? TR.accent : .black.opacity(0.44)
                    )
                    .padding(7)

                if option.localSelection == .morePhotos {
                    Text("MORE")
                        .font(TR.mono(8, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(TR.cream)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.62))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(7)
                }

                if option.photo.isVideo {
                    Label("CLIP", systemImage: "play.fill")
                        .font(TR.mono(8, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(TR.cream)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.66))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(7)
                }
            }
            .opacity(canSelect ? 1 : 0.42)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
        .accessibilityLabel(
            option.localSelection == .firstCut
                ? "First Cut \(option.photo.isVideo ? "video clip" : "photo")"
                : "More Moments \(option.photo.isVideo ? "video clip" : "photo")"
        )
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(canSelect ? "Double tap to toggle" : "Deselect another moment first")
        .accessibilityIdentifier("ai-photo-\(option.id)")
    }

    private func selectionAction(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                action()
            }
        } label: {
            Text(title)
                .font(TR.ui(11, weight: .semibold))
                .foregroundStyle(title == "Clear" ? .white.opacity(0.58) : TR.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(.white.opacity(0.055))
                .clipShape(Capsule())
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.96))
        .accessibilityIdentifier(identifier)
    }

    private var selectionSummary: String {
        if model.aiCutAvailablePhotoCount > model.aiCutPhotoSelectionLimit {
            return "\(model.aiCutSelectedPhotoCount) of \(model.aiCutAvailablePhotoCount) · best matches first"
        }
        return "\(model.aiCutSelectedPhotoCount) of \(model.aiCutAvailablePhotoCount) · quality + relevance"
    }

    private var selectAllTitle: String {
        if model.aiCutAvailablePhotoCount > model.aiCutPhotoSelectionLimit {
            return "Fill \(model.aiCutPhotoSelectionLimit)"
        }
        return "Select all"
    }
}

private struct AICutDirectionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let direction: AICutDirection
    let selected: Bool
    let recommended: Bool
    var actionLabel: String? = nil
    let action: () -> Void
    @State private var animates = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                DirectionMiniTimeline(direction: direction, animates: animates && !reduceMotion)
                    .frame(width: 78, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    if recommended {
                        Text("RECOMMENDED")
                            .font(TR.mono(9, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(TR.keep)
                    }
                    Text(direction.title)
                        .font(TR.ui(15, weight: .semibold))
                    Text(direction.detail)
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if let actionLabel {
                    HStack(spacing: 5) {
                        Text(actionLabel)
                            .font(TR.ui(11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(TR.accent)
                } else {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(selected ? TR.accent : .white.opacity(0.30))
                }
            }
            .foregroundStyle(TR.cream)
            .padding(14)
            .glassCard(cornerRadius: 18, highlighted: selected)
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel("\(direction.title). \(direction.detail)")
        .accessibilityValue(
            [recommended ? "Recommended" : nil, selected ? "Selected" : "Not selected"]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityHint(actionLabel == nil ? "Selects this reel recipe" : "Shows all reel recipes")
        .accessibilityIdentifier("ai-direction-\(direction.rawValue)")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: direction == .dynamic ? 0.9 : 1.8).repeatForever(autoreverses: true)) {
                animates = true
            }
        }
    }
}

private struct DirectionMiniTimeline: View {
    let direction: AICutDirection
    let animates: Bool

    private var widths: [CGFloat] {
        switch direction {
        case .betterStory: [17, 26, 14]
        case .dynamic: [12, 12, 12, 12]
        case .calm: [29, 24]
        case .people: [16, 25, 16]
        case .surpriseMe: [14, 21, 17]
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.22))

            VStack(spacing: 8) {
                Image(systemName: direction.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .scaleEffect(animates && direction == .people ? 1.12 : 1)

                HStack(spacing: 3) {
                    ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                        Capsule()
                            .fill(index == emphasisIndex ? TR.accent : .white.opacity(0.28))
                            .frame(width: animates && direction == .betterStory ? widths.reversed()[index] : width, height: 5)
                            .offset(y: animates && direction == .dynamic && index.isMultiple(of: 2) ? -2 : 0)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: animates)
        .accessibilityHidden(true)
    }

    private var emphasisIndex: Int {
        switch direction {
        case .people: 1
        case .surpriseMe: animates ? 2 : 0
        default: widths.indices.last ?? 0
        }
    }
}

struct AICutProcessingScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WarmBackground(variant: .rendering)

            VStack(spacing: 28) {
                Spacer(minLength: 18)

                processingArtwork

                if let failure = model.aiCutFailure {
                    VStack(spacing: 12) {
                        MetadataText(text: failure.stage, color: TR.accent)
                        Text(failure.title)
                            .font(TR.display(34))
                            .multilineTextAlignment(.center)
                        Text(failure.message)
                            .font(TR.ui(14))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: failure.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TR.keep)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("What to do")
                                    .font(TR.ui(11, weight: .semibold))
                                    .foregroundStyle(TR.cream)
                                Text(failure.suggestion)
                                    .font(TR.ui(11))
                                    .foregroundStyle(.white.opacity(0.52))
                                    .lineSpacing(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(13)
                        .glassCard(cornerRadius: 16)

                        Button(failure.actionTitle) { model.recoverFromAICutFailure() }
                            .buttonStyle(CreamButtonStyle())
                            .accessibilityIdentifier("ai-cut-retry")
                        Button(model.aiCutFallbackTitle) { model.leaveAICutFailure() }
                            .buttonStyle(GlassButtonStyle())
                            .accessibilityIdentifier("ai-cut-keep-after-failure")

                        Text("Reference · \(failure.reference)")
                            .font(TR.mono(8))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.28))
                    }
                } else {
                    VStack(spacing: 10) {
                        MetadataText(
                            text: model.selectedAICutDirection?.title ?? "AI Director",
                            color: TR.accent
                        )
                        Text(model.aiCutStatus)
                            .font(TR.display(34))
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.11))
                                Capsule().fill(TR.accent)
                                    .frame(width: proxy.size.width * max(0.03, model.aiCutProgress))
                            }
                        }
                        .frame(height: 3)
                        .animation(reduceMotion ? nil : TRMotion.progress, value: model.aiCutProgress)

                        Text("AI is comparing these previews with your First Cut’s order, pace, titles, music and motion. Rendering stays on your iPhone.")
                            .font(TR.ui(12))
                            .foregroundStyle(.white.opacity(0.50))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)

                        Button {
                            model.cancelAICut()
                        } label: {
                            Label("Cancel AI edit", systemImage: "xmark")
                        }
                        .buttonStyle(GlassButtonStyle())
                        .padding(.top, 8)
                        .accessibilityIdentifier("ai-cut-cancel")

                        Text("Your First Cut stays unchanged")
                            .font(TR.ui(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }

                Spacer(minLength: 22)
            }
            .padding(.horizontal, 28)
        }
        .accessibilityIdentifier("ai-processing-screen")
    }

    private var processingArtwork: some View {
        AIPhotoTransferArtwork(
            photos: transferPhotos,
            isSending: model.aiCutProgress >= 0.54 && model.aiCutFailure == nil,
            isActive: model.aiCutFailure == nil,
            reduceMotion: reduceMotion
        )
        .frame(height: 205)
    }

    private var transferPhotos: [ReelPhoto] {
        let selected = model.aiCutPhotoOptions
            .filter { model.selectedAICutPhotoIDs.contains($0.id) }
            .map(\.photo)
        if !selected.isEmpty {
            return Array(selected.prefix(6))
        }
        return Array((model.firstCutSnapshot?.keptPhotos ?? []).prefix(6))
    }
}

private struct AIPhotoTransferArtwork: View {
    let photos: [ReelPhoto]
    let isSending: Bool
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let routeY = proxy.size.height * 0.62
            let startX: CGFloat = 48
            let destinationX = isSending && isActive ? proxy.size.width - 48 : proxy.size.width * 0.5

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.black.opacity(0.24))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }

                VStack(spacing: 3) {
                    MetadataText(
                        text: !isActive
                            ? "Transfer stopped safely"
                            : isSending ? "Reduced previews · encrypted in transit" : "Preparing reduced previews",
                        color: !isActive ? TR.accent : isSending ? TR.keep : TR.accent
                    )
                    Text(
                        !isActive
                            ? "No new cut replaced your saved version"
                            : isSending ? "Sending copies securely to OpenAI" : "Original media remains on this iPhone"
                    )
                        .font(TR.ui(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .position(x: proxy.size.width / 2, y: 27)

                Capsule()
                    .fill(.white.opacity(0.09))
                    .frame(width: max(1, proxy.size.width - 100), height: 3)
                    .position(x: proxy.size.width / 2, y: routeY)

                SecureRouteDash()
                    .stroke(
                        isSending ? TR.keep.opacity(0.72) : TR.accent.opacity(0.62),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 7])
                    )
                    .frame(width: max(1, destinationX - startX), height: 28)
                    .position(x: (startX + destinationX) / 2, y: routeY)

                AITransferEndpoint(
                    symbol: "iphone.gen3",
                    title: "This iPhone",
                    detail: "Originals stay here",
                    tint: TR.accent
                )
                .position(x: startX, y: routeY)

                AITransferEndpoint(
                    symbol: "sparkles",
                    title: "OpenAI",
                    detail: "GPT-5.6 Luna",
                    tint: TR.keep
                )
                .opacity(isSending && isActive ? 1 : 0.34)
                .position(x: proxy.size.width - 48, y: routeY)

                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TR.ink)
                    .frame(width: 26, height: 26)
                    .background(isSending ? TR.keep : TR.accent)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.black.opacity(0.20), lineWidth: 1))
                    .position(x: proxy.size.width / 2, y: routeY)
                    .shadow(color: (isSending ? TR.keep : TR.accent).opacity(0.24), radius: 12)

                if photos.isEmpty {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.46))
                        .position(x: (startX + destinationX) / 2, y: routeY - 24)
                } else if reduceMotion || !isActive {
                    transferCard(photos[0], index: 0)
                        .position(x: (startX + destinationX) / 2, y: routeY - 24)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        ZStack {
                            ForEach(Array(photos.prefix(3).enumerated()), id: \.element.id) { index, photo in
                                let progress = transferProgress(at: timeline.date, index: index)
                                let eased = progress * progress * (3 - (2 * progress))
                                let x = startX + ((destinationX - startX) * eased)
                                let arc = sin(progress * .pi) * -18

                                transferCard(photo, index: index)
                                    .scaleEffect(0.82 + (sin(progress * .pi) * 0.18))
                                    .rotationEffect(.degrees(Double(index - 1) * 2.5))
                                    .opacity(edgeOpacity(for: progress))
                                    .position(x: x, y: routeY - 25 + arc)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isSending
                ? "Sending selected photo previews or sampled video frames securely to OpenAI GPT-5.6 Luna. Original media stays on this iPhone."
                : "Preparing reduced previews on this iPhone. Original media stays on this iPhone."
        )
        .accessibilityIdentifier("ai-transfer-artwork")
    }

    private func transferCard(_ photo: ReelPhoto, index: Int) -> some View {
        PhotoAssetView(source: photo.source)
            .frame(width: 48, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if photo.isVideo {
                    Image(systemName: "film.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(TR.cream)
                        .frame(width: 18, height: 18)
                        .background(.black.opacity(0.68))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.30), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.46), radius: 8, y: 5)
            .zIndex(Double(10 + index))
    }

    private func transferProgress(at date: Date, index: Int) -> CGFloat {
        let cycleDuration = 2.25
        let stagger = Double(index) * (cycleDuration / 3)
        let raw = (date.timeIntervalSinceReferenceDate + stagger)
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return CGFloat(raw < 0 ? raw + 1 : raw)
    }

    private func edgeOpacity(for progress: CGFloat) -> Double {
        let fadeIn = min(1, progress / 0.10)
        let fadeOut = min(1, (1 - progress) / 0.14)
        return Double(max(0, min(fadeIn, fadeOut)))
    }
}

private struct AITransferEndpoint: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.62))
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                .clipShape(Circle())

            VStack(spacing: 1) {
                Text(title)
                    .font(TR.ui(10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(detail)
                    .font(TR.ui(8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
            }
            .fixedSize()
        }
    }
}

private struct SecureRouteDash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}

struct AICutComparisonScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewSource: TripCutSource = .aiCut
    @State private var detailPage = 0
    @StateObject private var soundtrack = LocalSoundtrackPlayer()

    private var snapshot: TripEditSnapshot? {
        model.editSnapshot(for: previewSource) ?? model.firstCutSnapshot
    }

    private var previewTrack: MusicTrack? {
        model.musicTrack(withID: snapshot?.selectedTrackID)
    }

    private var previewSoundtrackVolume: Float {
        snapshot?.keptPhotos.contains(where: \.isVideo) == true ? 0.42 : 0.82
    }

    private var storyRecommendation: AICutRecommendation? {
        model.aiCutRecommendations.first { $0.kind == .story }
    }

    private var titleRecommendation: AICutRecommendation? {
        model.aiCutRecommendations.first { $0.kind == .titles }
    }

    private var musicRecommendation: AICutRecommendation? {
        model.aiCutRecommendations.first { $0.kind == .music }
    }

    private var treatmentRecommendation: AICutRecommendation? {
        model.aiCutRecommendations.first { $0.kind == .treatment }
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        MetadataText(text: "AI Cut · ready", color: TR.accent)
                        Text("A different take.")
                            .font(TR.display(35))
                        Text("Watch either cut, then swipe through what changed.")
                            .font(TR.ui(12))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .trEntrance(0, distance: 8)
                    .overlay(alignment: .topTrailing) {
                        Menu {
                            Button("Try another AI direction", systemImage: "arrow.triangle.2.circlepath") {
                                model.tryAnotherAICut()
                            }
                            Button("Keep First Cut", systemImage: "checkmark.shield") {
                                model.keepFirstCut()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("More cut options")
                        .accessibilityIdentifier("ai-comparison-more")
                    }

                    if let snapshot {
                        MontageView(
                            photos: snapshot.keptPhotos,
                            titleCards: snapshot.montageTitleCards,
                            textOverlays: snapshot.textOverlays,
                            dim: false,
                            watermark: false,
                            showLabels: false,
                            look: snapshot.montageLook,
                            motionIntensity: snapshot.motionIntensity,
                            secondsPerSlide: 1.85 - (snapshot.pace * 1.25),
                            playbackBehavior: .playOnce,
                            showsReplayControl: true,
                            onPlaybackStarted: {
                                soundtrack.play(
                                    track: previewTrack,
                                    volume: previewSoundtrackVolume,
                                    restart: true
                                )
                            },
                            onPlaybackEnded: {
                                soundtrack.finishNaturally()
                            }
                        )
                        .id(previewSource)
                        .frame(height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.14), lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                    }

                    HStack(spacing: 8) {
                        comparisonTab(.firstCut, duration: model.firstCutDurationText)
                        comparisonTab(.aiCut, duration: model.aiCutDurationText)
                    }
                    .padding(4)
                    .background(.black.opacity(0.22))
                    .clipShape(Capsule())

                    if let previewTrack {
                        Button {
                            soundtrack.toggle(track: previewTrack, volume: previewSoundtrackVolume)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: soundtrack.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .foregroundStyle(TR.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(previewSource == .aiCut ? "AI music · \(previewTrack.name)" : previewTrack.name)
                                        .font(TR.ui(12, weight: .semibold))
                                    Text(soundtrack.isPlaying ? "Tap to pause" : "Tap to hear this cut")
                                        .font(TR.ui(10))
                                        .foregroundStyle(.white.opacity(0.48))
                                }
                                Spacer()
                                Image(systemName: "waveform")
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .foregroundStyle(TR.cream)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .glassCard(cornerRadius: 16)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityIdentifier("ai-comparison-audio")
                    }

                    if previewSource == .aiCut {
                        TabView(selection: $detailPage) {
                            AIComparisonDetailPage(
                                eyebrow: "What changed",
                                title: model.aiCutDiagnosis?.verdict ?? "A clearer story shape",
                                detail: model.aiCutSummary ?? "AI rebalanced the strongest moments without changing your originals.",
                                symbol: "arrow.triangle.branch",
                                badges: AIComparisonDetailPage.changeBadges(model.aiCutComparison)
                            )
                            .tag(0)

                            AIComparisonDetailPage(
                                eyebrow: "Story & titles",
                                title: storyRecommendation?.title ?? "A stronger beginning and ending",
                                detail: titleRecommendation?.title ?? storyRecommendation?.detail ?? "Titles now support the story instead of interrupting it.",
                                symbol: "text.quote",
                                badges: [
                                    titleRecommendation.map { ("textformat", $0.title) },
                                    model.aiCutComparison.map { ("arrow.up.arrow.down", "\($0.reorderedCount) reordered") }
                                ].compactMap { $0 }
                            )
                            .tag(1)

                            AIComparisonDetailPage(
                                eyebrow: "Sound & movement",
                                title: musicRecommendation?.title ?? "A new rhythm",
                                detail: treatmentRecommendation?.title ?? musicRecommendation?.detail ?? "Music, timing and motion now move as one.",
                                symbol: "waveform.path",
                                badges: [
                                    musicRecommendation.map { ("music.note", $0.title) },
                                    treatmentRecommendation.map { ("wand.and.stars", $0.title) }
                                ].compactMap { $0 }
                            )
                            .tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 188)
                        .accessibilityLabel("AI cut details")
                        .accessibilityValue("Page \(detailPage + 1) of 3")

                        HStack(spacing: 7) {
                            ForEach(0..<3, id: \.self) { index in
                                Capsule()
                                    .fill(index == detailPage ? TR.accent : .white.opacity(0.20))
                                    .frame(width: index == detailPage ? 20 : 6, height: 6)
                                    .animation(reduceMotion ? nil : TRMotion.selection, value: detailPage)
                            }
                        }
                        .accessibilityHidden(true)
                    }

                    VStack(spacing: 11) {
                        Button(previewSource == .aiCut ? "Export AI Cut" : "Export First Cut") {
                            model.exportCut(previewSource)
                        }
                        .buttonStyle(CreamButtonStyle())
                        .accessibilityHint("Opens export with the version currently selected")
                        .accessibilityIdentifier("use-ai-cut-button")

                        Button(previewSource == .aiCut ? "Edit AI Cut" : "Edit First Cut") {
                            model.editCut(previewSource)
                        }
                            .buttonStyle(GlassButtonStyle())
                            .accessibilityIdentifier("edit-compared-cut-button")

                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .animation(reduceMotion ? nil : TRMotion.selection, value: previewSource)
        .onChange(of: previewSource) { _, _ in
            soundtrack.stop()
        }
        .onDisappear { soundtrack.stop() }
        .accessibilityIdentifier("ai-comparison-screen")
    }

    private func comparisonTab(_ source: TripCutSource, duration: String) -> some View {
        Button {
            previewSource = source
        } label: {
            VStack(spacing: 2) {
                Text(source == .aiCut ? "AI Cut ✦" : "First Cut")
                    .font(TR.ui(13, weight: .semibold))
                Text(duration)
                    .font(TR.mono(10))
                    .foregroundStyle(previewSource == source ? TR.ink.opacity(0.62) : .white.opacity(0.42))
            }
            .foregroundStyle(previewSource == source ? TR.ink : TR.cream.opacity(0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(previewSource == source ? TR.cream : .clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compare-\(source.rawValue)")
    }
}

private struct AIComparisonDetailPage: View {
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
    let badges: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TR.accent)
                    .frame(width: 34, height: 34)
                    .background(TR.accent.opacity(0.10))
                    .clipShape(Circle())
                MetadataText(text: eyebrow, color: TR.accent)
                Spacer()
                Label("Swipe", systemImage: "arrow.left.and.right")
                    .font(TR.mono(8))
                    .foregroundStyle(.white.opacity(0.34))
            }

            Text(title)
                .font(TR.ui(16, weight: .semibold))
                .foregroundStyle(TR.cream)
                .lineLimit(2)

            Text(detail)
                .font(TR.ui(11))
                .foregroundStyle(.white.opacity(0.54))
                .lineSpacing(2)
                .lineLimit(3)

            if !badges.isEmpty {
                HStack(spacing: 7) {
                    ForEach(Array(badges.prefix(3).enumerated()), id: \.offset) { _, badge in
                        Label(badge.1, systemImage: badge.0)
                            .font(TR.ui(9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 20)
        .padding(.horizontal, 1)
        .accessibilityElement(children: .combine)
    }

    static func changeBadges(_ comparison: AICutComparison?) -> [(String, String)] {
        guard let comparison else { return [] }
        var values: [(String, String)] = []
        if comparison.restoredCount > 0 {
            values.append(("arrow.uturn.backward", "+\(comparison.restoredCount) restored"))
        }
        if comparison.reorderedCount > 0 {
            values.append(("arrow.up.arrow.down", "\(comparison.reorderedCount) reordered"))
        }
        if comparison.retimedCount > 0 {
            values.append(("metronome", "\(comparison.retimedCount) re-timed"))
        }
        if comparison.motionChangedCount > 0 {
            values.append(("move.3d", "\(comparison.motionChangedCount) new moves"))
        }
        return values
    }
}

struct AIVideoIntroScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var activeRole: AIVideoMomentRole = .beginning
    @State private var showsConsent = false
    @State private var showsPrivacyPolicy = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        MetadataText(text: "AI VIDEO · NOTHING SENT YET", color: TR.accent)
                        Text("Turn two moments into a story.")
                            .font(TR.display(37))
                            .multilineTextAlignment(.center)
                        Text("A beginning and ending are ready. Tap either one to change it.")
                            .font(TR.ui(12))
                            .foregroundStyle(.white.opacity(0.56))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 36)

                    VStack(spacing: 10) {
                        HStack {
                            Label(
                                recommendationLabel,
                                systemImage: "iphone"
                            )
                            .font(TR.ui(11, weight: .semibold))
                            .foregroundStyle(TR.keep)
                            Spacer()
                            Text(model.aiVideoHasStoryPair ? "6 SEC · 9:16" : "4 SEC · 9:16")
                                .font(TR.mono(9))
                                .foregroundStyle(.white.opacity(0.46))
                        }

                        HStack(spacing: 10) {
                            ForEach(selectedRoles, id: \.self) { role in
                                if let photo = selectedPhoto(for: role) {
                                    momentCard(photo: photo, role: role)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 24)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHOOSE A DIFFERENT \(activeRole.title.uppercased())")
                            .font(TR.mono(9))
                            .foregroundStyle(TR.accent)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(model.aiVideoPhotoOptions) { photo in
                                    Button {
                                        model.selectAIVideoPhoto(photo.id, for: activeRole)
                                    } label: {
                                        PhotoAssetView(source: photo.source, samplingScale: 1.4)
                                            .frame(width: 58, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(
                                                        model.aiVideoSelectedPhotoIDs.contains(photo.id)
                                                            ? TR.accent
                                                            : .white.opacity(0.14),
                                                        lineWidth: model.aiVideoSelectedPhotoIDs.contains(photo.id) ? 2 : 1
                                                    )
                                            }
                                            .overlay(alignment: .topTrailing) {
                                                if let index = model.aiVideoSelectedPhotoIDs.firstIndex(of: photo.id) {
                                                    Text("\(index + 1)")
                                                        .font(TR.mono(9))
                                                        .foregroundStyle(TR.ink)
                                                        .frame(width: 20, height: 20)
                                                        .background(TR.accent)
                                                        .clipShape(Circle())
                                                        .padding(4)
                                                }
                                            }
                                    }
                                    .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
                                    .accessibilityLabel("Use \(photo.label) as the \(activeRole.title.lowercased())")
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                    .accessibilityIdentifier("ai-video-photo-picker")

                    TabView(selection: $page) {
                        AIVideoBenefitPage(
                            symbol: "camera.aperture",
                            eyebrow: "STORY ANCHORS",
                            title: "A beginning and an ending",
                            detail: "Seedance moves naturally between the two real moments you approved."
                        )
                        .tag(0)
                        AIVideoBenefitPage(
                            symbol: "textformat",
                            eyebrow: "MEMORIES FINISH",
                            title: model.aiVideoTitle,
                            detail: "Memories adds the title cleanly after generation—so the words stay sharp and editable."
                        )
                        .tag(1)
                        AIVideoBenefitPage(
                            symbol: "lock.shield",
                            eyebrow: "YOUR CHOICE",
                            title: model.aiVideoHasStoryPair ? "Two reduced copies" : "One reduced copy",
                            detail: "Only these metadata-free previews go via OpenRouter to ByteDance Seedance 2.0 after you agree."
                        )
                        .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 142)

                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? TR.accent : .white.opacity(0.20))
                                .frame(width: index == page ? 20 : 6, height: 6)
                                .animation(reduceMotion ? nil : TRMotion.selection, value: page)
                        }
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Button(model.aiVideoHasStoryPair ? "Use these two moments" : "Animate this moment") {
                            showsConsent = true
                        }
                            .buttonStyle(CreamButtonStyle())
                            .disabled(
                                !model.aiVideoIsConfigured ||
                                model.aiVideoSelectedPhotos.count < min(2, model.aiVideoPhotoOptions.count)
                            )
                            .opacity(model.aiVideoIsConfigured ? 1 : 0.52)
                            .accessibilityHint("Reviews a final sharing notice before uploading the reduced previews")
                            .accessibilityIdentifier("create-ai-video-button")

                        Button("Not now") { model.navigateBack() }
                            .font(TR.ui(14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .padding(.vertical, 8)
                            .buttonStyle(.plain)

                        Button("Privacy details") { showsPrivacyPolicy = true }
                            .font(TR.ui(11, weight: .medium))
                            .foregroundStyle(TR.accent)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
        }
        .animation(reduceMotion ? nil : TRMotion.selection, value: model.aiVideoSelectedPhotoIDs)
        .alert(model.aiVideoHasStoryPair ? "Send two reduced previews?" : "Send one reduced preview?", isPresented: $showsConsent) {
            Button("Agree & Create") { model.beginAIVideoGeneration() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Memories sends these metadata-free copies through our secure service to OpenRouter and ByteDance Seedance 2.0. The provider temporarily retains inputs and output to make the clip. AI may invent motion or details; your originals never change.")
        }
        .alert(
            "AI video",
            isPresented: Binding(
                get: { model.aiVideoFailureMessage != nil },
                set: { if !$0 { model.dismissAIVideoMessage() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissAIVideoMessage() }
        } message: {
            Text(model.aiVideoFailureMessage ?? "")
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            TripReelPrivacyPolicyView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("ai-video-intro-screen")
    }

    private var recommendationLabel: String {
        guard model.aiVideoSelectionIsRecommended else { return "Your two moments" }
        return model.aiVideoRecommendationIsVisionBased
            ? "Recommended on this iPhone"
            : "Suggested from your film"
    }

    private var selectedRoles: [AIVideoMomentRole] {
        model.aiVideoHasStoryPair ? [.beginning, .ending] : [.beginning]
    }

    private func selectedPhoto(for role: AIVideoMomentRole) -> ReelPhoto? {
        switch role {
        case .beginning: model.aiVideoSelectedPhoto
        case .ending: model.aiVideoEndingPhoto
        }
    }

    private func momentCard(photo: ReelPhoto, role: AIVideoMomentRole) -> some View {
        Button {
            activeRole = role
        } label: {
            ZStack(alignment: .bottomLeading) {
                PhotoAssetView(
                    source: photo.source,
                    contentMode: .fit,
                    samplingScale: 1.5
                )
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .background(.black.opacity(0.36))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.76)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.title.uppercased())
                        .font(TR.mono(8))
                        .foregroundStyle(TR.accent)
                    Text(role == .beginning ? "Start here" : "Land here")
                        .font(TR.ui(11, weight: .semibold))
                        .foregroundStyle(TR.cream)
                }
                .padding(11)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        activeRole == role ? TR.accent : .white.opacity(0.16),
                        lineWidth: activeRole == role ? 2 : 1
                    )
            }
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.97))
        .accessibilityLabel("\(role.title) moment, \(photo.label)")
        .accessibilityHint("Selects this slot so you can replace its photo")
        .accessibilityIdentifier("ai-video-\(role.rawValue)-card")
    }
}

private struct AIVideoBenefitPage: View {
    let symbol: String
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TR.accent)
                .frame(width: 42, height: 42)
                .background(TR.accent.opacity(0.10))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                MetadataText(text: eyebrow, color: TR.accent)
                Text(title)
                    .font(TR.ui(16, weight: .semibold))
                    .foregroundStyle(TR.cream)
                    .lineLimit(1)
                Text(detail)
                    .font(TR.ui(11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(2)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

struct AIVideoGeneratingScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transmitting = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .rendering)

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(TR.accent.opacity(transmitting ? 0.65 : 0.18), lineWidth: 1.5)
                        .frame(width: 190, height: 286)
                        .scaleEffect(transmitting ? 1.04 : 0.96)

                    ForEach(Array(model.aiVideoSelectedPhotos.enumerated()), id: \.element.id) { index, photo in
                        PhotoAssetView(source: photo.source, contentMode: .fit, samplingScale: 1.5)
                            .frame(width: 150, height: 246)
                            .background(.black.opacity(0.28))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .rotationEffect(.degrees(reduceMotion ? 0 : (index == 0 ? -4 : 4)))
                            .rotation3DEffect(
                                .degrees(reduceMotion ? 0 : (transmitting ? 2.5 : -2.5)),
                                axis: (x: 0, y: 1, z: 0)
                            )
                            .offset(
                                x: model.aiVideoHasStoryPair ? (index == 0 ? -35 : 35) : 0,
                                y: reduceMotion ? 0 : (transmitting ? -5 : 5)
                            )
                    }

                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(TR.accent)
                        .padding(13)
                        .background(.black.opacity(0.78))
                        .clipShape(Circle())
                        .offset(x: 88, y: -128)
                        .symbolEffect(.pulse.byLayer, options: .repeating, isActive: !reduceMotion)
                }
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: transmitting
                )

                VStack(spacing: 9) {
                    MetadataText(text: "SEEDANCE 2.0 · AI VIDEO", color: TR.accent)
                    Text(model.aiVideoHasStoryPair ? "Bringing your story to life…" : "Bringing it to life…")
                        .font(TR.display(38))
                    Text(model.aiVideoStatus)
                        .font(TR.ui(13))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 9) {
                    ProgressView(value: model.aiVideoProgress)
                        .tint(TR.accent)
                    HStack {
                        Text(model.aiVideoHasStoryPair ? "TWO REDUCED PREVIEWS" : "ONE REDUCED PREVIEW")
                        Spacer()
                        Text("\(Int((model.aiVideoProgress * 100).rounded()))%")
                    }
                    .font(TR.mono(9))
                    .foregroundStyle(.white.opacity(0.42))
                }
                .padding(.horizontal, 34)

                Button("Stop waiting") { model.cancelAIVideoGeneration() }
                    .buttonStyle(GlassButtonStyle())
                    .padding(.horizontal, 24)
                    .accessibilityHint("Returns to your two moments. Trying again resumes this generation")
                    .accessibilityIdentifier("cancel-ai-video-button")

                Text("Your submitted video keeps processing. Come back within 29 minutes to resume without starting over.")
                    .font(TR.ui(10))
                    .foregroundStyle(.white.opacity(0.38))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)

                Spacer()
            }
        }
        .onAppear { transmitting = true }
        .accessibilityIdentifier("ai-video-generating-screen")
    }
}

struct AIVideoReadyScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            WarmBackground(variant: .export)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        MetadataText(text: "AI-GENERATED MOTION · READY", color: TR.keep)
                        Text("A memory in motion.")
                            .font(TR.display(37))
                        Text("Review carefully—AI can invent small visual details.")
                            .font(TR.ui(11))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .padding(.horizontal, 28)

                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 470)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(.white.opacity(0.14), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
                    } else if let photo = model.aiVideoSelectedPhoto {
                        PhotoAssetView(source: photo.source, contentMode: .fit)
                            .frame(height: 470)
                            .background(.black.opacity(0.38))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    VStack(spacing: 10) {
                        Button(model.isSavingAIVideo ? "Saving…" : "Save to Photos") {
                            Task { await model.saveAIVideoToPhotos() }
                        }
                        .buttonStyle(CreamButtonStyle())
                        .disabled(model.isSavingAIVideo || model.aiVideoURL == nil)
                        .accessibilityIdentifier("save-ai-video-button")

                        if let url = model.aiVideoURL {
                            ShareLink(item: url) {
                                Text("Share video")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GlassButtonStyle())
                            .accessibilityIdentifier("share-ai-video-button")
                        }

                        Button("Back to both cuts") { model.navigateBack() }
                            .font(TR.ui(13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.vertical, 8)
                            .buttonStyle(.plain)
                    }

                    if let message = model.aiVideoSaveMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(TR.ui(12, weight: .semibold))
                            .foregroundStyle(TR.keep)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .task(id: model.aiVideoURL) {
            guard let url = model.aiVideoURL else { return }
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
        .alert(
            "AI video",
            isPresented: Binding(
                get: { model.aiVideoFailureMessage != nil },
                set: { if !$0 { model.dismissAIVideoMessage() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissAIVideoMessage() }
        } message: {
            Text(model.aiVideoFailureMessage ?? "")
        }
        .accessibilityIdentifier("ai-video-ready-screen")
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
                                .accessibilityIdentifier("cut-screen")

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
                            .accessibilityLabel(model.currentPhoto.isVideo ? "Cut video clip" : "Cut photo")

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
                            .accessibilityLabel(model.currentPhoto.isVideo ? "Keep video clip" : "Keep photo")
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

            if model.currentPhoto.isVideo {
                Label("VIDEO", systemImage: "play.fill")
                    .font(TR.mono(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(TR.cream)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.60))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(15)
            }

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
        .accessibilityLabel(
            "\(model.currentPhoto.isVideo ? "Video clip" : "Photo") \(model.currentPhotoIndex + 1) of \(model.photos.count)"
        )
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
                    eyebrow: "\(model.keptMediaSummary) in the cut",
                    title: "Set the pace"
                )
                .padding(.horizontal, 26)
                .padding(.leading, 48)
                .padding(.top, 4)
                .trEntrance(0, distance: 10)
                .accessibilityIdentifier("pace-screen")

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
                            Text(String(format: "%.1fs base pace", model.secondsPerPhoto))
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

                    Button("Advanced · per-moment timing") {
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
    }
}

private struct AdvancedTimingSheet: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "Per-moment timing") { dismiss() }

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
    @State private var selectedPhotoID: String?
    @StateObject private var soundtrack = LocalSoundtrackPlayer()

    var body: some View {
        ZStack {
            WarmBackground(variant: .cutting)

            GeometryReader { proxy in
                ViewThatFits(in: .vertical) {
                    studioContent(previewHeight: min(392, proxy.size.height * 0.47), compact: false)
                    studioContent(previewHeight: min(292, proxy.size.height * 0.39), compact: true)
                }
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
            PhotoEditorSheet(initialPhotoID: selectedPhotoID)
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
        .onChange(of: showFullPreview) { _, isShowing in
            if isShowing {
                soundtrack.stop()
            }
        }
        .onDisappear {
            soundtrack.stop()
        }
        .onChange(of: model.keptPhotos.map(\.id)) { _, ids in
            if let selectedPhotoID, !ids.contains(selectedPhotoID) {
                self.selectedPhotoID = nil
            }
        }
    }

    private func studioContent(previewHeight: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 52, height: 38)
                VStack(spacing: 4) {
                    MetadataText(text: "FILM STUDIO · \(model.tripShortPlace)", color: .white.opacity(0.82))
                        .accessibilityIdentifier("second-watch-screen")
                    Text("\(model.keptMediaSummary) · \(model.filmDurationText)\(trackSuffix)")
                        .font(TR.ui(11))
                        .foregroundStyle(.white.opacity(0.53))
                }
                .frame(maxWidth: .infinity)

                Button("Export") {
                    model.openExport()
                }
                .font(TR.ui(12, weight: .semibold))
                .foregroundStyle(TR.ink)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(TR.cream)
                .clipShape(Capsule())
                .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
                .accessibilityIdentifier("studio-export-button")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .trEntrance(0, distance: 7)

            Spacer(minLength: compact ? 5 : 12)

            ZStack {
                MontageView(
                    photos: previewPhotos,
                    titleCards: selectedPhotoID == nil ? model.montageTitleCards : [],
                    textOverlays: selectedPhotoID == nil ? model.textOverlays : model.textOverlays.filter { $0.photoID == selectedPhotoID },
                    showLabels: false,
                    look: model.montageLook,
                    motionIntensity: model.montageMotionIntensity,
                    secondsPerSlide: model.secondsPerPhoto,
                    playbackBehavior: .playOnce,
                    showsReplayControl: true,
                    onPlaybackStarted: {
                        soundtrack.play(
                            track: model.selectedTrack,
                            volume: model.previewSoundtrackVolume,
                            restart: true
                        )
                    },
                    onPlaybackEnded: {
                        soundtrack.finishNaturally()
                    }
                )
                .id(previewIdentity)
                .frame(width: previewHeight * 9 / 16, height: previewHeight)

                VStack {
                    HStack {
                        if selectedPhotoID != nil {
                            Label("CLIP", systemImage: "viewfinder")
                                .font(TR.mono(9, weight: .semibold))
                                .tracking(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.58))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Button {
                            selectedPhotoID = nil
                            soundtrack.stop()
                            showFullPreview = true
                        } label: {
                            Label("Play film", systemImage: "play.fill")
                                .font(TR.ui(11, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(.black.opacity(0.64))
                                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
                        .accessibilityIdentifier("full-preview-button")

                        Spacer()

                        Button {
                            soundtrack.toggle(track: model.selectedTrack, volume: model.previewSoundtrackVolume)
                        } label: {
                            Image(systemName: soundtrack.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.64))
                                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                                .clipShape(Circle())
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
                        .disabled(model.selectedTrack == nil)
                        .opacity(model.selectedTrack == nil ? 0.42 : 1)
                        .accessibilityLabel(soundtrack.isPlaying ? "Pause soundtrack" : "Play soundtrack")
                    }
                }
                .foregroundStyle(TR.cream)
                .padding(10)
            }
            .frame(width: previewHeight * 9 / 16, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                    .stroke(.white.opacity(0.17), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.56), radius: 28, y: 20)
            .trEntrance(1, distance: 12)

            if let errorMessage = soundtrack.errorMessage {
                Text(errorMessage)
                    .font(TR.ui(10, weight: .medium))
                    .foregroundStyle(TR.accent)
                    .lineLimit(1)
                    .padding(.top, 6)
            }

            Spacer(minLength: compact ? 6 : 10)

            FilmStudioTimeline(
                photos: model.keptPhotos,
                titleCards: model.montageTitleCards,
                trackName: model.selectedTrack?.name,
                defaultPhotoDuration: model.secondsPerPhoto,
                selectedPhotoID: $selectedPhotoID,
                onOpenTitles: { showTitles = true },
                onOpenMusic: { showMusic = true },
                onMove: { sourceID, targetID in
                    model.moveKeptPhoto(id: sourceID, before: targetID)
                    selectedPhotoID = sourceID
                }
            )
            .frame(height: compact ? 126 : 142)
            .trEntrance(2, distance: 8)

            studioToolDock
                .padding(.top, compact ? 3 : 7)
                .padding(.bottom, compact ? 0 : 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var studioToolDock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                studioTool("Moments", symbol: "photo.stack", identifier: "studio-tool-photos") {
                    model.editPhotoSelection()
                }
                studioTool("Crop", symbol: "crop.rotate", identifier: "studio-tool-framing") {
                    selectedPhotoID = selectedPhotoID ?? model.keptPhotos.first?.id
                    showPhotoEditor = true
                }
                studioTool("Text", symbol: "textformat", identifier: "studio-tool-titles") {
                    showTitles = true
                }
                studioTool("Music", symbol: "music.note", identifier: "studio-tool-music") {
                    showMusic = true
                }
                studioTool("Style", symbol: "wand.and.stars", identifier: "studio-tool-style") {
                    showStyle = true
                }
                studioTool("Pace", symbol: "metronome", identifier: "studio-tool-pace") {
                    model.go(.pace)
                }
            }
            .padding(.horizontal, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio-edit-menu")
    }

    private func studioTool(
        _ title: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 28)
                    .background(.white.opacity(0.065))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(TR.ui(9, weight: .semibold))
            }
            .foregroundStyle(TR.cream.opacity(0.78))
            .frame(width: 54)
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.93))
        .accessibilityIdentifier(identifier)
    }

    private var previewPhotos: [ReelPhoto] {
        guard let selectedPhotoID,
              let photo = model.keptPhotos.first(where: { $0.id == selectedPhotoID }) else {
            return model.keptPhotos
        }
        return [photo]
    }

    private var previewIdentity: String {
        "\(selectedPhotoID ?? "film")-\(model.montageLook.rawValue)-\(model.montageMotionIntensity.rawValue)-\(model.selectedTrackID ?? "none")"
    }

    private var trackSuffix: String {
        guard let track = model.selectedTrack else { return "" }
        return " · \(track.name)"
    }

}

private struct FilmStudioTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photos: [ReelPhoto]
    let titleCards: [MontageTitleCard]
    let trackName: String?
    let defaultPhotoDuration: Double
    @Binding var selectedPhotoID: String?
    let onOpenTitles: () -> Void
    let onOpenMusic: () -> Void
    let onMove: (String, String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                MetadataText(text: "TIMELINE", color: .white.opacity(0.45))
                Spacer()
                Text(selectedPhotoID == nil ? "Tap a clip · drag to reorder" : "Clip selected · tap Crop to edit")
                    .font(TR.ui(9, weight: .medium))
                    .foregroundStyle(selectedPhotoID == nil ? .white.opacity(0.38) : TR.accent.opacity(0.85))
            }
            .padding(.horizontal, 20)

            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case let .title(card):
                                titleClip(card)
                            case let .photo(photo):
                                photoClip(
                                    photo,
                                    index: photos.firstIndex(where: { $0.id == photo.id }) ?? 0
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Rectangle()
                    .fill(TR.accent)
                    .frame(width: 2, height: 70)
                    .shadow(color: TR.accent.opacity(0.7), radius: 4)
                    .allowsHitTesting(false)
            }
            .frame(height: 66)

            Button(action: onOpenMusic) {
                HStack(spacing: 9) {
                    Image(systemName: "music.note")
                        .foregroundStyle(TR.keep)
                    HStack(spacing: 3) {
                        ForEach(0..<18, id: \.self) { index in
                            Capsule()
                                .fill(TR.keep.opacity(0.46))
                                .frame(width: 2, height: CGFloat(4 + ((index * 7) % 10)))
                        }
                    }
                    Text(trackName ?? "Add music")
                        .font(TR.ui(9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(TR.keep.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.98))
            .padding(.horizontal, 20)
            .accessibilityIdentifier("studio-music-track")
        }
        .padding(.vertical, 7)
        .background(.black.opacity(0.24))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    private var timelineItems: [MontageTimelineItem] {
        MontageTimelineBuilder.make(photos: photos, titleCards: titleCards)
    }

    private func titleClip(_ card: MontageTitleCard) -> some View {
        Button(action: onOpenTitles) {
            VStack(spacing: 4) {
                Image(systemName: "textformat")
                Text(card.title)
                    .lineLimit(1)
            }
            .font(TR.ui(9, weight: .semibold))
            .foregroundStyle(TR.accent)
            .frame(width: 62, height: 62)
            .background(TR.accent.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(TR.accent.opacity(0.32), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
        .accessibilityLabel("Title, \(card.title)")
    }

    private func photoClip(_ photo: ReelPhoto, index: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : TRMotion.selection) {
                selectedPhotoID = selectedPhotoID == photo.id ? nil : photo.id
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                PhotoAssetView(source: photo.source)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                Text("\(index + 1) · \(String(format: "%.1fs", photo.durationSeconds ?? defaultPhotoDuration))")
                    .font(TR.mono(8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(5)
            }
            .frame(width: 58, height: 62)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        selectedPhotoID == photo.id ? TR.accent : .white.opacity(0.12),
                        lineWidth: selectedPhotoID == photo.id ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
        .draggable(photo.id) {
            PhotoAssetView(source: photo.source)
                .frame(width: 58, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .dropDestination(for: String.self) { sourceIDs, _ in
            guard let sourceID = sourceIDs.first, sourceID != photo.id else { return false }
            onMove(sourceID, photo.id)
            return true
        }
        .accessibilityLabel("Clip \(index + 1), \(photo.label)")
    }
}

private struct FullFilmPreview: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var soundtrack = LocalSoundtrackPlayer()
    @State private var controlsVisible = true
    @State private var playbackComplete = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MontageView(
                photos: model.keptPhotos,
                titleCards: model.montageTitleCards,
                textOverlays: model.textOverlays,
                showLabels: false,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.secondsPerPhoto,
                playbackBehavior: .playOnce,
                showsReplayControl: true,
                onPlaybackStarted: {
                    playbackComplete = false
                    soundtrack.play(
                        track: model.selectedTrack,
                        volume: model.previewSoundtrackVolume,
                        restart: true
                    )
                },
                onPlaybackEnded: {
                    playbackComplete = true
                    controlsVisible = true
                    soundtrack.finishNaturally()
                }
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
                .allowsHitTesting(!playbackComplete)

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
                            soundtrack.toggle(track: model.selectedTrack, volume: model.previewSoundtrackVolume)
                        }
                        .disabled(model.selectedTrack == nil)
                        .opacity(model.selectedTrack == nil ? 0.46 : 1)
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        MetadataText(text: "FULL FILM PREVIEW", color: .white.opacity(0.66))
                        Text("\(model.keptMediaSummary) · \(model.filmDurationText)\(trackSuffix)")
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

    init(initialPhotoID: String? = nil) {
        _selectedID = State(initialValue: initialPhotoID)
    }

    private var selectedPhoto: ReelPhoto? {
        let photos = model.keptPhotos
        return photos.first(where: { $0.id == selectedID }) ?? photos.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                SheetHeader(title: "Frame & trim") { dismiss() }

                Text("Photos use a face-aware crop. Videos start on the strongest locally detected moment. Pinch to reframe, then adjust only what needs it.")
                    .font(TR.ui(12))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineSpacing(4)

                if let photo = selectedPhoto {
                    editorPreview(photo)
                    photoStrip
                    frameControls(photo)
                    if photo.isVideo {
                        videoMotionNotice(photo)
                    } else {
                        motionControls(photo)
                    }
                    timingControls(photo)

                    Button(photo.isVideo ? "Reset this clip to Auto" : "Reset this photo to Auto") {
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
                        "No moments in this cut",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Keep a photo or video to edit it.")
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
                textOverlays: model.textOverlays.filter { $0.photoID == photo.id },
                showLabels: false,
                look: .story,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: model.duration(for: photo),
                playbackBehavior: .playOnce,
                showsReplayControl: true
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
                                .overlay(alignment: .bottomTrailing) {
                                    if photo.isVideo {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(TR.ink)
                                            .frame(width: 18, height: 18)
                                            .background(TR.accent)
                                            .clipShape(Circle())
                                            .padding(4)
                                    }
                                }
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

    private func videoMotionNotice(_ photo: ReelPhoto) -> some View {
        HStack(spacing: 11) {
            Image(systemName: photo.hasOriginalAudio ? "waveform" : "video.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TR.keep)
                .frame(width: 34, height: 34)
                .background(TR.keep.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Natural motion")
                    .font(TR.ui(12, weight: .semibold))
                    .foregroundStyle(TR.cream)
                Text(photo.hasOriginalAudio
                    ? "Original sound is mixed beneath the soundtrack."
                    : "This clip brings movement without artificial zooming.")
                    .font(TR.ui(10))
                    .foregroundStyle(.white.opacity(0.50))
            }
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func timingControls(_ photo: ReelPhoto) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MetadataText(
                    text: photo.isVideo ? "CLIP LENGTH" : "TIME ON SCREEN",
                    color: .white.opacity(0.43)
                )
                Spacer()
                Text(String(format: "%.1fs", model.duration(for: photo)))
                    .font(TR.mono(12))
                    .foregroundStyle(TR.accent)
            }
            let durationRange = (photo.isVideo ? 0.8 : 0.6)...maxDuration(for: photo)
            if durationRange.upperBound > durationRange.lowerBound {
                Slider(
                    value: Binding(
                        get: { model.duration(for: selectedPhoto ?? photo) },
                        set: { model.setPhotoDuration($0, forPhotoID: photo.id) }
                    ),
                    in: durationRange,
                    step: 0.1
                )
                .tint(TR.accent)
            } else if photo.isVideo {
                Text("This short video uses the full clip.")
                    .font(TR.ui(10))
                    .foregroundStyle(.white.opacity(0.48))
            }

            if photo.isVideo {
                HStack {
                    MetadataText(text: "MOMENT IN ORIGINAL", color: .white.opacity(0.43))
                    Spacer()
                    Text(videoRangeText(photo))
                        .font(TR.mono(11))
                        .foregroundStyle(.white.opacity(0.62))
                }
                let maximumStart = maxVideoStart(for: photo)
                if maximumStart > 0.05 {
                    Slider(
                        value: Binding(
                            get: { selectedPhoto?.videoStartSeconds ?? photo.videoStartSeconds },
                            set: { model.setVideoStart($0, forPhotoID: photo.id) }
                        ),
                        in: 0...maximumStart,
                        step: 0.1
                    )
                    .tint(TR.keep)
                }
            }
        }
    }

    private func maxDuration(for photo: ReelPhoto) -> Double {
        guard photo.isVideo else { return 4 }
        return max(0.8, min(4, photo.sourceDurationSeconds - photo.videoStartSeconds))
    }

    private func maxVideoStart(for photo: ReelPhoto) -> Double {
        max(0, photo.sourceDurationSeconds - model.duration(for: photo))
    }

    private func videoRangeText(_ photo: ReelPhoto) -> String {
        let current = selectedPhoto ?? photo
        let end = min(current.sourceDurationSeconds, current.videoStartSeconds + model.duration(for: current))
        return String(format: "%.1f–%.1fs", current.videoStartSeconds, end)
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
                    .accessibilityIdentifier("film-style-sheet")

                Text("Choose the mood, not every tiny transition. Memories still adapts portrait and landscape photos automatically.")
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
    }

    private var stylePreview: some View {
        HStack(spacing: 17) {
            MontageView(
                photos: previewPhotos,
                textOverlays: model.textOverlays.filter { overlay in previewPhotos.contains(where: { $0.id == overlay.photoID }) },
                showLabels: false,
                look: model.montageLook,
                motionIntensity: model.montageMotionIntensity,
                secondsPerSlide: max(1.15, model.secondsPerPhoto),
                playbackBehavior: .playOnce,
                showsReplayControl: true
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

                    Text("Suggested privately from this film's place, days and visual themes. Tap any card to rewrite it or remove it.")
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

                    if !model.textOverlays.isEmpty {
                        onPhotoTextControls
                    }
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
                backgroundSource: model.previewSource(forTitle: selectedKind),
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

    private var onPhotoTextControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetadataText(text: "ON-PHOTO STORY BEATS", color: TR.accent)
            Text("AI placed these short lines inside the reel. Rewrite them, move them, change how they enter, or remove them.")
                .font(TR.ui(12))
                .foregroundStyle(.white.opacity(0.52))
                .lineSpacing(3)

            ForEach(model.textOverlays) { overlay in
                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        "Text on photo",
                        text: Binding(
                            get: { model.textOverlays.first(where: { $0.id == overlay.id })?.text ?? "" },
                            set: { model.setTextOverlayText($0, id: overlay.id) }
                        ),
                        axis: .vertical
                    )
                    .font(overlay.style == .editorial ? TR.display(22) : TR.ui(15, weight: .semibold))
                    .lineLimit(1...3)
                    .accessibilityIdentifier("photo-text-\(overlay.id)")

                    HStack(spacing: 8) {
                        Menu(overlay.style.name) {
                            ForEach(MontageTitleStyle.allCases) { style in
                                Button(style.name) { model.setTextOverlayStyle(style, id: overlay.id) }
                            }
                        }
                        Menu(overlay.placement.name) {
                            ForEach(MontageTextPlacement.allCases) { placement in
                                Button(placement.name) { model.setTextOverlayPlacement(placement, id: overlay.id) }
                            }
                        }
                        Menu(overlay.animation.name) {
                            ForEach(MontageTextAnimation.allCases) { animation in
                                Button(animation.name) { model.setTextOverlayAnimation(animation, id: overlay.id) }
                            }
                        }
                        Button(role: .destructive) {
                            model.removeTextOverlay(id: overlay.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove text")
                    }
                    .font(TR.ui(11, weight: .semibold))
                    .foregroundStyle(TR.cream)
                }
                .padding(14)
                .background(.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.13), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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

                Text("Music previews are 90-second excerpts, trimmed, loudness-normalized, faded, and transcoded to AAC for Memories.")
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
        return model.cutToBeat ? "Moments land on the downbeat" : "Moments keep your pace"
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
