import Foundation
import Photos
import PhotosUI
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

enum PhotoSource: Hashable, Sendable {
    case bundled(String)
    case library(String)
    case imported(String)
}

struct TripAsset: Identifiable, Hashable, Sendable {
    let id: String
    let source: PhotoSource
    let creationDate: Date?
    let filename: String
    let isScreenshot: Bool

    init(
        id: String,
        source: PhotoSource,
        creationDate: Date?,
        filename: String,
        isScreenshot: Bool = false
    ) {
        self.id = id
        self.source = source
        self.creationDate = creationDate
        self.filename = filename
        self.isScreenshot = isScreenshot
    }
}

struct Trip: Identifiable, Hashable, Sendable {
    let id: String
    let place: String
    let dates: String
    let startDate: Date
    let endDate: Date
    let assets: [TripAsset]
    let coverID: String

    var photoCount: Int { assets.count }

    var coverSource: PhotoSource {
        assets.first(where: { $0.id == coverID })?.source
            ?? assets.first?.source
            ?? .bundled("my-khe-beach")
    }

    var shortPlace: String {
        place.split(separator: ",", maxSplits: 1).first.map(String.init) ?? place
    }

    func renamed(_ newPlace: String) -> Trip {
        Trip(
            id: id,
            place: newPlace,
            dates: dates,
            startDate: startDate,
            endDate: endDate,
            assets: assets,
            coverID: coverID
        )
    }

    func retainingAssets(withIDs identifiers: Set<String>) -> Trip? {
        let retained = assets.filter { identifiers.contains($0.id) }
        guard !retained.isEmpty else { return nil }
        return Trip(
            id: id,
            place: place,
            dates: dates,
            startDate: startDate,
            endDate: endDate,
            assets: retained,
            coverID: identifiers.contains(coverID) ? coverID : retained[retained.count / 2].id
        )
    }

    func replacingAssets(_ replacement: [TripAsset]) -> Trip? {
        guard !replacement.isEmpty else { return nil }
        let sorted = replacement.sorted {
            switch ($0.creationDate, $1.creationDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return $0.id < $1.id
            }
        }
        return Trip(
            id: id,
            place: place,
            dates: dates,
            startDate: startDate,
            endDate: endDate,
            assets: sorted,
            coverID: sorted.contains(where: { $0.id == coverID })
                ? coverID
                : sorted[sorted.count / 2].id
        )
    }
}

