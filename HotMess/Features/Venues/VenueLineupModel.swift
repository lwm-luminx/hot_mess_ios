//
//  VenueLineupModel.swift
//  HotMess
//

import AudienceKit
import AudienceKitUI
import Foundation
import Observation

/// A venue's lineup tonight and its karaoke signups, from the AudienceKit
/// SDK (`lineup(venueID:)`), for the venue page's host row, lineup strip and
/// karaoke list, and the full karaoke list it pushes. Kept apart from
/// `VenueViewModel` so signing up, leaving and the live refresh refetch only
/// the lineup, not the whole venue.
@MainActor
@Observable
final class VenueLineupModel {
    /// `nil` until it loads, and when the venue or API has no lineup; the
    /// venue page then falls back to the venue query's own lineup.
    private(set) var lineup: VenueLineup?
    /// The host on now's page, for their links and where to tip them.
    private(set) var host: PersonDetail?
    /// Whether a fetch has finished, loaded or not.
    private(set) var hasLoaded = false

    private let api: HotMessAPI
    let venueID: UUID
    private var isRefreshing = false
    private var refreshAgain = false

    init(api: HotMessAPI, venueID: UUID) {
        self.api = api
        self.venueID = venueID
    }

    /// Refetches the lineup, keeping the last one if this fetch fails, then
    /// the host's page when a different host is on. Asked again while a
    /// fetch is running (a signup during the poll), it fetches once more after.
    func refresh() async {
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoaded = true
        }

        repeat {
            refreshAgain = false
            if let fresh = try? await api.lineup(venueID: venueID) {
                lineup = fresh
                await loadHost()
            }
        } while refreshAgain && !Task.isCancelled
    }

    func signUp(_ signup: KaraokeSignup) async throws {
        try await api.signUpToSing(venueID: venueID, signup)
        await refresh()
    }

    func remove(_ request: SongRequest) async throws {
        try await api.withdrawSongRequest(request)
        await refresh()
    }

    /// The host on now, from the lineup.
    var hostEntry: AudienceKit.LineupEntry? { lineup?.hostOnNow }

    /// The host on now's links elsewhere, as icon buttons on the host row.
    var hostLinks: [HostLink] {
        guard let host, host.id == hostEntry?.personID else { return [] }
        return HostLink.links(for: host)
    }

    /// Where to tip the host on now (Cash App, Venmo), as their page offers.
    var hostTipLinks: [SocialLink] {
        guard let host, host.id == hostEntry?.personID else { return [] }
        return host.tipLinks
    }

    private func loadHost() async {
        guard let personID = hostEntry?.personID else {
            host = nil
            return
        }
        guard host?.id != personID else { return }
        host = try? await api.person(personID)
    }
}

extension VenueLineup {
    /// The host on now: the lineup's host entry that's on, else the one
    /// taking karaoke signups.
    var hostOnNow: AudienceKit.LineupEntry? {
        entries.first { $0.role == .host && $0.state == .on } ?? karaoke?.host
    }
}

extension AudienceKit.LineupEntry {
    /// The first person on it, whose page it opens; `nil` for an
    /// intermission, a singer, or an ID that isn't a record's.
    var personID: UUID? {
        people.first.flatMap { RecordID.uuid($0.id) }
    }
}

extension HostLink {
    /// A person's profiles as host row links: the ones with a URL, without
    /// the tip links (Tip covers those).
    static func links(for detail: PersonDetail) -> [HostLink] {
        detail.profileLinks.compactMap { link in
            guard let url = link.url else { return nil }
            return HostLink(
                title: String(localized: "\(detail.name) on \(link.serviceName)"),
                systemImage: link.hostSystemImage,
                url: url
            )
        }
    }
}

extension SocialLink {
    /// The network by name, for VoiceOver.
    var serviceName: String {
        switch provider.lowercased() {
        case "facebook": "Facebook"
        case "instagram": "Instagram"
        case "twitter", "x": "X"
        case "soundcloud": "SoundCloud"
        case "tiktok": "TikTok"
        case "youtube": "YouTube"
        default: label
        }
    }

    /// An SF Symbol for the host row, which can't draw the bundled network
    /// glyphs `SocialLinkRow` uses.
    var hostSystemImage: String {
        switch provider.lowercased() {
        case "instagram": "camera"
        case "facebook": "person.2"
        case "twitter", "x": "at"
        case "soundcloud": "waveform"
        case "tiktok", "youtube": "play.rectangle"
        default: systemImage
        }
    }
}
