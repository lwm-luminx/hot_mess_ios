//
//  NowScreen.swift
//  HotMess
//

import AudienceKit
import SwiftUI
import UIKit

/// The home tab, replacing `NowViewController` — a table view whose row
/// heights, section titles and cell identifiers were all decided by a chain of
/// `indexPath.section == 0` checks.
struct NowScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: NowViewModel?
    @State private var heroTone = HeroTone.placeholder
    @State private var heroCollapsed = false
    @State private var showingPingSheet = false
    /// Whether the app places the user at tonight's venue, so "I feel
    /// unsafe" shows. Its own request, so an API without safety alerts still
    /// shows Now.
    @State private var safety: VenueSafety?
    /// The Ping revision last loaded, so a change to Pings asks for a fresh
    /// report while a new position or a return to the tab can share one.
    @State private var loadedPingRevision: Int?
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?
    /// Tonight at the venue you're at (or your event's): the host, the
    /// lineup and karaoke signups, as its page shows them.
    @State private var lineupModel: VenueLineupModel?
    /// Pair me up at the venue you're at, or your event's.
    @State private var pairUpModel: PairUpModel?
    @State private var isPairingUp = false
    /// The order of Now's cards, ranked by the server for where you are.
    @State private var cardLayout: ScreenLayout?

    /// Every card Now can draw, in its built-in order: the lineup or karaoke,
    /// the room's chat, tonight's posts, small talk, the next events, the
    /// locale's updates, venues nearby, where your friends are, then pings.
    /// Announcements and promoted cards come only from the server.
    static let fallbackCards = [
        CardKind.nowStage, CardKind.nowChat, CardKind.postsTonight, CardKind.nowSmallTalk, CardKind.eventsUpcoming,
        CardKind.postsLocale, CardKind.venuesNearby, CardKind.venuesFriends, CardKind.pings,
    ]
    static let cardKinds = fallbackCards + [CardKind.web, CardKind.promoSlot]

    /// How often Now reloads while it's on screen. Standing still sends no new
    /// position, but the chat, the lineup and who's here keep changing.
    static let refreshInterval: Duration = .seconds(60)

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
                        // Taller at a venue with nothing on, for its details,
                        // over the venue page's firmer scrim.
                        let venueHero = now.event == nil && isAtVenue(now)
                        HeroHeader(
                            urls: [now.imageURL].compactMap { $0 },
                            topInset: proxy.safeAreaInsets.top,
                            tone: $heroTone,
                            minimumContrast: venueHero ? 7 : 4.5,
                            minimumScrim: venueHero ? ImageTone.accessibleScrimFloor : 0,
                            bodyHeight: venueHero ? HeroMetrics.venueNowHeight : HeroMetrics.bodyHeight
                        ) {
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

                        // The cards in the server's order (the built-in one
                        // when it can't be had); a kind this build doesn't
                        // draw was never asked for.
                        let layout = cardLayout?.layout ?? .fallback(Self.fallbackCards)
                        let pingsWithChat = layout.card(isAtVenue(now) ? CardKind.nowChat : CardKind.nowSmallTalk) != nil
                        ForEach(layout.cards) { card in
                            nowCard(card, now, layoutID: layout.id, pingsWithChat: pingsWithChat)
                        }
                        // Passes and who's out depend on this device, so they
                        // aren't cards: they go just above pings.
                        if layout.card(CardKind.pings) == nil {
                            venueExtrasSection(now)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .top)
                .trackingHeroCollapse($heroCollapsed)
                .refreshable {
                    let started = Date.now
                    await model.location.refreshPosition()
                    async let cards: Void = loadCards(force: true)
                    await viewModel?.load(from: model.location, sentAfter: started)
                    await cards
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
            // At a venue, Safety sits by Ping, big and labelled, so it's in
            // reach as you scroll. Only where the app places the user, as
            // staff can only help people who are there.
            if let venue = helpVenue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.helpPresentation = .venue(venue)
                    } label: {
                        Label(String(localized: "Safety"), systemImage: "shield.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.hotMess(.headline, semibold: true))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.hotMessAccent)
                    // The light accent carries white text in either mode.
                    .environment(\.colorScheme, .light)
                    .accessibilityHint(String(localized: "Tell staff quietly, reach a friend or a ride, or find support"))
                    .accessibilityIdentifier("now.toolbarGetHelp")
                }
            }
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
            async let cards: Void = loadCards(force: true)
            await viewModel?.load(from: model.location, sentAfter: pingsChanged ? .now : nil)
            await cards
        }
        // Coming back to the app, and every minute while it's open. Coming
        // back waits for the fresh fix the app asks for, so Now isn't loaded
        // for wherever you were when you left.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            ensureViewModel()
            await model.location.refreshPosition()
            while !Task.isCancelled {
                async let cards: Void = loadCards()
                await viewModel?.load(from: model.location)
                await cards
                await pairUpModel?.load()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        .onChange(of: model.checkout.revision) {
            reload()
        }
        .task(id: tonightVenueID) {
            lineupModel = VenueLineupModel.reusing(lineupModel, for: tonightVenueID, api: model.api)
        }
        .keepsLineupFresh(lineupModel)
        .task(id: tonightVenueID) {
            pairUpModel = tonightVenueID.map { PairUpModel(api: model.api, venueID: $0) }
            await pairUpModel?.load()
        }
        .task(id: tonightVenueID) {
            guard let tonightVenueID else { safety = nil; return }
            safety = (try? await model.api.venueSafety(tonightVenueID)) ?? nil
        }
        .sheet(isPresented: $isPairingUp, onDismiss: { Task { await pairUpModel?.load() } }) {
            if let pairUpModel {
                PairUpSheet(model: pairUpModel, venueName: viewModel?.state.value.flatMap { $0.venue?.name ?? $0.event?.venue?.name } ?? "")
                    .environment(model)
            }
        }
        // Who a karaoke signup goes under.
        .task { await model.session.refreshUser() }
        .contentReporting(report: $reportSubject, block: $blockTarget)
    }

    /// The venue you're at, or your event's.
    private var tonightVenueID: UUID? {
        guard let now = viewModel?.state.value else { return nil }
        return now.venue?.id ?? now.event?.venue?.id
    }

    /// Whether Now is about the venue the user is at.
    private func isAtVenue(_ now: Now) -> Bool {
        now.venues == nil && now.venue != nil
    }

    /// The venue "I feel unsafe" is about, while the app places the user there.
    private var helpVenue: HelpVenue? {
        guard safety?.canSend == true, let now = viewModel?.state.value, isAtVenue(now),
              let venue = now.venue else { return nil }
        return HelpVenue(venue)
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
            // Nothing on yet: the venue and where it is, then what's next,
            // tonight's cover and who's here.
            VStack(alignment: .leading, spacing: 10) {
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

                // Once you're here the address doesn't matter; the actions do.
                if helpVenue == nil, let address = venue.address, !address.isEmpty {
                    Text(address)
                        .font(.hotMess(.subheadline, semibold: true))
                        .lineLimit(2)
                }

                if let next = now.events.first {
                    NavigationLink(value: AppRoute.event(next.id)) {
                        HStack(spacing: 6) {
                            Text(next.nextUpLine)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .heroGlass(fillsWidth: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("now.nextEvent")
                }

                if let coverCharge = now.coverCharge {
                    Text(coverCharge.summary(isTonight: true))
                        .font(.hotMess(.subheadline, semibold: true))
                        .lineLimit(2)
                }

                if !now.friends.isEmpty {
                    HStack(spacing: 8) {
                        HeroFaces(friends: now.friends)
                        Text(Self.friendsHereLine(now.friends))
                            .font(.hotMess(.subheadline, semibold: true))
                            .lineLimit(1)
                    }
                }

                if let helpVenue {
                    HeroActionRow {
                        Button {
                            showingPingSheet = true
                        } label: {
                            Label(String(localized: "Ping"), systemImage: "paperplane.fill")
                                .heroGlass()
                        }
                        .accessibilityIdentifier("now.heroPing")

                        Button {
                            model.helpPresentation = .venue(helpVenue)
                        } label: {
                            Label(String(localized: "Safety"), systemImage: "shield.fill")
                                .heroGlass(selected: true)
                        }
                        .accessibilityHint(String(localized: "Tell staff quietly, reach a friend or a ride, or find support"))
                        .accessibilityIdentifier("now.heroSafety")

                        NavigationLink(value: AppRoute.venueChat(venue)) {
                            Label(String(localized: "Chat"), systemImage: "bubble.left.and.bubble.right.fill")
                                .heroGlass()
                        }
                        .accessibilityIdentifier("now.heroChat")
                    }
                }
            }
        } else {
            Text(now.title)
                .font(.hotMess(.largeTitle, semibold: true))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// "Sam is here", or "4 friends here".
    static func friendsHereLine(_ friends: [Friend]) -> String {
        if friends.count == 1, let friend = friends.first {
            return String(localized: "\(friend.firstName) is here")
        }
        return String(localized: "\(friends.count) friends here")
    }

    /// Now finds an event from an hour before it starts to an hour after it ends.
    private func eventStage(_ event: Event) -> String {
        let now = Date.now
        if event.startDate > now { return String(localized: "Starting soon") }
        if let end = event.endDate, end < now { return String(localized: "Just ended") }
        return String(localized: "Happening now")
    }

    // MARK: - Cards

    /// One of Now's cards: the section it has always been, drawn where the
    /// server ranked it.
    @ViewBuilder
    private func nowCard(_ card: LayoutCard, _ now: Now, layoutID: String?, pingsWithChat: Bool) -> some View {
        switch card.kind {
        case CardKind.nowStage:
            stageSection(now)
            stagePhotosSection(now)
        case CardKind.nowChat:
            // Quickie above the chat it leads to, when it's shown.
            pairUpSection
            venueChatSection(now)
            // Pings sit with the chat at a venue.
            if isAtVenue(now) {
                pingsSection(now)
            }
        case CardKind.postsTonight:
            tonightPostsSection(now)
        case CardKind.nowSmallTalk:
            localeChatSection(now)
            if !isAtVenue(now) {
                pingsSection(now)
            }
        case CardKind.eventsUpcoming:
            eventsSection(now)
        case CardKind.postsLocale:
            localePostsSection(now)
        case CardKind.venuesNearby:
            nearbySection(now, card: card)
        case CardKind.venuesFriends:
            friendVenuesSection(now)
        case CardKind.pings:
            venueExtrasSection(now)
            // A layout without the chat card still lists them.
            if !pingsWithChat {
                pingsSection(now)
            }
        case CardKind.web:
            if let content = card.web { WebCardView(content: content) }
        case CardKind.promoSlot:
            PromoSlotView(card: card, layoutID: layoutID)
        default:
            EmptyView()
        }
    }

    private func loadCards(force: Bool = false) async {
        await cardLayout?.load(coordinates: model.location.coordinates, localeID: model.location.locale?.id,
                               force: force)
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

    /// Venues near you, when you aren't at one, in the server's order.
    @ViewBuilder
    private func nearbySection(_ now: Now, card: LayoutCard) -> some View {
        if let nearby = now.venues {
            let venues = ordered(nearby, by: card.venueIDs, isFallback: card.isFallback)
            if venues.isEmpty {
                DetailSection(String(localized: "Venues")) {
                    Text("You aren't near any venues right now.")
                        .foregroundStyle(.secondary)
                }
            } else {
                CardSection(String(localized: "Venues"), grouped: true) {
                    ForEach(venues.prefix(3)) { venue in
                        VenueCardLink(venue: venue)
                    }
                }
            }
        }
    }

    /// At a venue, tonight's pass or the way to skip the line; when Now
    /// doesn't know where you are, your friends who are out.
    @ViewBuilder
    private func venueExtrasSection(_ now: Now) -> some View {
        if now.venues != nil {
            EmptyView()
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

    /// At a venue: tonight as its page shows it, the host, the lineup strip,
    /// karaoke signups and song requests. Until that loads, or from an older API, who's on and up
    /// next, and the event's karaoke session when it has one (held back while
    /// loading, so its pointer doesn't flash before the signups).
    @ViewBuilder
    private func stageSection(_ now: Now) -> some View {
        if let lineupModel, let lineup = lineupModel.lineup, !lineup.entries.isEmpty || lineup.showsKaraoke
            || lineup.showsSongRequests {
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

    /// At a venue: its photos, led by the camera. What you take goes on the
    /// venue's, the event's and the stage's pages.
    @ViewBuilder
    private func stagePhotosSection(_ now: Now) -> some View {
        if now.venues == nil, let venue = now.venue {
            PhotosSection(subject: .venue(venue.id), cameraVenueID: venue.id)
        }
    }

    /// Pair me up, just under the chat: once you're at a venue that has it, or
    /// while you're in it tonight.
    @ViewBuilder
    private var pairUpSection: some View {
        if let pairUp = pairUpModel?.pairUp, pairUp.here || pairUp.mine != nil {
            PairUpVenueRow(pairUp: pairUp, open: { isPairingUp = true }, goAgain: {
                Task {
                    await pairUpModel?.join(lookFor: nil)
                    isPairingUp = true
                }
            })
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
                venueName: venue.name,
                lineup: lineupModel?.lineup,
                route: now.event == nil ? .venueChat(venue) : .eventChat(room)
            )
            .padding(.horizontal, 16)
        }
    }

    /// The venue (an event's too), then you and your friends. The peek puts
    /// the lineup in chat now between them.
    private func chatParticipants(_ now: Now, room: ChatRoom) -> [ChatPeek.Participant] {
        guard let venue = room.place else { return viewerAndFriends(now) }
        let place = ChatPeek.Participant(
            id: "venue-\(room.id)", name: venue.name,
            avatarURL: venue.photoURL, isPlace: true
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
            CardSection(String(localized: "Where your friends are"), grouped: true) {
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

    /// At an event or venue: its posts from the last 24 hours.
    @ViewBuilder
    private func tonightPostsSection(_ now: Now) -> some View {
        if now.venues == nil, let venue = now.venue {
            let subject: PostsSubject = now.event.map { .event($0.id) } ?? .venue(venue.id)
            let title = now.event.map(\.name) ?? venue.name
            NowPostsSection(
                title: String(localized: "Latest from tonight"),
                subject: subject,
                withinHours: 24,
                seeAll: .posts(subject, title: title)
            )
        }
    }

    /// Away from venues: the locale's updates.
    @ViewBuilder
    private func localePostsSection(_ now: Now) -> some View {
        if now.venue == nil, let locale = now.locale {
            NowPostsSection(
                title: String(localized: "Updates in \(locale.name)"),
                subject: .locale(locale),
                seeAll: .updates(locale)
            )
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
        if cardLayout == nil {
            cardLayout = ScreenLayout(audienceKit: model.audienceKit, screen: .now, kinds: Self.cardKinds,
                                      fallback: Self.fallbackCards, appVersion: model.configuration.version)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            async let cards: Void = loadCards(force: true)
            await viewModel?.load(from: model.location, sentAfter: .now)
            await cards
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
