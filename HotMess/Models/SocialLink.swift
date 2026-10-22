//
//  SocialLink.swift
//  HotMess
//

import Foundation

struct SocialLink: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let handle: String
    let provider: String
    let url: URL?

    /// The bundled glyph for a known network, or `nil` to fall back to a
    /// system symbol.
    var assetName: String? {
        switch provider.lowercased() {
        case "facebook": "Facebook"
        case "soundcloud": "SoundCloud"
        case "instagram": "Instagram"
        case "twitter", "x": "Twitter"
        default: nil
        }
    }

    /// The system symbol for a network without a bundled glyph.
    var systemImage: String {
        switch provider.lowercased() {
        case "spotify", "apple_music": "music.note"
        case "apple_podcasts", "podcast_rss": "mic"
        default: "link"
        }
    }

    /// What the row says: the service for music links, whose handles are URL
    /// paths, otherwise "/handle".
    var label: String {
        switch provider.lowercased() {
        case "spotify": "Spotify"
        case "apple_music": "Apple Music"
        case "apple_podcasts": "Apple Podcasts"
        case "podcast_rss": "Podcast RSS"
        default: "/\(handle)"
        }
    }

    /// The app fans tip them with, for a Cash App or Venmo link; `nil` for a
    /// social profile.
    var tipApp: String? {
        switch provider.lowercased() {
        case "cashapp": "Cash App"
        case "venmo": "Venmo"
        default: nil
        }
    }

    /// A venue's links for its About section, in one order on every venue and
    /// platform: Facebook, Instagram, TikTok, X, YouTube, SoundCloud, then the
    /// rest as listed. The page's Facebook link stands in for a Facebook
    /// profile it doesn't list, and a link listed twice shows once.
    static func aboutLinks(_ links: [SocialLink], facebookURL: URL?) -> [SocialLink] {
        var seen = Set<URL>()
        var about = links.filter { link in
            guard let url = link.url, link.tipApp == nil else { return false }
            return seen.insert(url).inserted
        }
        if let facebookURL, !about.contains(where: { $0.provider.lowercased() == "facebook" }), !seen.contains(facebookURL) {
            about.append(SocialLink(id: pageFacebookID, handle: "", provider: "facebook", url: facebookURL))
        }
        return about.enumerated()
            .sorted { ($0.element.aboutRank, $0.offset) < ($1.element.aboutRank, $1.offset) }
            .map(\.element)
    }

    /// The ID of the Facebook link made from a page's own Facebook page.
    private static let pageFacebookID = UUID(uuidString: "00000000-0000-4000-8000-0000000000FB")!

    private var aboutRank: Int {
        switch provider.lowercased() {
        case "facebook": 0
        case "instagram": 1
        case "tiktok": 2
        case "twitter", "x": 3
        case "youtube": 4
        case "soundcloud": 5
        default: 6
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, handle, provider, url
    }

    init(id: UUID, handle: String, provider: String, url: URL? = nil) {
        self.id = id
        self.handle = handle
        self.provider = provider
        self.url = url
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        handle = try container.decodeIfPresent(String.self, forKey: .handle) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        url = try container.decodeURLIfPresent(forKey: .url)
    }
}
