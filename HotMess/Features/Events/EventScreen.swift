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
                        HeroHeader(url: event.bannerURL, topInset: proxy.safeAreaInsets.top, tone: $heroTone) {
                            heroText(event)
                        }

                        if !detail.hosts.isEmpty {
                            CardSection(detail.hosts.count == 1 ? String(localized: "Host") : String(localized: "Hosts")) {
                                ForEach(detail.hosts) { person in
                                    PersonCardLink(person: person)
                                }
                            }
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

                        DetailSection(String(localized: "Your RSVP")) {
                            RSVPPicker(selection: event.rsvp) { rsvp in
                                Task { await viewModel?.setRSVP(rsvp) }
                            }
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

                        PostsSection(
                            title: String(localized: "From the venue and hosts"),
                            subject: .event(event.id),
                            eventName: event.name,
                            eventVenueID: event.venue?.id,
                            eventPeople: (detail.hosts + detail.people).map(\.id) + [event.person?.id].compactMap { $0 }
                        )

                        PhotosSection(subject: .event(event.id))

                        detailsSection(event)

                        if let venue = event.venue {
                            CardSection(String(localized: "Venue")) {
                                VenueCardLink(venue: venue)
                            }
                        } else {
                            DetailSection(String(localized: "Venue")) {
                                Text(Event.toBeAnnounced)
                                    .foregroundStyle(.secondary)
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
                .trackingHeroCollapse($heroCollapsed)
            }
            // Ignoring the top here too is what makes the proxy report the bars' height.
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if let shareURL = event.shareURL {
                            ShareLink(item: shareURL) {
                                Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                            }
                        }

                        if model.session.isSignedIn {
                            Menu {
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

    private func heroText(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).uppercased())
                .font(.hotMess(.footnote, semibold: true))
                .tracking(0.8)

            Text(event.name)
                .font(.hotMess(.title, semibold: true))
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)

            if let place = event.venue?.name ?? event.person?.name {
                Text(place)
                    .font(.hotMess(.subheadline, semibold: true))
                    .lineLimit(1)
            }
        }
    }

    private func detailsSection(_ event: Event) -> some View {
        DetailSection {
            InfoRow(
                title: String(localized: "Starts"),
                value: event.startDate.formatted(date: .abbreviated, time: .shortened)
            )

            if let endDate = event.endDate {
                InfoRow(
                    title: String(localized: "Ends"),
                    value: endDate.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let facebookURL = event.facebookURL {
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
