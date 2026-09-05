import Foundation
import SwiftUI

enum AppScreen: String {
    case welcome
    case access
    case limited
    case trips
    case empty
    case building
    case firstWatch
    case cut
    case pace
    case secondWatch
    case export
    case paywall
    case rendering
    case done
    case cleanup
}

struct Trip: Identifiable, Hashable {
    let id = UUID()
    let place: String
    let dates: String
    let photoCount: Int
    let imageName: String
}

struct ReelPhoto: Identifiable, Hashable {
    let id: Int
    let imageName: String
    let label: String
    let time: String
    let isSimilar: Bool
}

enum TitleCardKind: String, CaseIterable, Identifiable {
    case opening
    case place
    case ending

    var id: String { rawValue }

    var name: String {
        switch self {
        case .opening: "Opening title"
        case .place: "Place card"
        case .ending: "End card"
        }
    }

    var placement: String {
        switch self {
        case .opening: "Before the first photo"
        case .place: "When the location changes"
        case .ending: "After the last photo"
        }
    }
}

struct MusicTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let mood: String
    let bpm: String
    let symbol: String
    let tint: Color
    let bars: [CGFloat]
}

struct ProjectFormat: Identifiable, Hashable {
    let id: String
    let name: String
    let apps: String
    let fileExtension: String
}

struct PhotoDecision: Equatable {
    let id: Int
    let previousIndex: Int
    let previousWasCut: Bool
}

enum ExportQuality: Equatable {
    case standard
    case hd

    var includesWatermark: Bool { self == .standard }
}

@MainActor
final class TripReelModel: ObservableObject {
    @Published var screen: AppScreen = .welcome
    @Published var buildCount = 0
    @Published var currentPhotoIndex = 0
    @Published var cutPhotoIDs: Set<Int> = []
    @Published var history: [PhotoDecision] = []
    @Published var pace: Double = 0.46
    @Published var showCutHint = true
    @Published var renderProgress = 0.0
    @Published var titleCards: Set<TitleCardKind> = [.opening]
    @Published var titleText = "Da Nang"
    @Published var selectedTrackID: String? = "coast"
    @Published var cutToBeat = true
    @Published var selectedFormatID = "sequence"
    @Published var cleanupSelection: Set<Int> = []
    @Published var cleanupShowsGrid = false
    @Published var selectedPhotoCount = 3
    @Published var exportQuality: ExportQuality = .standard

