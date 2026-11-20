//
//  SingAlongSection.swift
//  HotMess
//

import AudienceKit
import AudienceKitUI
import Observation
import SwiftUI

/// A sing-along night's playlist and its venue's rotation, kept fresh while
/// the night is on: the rotation every half minute, and as soon as the
/// player's report goes stale.
@MainActor
@Observable
final class SingAlongModel {
    private(set) var night: SingAlongNight?
    private(set) var hasLoaded = false

    private let api: HotMessAPI
    let eventID: UUID

    init(api: HotMessAPI, eventID: UUID) {
        self.api = api
        self.eventID = eventID
    }

    /// The whole night (playlist and rotation), keeping the last one if this fetch fails.
    func load() async {
        defer { hasLoaded = true }
        if let fresh = try? await api.singAlong(eventID: eventID) { night = fresh }
    }

    /// Just the rotation; the playlist doesn't change during the night.
    func refreshRotation() async {
        guard let night, let venueID = night.venueID else { return await load() }
        guard let playing = try? await api.nowPlaying(venueID: venueID) else {
            // Nothing reported, or the report went stale: drop it rather than show an old song.
            if night.nowPlaying?.isFresh() == false { self.night = night.with(nowPlaying: nil) }
            return
        }
        self.night = night.with(nowPlaying: playing)
    }

    /// How long until the rotation should be read again: half a minute, or
    /// sooner when the report runs out first.
    var nextRefresh: Duration {
        guard let expiresAt = night?.nowPlaying?.expiresAt else { return .seconds(30) }
        let seconds = min(30, max(5, expiresAt.timeIntervalSinceNow + 1))
        return .seconds(seconds)
    }
}

/// A sing-along night, in the Karaoke section's place on an event's page, on
/// Now and on the venue's page that night: what's playing and up next, Request
/// a song from the night's playlist, the viewer's requests, and the playlist.
/// The words are never shown here; they're on the venue's screens.
struct SingAlongSection: View {
    let eventID: UUID
    /// The night is on: the rotation and requests show. Before it, just the
    /// playlist and when requests open.
    let isLive: Bool
    /// Tonight's lineup at the venue, whose song requests a sing-along takes.
    var lineupModel: VenueLineupModel?

    @Environment(AppModel.self) private var model
    @State private var singAlong: SingAlongModel?
    @State private var picking = false
    @State private var browsing = false
    @State private var freeTextRequest = false

    private var night: SingAlongNight? { singAlong?.night }
    private var requests: SongRequestWindow? { isLive ? lineupModel?.lineup?.songRequests : nil }
    private var trackCount: Int? { night?.playlist?.tracks?.count }

