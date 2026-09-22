import Foundation

/// A quiet environmental layer mixed beneath music and original clip audio.
/// Every bundled recording is curated once and remains available offline.
struct MemoryAtmosphere: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let resourceName: String
    let sourceTitle: String
    let sourcePageURL: String
    let sourceAssetURL: String

    var bundledURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "m4a")
            ?? Bundle.main.url(
                forResource: resourceName,
                withExtension: "m4a",
                subdirectory: "Atmospheres"
            )
    }
}

enum MemoryAtmosphereCatalog {
    static let licenseName = "Mixkit Sound Effects Free License"
    static let licenseURL = "https://mixkit.co/license/#sfxFree"
    static let curatedOn = "2026-09-22"

    static let all: [MemoryAtmosphere] = [
        atmosphere(
            id: "city-day",
            name: "City in Motion",
            detail: "Street life and distant traffic",
            symbol: "building.2",
            sourceTitle: "City traffic background ambience",
            category: "city",
            assetID: 2930
        ),
        atmosphere(
            id: "city-night",
            name: "City After Dark",
            detail: "A soft, rain-lit night in the city",
            symbol: "moon.stars",
            sourceTitle: "Urban city ambience at night",
            category: "city",
            assetID: 2678
        ),
        atmosphere(
            id: "coast",
            name: "By the Sea",
            detail: "Rolling waves and distant birds",
            symbol: "water.waves",
            sourceTitle: "Sea waves with birds loop",
            category: "beach",
            assetID: 1185
        ),
        atmosphere(
            id: "forest",
            name: "Among the Trees",
            detail: "Birdsong beneath a quiet forest canopy",
            symbol: "leaf",
            sourceTitle: "Forest birds ambience",
            category: "forest",
            assetID: 1210
        ),
        atmosphere(
            id: "river",
            name: "Flowing Water",
            detail: "A steady river moving through the story",
            symbol: "drop",
            sourceTitle: "River water flowing",
            category: "rivers",
            assetID: 2454
        ),
        atmosphere(
            id: "rain",
            name: "After the Rain",
            detail: "A gentle rain bed",
            symbol: "cloud.rain",
            sourceTitle: "Light rain loop",
            category: "nature",
            assetID: 2393
        ),
        atmosphere(
            id: "gathering",
            name: "Together",
            detail: "Warm restaurant and gathering ambience",
            symbol: "person.3",
            sourceTitle: "Restaurant crowd talking ambience",
            category: "crowd",
            assetID: 444
        ),
        atmosphere(
            id: "airport",
            name: "The Journey Begins",
            detail: "The gentle movement of a departures hall",
            symbol: "airplane.departure",
            sourceTitle: "Airport departures hall",
            category: "airport",
            assetID: 357
        )
    ]

    static func atmosphere(withID id: String?) -> MemoryAtmosphere? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Selects a broad soundscape without sending coordinates, place names, or
    /// image labels off the device. Strong image evidence wins over a generic
    /// place name; location keywords help when the image set is ambiguous.
    static func recommended(
        place: String?,
        insights: [MontagePhotoInsight],
        captureDates: [Date],
        calendar: Calendar = .current
    ) -> MemoryAtmosphere {
        var scores = Dictionary(uniqueKeysWithValues: all.map { ($0.id, 0.0) })
        var evidence = normalized(place ?? "")
        for insight in insights {
            for classification in insight.classifications where classification.confidence >= 0.08 {
                evidence += " " + normalized(classification.identifier)
            }
            switch insight.contentKind {
            case .food:
                scores["gathering", default: 0] += 1.3
            case .people:
                scores["gathering", default: 0] += 0.65
            case .scenery:
                scores["forest", default: 0] += 0.18
            case .moment:
                break
            }
        }

        add(7, to: "airport", whenAny: ["airport", "airplane", "aircraft", "terminal", "runway"], in: evidence, scores: &scores)
        add(6, to: "coast", whenAny: ["beach", "coast", "ocean", "sea", "seaside", "shore", "island"], in: evidence, scores: &scores)
        add(6, to: "river", whenAny: ["river", "stream", "waterfall", "lake", "canal", "harbour", "harbor"], in: evidence, scores: &scores)
        add(6, to: "forest", whenAny: ["forest", "woods", "jungle", "tree", "mountain", "trail", "garden", "park"], in: evidence, scores: &scores)
        add(7, to: "rain", whenAny: ["rain", "rainy", "storm", "drizzle", "umbrella"], in: evidence, scores: &scores)
        add(4, to: "gathering", whenAny: ["restaurant", "market", "food", "dining", "festival", "party", "celebration", "crowd"], in: evidence, scores: &scores)
        add(3, to: "city-day", whenAny: ["city", "street", "downtown", "building", "urban", "traffic"], in: evidence, scores: &scores)

        let nightCount = captureDates.lazy.map { calendar.component(.hour, from: $0) }
            .filter { $0 >= 18 || $0 < 6 }.count
        let mostlyNight = !captureDates.isEmpty && nightCount * 2 >= captureDates.count
        if mostlyNight {
            scores["city-night", default: 0] += 4
            scores["city-day", default: 0] -= 1
        }

        let fallbackID: String
        let kinds = insights.map(\.contentKind)
        if kinds.contains(.food) || kinds.filter({ $0 == .people }).count * 3 >= max(1, kinds.count) {
            fallbackID = "gathering"
        } else if kinds.filter({ $0 == .scenery }).count * 2 >= max(1, kinds.count) {
            fallbackID = "forest"
        } else {
            fallbackID = mostlyNight ? "city-night" : "city-day"
        }

        let winner = scores.max { left, right in
            if left.value == right.value { return left.key > right.key }
            return left.value < right.value
        }
        let selectedID = (winner?.value ?? 0) >= 0.8 ? winner?.key : fallbackID
        return atmosphere(withID: selectedID) ?? all[0]
    }

    private static func atmosphere(
        id: String,
        name: String,
        detail: String,
        symbol: String,
        sourceTitle: String,
        category: String,
        assetID: Int
    ) -> MemoryAtmosphere {
        MemoryAtmosphere(
            id: id,
            name: name,
            detail: detail,
            symbol: symbol,
            resourceName: id,
            sourceTitle: sourceTitle,
            sourcePageURL: "https://mixkit.co/free-sound-effects/\(category)/",
            sourceAssetURL: "https://assets.mixkit.co/active_storage/sfx/\(assetID)/\(assetID)-preview.mp3"
        )
    }

    private static func add(
        _ value: Double,
        to id: String,
        whenAny terms: [String],
        in evidence: String,
        scores: inout [String: Double]
    ) {
        let paddedEvidence = " \(evidence) "
        let matches = terms.filter { term in
            paddedEvidence.contains(" \(normalized(term)) ")
        }.count
        guard matches > 0 else { return }
        scores[id, default: 0] += value + Double(matches - 1) * 0.65
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }
}