    private var workTask: Task<Void, Never>?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
#if DEBUG
        if let flagIndex = arguments.firstIndex(of: "-qaScreen"),
           arguments.indices.contains(flagIndex + 1),
           let requestedScreen = AppScreen(rawValue: arguments[flagIndex + 1]) {
            screen = requestedScreen
        }
        if arguments.contains("-qaNoHint") {
            showCutHint = false
        }
#endif
    }

    static let assetNames = [
        "my-khe-beach",
        "street-food",
        "golden-bridge",
        "hoi-an-lanes",
        "night-market",
        "han-river"
    ]

    static let photoLabels = [
        "MY KHE BEACH",
        "STREET FOOD, 8PM",
        "GOLDEN BRIDGE",
        "HOI AN LANES",
        "NIGHT MARKET",
        "HAN RIVER BOAT"
    ]

    let trips = [
        Trip(place: "Da Nang, Vietnam", dates: "Aug 2 – Aug 9, 2026", photoCount: 84, imageName: "my-khe-beach"),
        Trip(place: "Kyoto, Japan", dates: "Apr 11 – Apr 18, 2026", photoCount: 212, imageName: "hoi-an-lanes"),
        Trip(place: "Lisbon, Portugal", dates: "Nov 3 – Nov 8, 2025", photoCount: 96, imageName: "night-market"),
        Trip(place: "Big Sur, California", dates: "Jun 21 – Jun 23, 2025", photoCount: 41, imageName: "han-river")
    ]

    let tracks = [
        MusicTrack(id: "drift", name: "Slow Drift", mood: "Ambient piano", bpm: "72", symbol: "waveform", tint: Color(red: 0.56, green: 0.70, blue: 0.86), bars: [8, 15, 11, 20, 13]),
        MusicTrack(id: "coast", name: "Coast Road", mood: "Warm indie guitar", bpm: "96", symbol: "guitars", tint: TR.accent, bars: [12, 21, 15, 25, 18]),
        MusicTrack(id: "market", name: "Night Market", mood: "Percussive, bright", bpm: "118", symbol: "music.quarternote.3", tint: Color(red: 0.88, green: 0.54, blue: 0.42), bars: [17, 26, 20, 29, 23]),
        MusicTrack(id: "pulse", name: "Pulse", mood: "Electronic, driving", bpm: "128", symbol: "waveform.path.ecg", tint: Color(red: 0.71, green: 0.56, blue: 0.86), bars: [21, 28, 23, 29, 26]),
        MusicTrack(id: "none", name: "No music", mood: "Just the cut", bpm: "—", symbol: "speaker.slash", tint: Color.white.opacity(0.35), bars: [4, 4, 4, 4, 4])
    ]

    let formats = [
        ProjectFormat(id: "sequence", name: "Photo sequence + timing sheet", apps: "CapCut, InShot, anything", fileExtension: "ZIP"),
        ProjectFormat(id: "fcpxml", name: "Final Cut XML", apps: "Final Cut Pro, DaVinci Resolve", fileExtension: "FCPXML"),
        ProjectFormat(id: "edl", name: "Edit decision list", apps: "Premiere Pro, Avid", fileExtension: "EDL")
    ]

    lazy var photos: [ReelPhoto] = (0..<84).map { index in
        let assetIndex = index % Self.assetNames.count
        let hour = 7 + ((index * 3) % 12)
        let minute = (index * 17) % 60
        return ReelPhoto(
            id: index,
            imageName: Self.assetNames[assetIndex],
            label: "IMG_\(2140 + index)",
            time: String(format: "%02d:%02d", hour, minute),
            isSimilar: index % 4 == 1
        )
    }

    var currentPhoto: ReelPhoto {
        photos[min(currentPhotoIndex, photos.count - 1)]
    }

    var keptCount: Int {
        photos.count - cutPhotoIDs.count
    }

    var secondsPerPhoto: Double {
        1.85 - (pace * 1.25)
    }

    var durationText: String {
        let seconds = max(1, Int((Double(keptCount) * secondsPerPhoto).rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    var selectedTrack: MusicTrack? {
        tracks.first { $0.id == selectedTrackID }
    }

    var selectedFormat: ProjectFormat {
        formats.first { $0.id == selectedFormatID } ?? formats[0]
    }

    func go(_ next: AppScreen) {
        workTask?.cancel()
        withAnimation(.easeInOut(duration: 0.32)) {
            screen = next
        }
    }

    func startBuild() {
        workTask?.cancel()
        buildCount = 0
        currentPhotoIndex = 0
        cutPhotoIDs = []
        history = []
        go(.building)
        workTask = Task { [weak self] in
            guard let self else { return }
            for count in stride(from: 3, through: 84, by: 3) {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                self.buildCount = count
            }
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            self.go(.firstWatch)
        }
    }

    func decideCurrentPhoto(cut: Bool) {
        decidePhoto(id: currentPhoto.id, cut: cut)
    }

    func decidePhoto(id: Int, cut: Bool) {
        guard let photoIndex = photos.firstIndex(where: { $0.id == id }) else { return }

        history.append(
            PhotoDecision(
                id: id,
                previousIndex: currentPhotoIndex,
                previousWasCut: cutPhotoIDs.contains(id)
            )
        )

        if cut {
            cutPhotoIDs.insert(id)
        } else {
            cutPhotoIDs.remove(id)
        }

        if photoIndex >= photos.count - 1 {
            go(.pace)
        } else {
            currentPhotoIndex = photoIndex + 1
        }
    }

    func undoLastDecision() {
        guard let last = history.popLast() else { return }
        if last.previousWasCut {
            cutPhotoIDs.insert(last.id)
        } else {
            cutPhotoIDs.remove(last.id)
        }
        currentPhotoIndex = last.previousIndex
    }

    func selectTrack(_ track: MusicTrack) {
        if track.id == "none" {
            selectedTrackID = nil
            cutToBeat = false
        } else {
            selectedTrackID = track.id
        }
    }

    func startRender(hd: Bool = false) {
        workTask?.cancel()
        exportQuality = hd ? .hd : .standard
        renderProgress = 0
        go(.rendering)
        workTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...40 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                self.renderProgress = Double(step) / 40.0
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.go(.done)
        }
    }

    func restart() {
        cleanupSelection = []
        cleanupShowsGrid = false
        showCutHint = true
        go(.trips)
    }
}
