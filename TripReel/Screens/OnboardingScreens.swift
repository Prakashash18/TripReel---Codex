import Photos
import PhotosUI
import SwiftUI
import UIKit

struct WelcomeScreen: View {
    @EnvironmentObject private var model: TripReelModel

    var body: some View {
        ZStack {
            MontageView(dim: true)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, Color(red: 0.08, green: 0.035, blue: 0.015).opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    MetadataText(text: "TripReel", color: .white.opacity(0.64))

                    VStack(alignment: .leading, spacing: -15) {
                        Text("Turn your trip photos")
                            .font(TR.display(44))
                        Text("into a film you")
                            .font(TR.display(44))
                        Text("actually control")
                            .font(TR.displayItalic(44))
                    }
                        .tracking(-0.65)
                        .foregroundStyle(TR.cream)
                }

                Button("Get started") {
                    model.go(.access)
                }
                .buttonStyle(CreamButtonStyle())
            }
            .padding(.horizontal, 30)
            .safeAreaPadding(.bottom, 12)
        }
        .accessibilityIdentifier("welcome-screen")
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
            model.selectedPhotoCount = newItems.count
            model.go(.limited)
        }
        .alert("Photo access is off", isPresented: $showAccessDenied) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow TripReel to read your photos in Settings, or choose photos manually instead.")
        }
        .accessibilityIdentifier("photo-access-screen")
    }

    private func accessContent(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: compact ? 8 : 42)

            VStack(spacing: compact ? 14 : 24) {
                VStack(spacing: compact ? 6 : 11) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Photo access")
                        .font(TR.ui(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.63))
                }

                Text("Let TripReel find your trips")
                    .font(TR.display(compact ? 32 : 38))
                    .tracking(-0.38)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                MontageView(showLabels: false)
                    .frame(width: compact ? 134 : 184, height: compact ? 169 : 232)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 26, y: 18)

                Text("We look at where and when your photos were taken to find your trips. Nothing leaves your phone.")
                    .font(TR.ui(compact ? 13 : 15))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(compact ? 2 : 5)
                    .frame(maxWidth: 300)
            }

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
                        Text(requestingAccess ? "Opening Photos…" : "Allow photo access")
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
                    maxSelectionCount: 84,
                    matching: .images
                )
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, compact ? 0 : 20)
        .safeAreaPadding(.vertical)
        .offset(y: compact ? 0 : 24)
    }

    private func requestAccess() {
        requestingAccess = true
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                requestingAccess = false
                switch status {
                case .authorized:
                    model.go(.trips)
                case .limited:
                    model.go(.limited)
                case .denied, .restricted, .notDetermined:
                    showAccessDenied = true
                @unknown default:
                    showAccessDenied = true
                }
            }
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
                                if index < 3 {
                                    PhotoAssetView(imageName: TripReelModel.assetNames[index])
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(.white.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                }
                            }
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Text("TripReel can't look for trips in the rest of your library, so some films will be missing.")
                        .font(TR.ui(15))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 300)
                }

                Spacer(minLength: 48)

                VStack(spacing: 16) {
                    Button("Expand access") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                    .buttonStyle(CreamButtonStyle())

                    Button("Continue with \(model.selectedPhotoCount) photos") {
                        model.go(.trips)
                    }
                    .font(TR.ui(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.57))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
            .safeAreaPadding(.vertical)
        }
        .accessibilityIdentifier("limited-access-screen")
    }
}
