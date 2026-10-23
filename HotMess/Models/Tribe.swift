//
//  Tribe.swift
//  HotMess
//

import Foundation

/// One of the audience's curated tribes, as the picker lists it (a tag with
/// `tribe` set).
struct Tribe: Hashable, Sendable, Identifiable, Decodable {
    let id: String
    let name: String
}

/// A group of tribes in the picker: "Arts and culture", or "More" for the
/// ones the audience made itself.
struct TribeCategory: Hashable, Sendable, Identifiable, Decodable {
    let key: String
    let name: String
    let tribes: [Tribe]

    var id: String { key }
}

/// The picker's whole list, how many anyone may pick, and the user's picks.
struct TribeChoices: Hashable, Sendable {
    var categories: [TribeCategory]
    /// `max(1, floor(N / 4))` of the N tribes, from the API.
    var cap: Int
    /// The tribes the user picked, by ID.
    var picked: Set<String>

    var all: [Tribe] { categories.flatMap(\.tribes) }

    /// The picked tribes by name, for the "Your picks" chips.
    var pickedTribes: [Tribe] {
        all.filter { picked.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var isAtCap: Bool { picked.count >= cap }

    /// A search result: the tribe and its category's name.
    struct Match: Hashable, Sendable, Identifiable {
        let tribe: Tribe
        let category: String

        var id: String { tribe.id }
    }

    /// Tribes whose name contains the search, by name.
    func matching(_ search: String) -> [Match] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return categories.flatMap { category in
            category.tribes
                .filter { $0.name.localizedStandardContains(query) }
                .map { Match(tribe: $0, category: category.name) }
        }
        .sorted { $0.tribe.name.localizedStandardCompare($1.tribe.name) == .orderedAscending }
    }
}

/// A tribe the user and someone else in a venue chat both picked. Only the
/// two of them ever see it: the API resolves `sharedTribes` for the viewer
/// alone, and the app shows it only in venue and locale chat.
struct SharedTribe: Hashable, Sendable, Identifiable, Decodable {
    let id: String
    let name: String
    /// "You're both bears", the curated phrase for this tribe.
    let bothPhrase: String

    private enum CodingKeys: String, CodingKey {
        case id, name
        case bothPhrase = "both_phrase"
    }

    init(id: String, name: String, bothPhrase: String) {
        self.id = id
        self.name = name
        self.bothPhrase = bothPhrase
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bothPhrase = (try? container.decodeIfPresent(String.self, forKey: .bothPhrase))
            .flatMap { $0 } ?? String(localized: "You both picked \(name)")
    }

    /// What the GraphQL documents ask for, aliased to the keys above.
    static let fields = "id name both_phrase: bothPhrase"
}

extension [SharedTribe] {
    /// The BothLine: the first tribe's phrase, plus a count of the rest
    /// ("You're both bears +1"). `nil` when there's nothing shared.
    var bothLine: String? {
        guard let first else { return nil }
        return count == 1 ? first.bothPhrase : "\(first.bothPhrase) +\(count - 1)"
    }

    /// What VoiceOver adds after a name: "you share 2 tribes".
    var accessibilityPhrase: String? {
        switch count {
        case 0: nil
        case 1: String(localized: "you share a tribe: \(self[0].name)")
        default: String(localized: "you share \(count) tribes")
        }
    }
}
