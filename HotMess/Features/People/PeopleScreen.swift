//
//  PeopleScreen.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// The people tab, replacing `PeopleViewController` — which registered its
/// refresh observer with `object: self`, so the notification it was waiting for
/// never matched and the list only ever loaded once.
///
/// Once the device's city is known it opens on who's local there: people
/// playing it this week, then people based there. Everyone is a tap away.
struct PeopleScreen: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: PeopleViewModel?
    @State private var scope = Scope.local
    /// The groups' order, ranked by the server; promoted cards go between
    /// groups, never inside one.
    @State private var cardLayout: ScreenLayout?

    static let localCards = [CardKind.peoplePlayingThisWeek, CardKind.peopleBasedHere]
    static let cardKinds = localCards + [CardKind.peopleEveryone, CardKind.web, CardKind.promoSlot]

    private enum Scope: Hashable {
        case local
        case everyone
    }

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { listing in
            if listing.isEmpty {
                ContentUnavailableView(
                    String(localized: "No One Yet"),
                    systemImage: "person.2",
                    description: Text("Nobody is listed yet.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        if let locale = model.location.locale {
                            Picker(String(localized: "Show"), selection: $scope) {
                                Text(locale.name).tag(Scope.local)
                                Text("Everyone").tag(Scope.everyone)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)

                            if scope == .local {
                                localSections(listing.local(to: locale.id), in: locale)
                            } else {
                                everyoneSection(listing)
                            }
                        } else {
                            everyoneSection(listing)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(String(localized: "People"))
        .task {
            ensureViewModel()
            await viewModel?.load()
        }
        .task(id: model.location.locale?.id) {
            ensureViewModel()
            await loadCards(force: true)
        }
        .refreshable {
            await model.location.refreshPosition()
            async let cards: Void = loadCards(force: true)
            await viewModel?.load()
            await cards
        }
    }

    @ViewBuilder
    private func localSections(_ local: PeopleListing.Local, in locale: AppLocale) -> some View {
        if local.isEmpty {
            DetailSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No one based in \(locale.name) yet.")
                        .foregroundStyle(.secondary)

                    Button(String(localized: "Show everyone")) {
                        scope = .everyone
                    }
                }
            }
        } else {
            ForEach(localGroupCards) { card in
                localCard(card, local, layoutID: cardLayout?.layout.id)
            }
        }
    }

    /// The local groups in the server's order (promoted cards between them)
    /// when it sent them, else the built-in order.
    private var localGroupCards: [LayoutCard] {
        let served = (cardLayout?.layout.cards ?? []).filter { $0.kind != CardKind.peopleEveryone }
        guard served.contains(where: { Self.localCards.contains($0.kind) }) else {
            return CardLayout.fallback(Self.localCards).cards
        }
        return served
    }

    @ViewBuilder
    private func localCard(_ card: LayoutCard, _ local: PeopleListing.Local, layoutID: String?) -> some View {
        switch card.kind {
        case CardKind.peoplePlayingThisWeek:
            let ranked = ordered(local.playing, by: card.personIDs, isFallback: card.isFallback)
            CardSection(String(localized: "Playing this week")) {
                ForEach(ranked.isEmpty ? local.playing : ranked) { playing in
                    PersonCardLink(
                        person: playing.entry.person,
                        description: gigLine(playing.gig),
                        friends: playing.entry.friends
                    )
                }
            }
        case CardKind.peopleBasedHere:
            let ranked = ordered(local.based, by: card.personIDs, isFallback: card.isFallback)
            CardSection(String(localized: "Based here")) {
                ForEach(ranked.isEmpty ? local.based : ranked) { entry in
                    PersonCardLink(person: entry.person, friends: entry.friends)
                }
            }
        case CardKind.web:
            if let content = card.web { WebCardView(content: content) }
        case CardKind.promoSlot:
            PromoSlotView(card: card, layoutID: layoutID)
        default:
            EmptyView()
        }
    }

    private func everyoneSection(_ listing: PeopleListing) -> some View {
        let card = cardLayout?.layout.card(CardKind.peopleEveryone)
        let ranked = card.map { ordered(listing.everyone, by: $0.personIDs, isFallback: $0.isFallback) } ?? []
        return CardSection {
            ForEach(ranked.isEmpty ? listing.everyone : ranked) { entry in
                PersonCardLink(person: entry.person, friends: entry.friends)
            }
        }
    }

    /// "Tonight · Neighbours", or "Fri · Neighbours" later in the week.
    private func gigLine(_ gig: PersonEntry.Gig) -> String {
        let day = Calendar.current.isDateInToday(gig.date)
            ? String(localized: "Tonight")
            : gig.date.formatted(.dateTime.weekday(.abbreviated))
        guard let venue = gig.venueName, !venue.isEmpty else { return day }
        return "\(day) · \(venue)"
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = PeopleViewModel(audienceKit: model.audienceKit)
        }
        if cardLayout == nil {
            cardLayout = ScreenLayout(audienceKit: model.audienceKit, screen: .people, kinds: Self.cardKinds,
                                      fallback: Self.localCards + [CardKind.peopleEveryone],
                                      appVersion: model.configuration.version)
        }
    }

    private func loadCards(force: Bool) async {
        await cardLayout?.load(coordinates: model.location.coordinates, localeID: model.location.locale?.id,
                               force: force)
    }

    private func reload() {
        Task {
            ensureViewModel()
            await viewModel?.load()
        }
    }
}
