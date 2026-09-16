import PhotosUI
import SwiftUI

enum MemoryCollection: String, CaseIterable, Identifiable {
    case overseas = "Overseas"
    case local = "Local"

    var id: String { rawValue }

    static func available(overseasCount: Int, localCount: Int) -> [MemoryCollection] {
        allCases.filter { collection in
            switch collection {
            case .overseas: overseasCount > 0
            case .local: localCount > 0
            }
        }
    }

    static func resolvedSelection(
        _ selection: MemoryCollection,
        available: [MemoryCollection]
    ) -> MemoryCollection {
        available.contains(selection) ? selection : (available.first ?? .overseas)
    }
}

struct TripsScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collection: MemoryCollection = .overseas
    @Namespace private var collectionSelection
    @State private var rowCentres: [String: CGFloat] = [:]
    @State private var viewportCentre: CGFloat = 0
    @State private var playingTripID: String?

    private var availableCollections: [MemoryCollection] {
        MemoryCollection.available(
            overseasCount: model.trips.count,
            localCount: model.nearbyEvents.count
        )
    }

    private var activeCollection: MemoryCollection {
        MemoryCollection.resolvedSelection(collection, available: availableCollections)
    }

    private var displayedMemories: [Trip] {
        activeCollection == .overseas ? model.trips : model.nearbyEvents
    }

    private var isShowingLocalMemories: Bool {
        activeCollection == .local
    }

    private func updatePlayingRow() {
        guard !reduceMotion, viewportCentre > 0, !rowCentres.isEmpty else {
            playingTripID = nil
            return
        }
        let nearest = rowCentres.min {
            abs($0.value - viewportCentre) < abs($1.value - viewportCentre)
        }
        // A row scrolled well clear of the middle plays nothing, so an
        // off-screen card never keeps decoding.
        guard let nearest, abs(nearest.value - viewportCentre) < 160 else {
            playingTripID = nil
            return
        }
        guard playingTripID != nearest.key else { return }
        playingTripID = nearest.key
    }

    private var cleanupBanner: some View {
        HStack(spacing: 11) {
            Button {
                model.openCleanupFromBanner()
            } label: {
                Text(model.cleanupBannerText)
                    .font(TR.ui(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityIdentifier("cleanup-banner")

            Button {
                model.dismissCleanupBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("cleanup-banner-dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 14)
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .trips)

            VStack(spacing: 0) {
                ScreenHeading(
                    eyebrow: isShowingLocalMemories
                        ? model.localMemoriesEyebrow
                        : model.overseasMemoriesEyebrow,
                    title: "Your memories"
                )
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 13)
                    .trEntrance(0, distance: 10)

                if availableCollections.count > 1 {
                    collectionPicker
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                        .trEntrance(1, distance: 8)
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        if model.isScanningLibrary && model.trips.isEmpty && model.nearbyEvents.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(TR.accent)
                                Text("Looking through \(model.libraryPhotoCount) accessible moments…")
                                    .font(TR.ui(13))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 72)
                        } else if displayedMemories.isEmpty {
                            emptyCollection
                        } else {
                            ForEach(Array(displayedMemories.enumerated()), id: \.element.id) { index, trip in
                                TripRow(
                                    trip: trip,
                                    isNearby: isShowingLocalMemories,
                                    isPlaying: playingTripID == trip.id
                                ) {
                                    model.requestBuild(trip: trip)
                                }
                                .trEntrance(min(index, 4), distance: 8)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: RowCentreKey.self,
                                            value: [trip.id: proxy.frame(in: .global).midY]
                                        )
                                    }
                                )
                            }

                            if isShowingLocalMemories {
                                Text("One-day memories near places you visit often. Screenshots never create a memory.")
                                    .font(TR.ui(11))
                                    .foregroundStyle(.white.opacity(0.39))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                            }
                        }

                        if let anniversary = model.anniversaryMemory,
                           let line = model.anniversaryMemoryLine,
                           !isShowingLocalMemories {
                            AnniversaryCard(trip: anniversary, line: line) {
                                model.requestBuild(trip: anniversary)
                            }
                            .trEntrance(0, distance: 10)
                        }

                        if model.showsCleanupBanner {
                            cleanupBanner
                                .trEntrance(0, distance: 8)
                        }

                        if model.usesDemoData {
                            Button("See the empty state") {
                                model.go(.empty)
                            }
                            .font(TR.ui(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                            .buttonStyle(.plain)
                            .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .trEntrance(2, distance: 10)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ViewportCentreKey.self,
                            value: proxy.frame(in: .global).midY
                        )
                    }
                )
                .onPreferenceChange(RowCentreKey.self) { centres in
                    rowCentres = centres
                    updatePlayingRow()
                }
                .onPreferenceChange(ViewportCentreKey.self) { centre in
                    viewportCentre = centre
                    updatePlayingRow()
                }
                .refreshable {
                    await model.refreshPhotoLibraryIfAuthorized(force: true)
                }
            }
        }
        .onChange(of: availableCollections, initial: true) { _, available in
            collection = MemoryCollection.resolvedSelection(collection, available: available)
        }
        .accessibilityIdentifier("trips-screen")
    }

    private var collectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(availableCollections) { item in
                Button {
                    withAnimation(
                        reduceMotion
                            ? .easeInOut(duration: 0.16)
                            : TRMotion.selection
                    ) {
                        collection = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(collection == item ? TR.ink : .white.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if collection == item {
                                if reduceMotion {
                                    Capsule().fill(TR.cream)
                                } else {
                                    Capsule()
                                        .fill(TR.cream)
                                        .matchedGeometryEffect(
                                            id: "trip-collection-selection",
                                            in: collectionSelection
                                        )
                                }
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityValue(collection == item ? "Selected" : "Not selected")
            }
        }
        .padding(4)
        .background(.white.opacity(0.065))
        .overlay(Capsule().stroke(.white.opacity(0.11), lineWidth: 1))
        .clipShape(Capsule())
        .sensoryFeedback(.selection, trigger: collection)
    }

    private var emptyCollection: some View {
        VStack(spacing: 12) {
            Image(systemName: isShowingLocalMemories ? "mappin.and.ellipse" : "airplane")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(TR.accent.opacity(0.8))
            Text(isShowingLocalMemories ? "No local memories yet" : "No overseas memories yet")
                .font(TR.display(22))
                .foregroundStyle(TR.cream)
            Text(isShowingLocalMemories
                 ? "Local memories appear after Memories recognizes a familiar area and a compact day with six or more moments."
                 : "Pull down to scan again, or pick the moments that matter yourself.")
                .font(TR.ui(12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 48)
    }
}

/// Asked once, at the moment the user taps a memory, over its cover. One
/// optional line — and the skip is real.
struct ClueScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @FocusState private var clueFocused: Bool

    private var cover: PhotoSource {
        model.clueTrip?.coverSource ?? .bundled("my-khe-beach")
    }

    var body: some View {
        ZStack {
            PhotoAssetView(source: cover)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 7) {
                    MetadataText(
                        text: "\(model.clueTrip?.shortPlace ?? "This memory") · \(model.clueTrip?.dates ?? "")",
                        color: TR.accent
                    )
                    Text("What was this day?")
                        .font(TR.display(40))
                        .tracking(-0.5)
                        .foregroundStyle(TR.cream)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("One line, in your words. It shapes the titles — and it never leaves your phone unless you ask for AI.")
                        .font(TR.ui(14))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("clue-screen")

                TextField("", text: $model.storyClue, axis: .vertical)
                    .font(TR.ui(14))
                    .foregroundStyle(TR.cream)
                    .tint(TR.accent)
                    .lineLimit(1...3)
                    .focused($clueFocused)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background(.black.opacity(0.34))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(clueFocused ? TR.accent.opacity(0.6) : .white.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("What was this day?")
                    .accessibilityIdentifier("clue-field")

                FlowingChips(suggestions: model.aiCutStoryContextSuggestions) { suggestion in
                    model.storyClue = suggestion
                    clueFocused = false
                }

                Button("Make my film") {
                    model.confirmClue()
                }
                .buttonStyle(CreamButtonStyle())
                .accessibilityIdentifier("clue-make-film")

                Button("Skip — just make it") {
                    model.skipClue()
                }
                .font(TR.ui(14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("clue-skip")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .trEntrance(0, distance: 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct FlowingChips: View {
    let suggestions: [String]
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        pick(suggestion)
                    }
                    .font(TR.ui(11, weight: .semibold))
                    .foregroundStyle(TR.cream.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.08), in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clue-chip")
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }
}

private struct RowCentreKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

private struct ViewportCentreKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// The only earned reason to open the app on a day the user took no photos.
private struct AnniversaryCard: View {
    let trip: Trip
    let line: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                MontageView(
                    photos: trip.teaserPhotos,
                    showLabels: false,
                    secondsPerSlide: 2.2
                )

                LinearGradient(
                    colors: [.black.opacity(0.1), .black.opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        MetadataText(text: "This day last year", color: TR.accent)
                        Text(line)
                            .font(TR.display(27))
                            .foregroundStyle(TR.cream)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text("Watch")
                        .font(TR.ui(12, weight: .semibold))
                        .foregroundStyle(TR.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(TR.cream, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .frame(height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(TR.accent.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel("This day last year. \(line)")
        .accessibilityIdentifier("anniversary-card")
    }
}

private struct TripRow: View {
    let trip: Trip
    let isNearby: Bool
    var isPlaying = false
    let action: () -> Void

    private var storyTitle: String {
        LocalStoryIntelligence.collectionTitle(for: trip, isNearby: isNearby)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if isPlaying, !trip.teaserPhotos.isEmpty {
                        MontageView(
                            photos: trip.teaserPhotos,
                            showLabels: false,
                            secondsPerSlide: 1.0
                        )
                    } else {
                        PhotoAssetView(source: trip.coverSource)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(storyTitle)
                        .font(TR.ui(17, weight: .semibold))
                        .foregroundStyle(TR.cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(detailText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .font(TR.mono(10))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.trailing, 6)
            }
            .padding(11)
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel(
            [storyTitle, trip.dates, trip.mediaCountText]
                .joined(separator: ", ")
        )
        .accessibilityIdentifier("trip-row-\(trip.id)")
    }

    private var detailText: String {
        if LocalStoryIntelligence.friendlyPlaceName(from: trip.place) == nil {
            return trip.mediaCountText.uppercased()
        }
        return "\(trip.dates) · \(trip.mediaCountText.uppercased())"
    }
}

struct EmptyTripsScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack {
            WarmBackground(variant: .trips)

            VStack(spacing: 0) {
                ScreenHeading(eyebrow: nil, title: "Your memories")
                    .padding(.horizontal, 24)
                    .padding(.top, 30)
                    .trEntrance(0, distance: 8)

                Spacer()

                VStack(spacing: 22) {
                    HStack(alignment: .bottom, spacing: 7) {
                        dashedPhoto(width: 26)
                        dashedPhoto(width: 38)
                        dashedPhoto(width: 26)
                    }
                    .opacity(0.55)

                    Text("We couldn't find a clear memory yet. Pick the photos and videos that matter, or add more moments and scan again.")
                        .font(TR.display(21))
                        .foregroundStyle(.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 34)
                .trEntrance(1, distance: 12)

                Spacer()

                VStack(spacing: 15) {
                    Button("Pick moments manually") {
                        showPicker = true
                    }
                    .buttonStyle(CreamButtonStyle())
                    .photosPicker(
                        isPresented: $showPicker,
                        selection: $pickerItems,
                        maxSelectionCount: 0,
                        matching: .any(of: [.images, .videos]),
                        preferredItemEncoding: .current,
                        photoLibrary: .shared()
                    )

                    Button(model.isScanningLibrary ? "Scanning library…" : "Scan photo library again") {
                        Task {
                            await model.refreshPhotoLibraryIfAuthorized(force: true)
                            if !model.trips.isEmpty { model.go(.trips) }
                        }
                    }
                    .font(TR.ui(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.53))
                    .buttonStyle(.plain)
                    .disabled(model.isScanningLibrary)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
                .trEntrance(2, distance: 9)
            }
            .safeAreaPadding(.vertical)
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                let loaded = await model.loadManualSelection(items: newItems)
                if loaded { pickerItems = [] }
            }
        }
        .accessibilityIdentifier("empty-trips-screen")
    }

    private func dashedPhoto(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .frame(width: width, height: width)
    }
}

struct BuildingScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ZStack {
            WarmBackground(variant: .building)

            VStack(spacing: 0) {
                ZStack {
                    MontageView(
                        photos: model.photos,
                        titleCards: model.montageTitleCards,
                        textOverlays: model.textOverlays,
                        showLabels: false,
                        look: model.montageLook,
                        motionIntensity: model.montageMotionIntensity,
                        secondsPerSlide: 1.15
                    )
                        .frame(width: 216, height: 290)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.56), radius: 30, y: 22)

                    flyingPhoto(model.previewSource(at: 1), size: 62, x: -132, y: -94, phase: -8)
                    flyingPhoto(model.previewSource(at: 2), size: 54, x: 130, y: 6, phase: 9)
                    flyingPhoto(model.previewSource(at: 3), size: 48, x: -114, y: 124, phase: -6)
                }
                .padding(.bottom, 38)
                .trEntrance(0, distance: 14)

                MetadataText(text: model.tripPlace, color: .white.opacity(0.58))
                    .trEntrance(1, distance: 7)

                Text("Building your film")
                    .font(TR.display(34))
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .trEntrance(2, distance: 8)

                Text("\(model.buildCount) of \(model.photos.count) moments placed")
                    .font(TR.ui(15))
                    .foregroundStyle(.white.opacity(0.61))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : TRMotion.progress, value: model.buildCount)

                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.10))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [TR.accent.opacity(0.62), TR.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: bar.size.width * CGFloat(model.buildCount)
                                    / CGFloat(max(1, model.photos.count))
                            )
                    }
                }
                .frame(width: 188, height: 4)
                .padding(.top, 16)
                .animation(reduceMotion ? nil : TRMotion.progress, value: model.buildCount)
                .trEntrance(3, distance: 6)
            }
        }
        .task(id: reduceMotion) { floating = !reduceMotion }
        .accessibilityIdentifier("building-screen")
    }

    private func flyingPhoto(_ source: PhotoSource, size: CGFloat, x: CGFloat, y: CGFloat, phase: CGFloat) -> some View {
        PhotoAssetView(source: source)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.34), radius: 14, y: 8)
            .offset(x: x, y: y + (floating ? phase : -phase))
            .rotationEffect(.degrees(floating ? phase * 0.4 : -phase * 0.4))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.45 + abs(phase) * 0.02).repeatForever(autoreverses: true),
                value: floating
            )
    }
}
