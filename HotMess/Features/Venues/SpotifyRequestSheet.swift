//
//  SpotifyRequestSheet.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// A song from someone's own Spotify, sent to the bar as a song request:
/// shared to Hot Mess from Spotify's share sheet (`SpotifyShareInbox`) or
/// pasted on a venue page. It shows the song with Spotify's name and a link
/// back, and sends it with a note to the venue whose requests are open.
/// Nobody signs in to Spotify, and nothing plays here.
struct SpotifyShare: Identifiable, Hashable {
    let link: String
    /// Where it goes: the venue whose song requests are open; nil when the
    /// person hasn't been on one recently.
    let venueID: String?
    let venueName: String?

    var id: String { link + (venueID ?? "") }

    /// The share waiting from the extension, going to the venue the person
    /// last saw taking requests.
    static func fromInbox() -> SpotifyShare? {
        guard let share = SpotifyShareInbox.take() else { return nil }
        let venue = SpotifyShareInbox.requestVenue()
        return SpotifyShare(link: share.link, venueID: venue?.id, venueName: venue?.name)
    }
}

struct SpotifyRequestSheet: View {
    let share: SpotifyShare
    /// After a request is sent, so the venue page can refresh its queue.
    var onSent: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var song: SpotifyLink?
    @State private var loaded = false
    @State private var note = ""
    @State private var sending = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let song {
                        songRow(song)
                    } else if loaded {
                        Text(String(localized: "That isn't a Spotify link."))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                } footer: {
                    if song != nil { Text(String(localized: "From Spotify")) }
                }

                if let song, song.isSong, share.venueID != nil {
                    Section(String(localized: "Note for the host")) {
                        TextField(String(localized: "A dedication or a word for the host"), text: $note,
                                  axis: .vertical)
                            .onChange(of: note) { _, text in if text.count > 280 { note = String(text.prefix(280)) } }
                    }
                }

                if let song, !song.isSong {
                    Section {
                        Text(String(localized: "Request one song at a time: open it in Spotify, tap Share on a song and choose Hot Mess."))
                            .foregroundStyle(.secondary)
                    }
                } else if share.venueID == nil, song != nil {
                    Section {
                        Text(String(localized: "Open the venue's page in Hot Mess while you're there and its song requests are open, then paste the link under Song requests."))
                            .foregroundStyle(.secondary)
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(.red) }
                }
            }
            .navigationTitle(String(localized: "Request a song"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let song, song.isSong, let venueName = share.venueName {
                        Button(String(localized: "Send to \(venueName)")) { Task { await send() } }
                            .disabled(sending)
                    }
                }
            }
            .task { await load() }
        }
    }

    private func songRow(_ song: SpotifyLink) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: song.thumbnailUrl) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? String(localized: "Spotify")).font(.headline)
                if let artist = song.artist { Text(artist).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
            Button {
                openURL(song.url)
            } label: {
                Label(String(localized: "Open in Spotify"), systemImage: "arrow.up.right.square").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Open in Spotify"))
        }
    }

    private func load() async {
        defer { loaded = true }
        guard !share.link.isEmpty else { return }
        song = try? await model.audienceKit.spotifyLink(url: share.link)
    }

    private func send() async {
        guard let venueID = share.venueID else { return }
        sending = true
        defer { sending = false }
        do {
            try await model.audienceKit.requestSong(venueID: venueID, spotifyURL: share.link, note: note)
            onSent?()
            dismiss()
        } catch let error as AudienceKitError {
            problem = APIError(error).errorDescription
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The night's set list on Spotify, mirrored by the venue: a Listen in
/// Spotify button that opens it in the person's own Spotify, to save, add to
/// their own playlists or listen to rehearse. Nothing when the venue hasn't
/// mirrored it.
struct SetListOnSpotifyButton: View {
    let eventID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var setList: EventSetList?

    var body: some View {
        Group {
            if let setList {
                Button {
                    openURL(setList.spotifyUrl)
                } label: {
                    Label(String(localized: "Listen to the set list in Spotify"), systemImage: "music.note.list")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .task(id: eventID) {
            setList = try? await model.audienceKit.setList(eventID: eventID.uuidString.lowercased())
        }
    }
}
