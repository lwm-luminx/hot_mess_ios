//
//  VenueLineupSection.swift
//  HotMess
//

import AudienceKit
import AudienceKitUI
import SwiftUI

/// Tonight at a venue, from AudienceKitUI: the host on now with their links
/// and Tip, the lineup strip (each act opening its page), karaoke, its first
/// few singers with See all pushing the whole list, and song requests when
/// the venue takes them.
struct VenueLineupSection: View {
    let lineupModel: VenueLineupModel
    let lineup: VenueLineup

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var choosingTip = false

    var body: some View {
        VStack(spacing: 24) {
            if let host = lineupModel.hostEntry {
                VenueHostRow(
                    host: host,
                    links: lineupModel.hostLinks,
                    onTip: tipAction,
                    onSelect: host.personID.map { id in { model.push(.person(id)) } }
                )
            }

            VenueLineupStrip(lineup: lineup) { entry in
                if let id = entry.personID { model.push(.person(id)) }
            }

            KaraokeQueue(
                lineup: lineup,
                viewerName: model.session.singerName,
                previewLimit: 3,
                onSeeAll: { model.push(.karaokeList(lineupModel.venueID)) },
                onSignUp: lineupModel.signUp,
                onRemove: lineupModel.remove
            )

            if lineup.showsSongRequests {
                SongRequestsSection(
                    lineup: lineup,
                    signedIn: model.session.isSignedIn,
                    onRequest: lineupModel.requestSong,
                    onWithdraw: lineupModel.remove
                )
            }
        }
        .audiencePreset(model.brand.preset)
        .confirmationDialog(
            String(localized: "Tip \(lineupModel.hostEntry?.displayName ?? "")"),
            isPresented: $choosingTip,
            titleVisibility: .visible
        ) {
            ForEach(lineupModel.hostTipLinks) { link in
                if let url = link.url, let app = link.tipApp {
                    Button(String(localized: "Tip on \(app)")) { openURL(url) }
                }
            }
        }
    }

    /// Tips go to the host the way their page takes them: straight to the one
    /// app they take tips on, or a choice of them. No Tip without one.
    private var tipAction: (() -> Void)? {
        let links = lineupModel.hostTipLinks
        guard let first = links.first?.url else { return nil }
        if links.count == 1 { return { openURL(first) } }
        return { choosingTip = true }
    }
}

/// Every karaoke singer tonight, the ones who've sung behind a row, pushed
/// from the venue page's See all.
struct KaraokeListScreen: View {
    let venueID: UUID

    @Environment(AppModel.self) private var model
    @State private var lineupModel: VenueLineupModel?

    var body: some View {
        ScrollView {
            if let lineupModel, let lineup = lineupModel.lineup {
                KaraokeQueue(
                    lineup: lineup,
                    viewerName: model.session.singerName,
                    title: nil,
                    previewLimit: nil,
                    onSignUp: lineupModel.signUp,
                    onRemove: lineupModel.remove
                )
                .padding(.vertical, 16)
            } else if lineupModel?.hasLoaded == true {
                ContentUnavailableView(
                    String(localized: "No karaoke tonight"),
                    systemImage: "music.mic",
                    description: Text("Nobody's signed up to sing here tonight.")
                )
            } else {
                ProgressView()
                    .padding(.top, 40)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(String(localized: "Karaoke"))
        .navigationBarTitleDisplayMode(.inline)
        .audiencePreset(model.brand.preset)
        .refreshable { await lineupModel?.refresh() }
        .keepsLineupFresh(lineupModel)
        .task {
            if lineupModel == nil {
                lineupModel = VenueLineupModel(api: model.api, venueID: venueID)
            }
        }
    }
}

extension View {
    /// Refetches the lineup while the app is in front: on appearing, coming
    /// back, and every half minute, for the singers others sign up and the
    /// show advancing when the venue's chat isn't open to say so.
    func keepsLineupFresh(_ lineupModel: VenueLineupModel?) -> some View {
        modifier(LineupRefresh(lineupModel: lineupModel))
    }
}

private struct LineupRefresh: ViewModifier {
    let lineupModel: VenueLineupModel?
    @Environment(\.scenePhase) private var scenePhase

    private struct Key: Hashable {
        var venueID: UUID?
        var active: Bool
    }

    func body(content: Content) -> some View {
        content.task(id: Key(venueID: lineupModel?.venueID, active: scenePhase == .active)) {
            guard let lineupModel, scenePhase == .active else { return }
            while !Task.isCancelled {
                await lineupModel.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

extension SessionStore {
    /// The name a karaoke signup goes under: the user's own, `nil` until it
    /// loads (the signup sheet then asks for it).
    var singerName: String? {
        guard let name = user?.name, !name.isEmpty else { return nil }
        return name
    }
}
