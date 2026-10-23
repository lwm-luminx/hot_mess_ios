//
//  EventPhoto.swift
//  HotMess
//

import Foundation

/// A photo of a venue or event: a photographer's, or one a member took with
/// the app's camera there. Either is tagged with whoever was on stage, so it
/// shows on the venue's, the event's and their pages (`IPosts.photos`).
struct EventPhoto: Decodable, Identifiable, Hashable, Sendable {
    /// Someone on stage when it was taken, whose page it opens.
    struct Tag: Decodable, Identifiable, Hashable, Sendable {
        let id: UUID
        let name: String
    }

    /// The event it was taken at, for its "at {event}" line.
    struct EventLink: Decodable, Hashable, Sendable {
        let id: UUID
        let name: String
    }

    let id: UUID
    let url: URL?
    let altText: String?
    let caption: String?
    /// A photographer's, rather than a member's from the app's camera.
    let isProfessional: Bool
    /// The photographer's name, or the member's short name ("Aurora B.").
    let takenBy: String?
    let takenAt: Date?
    let people: [Tag]
    let event: EventLink?
    /// The photographer's page for it, to see it full size or buy it.
    let viewURL: URL?
    /// The viewer took it, so they can remove it.
    let viewerCanRemove: Bool

    private enum CodingKeys: String, CodingKey {
        case id, url, altText, caption, source, takenBy, takenAt, people, event, viewerCanRemove
        case viewURL = "viewUrl"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decodeURLIfPresent(forKey: .url)
        altText = try container.decodeIfPresent(String.self, forKey: .altText)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        isProfessional = try container.decodeIfPresent(String.self, forKey: .source) != "AMATEUR"
        takenBy = try container.decodeIfPresent(String.self, forKey: .takenBy)
        takenAt = try container.decodeIfPresent(Date.self, forKey: .takenAt)
        people = try container.decodeIfPresent([Tag].self, forKey: .people) ?? []
        event = try container.decodeIfPresent(EventLink.self, forKey: .event)
        viewURL = try container.decodeURLIfPresent(forKey: .viewURL)
        viewerCanRemove = try container.decodeIfPresent(Bool.self, forKey: .viewerCanRemove) ?? false
    }

    /// "Photo by Jo Lens" or "Taken by Aurora B.", under it.
    var credit: String? {
        guard let takenBy else { return nil }
        return isProfessional
            ? String(localized: "Photo by \(takenBy)")
            : String(localized: "Taken by \(takenBy)")
    }

    /// Who it's of, for its line and VoiceOver: "Aurora Borealis & Bianca Bee".
    var peopleNames: String? {
        people.isEmpty ? nil : people.map(\.name).formatted(.list(type: .and))
    }
}