    var body: some View {
        DetailSection(String(localized: "Sing-along")) {
            if isLive, let playing = night?.nowPlaying {
                NowPlayingRow(playing: playing, mine: mineUp(playing))
            } else {
                intro
            }

            // Requests go under the viewer's name, so only once they're signed in.
            if let requests, requests.permitted, model.session.isSignedIn {
                requestRows(requests)
            }

            playlistRow
        } footer: {
            if !isLive, night?.playlist != nil {
                Text(String(localized: "Requests open on the night."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .audiencePreset(model.brand.preset)
        .task(id: eventID) {
            if singAlong?.eventID != eventID { singAlong = SingAlongModel(api: model.api, eventID: eventID) }
            await singAlong?.load()
        }
        .task(id: RefreshKey(eventID: eventID, live: isLive)) {
            guard isLive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: singAlong?.nextRefresh ?? .seconds(30))
                guard !Task.isCancelled else { return }
                await singAlong?.refreshRotation()
            }
        }
        .sheet(isPresented: $picking) {
            if let night {
                SingAlongPlaylistSheet(night: night, requests: requests, picks: true, submit: request)
            }
        }
        .sheet(isPresented: $browsing) {
            if let night {
                SingAlongPlaylistSheet(night: night, requests: requests, picks: false, submit: request)
            }
        }
        .sheet(isPresented: $freeTextRequest) {
            SongRequestSheet(venueName: night?.venueName ?? "",
                             hostName: requests?.host?.displayName, submit: request)
        }
    }

    private struct RefreshKey: Hashable {
        var eventID: UUID
        var live: Bool
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "music.note.tv")
                .font(.title3)
                .foregroundStyle(Color.hotMessSuccess)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Sing-along night"))
                    .font(.hotMess(.body, semibold: true))
                Text(isLive
                     ? String(localized: "It's on. Look up, the words are on the screens.")
                     : String(localized: "No sign-ups, no solos. The whole bar sings, words on the screens."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("singAlong.intro")
    }

    @ViewBuilder
    private func requestRows(_ window: SongRequestWindow) -> some View {
        let mine = window.mine.filter { $0.isSong && $0.state.isOpen }
        SongRequestButton(window: window,
                          label: mine.isEmpty ? String(localized: "Request a song") : String(localized: "Request another")) {
            if night?.playlist?.tracks?.isEmpty == false {
                picking = true
            } else {
                freeTextRequest = true
            }
        }
        .accessibilityIdentifier("singAlong.request")

        ForEach(mine) { request in
            MySongRequestRow(request: request, requestsBefore: window.requestsBefore(request),
                             onWithdraw: lineupModel.map { model in { try await model.remove($0) } })
                .padding(.horizontal, -20)
                .padding(.vertical, -11)
        }
    }

    @ViewBuilder
    private var playlistRow: some View {
        if let playlist = night?.playlist {
            if let count = trackCount, count > 0 {
                Button { browsing = true } label: {
                    HStack(spacing: 8) {
                        InfoRow(title: isLive ? String(localized: "Tonight's playlist") : String(localized: "The playlist"),
                                value: String(localized: "\(count) songs"), systemImage: "music.note.list")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("singAlong.playlist")
            } else if let url = URL(string: playlist.url), url.scheme == "https" {
                Link(destination: url) {
                    InfoRow(title: String(localized: "Open in Spotify"), value: nil, systemImage: "arrow.up.right.square")
                }
                .accessibilityIdentifier("singAlong.openPlaylist")
            }
        }
    }

    /// The viewer's request that's playing now, if it's this song.
    private func mineUp(_ playing: NowPlaying) -> Bool {
        requests?.mine.contains { $0.isSong && $0.state == .up && SingAlongTrack(title: $0.title, artist: $0.artist, uri: "")
            .matches(title: playing.title, artist: playing.artist) } ?? false
    }

    private func request(_ draft: SongRequestDraft) async throws {
        guard let lineupModel else { return }
        try await lineupModel.requestSong(draft)
    }
}

/// What's playing: the cover, the song, a "Now playing" pill, and the next
/// few songs under it. One element for VoiceOver, and no live announcements:
/// songs change every few minutes.
private struct NowPlayingRow: View {
    let playing: NowPlaying
    /// The viewer asked for it.
    let mine: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    private var upNext: ArraySlice<UpNextSong> { playing.upNext.prefix(3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(playing.title)
                        .font(.hotMess(.headline, semibold: true))
                        .lineLimit(2)
                    if let line = artistLine {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if typeSize.isAccessibilitySize { NowPlayingBadge() }
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { NowPlayingBadge() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(nowLabel)

            if !upNext.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Up next"))
                        .font(.hotMess(.caption, semibold: true))
                        .foregroundStyle(.secondary)
                    ForEach(Array(upNext.enumerated()), id: \.offset) { _, song in
                        (Text(song.title) + Text(song.artist.map { " · \($0)" } ?? "").foregroundStyle(.secondary))
                            .font(.subheadline)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }
                }
                .padding(.leading, 60)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(upNextLabel)
            }
        }
        .accessibilityIdentifier("singAlong.nowPlaying")
    }

    private var artistLine: String? {
        guard mine else { return playing.artist }
        return [String(localized: "Your request"), playing.artist].compactMap { $0 }.joined(separator: " · ")
    }

    private var artwork: some View {
        Group {
            if let url = playing.artworkUrl.flatMap(URL.init(string:)), url.scheme == "https" {
                RemoteImage(url: url)
            } else {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(Color.hotMessSuccess)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.hotMessSuccessSoft)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(.rect(cornerRadius: HotMessRadius.lg))
        .accessibilityHidden(true)
    }

    private var nowLabel: String {
        if let artist = playing.artist { return String(localized: "Now playing: \(playing.title) by \(artist)") }
        return String(localized: "Now playing: \(playing.title)")
    }

    private var upNextLabel: String {
        let songs = upNext.map { song in
            song.artist.map { String(localized: "\(song.title) by \($0)") } ?? song.title
        }
        return String(localized: "Up next: \(songs.joined(separator: String(localized: ", then ")))")
    }
}

/// The green "Now playing" pill, shaped like "On now".
private struct NowPlayingBadge: View {
    var body: some View {
        Label(String(localized: "Now playing"), systemImage: "speaker.wave.2")
            .font(.hotMess(.caption, semibold: true))
            .foregroundStyle(Color.hotMessSuccess)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.hotMessSuccessSoft, in: .capsule)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The night's playlist, A to Z with search. Picking a song (when `picks`)
/// goes on to a dedication and Send request. Songs that are on, up next or
/// already asked for are dimmed with why. Only songs on the playlist can be
/// asked for: the screens only have the words for those.
struct SingAlongPlaylistSheet: View {
    let night: SingAlongNight
    let requests: SongRequestWindow?
    let picks: Bool
    let submit: @MainActor (SongRequestDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var tracks: [SingAlongTrack] { night.pickableTracks(matching: search) }
    private var total: Int { night.playlist?.tracks?.count ?? 0 }

    var body: some View {
        NavigationStack {
            List {
                if picks, let venue = night.venueName {
                    Text(String(localized: "Tonight at \(venue). Pick from the playlist."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(tracks) { track in
                    row(track)
                }
            }
            .overlay {
                if tracks.isEmpty, !search.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Not on tonight's playlist"),
                        systemImage: "music.note.list",
                        description: Text(String(localized: "Try another. Everyone needs to know the words."))
                    )
                }
            }
            .searchable(text: $search, prompt: String(localized: "Search \(total) songs"))
            .navigationTitle(picks ? String(localized: "Request a song") : String(localized: "Tonight's playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SingAlongTrack.self) { track in
                SingAlongRequestForm(track: track, venueName: night.venueName) { draft in
                    try await submit(draft)
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(picks ? String(localized: "Cancel") : String(localized: "Done")) { dismiss() }
                }
                if let url = night.playlist.flatMap({ URL(string: $0.url) }), url.scheme == "https" {
                    ToolbarItem(placement: .primaryAction) {
                        Link(destination: url) {
                            Label(String(localized: "Open in Spotify"), systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func row(_ track: SingAlongTrack) -> some View {
        let status = night.status(of: track, requests: requests)
        let label = TrackRow(track: track, status: status)
        if picks, status == nil {
            NavigationLink(value: track) { label }
                .accessibilityIdentifier("singAlong.track")
        } else {
            label
        }
    }
}

private struct TrackRow: View {
    let track: SingAlongTrack
    let status: SingAlongTrackStatus?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                if let artist = track.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let status {
                Label(status.label, systemImage: status.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .opacity(status == nil ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityValue(status?.label ?? "")
    }
}

extension SingAlongTrackStatus {
    var label: String {
        switch self {
        case .playingNow: String(localized: "Playing now")
        case .upNext: String(localized: "Up next")
        case .requested: String(localized: "Requested")
        case .inQueue: String(localized: "In the queue")
        }
    }

    var systemImage: String {
        switch self {
        case .playingNow: "speaker.wave.2"
        case .upNext: "forward"
        case .requested: "checkmark"
        case .inQueue: "clock"
        }
    }
}

/// The song picked, an optional dedication, and Send request. The server's
/// refusal (requests closed, not at the venue) shows above, worded for the room.
private struct SingAlongRequestForm: View {
    let track: SingAlongTrack
    let venueName: String?
    let send: @MainActor (SongRequestDraft) async throws -> Void

    @State private var note = ""
    @State private var sending = false
    @State private var failure: String?

    var body: some View {
        Form {
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.hotMess(.headline, semibold: true))
                    if let artist = track.artist {
                        Text(artist).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                TextField(String(localized: "Dedication or note (optional)"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: note) { _, value in
                        if value.count > 280 { note = String(value.prefix(280)) }
                    }
                    .accessibilityIdentifier("singAlong.note")
            }
            Section {
                Button {
                    sendRequest()
                } label: {
                    HStack {
                        Spacer()
                        if sending { ProgressView() } else { Text(String(localized: "Send request")).bold() }
                        Spacer()
                    }
                }
                .disabled(sending)
                .accessibilityIdentifier("singAlong.send")
            }
        }
        .navigationTitle(String(localized: "Request a song"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendRequest() {
        sending = true
        failure = nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            defer { sending = false }
            do {
                try await send(SongRequestDraft(title: track.title, artist: track.artist,
                                                note: trimmed.isEmpty ? nil : trimmed))
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
