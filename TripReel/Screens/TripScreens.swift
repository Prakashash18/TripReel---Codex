import PhotosUI
import SwiftUI

struct TripsScreen: View {
    @EnvironmentObject private var model: TripReelModel
    @State private var collection: TripCollection = .trips

    private enum TripCollection: String, CaseIterable, Identifiable {
        case trips = "Trips"
        case nearby = "Nearby"

        var id: String { rawValue }
    }

    private var displayedTrips: [Trip] {
        collection == .trips ? model.trips : model.nearbyEvents
    }

    var body: some View {
        ZStack {
            WarmBackground(variant: .trips)

            VStack(spacing: 0) {
                ScreenHeading(
                    eyebrow: collection == .trips ? model.tripsEyebrow : model.nearbyEyebrow,
                    title: collection == .trips ? "Your trips" : "Nearby moments"
                )
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 13)

                collectionPicker
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        if model.isScanningLibrary && model.trips.isEmpty && model.nearbyEvents.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(TR.accent)
                                Text("Looking through \(model.libraryPhotoCount) accessible photos…")
                                    .font(TR.ui(13))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 72)
                        } else if displayedTrips.isEmpty {
                            emptyCollection
                        } else {
                            ForEach(displayedTrips) { trip in
                                TripRow(trip: trip) {
                                    model.requestBuild(trip: trip)
                                }
                            }

                            if collection == .nearby {
                                Text("One-day photo outings near places you visit often. Screenshots never create an event.")
                                    .font(TR.ui(11))
                                    .foregroundStyle(.white.opacity(0.39))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                            }
                        }

                        if !model.usesDemoData {
                            CloudAnalysisSettingsCard(
                                isEnabled: model.cloudAnalysisIsEnabled,
                                isAvailable: model.cloudAnalysisIsConfigured
                            ) {
                                model.presentCloudAnalysisSettings()
                            }
                            .padding(.top, 8)
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
                .refreshable {
                    await model.refreshPhotoLibraryIfAuthorized(force: true)
                }
            }
        }
        .onAppear {
            if model.trips.isEmpty && !model.nearbyEvents.isEmpty {
                collection = .nearby
            }
        }
        .accessibilityIdentifier("trips-screen")
    }

    private var collectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(TripCollection.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { collection = item }
                } label: {
                    Text(item.rawValue)
                        .font(TR.ui(13, weight: .semibold))
                        .foregroundStyle(collection == item ? TR.ink : .white.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(collection == item ? TR.cream : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityValue(collection == item ? "Selected" : "Not selected")
            }
        }
        .padding(4)
        .background(.white.opacity(0.065))
        .overlay(Capsule().stroke(.white.opacity(0.11), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var emptyCollection: some View {
        VStack(spacing: 12) {
            Image(systemName: collection == .trips ? "airplane" : "mappin.and.ellipse")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(TR.accent.opacity(0.8))
            Text(collection == .trips ? "No multi-day trips found" : "No nearby outings yet")
                .font(TR.display(22))
                .foregroundStyle(TR.cream)
            Text(collection == .trips
                 ? "Try Nearby for one-day moments, or pull down to scan again."
                 : "Nearby appears after TripReel recognizes a familiar area and a compact day with six or more photos.")
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

private struct TripRow: View {
    let trip: Trip
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                PhotoAssetView(source: trip.coverSource)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.place)
                        .font(TR.ui(17, weight: .semibold))
                        .foregroundStyle(TR.cream)

                    Text(trip.dates)
                        .font(TR.ui(13))
                        .foregroundStyle(.white.opacity(0.61))

                    Text("\(trip.photoCount) PHOTOS")
                        .font(TR.mono(11))
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
        .buttonStyle(.plain)
        .accessibilityLabel("\(trip.place), \(trip.photoCount) photos")
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
                ScreenHeading(eyebrow: nil, title: "Your trips")
                    .padding(.horizontal, 24)
                    .padding(.top, 30)

                Spacer()

                VStack(spacing: 22) {
                    HStack(alignment: .bottom, spacing: 7) {
                        dashedPhoto(width: 26)
                        dashedPhoto(width: 38)
                        dashedPhoto(width: 26)
                    }
                    .opacity(0.55)

                    Text("We couldn't find any trips yet — trips need at least 15 photos taken in one place over a day or more.")
                        .font(TR.display(21))
                        .foregroundStyle(.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 34)

                Spacer()

                VStack(spacing: 15) {
                    Button("Pick photos manually") {
                        showPicker = true
                    }
                    .buttonStyle(CreamButtonStyle())
                    .photosPicker(
                        isPresented: $showPicker,
                        selection: $pickerItems,
                        maxSelectionCount: 0,
                        matching: .images,
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

                MetadataText(text: model.tripPlace, color: .white.opacity(0.58))

                Text("Building your film")
                    .font(TR.display(34))
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Text("\(model.buildCount) of \(model.photos.count) photos placed")
                    .font(TR.ui(15))
                    .foregroundStyle(.white.opacity(0.61))
                    .contentTransition(.numericText())
            }
        }
        .onAppear { floating = !reduceMotion }
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
