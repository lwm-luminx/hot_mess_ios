//
//  VenueScreen.swift
//  HotMess
//

import MapKit
import SwiftUI

/// Venue detail, replacing `VenueViewController` — whose share button was wired
/// to `#selector(EventViewController.actionButton)` on a method that wasn't
/// even `@objc`, so tapping it crashed.
struct VenueScreen: View {
    let venueID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var viewModel: VenueViewModel?
    @State private var lineupModel: VenueLineupModel?
    @State private var pairUpModel: PairUpModel?
    @State private var isPairingUp = false
    @State private var heroTone = HeroTone.placeholder
    @State private var heroCollapsed = false
    @State private var pingSeed: PingSeed?
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?
    /// Whether it's reported closed, and its details as a fix starts from.
    @State private var suggestionState: VenueSuggestionState?
    @State private var fixTarget: SuggestionTarget?
    /// Whether the app places the user here, so "Get help" shows. Its own
    /// request, so an API without safety alerts still shows the venue.
    @State private var safety: VenueSafety?

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { overview in
            let venue = overview.venue

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // Its photos in turn, over a firmer scrim than a still
                        // hero so the name reads the same on each.
                        HeroHeader(
                            urls: overview.heroPhotos,
                            topInset: proxy.safeAreaInsets.top,
                            tone: $heroTone,
                            minimumContrast: 7,
                            minimumScrim: ImageTone.accessibleScrimFloor,
                            bodyHeight: HeroMetrics.detailHeight
                        ) {
                            heroText(overview)
                        }

                        if suggestionState?.reportedClosed == true {
                            ReportedClosedNotice(venueID: venue.id) { stillReported in
                                suggestionState?.reportedClosed = stillReported
                            }
                        }

                        let coverCharge = overview.coverCharge
                        if coverCharge != nil || overview.viewerAdmission?.isPaid == true {
                            CoverSection(
                                coverCharge: coverCharge,
                                isTonight: true,
                                admission: overview.viewerAdmission,
                                venueID: venue.id,
                                venueName: venue.name
                            )
                        }
                        if let coatCheck = coverCharge?.coatCheck {
                            if overview.viewerCoatCheck?.isPaid == true || overview.viewerAdmission?.isPaid == true {
                                CoatCheckSection(
                                    coatCheck: coatCheck,
                                    admission: overview.viewerCoatCheck,
                                    venueID: venue.id,
                                    venueName: venue.name
                                )
                            }
                        } else if let viewerCoatCheck = overview.viewerCoatCheck, viewerCoatCheck.isPaid {
                            CoatCheckSection(
                                coatCheck: CoatCheckCharge(
                                    amount: viewerCoatCheck.total,
                                    fee: Money(cents: 0, currency: viewerCoatCheck.total.currency),
                                    total: viewerCoatCheck.total,
                                    night: viewerCoatCheck.night,
                                    payable: false
                                ),
                                admission: viewerCoatCheck,
                                venueID: venue.id,
                                venueName: venue.name
                            )
                        }
                        // The next event is on the hero and the two after it
                        // sit up top, above the fold; the rest wait at the bottom.
                        if !overview.comingUp.isEmpty {
                            CardSection(String(localized: "Coming Up")) {
                                ForEach(overview.comingUp) { event in
                                    EventCardLink(event: event, photoURL: event.photoURL(prioritizing: .personFirst, venueFallback: venue))
                                }
                            }
                        }

                        // Pair me up, where the venue has it: once you're here,
                        // or while you're in it tonight. Above the chat it leads to.
                        if let pairUp = pairUpModel?.pairUp, pairUp.here || pairUp.mine != nil {
                            PairUpVenueRow(pairUp: pairUp, open: { isPairingUp = true }, goAgain: {
                                Task {
                                    await pairUpModel?.join(lookFor: nil)
                                    isPairingUp = true
                                }
                            })
                        }

                        if overview.chatOpen {
                            LiveChatPeek(
                                title: String(localized: "Chat"),
                                room: .venue(venue),
                                messages: overview.recentMessages,
                                route: .venueChat(venue),
                                onMessage: lineupChanged
                            )
                            .padding(.horizontal, 16)
                        }

                        // Pings with the chat, so they aren't below the fold.
                        PingPlaceStrip(
                            pings: (viewModel?.activePings ?? []).filter { !model.safety.isBlocked($0.user.id) },
                            isJoined: viewModel?.isJoinedHere(userID: model.session.userID) == true,
                            isBusy: viewModel?.isUpdatingPings == true,
                            pingForHere: { pingSeed = .venue(venue) },
                            join: { Task { await viewModel?.joinHere(userID: model.session.userID) } },
                            leave: { Task { await viewModel?.leaveHere(userID: model.session.userID) } }
                        )


                        // Tonight from AudienceKit: the host, the lineup and
                        // karaoke. Until it loads, or if it can't, the venue
                        // query's whole night, else just who's on (an older API).
                        if let lineupModel, let lineup = lineupModel.lineup {
                            VenueLineupSection(lineupModel: lineupModel, lineup: lineup)
                        } else if !overview.onNow.lineup.isEmpty {
                            TonightLineupSection(onNow: overview.onNow)
                        } else if overview.onNow.hasAnything {
                            OnNowSection(onNow: overview.onNow)
                        }

                        // Photos of the venue, and the camera once you're
                        // here: what you take goes on the stage's pages too.
                        PhotosSection(subject: .venue(venue.id), cameraVenueID: overview.chatOpen ? venue.id : nil)

                        PostsSection(title: String(localized: "Posts"), subject: .venue(venue.id))

                        aboutSection(venue, links: SocialLink.aboutLinks(overview.socialLinks, facebookURL: venue.facebookURL))

                        testingSection(venue)

                        if overview.events.isEmpty {
                            DetailSection(String(localized: "Events")) {
                                Text("No upcoming events.")
                                    .foregroundStyle(.secondary)
                            }
                        } else if !overview.laterEvents.isEmpty {
                            CardSection(String(localized: "More Events")) {
                                ForEach(overview.laterEvents) { event in
                                    EventCardLink(event: event, photoURL: event.photoURL(prioritizing: .personFirst, venueFallback: venue))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .top)
                .trackingHeroCollapse($heroCollapsed, bodyHeight: HeroMetrics.detailHeight)
            }
            // Ignoring the top here too is what makes the proxy report the bars' height.
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        SignedShareButton(path: "/venues/\(venue.id.uuidString.lowercased())")

                        Menu {
                            Button {
                                fixTarget = .venue(venue, suggestionState)
                            } label: {
                                Label(String(localized: "Suggest a Fix…"), systemImage: "pencil")
                            }
                            .accessibilityIdentifier("venue.suggestFix")

                            Button(role: .destructive) {
                                reportSubject = ReportSubject(target: .venue, targetID: venue.id.uuidString.lowercased())
                            } label: {
                                Label(String(localized: "Report Venue…"), systemImage: "exclamationmark.bubble")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body)
                        }
                        .accessibilityIdentifier("venue.optionsMenu")
                    }
                }
            }
        }
        .heroNavigationBar(
            title: viewModel?.state.value?.venue.name ?? String(localized: "Venue"),
            tone: heroTone,
            collapsed: heroCollapsed || viewModel?.state.value == nil
        )
        .contentReporting(report: $reportSubject, block: $blockTarget)
        .task {
            ensureViewModel()
            await viewModel?.load()
        }
        .task {
            ensureViewModel()
            await pairUpModel?.load()
        }
        // Its own request, so an API without suggestions still shows the venue.
        .task { suggestionState = try? await model.api.venueSuggestionState(venueID) }
        .task { await loadSafety() }
        .sheet(item: $fixTarget) { target in
            SuggestFixSheet(target: target)
                .environment(model)
        }
        .keepsLineupFresh(lineupModel)
        // Who a karaoke signup goes under.
        .task { await model.session.refreshUser() }
        // Whether App Review may pretend to be here.
        .task { await model.safety.load() }
        .sheet(item: $pingSeed) { seed in
            PingSheet(seed: seed)
                .environment(model)
        }
        .sheet(isPresented: $isPairingUp, onDismiss: { Task { await pairUpModel?.load() } }) {
            if let pairUpModel {
                PairUpSheet(model: pairUpModel, venueName: viewModel?.state.value?.venue.name ?? "")
                    .environment(model)
            }
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
        .onChange(of: model.checkout.revision) {
            // A cover was paid or refunded: show the pass, or the way to pay.
            reload()
        }
    }

    private func heroText(_ overview: VenueOverview) -> some View {
        let venue = overview.venue

        return VStack(alignment: .leading, spacing: 10) {
            Text(venue.name)
                .font(.hotMess(.title, semibold: true))
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)

            if let next = overview.nextEvent {
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
            }

            // Once you're here the address doesn't matter; the actions do.
            let isHere = safety?.canSend == true
            let details = [venue.address, venue.distance.map(DistanceFormat.string(fromMetres:))]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !isHere, !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.hotMess(.subheadline, semibold: true))
                    .lineLimit(2)
            }

            if !overview.friends.isEmpty {
                HStack(spacing: 8) {
                    HeroFaces(friends: overview.friends)
                    Text(friendsHereLine(overview.friends))
                        .font(.hotMess(.subheadline, semibold: true))
                        .lineLimit(1)
                }
            }

            HeroActionRow {
                if isHere {
                    Button {
                        pingSeed = .venue(venue)
                    } label: {
                        Label(String(localized: "Ping"), systemImage: "paperplane.fill")
                            .heroGlass()
                    }
                    .accessibilityIdentifier("venue.heroPing")

                    Button {
                        model.helpPresentation = .venue(HelpVenue(venue))
                    } label: {
                        Label(String(localized: "Safety"), systemImage: "shield.fill")
                            .heroGlass(selected: true)
                    }
                    .accessibilityHint(String(localized: "Tell staff quietly, reach a friend or a ride, or find support"))
                    .accessibilityIdentifier("venue.getHelp")
                } else if venue.coordinate != nil {
                    Button {
                        openInMaps(venue)
                    } label: {
                        Label(String(localized: "Directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .heroGlass()
                    }
                }

                if overview.chatOpen {
                    NavigationLink(value: AppRoute.venueChat(venue)) {
                        Label(String(localized: "Chat"), systemImage: "bubble.left.and.bubble.right.fill")
                            .heroGlass()
                    }
                }

                if !isHere, let phone = venue.phone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                    Link(destination: url) {
                        Label(String(localized: "Call"), systemImage: "phone.fill")
                            .heroGlass()
                    }
                    .accessibilityLabel(String(localized: "Call \(phone)"))
                }
            }
        }
    }

    /// "Sam is here", or "4 friends here".
    private func friendsHereLine(_ friends: [Friend]) -> String {
        if friends.count == 1, let friend = friends.first {
            return String(localized: "\(friend.firstName) is here")
        }
        return String(localized: "\(friends.count) friends here")
    }

    /// What it is, where, how to reach it, and its links elsewhere in one
    /// order (`SocialLink.aboutLinks`), each row naming where it goes.
    @ViewBuilder
    private func aboutSection(_ venue: Venue, links: [SocialLink]) -> some View {
        DetailSection(String(localized: "About")) {
            if let subtitle = venue.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.hotMess(.subheadline))
            }

            // Its address, distance and phone are on the hero, which has
            // Directions and Call.
            ForEach(links) { link in
                SocialLinkRow(link: link, namesService: true)
            }

            if model.session.isSignedIn {
                Button {
                    fixTarget = .venue(venue, suggestionState)
                } label: {
                    InfoRow(title: String(localized: "Suggest a fix"), value: nil, systemImage: "pencil")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("venue.suggestFixRow")
            }
        }
    }

    /// Test builds, and the App Review account while the API allows it:
    /// report the venue's own position, so the app (and the API) treat you as
    /// inside it wherever you really are.
    @ViewBuilder
    private func testingSection(_ venue: Venue) -> some View {
        let isTestBuild = model.configuration.isTestBuild
        let isReview = model.isReviewMode
        if model.showsReviewAids, let coordinate = venue.coordinate {
            DetailSection(isTestBuild ? String(localized: "Testing") : String(localized: "App Review")) {
                if model.location.simulatedVenueName == venue.name {
                    Button(String(localized: "Stop pretending"), systemImage: "location.slash") {
                        Task {
                            await model.location.stopSimulating()
                            await viewModel?.load()
                            await loadSafety()
                            await pairUpModel?.load()
                        }
                    }
                } else {
                    Button(String(localized: "Pretend I'm here"), systemImage: "location.fill") {
                        // Reload once the visit is recorded, so the chat row appears.
                        Task {
                            await model.location.simulate(at: coordinate, venueName: venue.name, allowed: isReview)
                            await viewModel?.load()
                            await loadSafety()
                            await pairUpModel?.load()
                        }
                    }
                }
            } footer: {
                Text(isTestBuild
                    ? String(localized: "Test builds only. Reports this venue's location instead of yours until you stop.")
                    : String(localized: "For App Review. Reports this venue's location instead of yours until you stop, so you can try its chat."))
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openInMaps(_ venue: Venue) {
        guard let coordinate = venue.coordinate else { return }

        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = venue.name
        item.openInMaps()
    }

    /// Advancing the lineup posts an "On now" announcement as the venue, so
    /// one from the venue or its talent refetches the lineup at once rather
    /// than at the next poll.
    private func lineupChanged(_ message: VenueMessage) {
        guard message.kind == .announcement || message.isFromListing else { return }
        Task { await lineupModel?.refresh() }
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = VenueViewModel(api: model.api, venueID: venueID, friends: model.friends)
        }
        if lineupModel == nil {
            lineupModel = VenueLineupModel(api: model.api, venueID: venueID)
        }
        if pairUpModel == nil {
            pairUpModel = PairUpModel(api: model.api, venueID: venueID)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            await viewModel?.load()
            await lineupModel?.refresh()
            await pairUpModel?.load()
            await loadSafety()
        }
    }

    private func loadSafety() async {
        if let fresh = try? await model.api.venueSafety(venueID) { safety = fresh }
    }
}
