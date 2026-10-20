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

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { overview in
            let venue = overview.venue

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        HeroHeader(url: venue.bannerURL ?? venue.photoURL, topInset: proxy.safeAreaInsets.top, tone: $heroTone) {
                            heroText(venue)
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

                        PingPlaceStrip(
                            pings: (viewModel?.activePings ?? []).filter { !model.safety.isBlocked($0.user.id) },
                            isJoined: viewModel?.isJoinedHere(userID: model.session.userID) == true,
                            isBusy: viewModel?.isUpdatingPings == true,
                            pingForHere: { pingSeed = .venue(venue) },
                            join: { Task { await viewModel?.joinHere(userID: model.session.userID) } },
                            leave: { Task { await viewModel?.leaveHere(userID: model.session.userID) } }
                        )

                        // Pair me up, where the venue has it: once you're here,
                        // or while you're in it tonight.
                        if let pairUp = pairUpModel?.pairUp, pairUp.here || pairUp.mine != nil {
                            PairUpVenueRow(pairUp: pairUp) { isPairingUp = true }
                        }

                        aboutSection(venue)

                        let socialLinks = overview.socialLinks.filter { $0.url != nil }
                        if !socialLinks.isEmpty {
                            DetailSection(String(localized: "Elsewhere")) {
                                ForEach(socialLinks) { link in
                                    SocialLinkRow(link: link)
                                }
                            }
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

                        if !overview.friends.isEmpty {
                            DetailSection(String(localized: "Friends Here")) {
                                FriendStrip(friends: overview.friends)
                                    .padding(.horizontal, -20)
                            }
                        }

                        testingSection(venue)

                        if overview.events.isEmpty {
                            DetailSection(String(localized: "Events")) {
                                Text("No upcoming events.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            CardSection(String(localized: "Events")) {
                                ForEach(overview.events) { event in
                                    EventCardLink(event: event, photoURL: event.photoURL(prioritizing: .personFirst, venueFallback: venue))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .top)
                .trackingHeroCollapse($heroCollapsed)
            }
            // Ignoring the top here too is what makes the proxy report the bars' height.
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        RecordShareLink(path: venue.sharePath)

                        Menu {
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

    private func heroText(_ venue: Venue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(venue.name)
                .font(.hotMess(.title, semibold: true))
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)

            let details = [venue.address, venue.distance.map(DistanceFormat.string(fromMetres:))]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.hotMess(.subheadline, semibold: true))
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func aboutSection(_ venue: Venue) -> some View {
        DetailSection(String(localized: "About")) {
            if let subtitle = venue.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.hotMess(.subheadline))
            }

            if let address = venue.address, !address.isEmpty {
                Button {
                    openInMaps(venue)
                } label: {
                    InfoRow(title: String(localized: "Address"), value: address, systemImage: "mappin")
                }
                .buttonStyle(.plain)
            }

            if let phone = venue.phone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                Link(destination: url) {
                    InfoRow(title: String(localized: "Phone"), value: phone, systemImage: "phone")
                }
            }

            if let distance = venue.distance {
                InfoRow(
                    title: String(localized: "Distance"),
                    value: DistanceFormat.string(fromMetres: distance),
                    systemImage: "figure.walk"
                )
            }

            if let facebookURL = venue.facebookURL {
                Link(destination: facebookURL) {
                    InfoRow(
                        title: String(localized: "Open in Facebook"),
                        value: nil,
                        systemImage: "arrow.up.right.square"
                    )
                }
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
                            await pairUpModel?.load()
                        }
                    }
                } else {
                    Button(String(localized: "Pretend I'm here"), systemImage: "location.fill") {
                        // Reload once the visit is recorded, so the chat row appears.
                        Task {
                            await model.location.simulate(at: coordinate, venueName: venue.name, allowed: isReview)
                            await viewModel?.load()
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
        }
    }
}
