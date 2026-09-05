import PhotosUI
import SwiftUI

struct TripsScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            WarmBackground(variant: .trips)

            VStack(spacing: 0) {
                ScreenHeading(eyebrow: model.tripsEyebrow, title: "Your trips")
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 19)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        if model.isScanningLibrary && model.trips.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(TR.accent)
                                Text("Looking through \(model.libraryPhotoCount) accessible photos…")
                                    .font(TR.ui(13))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 72)
                        } else {
                            ForEach(model.trips) { trip in
                                TripRow(trip: trip) {
                                    model.startBuild(trip: trip)
                                }
                            }
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
        .accessibilityIdentifier("trips-screen")
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
                    MontageView(photos: model.photos, showLabels: false)
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