struct ReelPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let source: PhotoSource
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
    let id: String
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
    @Published var cutPhotoIDs: Set<String> = []
    @Published var history: [PhotoDecision] = []
    @Published var pace: Double = 0.46
    @Published var showCutHint = true
    @Published var renderProgress = 0.0
    @Published var titleCards: Set<TitleCardKind> = [.opening]
    @Published var titleText = "My trip"
    @Published var selectedTrackID: String? = "coast"
    @Published var cutToBeat = true
    @Published var selectedFormatID = "sequence"
    @Published var cleanupSelection: Set<String> = []
    @Published var cleanupShowsGrid = false
    @Published var selectedPhotoCount = 0
    @Published var exportQuality: ExportQuality = .standard
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var selectedTrip: Trip?
    @Published private(set) var photos: [ReelPhoto] = []
    @Published private(set) var libraryPreviewPhotos: [ReelPhoto] = []
    @Published private(set) var libraryPhotoCount = 0
    @Published private(set) var isScanningLibrary = false
    @Published private(set) var libraryErrorMessage: String?
    @Published private(set) var cloudAnalysisPreference: CloudAnalysisPreference
    @Published var isCloudAnalysisConsentPresented = false
    @Published private(set) var cloudConsentIsSettings = false
    @Published private(set) var isAnalyzingPhotos = false
    @Published private(set) var photoAnalysisProgress = 0.0
    @Published private(set) var photoAnalysisStatus = "Preparing smart selection"
    @Published private(set) var excludedPhotos: [SmartExcludedPhoto] = []
    @Published var isSmartSelectionReviewPresented = false

    let usesDemoData: Bool

    private let photoLibrary: any PhotoLibraryServing
    private let cloudPhotoAnalysis: any CloudPhotoAnalysisServing
    private let photoAnalysisThumbnails: any PhotoAnalysisThumbnailServing
    private let nativePhotoIntelligence: any NativePhotoIntelligenceServing
    private let preferenceStore: UserDefaults
    private let manualPhotoImporter = ManualPhotoImportService()
    private var workTask: Task<Void, Never>?
    private var photoAnalysisTask: Task<Void, Never>?
    private var photoAnalysisGeneration = UUID()
    private var placeTask: Task<Void, Never>?
    private var detectorTask: Task<[DetectedTrip], Never>?
    private var scanGeneration = UUID()
    private var manualSelectionGeneration = UUID()
    private var pendingResultNavigation = false
    private var isManualSelectionInProgress = false
    private var scanCoordinatorActive = false
    private var scanAgainRequested = false
    private var hasScannedLibrary = false
    private var hasManualSelection = false
    private var hasPermissionFreeSelection = false
    private var lastAuthorizationStatus: PHAuthorizationStatus?
    private let placeResolver = TripPlaceResolver()
    private var resolvedCoordinates: [String: PhotoCoordinate] = [:]
    private var activeImportedPhotos: [ManualImportedPhoto] = []
    private var pendingBuildTrip: Trip?

    private static let cloudPreferenceKey = "tripreel.cloud-photo-analysis-preference.v1"

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        useDemoData: Bool? = nil,
        photoLibrary: (any PhotoLibraryServing)? = nil,
        cloudPhotoAnalysis: (any CloudPhotoAnalysisServing)? = nil,
        photoAnalysisThumbnails: (any PhotoAnalysisThumbnailServing)? = nil,
        nativePhotoIntelligence: (any NativePhotoIntelligenceServing)? = nil,
        preferenceStore: UserDefaults = .standard
    ) {
        let demoMode = useDemoData ?? arguments.contains("-qaScreen")
        usesDemoData = demoMode
        self.photoLibrary = photoLibrary ?? PhotoLibraryService()
        self.cloudPhotoAnalysis = cloudPhotoAnalysis ?? CloudPhotoAnalysisClient()
        self.photoAnalysisThumbnails = photoAnalysisThumbnails ?? PhotoAnalysisThumbnailService()
        self.nativePhotoIntelligence = nativePhotoIntelligence ?? NativePhotoIntelligenceService()
        self.preferenceStore = preferenceStore
        cloudAnalysisPreference = CloudAnalysisPreference(
            rawValue: preferenceStore.string(forKey: Self.cloudPreferenceKey) ?? ""
        ) ?? .undecided

        if demoMode {
            let fixtures = Self.makeDemoTrips()
            trips = fixtures
            selectedTrip = fixtures.first
            photos = fixtures.first.map { Self.makeReelPhotos(from: $0) } ?? []
            libraryPreviewPhotos = Array(photos.prefix(6))
            libraryPhotoCount = fixtures.reduce(0) { $0 + $1.photoCount }
            selectedPhotoCount = 3
            titleText = fixtures.first?.shortPlace ?? "My trip"
        } else {
            self.photoLibrary.onLibraryChange = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          !self.hasPermissionFreeSelection,
                          !self.isManualSelectionInProgress else { return }
                    if self.hasManualSelection {
                        await self.reconcilePhotoKitManualSelection()
                    } else {
                        await self.refreshPhotoLibraryIfAuthorized(force: true)
                    }
                }
            }
        }

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

    var currentPhoto: ReelPhoto {
        guard !photos.isEmpty else { return Self.placeholderPhoto }
        return photos[min(max(0, currentPhotoIndex), photos.count - 1)]
    }

    var keptPhotos: [ReelPhoto] {
        photos.filter { !cutPhotoIDs.contains($0.id) }
    }

    var keptCount: Int { keptPhotos.count }

    var secondsPerPhoto: Double {
        1.85 - (pace * 1.25)
    }

    var durationText: String {
        Self.durationText(photoCount: keptCount, secondsPerPhoto: secondsPerPhoto)
    }

    var rawDurationText: String {
        Self.durationText(photoCount: photos.count, secondsPerPhoto: 4.0 / 3.0)
    }

    var selectedTrack: MusicTrack? {
        tracks.first { $0.id == selectedTrackID }
    }

    var selectedFormat: ProjectFormat {
        formats.first { $0.id == selectedFormatID } ?? formats[0]
    }

    var tripsEyebrow: String {
        if isScanningLibrary { return "Scanning \(libraryPhotoCount) photos" }
        if !usesDemoData {
            return "\(trips.count) trip\(trips.count == 1 ? "" : "s") · \(libraryPhotoCount) photos scanned"
        }
        return "\(trips.count) trip\(trips.count == 1 ? "" : "s") found"
    }

    var tripPlace: String { selectedTrip?.place ?? "Your trip" }
    var tripShortPlace: String { selectedTrip?.shortPlace ?? "Your trip" }
    var tripDates: String { selectedTrip?.dates ?? "Selected photos" }

    var tripMonthYear: String {
        guard let date = selectedTrip?.startDate else { return "Your trip" }
        return Self.monthYearFormatter.string(from: date)
    }

    func previewSource(at index: Int) -> PhotoSource {
        guard !photos.isEmpty else {
            return .bundled(Self.assetNames[index.modulo(Self.assetNames.count)])
        }
        return photos[index.modulo(photos.count)].source
    }

    func go(_ next: AppScreen) {
        workTask?.cancel()
        withAnimation(.easeInOut(duration: 0.32)) {
            screen = next
        }
    }

    func dismissLibraryMessage() {
        libraryErrorMessage = nil
    }

    var cloudAnalysisIsEnabled: Bool {
        cloudAnalysisPreference == .enabled
    }

    var cloudAnalysisIsConfigured: Bool {
        cloudPhotoAnalysis.isConfigured
    }

    var smartSelectionSummary: String? {
        guard !excludedPhotos.isEmpty else { return nil }
        let count = excludedPhotos.count
        return "\(count) photo\(count == 1 ? "" : "s") left in More Photos"
    }

    /// Entry point used by the trip list. It is the only path that can begin an
    /// optional upload, and first use always pauses for explicit consent.
    func requestBuild(trip: Trip) {
        guard !trip.assets.isEmpty else { return }
        if usesDemoData {
            startBuild(trip: trip)
            return
        }

        pendingBuildTrip = trip
        if cloudAnalysisPreference == .undecided {
            cloudConsentIsSettings = false
            isCloudAnalysisConsentPresented = true
        } else {
            beginSmartPhotoSelection(for: trip)
        }
    }

    func presentCloudAnalysisSettings() {
        pendingBuildTrip = nil
        cloudConsentIsSettings = true
        isCloudAnalysisConsentPresented = true
    }

    func useCloudEnhancement() {
        setCloudAnalysisPreference(.enabled)
        isCloudAnalysisConsentPresented = false
        if let trip = pendingBuildTrip {
            pendingBuildTrip = nil
            beginSmartPhotoSelection(for: trip)
        }
    }

    func keepAnalysisOnDevice() {
        setCloudAnalysisPreference(.onDeviceOnly)
        isCloudAnalysisConsentPresented = false
        if let trip = pendingBuildTrip {
            pendingBuildTrip = nil
            beginSmartPhotoSelection(for: trip)
        }
    }

    func cancelPhotoAnalysis() {
        photoAnalysisGeneration = UUID()
        photoAnalysisTask?.cancel()
        photoAnalysisTask = nil
        isAnalyzingPhotos = false
        photoAnalysisProgress = 0
        photoAnalysisStatus = "Preparing smart selection"
    }

    func includeExcludedPhoto(id: String) {
        guard let excludedIndex = excludedPhotos.firstIndex(where: { $0.id == id }),
              let selectedTrip else { return }
        let restored = excludedPhotos.remove(at: excludedIndex)
        guard let updatedTrip = selectedTrip.replacingAssets(selectedTrip.assets + [restored.asset]) else {
            return
        }
        self.selectedTrip = updatedTrip
        photos = Self.makeReelPhotos(from: updatedTrip)
        cutPhotoIDs.formIntersection(Set(photos.map(\.id)))
        currentPhotoIndex = min(currentPhotoIndex, max(0, photos.count - 1))
    }

    private func setCloudAnalysisPreference(_ preference: CloudAnalysisPreference) {
        cloudAnalysisPreference = preference
        preferenceStore.set(preference.rawValue, forKey: Self.cloudPreferenceKey)
    }

    private func beginSmartPhotoSelection(for trip: Trip) {
        photoAnalysisTask?.cancel()
        let generation = UUID()
        photoAnalysisGeneration = generation
        excludedPhotos = []
        photoAnalysisProgress = 0
        photoAnalysisStatus = "Preparing smart selection"

        // The analysis coordinator is installed below; keeping this launch in a
        // cancellable task prevents a second trip tap from racing the first.
        photoAnalysisTask = Task { [weak self] in
            guard let self else { return }
            await self.analyzeAndBuild(trip: trip, generation: generation)
        }
    }

    private func analyzeAndBuild(trip: Trip, generation: UUID) async {
        guard photoAnalysisGeneration == generation else { return }
        isAnalyzingPhotos = true
        var decisions: [String: SmartExcludedPhoto] = [:]
        var pendingCloudBatch: [(asset: TripAsset, jpegData: Data)] = []
        var analyzedCount = 0
        var unavailableCount = 0
        var cloudReviewedCount = 0
        var cloudFailureMessage: String?
        var cloudFailed = false

        for (index, asset) in trip.assets.enumerated() {
            guard photoAnalysisGeneration == generation, !Task.isCancelled else {
                finishPhotoAnalysisCancellation(generation: generation)
                return
            }

            if let metadataDecision = SmartPhotoSelectionPolicy.metadataDecision(for: asset) {
                decisions[asset.id] = metadataDecision
                updatePhotoAnalysisProgress(index: index, total: trip.assets.count)
                continue
            }

            do {
                let thumbnail = try await photoAnalysisThumbnails.prepare(asset: asset)
                let nativeResult = try await nativePhotoIntelligence.analyze(
                    cgImage: thumbnail.cgImage,
                    orientation: .up,
                    metadata: NativePhotoIntelligenceMetadata(
                        sourceIdentifier: asset.id,
                        isScreenshot: asset.isScreenshot
                    )
                )
                analyzedCount += 1

                if let localDecision = SmartPhotoSelectionPolicy.nativeDecision(
                    for: asset,
                    result: nativeResult
                ) {
                    decisions[asset.id] = localDecision
                } else if cloudAnalysisPreference == .enabled,
                          cloudPhotoAnalysis.isConfigured,
                          !cloudFailed,
                          nativeResult.cloudReviewGate.disposition == .eligibleAfterExplicitConsent {
                    pendingCloudBatch.append((asset, thumbnail.jpegData))

                    if pendingCloudBatch.count == CloudPhotoAnalysisClient.maximumBatchSize {
                        do {
                            let reviewed = try await reviewCloudBatch(pendingCloudBatch)
                            cloudReviewedCount += pendingCloudBatch.count
                            for decision in reviewed { decisions[decision.id] = decision }
                            pendingCloudBatch.removeAll(keepingCapacity: false)
                        } catch is CancellationError {
                            finishPhotoAnalysisCancellation(generation: generation)
                            return
                        } catch {
                            cloudFailed = true
                            cloudFailureMessage = "Cloud enhancement wasn't available, so TripReel finished safely on this iPhone."
                            pendingCloudBatch.removeAll(keepingCapacity: false)
                        }
                    }
                }
            } catch is CancellationError {
                finishPhotoAnalysisCancellation(generation: generation)
                return
            } catch {
                // A missing iCloud thumbnail or unsupported image should never
                // remove a memory. It stays in the film by default.
                unavailableCount += 1
            }

            updatePhotoAnalysisProgress(index: index, total: trip.assets.count)
        }

        guard photoAnalysisGeneration == generation, !Task.isCancelled else {
            finishPhotoAnalysisCancellation(generation: generation)
            return
        }

        if !pendingCloudBatch.isEmpty, !cloudFailed {
            photoAnalysisStatus = "Reviewing uncertain photos with GPT-5.6 Luna"
            do {
                let reviewed = try await reviewCloudBatch(pendingCloudBatch)
                cloudReviewedCount += pendingCloudBatch.count
                for decision in reviewed { decisions[decision.id] = decision }
            } catch is CancellationError {
                finishPhotoAnalysisCancellation(generation: generation)
                return
            } catch {
                cloudFailureMessage = "Cloud enhancement wasn't available, so TripReel finished safely on this iPhone."
            }
            pendingCloudBatch.removeAll(keepingCapacity: false)
        } else if cloudAnalysisPreference == .enabled, !cloudPhotoAnalysis.isConfigured {
            cloudFailureMessage = "Cloud enhancement needs a secure service endpoint. TripReel kept this analysis on your iPhone."
        }

        guard photoAnalysisGeneration == generation, !Task.isCancelled else {
            finishPhotoAnalysisCancellation(generation: generation)
            return
        }

        // Never allow automation to create an empty film. If every image was a
        // high-confidence utility photo, keep the middle one and let the user
        // decide in the regular cut flow.
        var includedAssets = trip.assets.filter { decisions[$0.id] == nil }
        if includedAssets.isEmpty, !trip.assets.isEmpty {
            let fallback = trip.assets[trip.assets.count / 2]
            decisions.removeValue(forKey: fallback.id)
            includedAssets = [fallback]
        }
        guard let selected = trip.replacingAssets(includedAssets) else {
            finishPhotoAnalysisCancellation(generation: generation)
            return
        }

        excludedPhotos = trip.assets.compactMap { decisions[$0.id] }
        photoAnalysisProgress = 1
        photoAnalysisStatus = cloudReviewedCount > 0
            ? "Smart selection complete · \(cloudReviewedCount) cloud reviewed"
            : "Smart selection complete on this iPhone"
        isAnalyzingPhotos = false
        photoAnalysisTask = nil

        if let cloudFailureMessage {
            libraryErrorMessage = cloudFailureMessage
        } else if unavailableCount > 0 {
            libraryErrorMessage = "\(unavailableCount) photo\(unavailableCount == 1 ? " was" : "s were") unavailable for analysis and stayed in your film."
        }

        _ = SmartPhotoSelectionOutcome(
            includedAssets: includedAssets,
            excludedPhotos: excludedPhotos,
            analyzedCount: analyzedCount,
            cloudReviewedCount: cloudReviewedCount,
            unavailableCount: unavailableCount
        )
        startBuild(trip: selected)
    }

    private func reviewCloudBatch(
        _ batch: [(asset: TripAsset, jpegData: Data)]
    ) async throws -> [SmartExcludedPhoto] {
        guard !batch.isEmpty else { return [] }
        // Local PhotoKit identifiers and filenames are never sent. Ephemeral
        // per-request IDs are enough to correlate this one in-memory response.
        let wireItems = batch.enumerated().map { index, item in
            (id: "p\(index)", asset: item.asset, jpegData: item.jpegData)
        }
        let results = try await cloudPhotoAnalysis.analyze(
            wireItems.map { CloudPhotoAnalysisInput(id: $0.id, jpegData: $0.jpegData) }
        )
        let assetsByID = Dictionary(uniqueKeysWithValues: wireItems.map { ($0.id, $0.asset) })
        return results.compactMap { result in
            guard let asset = assetsByID[result.id] else { return nil }
            return SmartPhotoSelectionPolicy.cloudDecision(for: asset, result: result)
        }
    }

    private func updatePhotoAnalysisProgress(index: Int, total: Int) {
        let completed = Double(index + 1)
        photoAnalysisProgress = total == 0 ? 1 : min(0.92, completed / Double(total) * 0.92)
        photoAnalysisStatus = "Analyzing \(index + 1) of \(total) on this iPhone"
    }

    private func finishPhotoAnalysisCancellation(generation: UUID) {
        guard photoAnalysisGeneration == generation else { return }
        isAnalyzingPhotos = false
        photoAnalysisProgress = 0
        photoAnalysisStatus = "Preparing smart selection"
        photoAnalysisTask = nil
    }

    func scanPhotoLibrary(navigateToResults: Bool) async {
        guard !usesDemoData else {
            if navigateToResults { showTripResults() }
            return
        }

        pendingResultNavigation = pendingResultNavigation || navigateToResults
        if scanCoordinatorActive {
            scanAgainRequested = true
            return
        }

        scanCoordinatorActive = true
        defer {
            scanCoordinatorActive = false
            scanAgainRequested = false
        }

        var completedGeneration: UUID?
        repeat {
            scanAgainRequested = false
            guard let generation = await performPhotoLibraryScan() else { return }
            completedGeneration = generation
        } while scanAgainRequested && !Task.isCancelled

        guard let completedGeneration, !Task.isCancelled else {
            pendingResultNavigation = false
            return
        }

        if pendingResultNavigation {
            pendingResultNavigation = false
            showTripResults()
        } else if screen == .trips && trips.isEmpty {
            go(.empty)
        } else if screen == .empty && !trips.isEmpty {
            go(.trips)
        }

        placeTask = Task { [weak self] in
            await self?.resolveTripNames(generation: completedGeneration)
        }
    }

    private func performPhotoLibraryScan() async -> UUID? {
        let generation = UUID()
        scanGeneration = generation
        placeTask?.cancel()
        detectorTask?.cancel()
        isScanningLibrary = true
        libraryErrorMessage = nil
        lastAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        defer {
            if scanGeneration == generation {
                isScanningLibrary = false
                if Task.isCancelled {
                    pendingResultNavigation = false
                }
            }
        }

        let metadata = await photoLibrary.fetchAllPhotos()
        guard scanGeneration == generation, !Task.isCancelled else { return nil }

        libraryPhotoCount = metadata.count
        selectedPhotoCount = metadata.count
        libraryPreviewPhotos = Self.makePreviewPhotos(from: metadata)

        let task = Task.detached(priority: .userInitiated) {
            TripDetector.detect(in: metadata, shouldCancel: { Task.isCancelled })
        }
        detectorTask = task
        let detected = await task.value
        if scanGeneration == generation {
            detectorTask = nil
        }
        guard scanGeneration == generation, !Task.isCancelled else { return nil }

        trips = detected.map { Self.makeTrip(from: $0) }
        discardImportedPhotoFiles()
        hasManualSelection = false
        hasPermissionFreeSelection = false
        isManualSelectionInProgress = false
        resolvedCoordinates = Dictionary(
            uniqueKeysWithValues: detected.compactMap { trip in
                trip.centroid.map { (trip.id, $0) }
            }
        )
        reconcileActiveFilm(withAvailableLibraryIDs: Set(metadata.map(\.id)))
        hasScannedLibrary = true
        return generation
    }

    func refreshPhotoLibraryIfAuthorized(force: Bool = false) async {
        guard !usesDemoData else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let previousStatus = lastAuthorizationStatus

        guard status == .authorized || status == .limited else {
            if hasPermissionFreeSelection { return }
            clearLibraryState(afterAuthorizationChangedTo: status)
            return
        }

        if hasManualSelection && !force {
            if !hasPermissionFreeSelection {
                await reconcilePhotoKitManualSelection()
            }
            return
        }

        let upgradedFromLimited = status == .authorized && previousStatus == .limited
        let shouldNavigate = upgradedFromLimited && screen == .limited
        guard force || shouldNavigate || !hasScannedLibrary || previousStatus != status else { return }
        await scanPhotoLibrary(navigateToResults: shouldNavigate)
    }

    @discardableResult
    func loadManualSelection(identifiers: [String]) async -> Bool {
        guard !identifiers.isEmpty else { return false }
        let generation = beginManualSelection()
        defer {
            if manualSelectionGeneration == generation {
                isManualSelectionInProgress = false
            }
        }
        let metadata = await photoLibrary.fetchPhotos(withLocalIdentifiers: identifiers)
        guard manualSelectionGeneration == generation, !Task.isCancelled else { return false }
        guard !metadata.isEmpty, Set(metadata.map(\.id)) == Set(identifiers) else {
            isManualSelectionInProgress = false
            libraryErrorMessage = "Some selected photos are outside TripReel's current Photo Library access. Allow Full Access or add them to Limited Access, then try again."
            return false
        }

        return await installPhotoKitManualSelection(
            metadata: metadata,
            identifiers: identifiers,
            generation: generation
        )
    }

    private func installPhotoKitManualSelection(
        metadata: [PhotoMetadata],
        identifiers: [String],
        generation: UUID
    ) async -> Bool {
        guard manualSelectionGeneration == generation, !Task.isCancelled else { return false }
        invalidateAutomaticScan()
        var order: [String: Int] = [:]
        for (index, identifier) in identifiers.enumerated() where order[identifier] == nil {
            order[identifier] = index
        }
        let sorted = metadata.sorted {
            let left = order[$0.id] ?? .max
            let right = order[$1.id] ?? .max
            return left == right ? $0.id < $1.id : left < right
        }
        let dated = sorted.compactMap(\.creationDate)
        let startDate = dated.min() ?? Date()
        let endDate = dated.max() ?? startDate
        let assets = sorted.map {
            TripAsset(
                id: $0.id,
                source: .library($0.id),
                creationDate: $0.creationDate,
                filename: $0.filename,
                isScreenshot: $0.isScreenshot
            )
        }
        let coordinate = sorted.compactMap(\.coordinate).first
        return await installManualTrip(
            assets: assets,
            startDate: startDate,
            endDate: endDate,
            coordinate: coordinate,
            importedPhotos: [],
            generation: generation
        )
    }

    /// Imports picker items directly when PhotoKit identifiers are unavailable
    /// or outside the current Limited-access set. This keeps the manual picker
    /// useful even when the user declines library-wide access.
    @discardableResult
    func loadManualSelection(items: [PhotosPickerItem]) async -> Bool {
        guard !items.isEmpty else { return false }
        let generation = beginManualSelection()
        defer {
            if manualSelectionGeneration == generation {
                isManualSelectionInProgress = false
            }
        }

        let identifiers = items.compactMap(\.itemIdentifier)
        if identifiers.count == items.count {
            let metadata = await photoLibrary.fetchPhotos(withLocalIdentifiers: identifiers)
            guard manualSelectionGeneration == generation, !Task.isCancelled else { return false }
            if Set(metadata.map(\.id)) == Set(identifiers) {
                return await installPhotoKitManualSelection(
                    metadata: metadata,
                    identifiers: identifiers,
                    generation: generation
                )
            }
        }

        let result = await manualPhotoImporter.importItems(items)
        guard manualSelectionGeneration == generation, !Task.isCancelled else {
            await manualPhotoImporter.removeImportedFiles(for: result.photos)
            return false
        }
        invalidateAutomaticScan()

        var seen = Set<String>()
        let imported = result.photos.filter { seen.insert($0.id).inserted }
        guard !imported.isEmpty else {
            isManualSelectionInProgress = false
            libraryErrorMessage = "TripReel couldn't import the selected photos. Check your iCloud connection and try again."
            return false
        }

        let assets = imported.map { photo in
            TripAsset(
                id: photo.id,
                source: .imported(photo.filePath),
                creationDate: photo.creationDate,
                filename: photo.filename
            )
        }
        let dated = imported.compactMap(\.creationDate)
        let startDate = dated.min() ?? Date()
        let endDate = dated.max() ?? startDate
        if result.failureCount > 0 {
            libraryErrorMessage = "Imported \(imported.count) photos. \(result.failureCount) couldn't be downloaded from Photos; you can try those again when iCloud is available."
        }

        return await installManualTrip(
            assets: assets,
            startDate: startDate,
            endDate: endDate,
            coordinate: imported.compactMap(\.coordinate).first,
            importedPhotos: imported,
            generation: generation
        )
    }

    private func installManualTrip(
        assets: [TripAsset],
        startDate: Date,
        endDate: Date,
        coordinate: PhotoCoordinate?,
        importedPhotos: [ManualImportedPhoto],
        generation: UUID
    ) async -> Bool {
        guard !assets.isEmpty,
              manualSelectionGeneration == generation,
              !Task.isCancelled else {
            if !importedPhotos.isEmpty {
                await manualPhotoImporter.removeImportedFiles(for: importedPhotos)
            }
            return false
        }
        let trip = Trip(
            id: "manual-\(assets[0].id)",
            place: "Selected photos",
            dates: Self.dateText(from: startDate, to: endDate),
            startDate: startDate,
            endDate: endDate,
            assets: assets,
            coverID: assets[assets.count / 2].id
        )

        discardImportedPhotoFiles()
        activeImportedPhotos = importedPhotos
        hasManualSelection = true
        hasPermissionFreeSelection = !importedPhotos.isEmpty
        isManualSelectionInProgress = false
        trips = [trip]
        selectedTrip = nil
        photos = []
        selectedPhotoCount = assets.count
        libraryPhotoCount = max(libraryPhotoCount, assets.count)
        libraryPreviewPhotos = Array(Self.makeReelPhotos(from: trip).prefix(6))
        hasScannedLibrary = true
        isScanningLibrary = false
        showTripResults()

        if let coordinate,
           let name = await placeResolver.placeName(for: coordinate),
           manualSelectionGeneration == generation,
           trips.first?.id == trip.id {
            let renamed = trip.renamed(name)
            trips[0] = renamed
            if selectedTrip?.id == trip.id { selectedTrip = renamed }
        }
        return true
    }

    func showTripResults() {
        go(trips.isEmpty ? .empty : .trips)
    }

    func startBuild(trip: Trip) {
        guard !trip.assets.isEmpty else { return }
        selectedTrip = trip
        photos = Self.makeReelPhotos(from: trip)
        titleText = trip.shortPlace
        workTask?.cancel()
        buildCount = 0
        currentPhotoIndex = 0
        cutPhotoIDs = []
        history = []
        cleanupSelection = []
        go(.building)

        let total = photos.count
        let steps = min(30, max(1, total))
        workTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                let currentTotal = self.photos.count
                self.buildCount = min(currentTotal, Int(ceil(Double(total * step) / Double(steps))))
            }
            self.buildCount = self.photos.count
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            self.go(.firstWatch)
        }
    }

    func startBuild() {
        guard let trip = selectedTrip ?? trips.first else { return }
        startBuild(trip: trip)
    }

    func decideCurrentPhoto(cut: Bool) {
        guard !photos.isEmpty else { return }
        decidePhoto(id: currentPhoto.id, cut: cut)
    }

    func decidePhoto(id: String, cut: Bool) {
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

    private func resolveTripNames(generation: UUID) async {
        let tripIDs = trips.map(\.id)
        for tripID in tripIDs {
            guard !Task.isCancelled, scanGeneration == generation else { return }
            guard trips.contains(where: { $0.id == tripID }) else { continue }
            guard let detectedCoordinate = resolvedCoordinates[tripID] else { continue }
            guard let name = await placeResolver.placeName(for: detectedCoordinate) else { continue }
            guard !Task.isCancelled, scanGeneration == generation else { return }
            guard let currentIndex = trips.firstIndex(where: { $0.id == tripID }) else { continue }
            let renamed = trips[currentIndex].renamed(name)
            trips[currentIndex] = renamed
            if selectedTrip?.id == tripID { selectedTrip = renamed }
        }
    }

    func clearLibraryState(afterAuthorizationChangedTo status: PHAuthorizationStatus) {
        cancelPhotoAnalysis()
        pendingBuildTrip = nil
        isCloudAnalysisConsentPresented = false
        cloudConsentIsSettings = false
        isSmartSelectionReviewPresented = false
        excludedPhotos = []
        scanGeneration = UUID()
        pendingResultNavigation = false
        scanAgainRequested = false
        detectorTask?.cancel()
        detectorTask = nil
        placeTask?.cancel()
        lastAuthorizationStatus = status
        hasScannedLibrary = false
        hasManualSelection = false
        hasPermissionFreeSelection = false
        isScanningLibrary = false
        trips = []
        selectedTrip = nil
        photos = []
        libraryPreviewPhotos = []
        libraryPhotoCount = 0
        selectedPhotoCount = 0
        resolvedCoordinates = [:]
        cutPhotoIDs = []
        history = []

        if screen != .welcome && screen != .access {
            go(.access)
        }
    }

    @discardableResult
    private func beginManualSelection() -> UUID {
        let generation = UUID()
        manualSelectionGeneration = generation
        isManualSelectionInProgress = true
        invalidateAutomaticScan()
        libraryErrorMessage = nil
        return generation
    }

    private func invalidateAutomaticScan() {
        scanGeneration = UUID()
        pendingResultNavigation = false
        scanAgainRequested = false
        detectorTask?.cancel()
        detectorTask = nil
        placeTask?.cancel()
        isScanningLibrary = false
    }

    private func discardImportedPhotoFiles() {
        guard !activeImportedPhotos.isEmpty else { return }
        let discarded = activeImportedPhotos
        activeImportedPhotos = []
        Task { [manualPhotoImporter] in
            await manualPhotoImporter.removeImportedFiles(for: discarded)
        }
    }

    private func reconcilePhotoKitManualSelection() async {
        guard hasManualSelection,
              !hasPermissionFreeSelection,
              !isManualSelectionInProgress,
              let manualTrip = trips.first else { return }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            clearLibraryState(afterAuthorizationChangedTo: status)
            return
        }

        let generation = manualSelectionGeneration
        let identifiers = manualTrip.assets.compactMap { asset -> String? in
            if case let .library(identifier) = asset.source { return identifier }
            return nil
        }
        guard !identifiers.isEmpty else { return }

        let availableMetadata = await photoLibrary.fetchPhotos(withLocalIdentifiers: identifiers)
        guard manualSelectionGeneration == generation,
              hasManualSelection,
              !Task.isCancelled else { return }

        let availableIDs = Set(availableMetadata.map(\.id))
        guard availableIDs.count != Set(identifiers).count else { return }
        let removedCount = Set(identifiers).subtracting(availableIDs).count
        let retainedTrip = manualTrip.retainingAssets(withIDs: availableIDs)

        trips = retainedTrip.map { [$0] } ?? []
        selectedPhotoCount = retainedTrip?.photoCount ?? 0
        libraryPreviewPhotos = retainedTrip.map {
            Array(Self.makeReelPhotos(from: $0).prefix(6))
        } ?? []
        if selectedTrip?.id == manualTrip.id {
            selectedTrip = retainedTrip
        }
        libraryErrorMessage = "\(removedCount) selected photo\(removedCount == 1 ? " is" : "s are") no longer available and \(removedCount == 1 ? "was" : "were") removed."
        reconcileActiveFilm(withAvailableLibraryIDs: availableIDs)

        if retainedTrip == nil {
            hasManualSelection = false
            hasScannedLibrary = false
            if photos.isEmpty {
                go(.empty)
            }
        }
    }

    private func reconcileActiveFilm(withAvailableLibraryIDs availableIDs: Set<String>) {
        guard !photos.isEmpty else { return }

        let retainedPhotoIDs = Set(photos.compactMap { photo -> String? in
            switch photo.source {
            case .bundled:
                return photo.id
            case let .library(identifier):
                return availableIDs.contains(identifier) ? photo.id : nil
            case .imported:
                return photo.id
            }
        })
        guard retainedPhotoIDs.count != photos.count else { return }

        photos.removeAll { !retainedPhotoIDs.contains($0.id) }
        cutPhotoIDs.formIntersection(retainedPhotoIDs)
        cleanupSelection.formIntersection(retainedPhotoIDs)
        history.removeAll { !retainedPhotoIDs.contains($0.id) }
        currentPhotoIndex = min(currentPhotoIndex, max(0, photos.count - 1))
        buildCount = min(buildCount, photos.count)
        selectedTrip = selectedTrip?.retainingAssets(withIDs: retainedPhotoIDs)

        guard !photos.isEmpty else {
            workTask?.cancel()
            selectedTrip = nil
            go(trips.isEmpty ? .empty : .trips)
            return
        }

        libraryErrorMessage = "Some photos in this film are no longer available, so TripReel removed those frames."
    }

    private static func makeTrip(from detected: DetectedTrip) -> Trip {
        let assets = detected.photos.map {
            TripAsset(
                id: $0.id,
                source: .library($0.id),
                creationDate: $0.creationDate,
                filename: $0.filename,
                isScreenshot: $0.isScreenshot
            )
        }
        let fallbackPlace = detected.centroid == nil
            ? "Photo trip"
            : "Travel · \(monthYearFormatter.string(from: detected.startDate))"
        return Trip(
            id: detected.id,
            place: fallbackPlace,
            dates: dateText(from: detected.startDate, to: detected.endDate),
            startDate: detected.startDate,
            endDate: detected.endDate,
            assets: assets,
            coverID: detected.coverID
        )
    }

    private static func makePreviewPhotos(from metadata: [PhotoMetadata]) -> [ReelPhoto] {
        let assets = metadata.suffix(6).map {
            TripAsset(
                id: $0.id,
                source: .library($0.id),
                creationDate: $0.creationDate,
                filename: $0.filename,
                isScreenshot: $0.isScreenshot
            )
        }
        return makeReelPhotos(
            from: Trip(
                id: "library-preview",
                place: "Library",
                dates: "",
                startDate: Date(),
                endDate: Date(),
                assets: assets,
                coverID: assets.first?.id ?? ""
            )
        )
    }

    private static func makeReelPhotos(from trip: Trip) -> [ReelPhoto] {
        trip.assets.enumerated().map { index, asset in
            let fallbackLabel = "PHOTO_\(String(format: "%04d", index + 1))"
            let label = asset.filename.isEmpty ? fallbackLabel : asset.filename
            return ReelPhoto(
                id: asset.id,
                source: asset.source,
                label: label,
                time: asset.creationDate.map(timeFormatter.string) ?? "—",
                isSimilar: {
                    if case .bundled = asset.source { return index % 4 == 1 }
                    return false
                }()
            )
        }
    }

    private static func makeDemoTrips() -> [Trip] {
        [
            makeDemoTrip(id: "da-nang", place: "Da Nang, Vietnam", dates: "Aug 2 – Aug 9, 2026", count: 84, start: date(2026, 8, 2), end: date(2026, 8, 9), coverName: "my-khe-beach"),
            makeDemoTrip(id: "kyoto", place: "Kyoto, Japan", dates: "Apr 11 – Apr 18, 2026", count: 212, start: date(2026, 4, 11), end: date(2026, 4, 18), coverName: "hoi-an-lanes"),
            makeDemoTrip(id: "lisbon", place: "Lisbon, Portugal", dates: "Nov 3 – Nov 8, 2025", count: 96, start: date(2025, 11, 3), end: date(2025, 11, 8), coverName: "night-market"),
            makeDemoTrip(id: "big-sur", place: "Big Sur, California", dates: "Jun 21 – Jun 23, 2025", count: 41, start: date(2025, 6, 21), end: date(2025, 6, 23), coverName: "han-river")
        ]
    }

    private static func makeDemoTrip(
        id: String,
        place: String,
        dates: String,
        count: Int,
        start: Date,
        end: Date,
        coverName: String
    ) -> Trip {
        let duration = end.timeIntervalSince(start)
        let assets = (0..<count).map { index in
            let imageName = assetNames[index % assetNames.count]
            let progress = count <= 1 ? 0 : Double(index) / Double(count - 1)
            return TripAsset(
                id: "demo-\(id)-\(index)",
                source: .bundled(imageName),
                creationDate: start.addingTimeInterval(duration * progress),
                filename: "IMG_\(2140 + index)"
            )
        }
        let coverID = assets.first(where: {
            if case let .bundled(name) = $0.source { return name == coverName }
            return false
        })?.id ?? assets[0].id
        return Trip(
            id: "demo-\(id)",
            place: place,
            dates: dates,
            startDate: start,
            endDate: end,
            assets: assets,
            coverID: coverID
        )
    }

    private static func durationText(photoCount: Int, secondsPerPhoto: Double) -> String {
        let seconds = max(1, Int((Double(photoCount) * secondsPerPhoto).rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private static func dateText(from startDate: Date, to endDate: Date) -> String {
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return singleDateFormatter.string(from: startDate)
        }
        return intervalFormatter.string(from: startDate, to: endDate)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 8))!
    }

    private static let placeholderPhoto = ReelPhoto(
        id: "placeholder",
        source: .bundled("my-khe-beach"),
        label: "PHOTO",
        time: "—",
        isSimilar: false
    )

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return formatter
    }()

    private static let singleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        return formatter
    }()

    private static let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
