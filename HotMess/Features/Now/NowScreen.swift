//
//  NowScreen.swift
//  HotMess
//

import SwiftUI
import UIKit

/// The home tab, replacing `NowViewController` — a table view whose row
/// heights, section titles and cell identifiers were all decided by a chain of
/// `indexPath.section == 0` checks.
struct NowScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var viewModel: NowViewModel?
    @State private var heroTone = HeroTone.placeholder
    @State private var heroCollapsed = false
    @State private var showingPingSheet = false
    /// The Ping revision last loaded, so a change to Pings asks for a fresh
    /// report while a new position or a return to the tab can share one.
    @State private var loadedPingRevision: Int?
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?
    /// Tonight at the venue you're at (or your event's): the host, the
    /// lineup and karaoke signups, as its page shows them.
    @State private var lineupModel: VenueLineupModel?

    /// Reloads when the position changes or Pings change elsewhere.
    private struct LoadKey: Hashable {
        var coordinates: Coordinates?
        var pingRevision: Int
    }

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { now in
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        HeroHeader(url: now.imageURL, topInset: proxy.safeAreaInsets.top, tone: $heroTone) {
                            heroText(now)
                        }

                        if let simulated = model.location.simulatedVenueName {
                            DetailSection(String(localized: "Pretending to be at \(simulated)")) {
                                Button(String(localized: "Stop pretending"), systemImage: "location.slash") {
                                    Task { await model.location.stopSimulating() }
                                }
                            }
                        }

                        if !model.location.isAuthorized, model.location.simulatedVenueName == nil {
                            locationNotice
                        }

                        if !model.safety.hasFacebook {
                            DetailSection(String(localized: "Friends")) {
                                ConnectFacebookButton()
                            } footer: {
                                ConnectFacebookFooter()
                                    .font(.hotMess(.footnote))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // The lineup or karaoke, small talk, the next three events, then venues.
                        stageSection(now)
                        venueChatSection(now)
                        localeChatSection(now)
                        eventsSection(now)
                        nearbySection(now)
                        friendVenuesSection(now)
                        pingsSection(now)
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .top)
                .trackingHeroCollapse($heroCollapsed)
                .refreshable {
                    let started = Date.now
                    await model.location.refreshPosition()
                    await viewModel?.load(from: model.location, sentAfter: started)
                }
            }
            // Ignoring the top here too is what makes the proxy report the bars' height.
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .heroNavigationBar(
            title: navigationTitle,
            tone: heroTone,
            collapsed: heroCollapsed || viewModel?.state.value == nil
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPingSheet = true
                } label: {
                    Text("Ping")
                        .font(.hotMess(.headline, semibold: true))
                }
                .accessibilityHint(String(localized: "Tell your friends you want to go out tonight"))
            }
        }
        .sheet(isPresented: $showingPingSheet) {
            PingSheet { ping in
                viewModel?.show(ping)
            }
            .environment(model)
        }
        .alert(
            String(localized: "Couldn't update ping"),
            isPresented: Binding(
                get: { viewModel?.pingError != nil },
                set: { if !$0 { viewModel?.pingError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel?.pingError ?? "")
        }
        // Whether to offer Connect Facebook.
        .task { await model.safety.load() }
        .task(id: LoadKey(coordinates: model.location.coordinates, pingRevision: model.pingRevision)) {
            ensureViewModel()
            let pingsChanged = loadedPingRevision.map { $0 != model.pingRevision } ?? false
            loadedPingRevision = model.pingRevision
            await viewModel?.load(from: model.location, sentAfter: pingsChanged ? .now : nil)
        }
        .onChange(of: model.checkout.revision) {
            reload()
        }
        .task(id: tonightVenueID) {
            lineupModel = VenueLineupModel.reusing(lineupModel, for: tonightVenueID, api: model.api)
        }
        .keepsLineupFresh(lineupModel)
        // Who a karaoke signup goes under.
        .task { await model.session.refreshUser() }
        .contentReporting(report: $reportSubject, block: $blockTarget)
    }

    /// The venue you're at, or your event's.
    private var tonightVenueID: UUID? {
        guard let now = viewModel?.state.value else { return nil }
        return now.venue?.id ?? now.event?.venue?.id
    }

    private var navigationTitle: String {
        viewModel?.state.value?.title ?? String(localized: "Now")
    }

    @ViewBuilder
    private func heroText(_ now: Now) -> some View {
        if let event = now.event {
            // At an event: it leads, with its venue (or host) underneath.
            NavigationLink(value: AppRoute.event(event.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eventStage(event))
                        .font(.hotMess(.subheadline, semibold: true))
                        .textCase(.uppercase)
                    HStack(spacing: 12) {
                        Text(event.name)
                            .font(.hotMess(.largeTitle, semibold: true))
                            .lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        Image(systemName: "chevron.right")
                            .font(.hotMess(.headline, semibold: true))
                            .accessibilityHidden(true)
                    }
                    Text(event.subtitle)
                        .font(.hotMess(.headline))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("now.event")
            .accessibilityHint(String(localized: "View event details"))
        } else if let venue = now.venue {
            VenueCardLink(venue: venue) {
                HStack(spacing: 12) {
                    Text(venue.name)
                        .font(.hotMess(.largeTitle, semibold: true))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Image(systemName: "chevron.right")
                        .font(.hotMess(.headline, semibold: true))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint(String(localized: "View venue details"))
        } else {
            Text(now.title)
                .font(.hotMess(.largeTitle, semibold: true))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Now finds an event from an hour before it starts to an hour after it ends.
    private func eventStage(_ event: Event) -> String {
        let now = Date.now
        if event.startDate > now { return String(localized: "Starting soon") }
        if let end = event.endDate, end < now { return String(localized: "Just ended") }
        return String(localized: "Happening now")
    }

    // MARK: - Sections

    /// Your own Ping on top, then friends' Pings, newest first.
    @ViewBuilder
    private func pingsSection(_ now: Now) -> some View {
        if let ping = now.myPing, ping.isActive(at: .now) {
            MyPingCard(ping: ping) {
                showingPingSheet = true
            } end: {
                Task { await viewModel?.endMyPing() }
            }
            .disabled(viewModel?.busyPingIDs.contains(ping.id) == true)
            .padding(.horizontal, 16)
        }

        // People the user blocked are left out at once.
        let blocked = model.safety.blockedIDs
        CardSection(String(localized: "Friends going out tonight")) {
            ForEach(Ping.friendFeed(now.friendPings, at: .now).filter { !blocked.contains($0.user.id) }) { ping in
                let sender = BlockedUser(id: ping.user.id, name: ping.user.name, avatarURL: ping.user.avatarURL)
                FriendPingCard(
                    ping: ping,
                    userID: model.session.userID,
                    isBusy: viewModel?.busyPingIDs.contains(ping.id) == true,
                    join: { target in
                        Task { await viewModel?.join(ping, target: target) }
                    },
                    leave: {
                        Task { await viewModel?.leave(ping) }
                    },
                    report: {
                        reportSubject = ReportSubject(target: .ping, targetID: ping.id, sender: sender)
                    },
                    block: {
                        blockTarget = sender
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func nearbySection(_ now: Now) -> some View {
        if let venues = now.venues {
            if venues.isEmpty {
                DetailSection(String(localized: "Venues")) {
                    Text("You aren't near any venues right now.")
                        .foregroundStyle(.secondary)
                }
            } else {
                CardSection(String(localized: "Venues")) {
                    ForEach(venues.prefix(3)) { venue in
                        VenueCardLink(venue: venue)
                    }
                }
            }
        } else if let venue = now.venue {
            // A pass for tonight leads the venue's cards, ready for the door; otherwise
            // the way to skip the line when the cover can be paid here.
            if let pass = now.viewerAdmission, pass.isPaid {
                TonightPassCard(admission: pass)
            } else if let coverCharge = now.coverCharge, coverCharge.payable {
                SkipTheLineCard(venue: venue, coverCharge: coverCharge)
            }

            if let coatPass = now.viewerCoatCheck, coatPass.isPaid {
                TonightPassCard(admission: coatPass)
            } else if let coatCheck = now.coverCharge?.coatCheck, coatCheck.payable {
                CoatCheckCard(venue: venue, coatCheck: coatCheck)
            }
        } else {
            friendsSection(now, title: String(localized: "People"))
        }
    }

    /// At a venue: tonight as its page shows it, the host, the lineup strip and
    /// karaoke signups. Until that loads, or from an older API, who's on and up
    /// next, and the event's karaoke session when it has one (held back while
    /// loading, so its pointer doesn't flash before the signups).
    @ViewBuilder
    private func stageSection(_ now: Now) -> some View {
        if let lineupModel, let lineup = lineupModel.lineup, !lineup.entries.isEmpty || lineup.showsKaraoke {
            VenueLineupSection(lineupModel: lineupModel, lineup: lineup)
        } else if now.venues == nil, now.venue != nil {
            if now.onNow.hasAnything {
                OnNowSection(onNow: now.onNow)
            }
            if let karaoke = now.event?.karaoke, lineupModel?.hasLoaded != false {
                KaraokeSection(karaoke: karaoke)
            }
        }
    }

    /// At a venue: its room. At an event the room is the event's, named and pictured for it.
    @ViewBuilder
    private func venueChatSection(_ now: Now) -> some View {
        if now.venues == nil, let venue = now.venue {
            let room = now.event.map { ChatRoom.event($0, at: venue) } ?? .venue(venue)
            LiveChatPeek(
                title: String(localized: "Small talk"),
                room: room,
                messages: now.recentMessages,
                participants: chatParticipants(now, room: room),
                route: now.event == nil ? .venueChat(venue) : .eventChat(room)
            )
            .padding(.horizontal, 16)
        }
    }

    private func chatParticipants(_ now: Now, room: ChatRoom) -> [ChatPeek.Participant] {
        let place = ChatPeek.Participant(
            id: "venue-\(room.id)", name: room.name,
            avatarURL: room.photoURL, isPlace: true
        )
        return [place] + viewerAndFriends(now)
    }

    /// Without location access Now can't show what's near: venues, who's
    /// there, the locale's room. Pings and friends still load.
    private var locationNotice: some View {
        DetailSection(String(localized: "Location is off")) {
            Button(String(localized: "Turn On Location"), systemImage: "location") {
                if model.location.isDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    model.location.start()
                }
            }
            .accessibilityIdentifier("now.enableLocation")
        } footer: {
            Text("Hot Mess can't show venues, events or who's out near you without access to your location.")
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
        }
    }

    /// The locale's room has no place to show first: you, then your friends out in it.
    private func localeChatParticipants(_ now: Now) -> [ChatPeek.Participant] {
        now.friends.isEmpty ? [] : viewerAndFriends(now)
    }

    private func viewerAndFriends(_ now: Now) -> [ChatPeek.Participant] {
        let viewerID = model.session.userID
        var participants = [
            ChatPeek.Participant(
                id: "viewer", name: String(localized: "You"),
                avatarURL: model.session.user?.avatarURL
            )
        ]
        var seen = Set<UUID>()
        for friend in now.friends where friend.id != viewerID && seen.insert(friend.id).inserted {
            participants.append(ChatPeek.Participant(
                id: friend.id.uuidString, name: friend.name,
                avatarURL: friend.avatarURL,
                presence: friend.presence
            ))
        }
        return participants
    }

    private func friendsSection(_ now: Now, title: String) -> some View {
        DetailSection(title) {
            if now.friends.isEmpty {
                Text(now.venue == nil ? "None of your friends are out yet." : "None of your friends are here yet.")
                    .foregroundStyle(.secondary)
            } else {
                FriendStrip(friends: now.friends)
                    .padding(.horizontal, -20)
            }
        }
    }

    /// Away from venues: the locale's chat room, for everyone out in it who
    /// isn't at a venue. Shown only when the API says the user can join.
    @ViewBuilder
    private func localeChatSection(_ now: Now) -> some View {
        if now.venue == nil, now.localeChatOpen, let locale = now.locale {
            LiveChatPeek(
                title: String(localized: "Small talk in \(locale.name)"),
                room: .locale(locale),
                messages: now.localeMessages,
                participants: localeChatParticipants(now),
                route: .localeChat(locale)
            )
            .padding(.horizontal, 16)
        }
    }

    /// Away from venues: where your friends are, as a count per venue.
    @ViewBuilder
    private func friendVenuesSection(_ now: Now) -> some View {
        if now.venue == nil, !now.friendVenues.isEmpty {
            CardSection(String(localized: "Where your friends are")) {
                ForEach(now.friendVenues) { entry in
                    VenueCardLink(venue: entry.venue) {
                        VenueCard(
                            venue: entry.venue,
                            description: entry.friends.map(\.name).formatted(.list(type: .and)),
                            pill: entry.friendCount == 1
                                ? String(localized: "1 friend")
                                : String(localized: "\(entry.friendCount) friends")
                        ) {
                            FriendFaces(friends: entry.friends)
                        }
                    }
                }
            }
        }
    }

    private func eventsSection(_ now: Now) -> some View {
        Group {
            if now.events.isEmpty {
                DetailSection(String(localized: "Events")) {
                    Text("There are no upcoming events.")
                        .foregroundStyle(.secondary)
                }
            } else {
                CardSection(String(localized: "Events")) {
                    ForEach(now.events.prefix(3)) { event in
                        EventCardLink(event: event)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = NowViewModel(api: model.api, friends: model.friends)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            await viewModel?.load(from: model.location, sentAfter: .now)
        }
    }
}

/// The horizontal row of friends who are out, replacing
/// `FriendListTableViewCell` — a table cell that hosted its own collection view
/// and data source.
struct FriendStrip: View {
    let friends: [Friend]

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(friends) { friend in
                    Button {
                        if let url = friend.messengerURL { openURL(url) }
                    } label: {
                        VStack(spacing: 6) {
                            Avatar(
                                url: friend.avatarURL,
                                initials: friend.name.initialsForDisplay,
                                size: 56,
                                presence: friend.presence
                            )

                            // Friends see each other's full names; two lines
                            // fit most, and longer ones truncate at the end.
                            Text(friend.name)
                                .font(.hotMess(.caption))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                        .frame(width: 72)
                    }
                    .buttonStyle(.plain)
                    .disabled(friend.messengerURL == nil)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}
