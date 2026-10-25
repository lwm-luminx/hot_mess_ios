//
//  EventScreen.swift
//  HotMess
//

import AudienceKitUI
import SwiftUI

/// Event detail, replacing `EventViewController`.
///
/// The original decided its section count from two `if` statements and then
/// indexed sections with different numbers in `cellForRowAt`, so the host row
/// was unreachable and the venue row could read a `nil` venue.
struct EventScreen: View {
    let eventID: UUID

    @Environment(AppModel.self) private var model
    @State private var viewModel: EventViewModel?
    @State private var heroTone = HeroTone.placeholder
    @State private var heroCollapsed = false
    @State private var pingSeed: PingSeed?
    /// Its venue's lineup on the night, for karaoke signups right here.
    @State private var lineupModel: VenueLineupModel?
    @State private var fixTarget: SuggestionTarget?

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { detail in
            let event = detail.event

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // When, where, who and your RSVP all ride on the photo.
                        HeroHeader(
                            url: event.bannerURL,
                            topInset: proxy.safeAreaInsets.top,
                            tone: $heroTone,
                            bodyHeight: HeroMetrics.detailHeight
                        ) {
                            heroText(detail)
                        }

                        if viewModel?.isTonight == true || viewModel?.activePings.isEmpty == false {
                            PingPlaceStrip(
                                pings: (viewModel?.activePings ?? []).filter { !model.safety.isBlocked($0.user.id) },
                                isJoined: viewModel?.isJoinedHere(userID: model.session.userID) == true,
                                isBusy: viewModel?.isUpdatingPings == true,
                                pingForHere: pingForHere(event),
                                join: { Task { await viewModel?.joinHere(userID: model.session.userID) } },
                                leave: { Task { await viewModel?.leaveHere(userID: model.session.userID) } }
                            )
                        }

                        if let coverCharge = detail.coverCharge {
                            // Only tonight's cover can be paid; other nights show the price.
                            CoverSection(
                                coverCharge: coverCharge,
                                isTonight: detail.isCoverTonight,
                                admission: detail.isCoverTonight ? detail.viewerAdmission : nil,
                                venueID: event.venue?.id,
                                venueName: event.venue?.name ?? ""
                            )
                        }

                        // On the night, the venue's karaoke itself: who's singing
                        // and Sign up to sing. Otherwise how to join, held back
                        // while tonight's lineup loads so it doesn't flash.
                        if let lineupModel, let lineup = lineupModel.lineup, lineup.showsKaraoke {
                            KaraokeQueue(
                                lineup: lineup,
                                viewerName: model.session.singerName,
                                previewLimit: 3,
                                onSeeAll: { model.push(.karaokeList(lineupModel.venueID)) },
                                onSignUp: lineupModel.signUp,
                                onRemove: lineupModel.remove
                            )
                            .audiencePreset(model.brand.preset)
                        } else if let karaoke = event.karaoke, lineupModel?.hasLoaded != false {
                            KaraokeSection(karaoke: karaoke, venue: event.venue)
                        }

                        // On the night, song requests too, when the venue takes them.
                        if let lineupModel, let lineup = lineupModel.lineup, lineup.showsSongRequests {
                            SongRequestsSection(
                                lineup: lineup,
                                signedIn: model.session.isSignedIn,
                                onRequest: lineupModel.requestSong,
                                onWithdraw: lineupModel.remove
                            )
                            .audiencePreset(model.brand.preset)
                        }

                        PostsSection(title: String(localized: "From the venue and hosts"), subject: .event(event.id))

                        PhotosSection(subject: .event(event.id))

                        if let facebookURL = event.facebookURL {
                            DetailSection {
                                Link(destination: facebookURL) {
                                    InfoRow(
                                        title: String(localized: "Open in Facebook"),
                                        value: nil,
                                        systemImage: "arrow.up.right.square"
                                    )
                                }
                            }
                        }

                        if !detail.people.isEmpty {
                            CardSection(String(localized: "Lineup")) {
                                ForEach(detail.people) { person in
                                    PersonCardLink(person: person)
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
                        SignedShareButton(path: "/events/\(event.id.uuidString.lowercased())")

                        if model.session.isSignedIn {
                            Menu {
                                // Going and Interested are on the hero.
                                Button {
                                    Task { await viewModel?.setRSVP(.declined) }
                                } label: {
                                    Label(RSVP.declined.title, systemImage: event.rsvp == .declined ? "checkmark" : RSVP.declined.systemImage)
                                }
                                .accessibilityIdentifier("event.notGoing")

                                Button {
                                    fixTarget = .event(event)
                                } label: {
                                    Label(String(localized: "Suggest a Fix…"), systemImage: "pencil")
                                }
                                .accessibilityIdentifier("event.suggestFix")
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body)
                            }
                            .accessibilityIdentifier("event.optionsMenu")
                        }
                    }
                }
            }
        }
        .heroNavigationBar(
            title: viewModel?.state.value?.event.name ?? String(localized: "Event"),
            tone: heroTone,
            collapsed: heroCollapsed || viewModel?.state.value == nil
        )
        .task {
            ensureViewModel()
            await viewModel?.load()
        }
        .task(id: tonightVenueID) {
            lineupModel = VenueLineupModel.reusing(lineupModel, for: tonightVenueID, api: model.api)
        }
        .keepsLineupFresh(lineupModel)
        // Who a karaoke signup goes under.
        .task { await model.session.refreshUser() }
        .sheet(item: $pingSeed) { seed in
            PingSheet(seed: seed)
                .environment(model)
        }
        .sheet(item: $fixTarget) { target in
            SuggestFixSheet(target: target)
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
        .onChange(of: model.checkout.revision) {
            reload()
        }
        .alert(
            String(localized: "Couldn't Save RSVP"),
            isPresented: Binding(
                get: { viewModel?.rsvpError != nil },
                set: { if !$0 { viewModel?.dismissRSVPError() } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel?.rsvpError ?? "")
        }
    }

    /// Its venue, while the event is on tonight: a karaoke night's signups are
    /// the venue's lineup tonight.
    private var tonightVenueID: UUID? {
        guard viewModel?.isTonight == true, let event = viewModel?.state.value?.event, event.karaoke != nil else { return nil }
        return event.venue?.id
    }

    /// "Ping here", only for an event tonight.
    private func pingForHere(_ event: Event) -> (() -> Void)? {
        guard viewModel?.isTonight == true else { return nil }
        return { pingSeed = .event(event) }
    }

    private func heroText(_ detail: EventDetail) -> some View {
        let event = detail.event

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(whenLine(event).uppercased())
                    .font(.hotMess(.footnote, semibold: true))
                    .tracking(0.8)

                Text(event.name)
                    .font(.hotMess(.title, semibold: true))
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
            }

            if let venue = event.venue {
                NavigationLink(value: AppRoute.venue(venue.id)) {
                    HStack(spacing: 8) {
                        Avatar(url: venue.photoURL ?? venue.bannerURL, initials: venue.name.initialsForDisplay, size: 22, isPlace: true)
                        Text(venue.name)
                        if let distance = venue.distance {
                            Text(DistanceFormat.string(fromMetres: distance))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.leading, -8)
                    .heroGlass(fillsWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "Opens the venue"))
            } else {
                Text(Event.toBeAnnounced)
                    .font(.hotMess(.subheadline, semibold: true))
            }

            if !detail.hosts.isEmpty {
                hostsLine(detail.hosts)
            }

            HeroActionRow {
                rsvpButton(.attending, event: event, systemImage: "checkmark")
                rsvpButton(.maybe, event: event, systemImage: "star")
            }
        }
    }

    /// "Fri Oct 24 · 9:00 PM to 2:00 AM".
    private func whenLine(_ event: Event) -> String {
        let day = event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        guard let endDate = event.endDate, endDate > event.startDate else { return "\(day) · \(start)" }
        let end = endDate.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(day) · \(start) to \(end)")
    }

    /// "Hosted by Sasha and Bea" with their faces; one host opens their page.
    @ViewBuilder
    private func hostsLine(_ hosts: [Person]) -> some View {
        let line = HStack(spacing: 8) {
            HeroFaces(people: hosts)
            Text("Hosted by \(hosts.map(\.name).formatted(.list(type: .and)))")
                .font(.hotMess(.subheadline, semibold: true))
                .lineLimit(2)
        }

        if hosts.count == 1, let host = hosts.first {
            NavigationLink(value: AppRoute.person(host.id)) { line }
                .buttonStyle(.plain)
        } else {
            line
        }
    }

    private func rsvpButton(_ rsvp: RSVP, event: Event, systemImage: String) -> some View {
        let isSelected = event.rsvp == rsvp
        return Button {
            Task { await viewModel?.setRSVP(rsvp) }
        } label: {
            Label(rsvp.title, systemImage: isSelected ? "checkmark.circle.fill" : systemImage)
                .heroGlass(selected: isSelected)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = EventViewModel(api: model.api, eventID: eventID)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            await viewModel?.load()
        }
    }
}
