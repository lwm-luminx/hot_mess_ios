//
//  LocaleShowcase.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// A locale on the Venues tab's Everywhere view (`locales.showcase`): its
/// name over one of its venues' photos, moving on to the next of the few the
/// server picked every few seconds. Tapping it opens the locale's page.
struct LocaleShowcaseCard: View {
    let localeID: UUID
    let name: String
    /// The venues to show in turn, in the server's order.
    let venues: [Venue]

    /// How long each venue shows.
    static let interval: TimeInterval = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationLink(value: AppRoute.locale(localeID, name: name)) {
            if reduceMotion || venues.count < 2 {
                card(showing: venues.first)
            } else {
                TimelineView(.periodic(from: .now, by: Self.interval)) { context in
                    let index = Int(context.date.timeIntervalSinceReferenceDate / Self.interval) % venues.count
                    card(showing: venues[index])
                        .animation(.easeInOut(duration: 0.6), value: venues[index].id)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.locale.\(localeID)")
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(venues.map(\.name).formatted(.list(type: .and))))
        .accessibilityHint(Text("Shows its events and venues"))
    }

    private func card(showing venue: Venue?) -> some View {
        RecordCard(
            title: name,
            description: venue?.name,
            photoURL: venue?.bannerURL ?? venue?.photoURL,
            minHeight: CardMetrics.featuredHeight,
            topClearance: 44,
            titleStyle: .title2,
            descriptionLines: 1
        ) {
            EmptyView()
        } trailing: {
            if venues.count > 1, let venue, let position = venues.firstIndex(of: venue) {
                HStack(spacing: 4) {
                    ForEach(venues.indices, id: \.self) { index in
                        Circle()
                            .fill(index == position ? Color.white : Color.white.opacity(0.45))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityHidden(true)
            }
        }
        .id(venue?.id)
        .transition(.opacity)
    }
}

/// A locale's page, opened from its card on the Everywhere view: some of its
/// events and its venues, in the order the server's `LOCALE` layout gives.
/// Without the layout it shows the locale's next events, then its venues.
struct LocaleScreen: View {
    let localeID: UUID
    let name: String

    @Environment(AppModel.self) private var model
    @State private var cardLayout: ScreenLayout?
    @State private var venues: LoadState<VenueCollection> = .idle
    /// Every visible venue in the audience, to pick the server's ids from: a
    /// public venue filed under another locale can still list here.
    @State private var allVenues = VenueCollection()
    @State private var events: [Event] = []

    static let fallbackCards = [CardKind.eventsUpcoming, CardKind.venuesAll]
    static let cardKinds = [CardKind.eventsUpcoming, CardKind.venuesTonight, CardKind.venuesAll, CardKind.web,
                            CardKind.promoSlot]
    /// How many events the built-in order shows.
    static let fallbackEventCount = 8

    var body: some View {
        LoadStateView(state: venues, retry: { Task { await load() } }) { local in
            ScrollView {
                VStack(spacing: 24) {
                    // A layout without the locale's venues (a city the server doesn't know) gets the built-in order.
                    let served = cardLayout?.layout
                    let layout = served?.card(CardKind.venuesAll) != nil ? served! : .fallback(Self.fallbackCards)
                    ForEach(layout.cards) { card in
                        localeCard(card, local: local, layoutID: layout.id)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(name)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func localeCard(_ card: LayoutCard, local: VenueCollection, layoutID: String?) -> some View {
        switch card.kind {
        case CardKind.eventsUpcoming:
            let picked = card.isFallback ? [] : ordered(events, by: card.eventIDs, isFallback: false)
            // Ids this list doesn't have (an event at a venue filed elsewhere) fall back to the next few.
            let shown = picked.isEmpty ? Array(events.prefix(Self.fallbackEventCount)) : picked
            CardSection(card.title ?? String(localized: "Coming up")) {
                ForEach(shown) { event in
                    EventCardLink(event: event)
                }
            }
        case CardKind.venuesTonight:
            CardSection(card.title, grouped: true) {
                ForEach(ordered(allVenues.venues, by: card.venueIDs, isFallback: false)) { venue in
                    VenueCardLink(venue: venue, nextEvent: nextEvents[venue.id])
                }
            }
        case CardKind.venuesAll:
            let picked = ordered(allVenues.venues, by: card.venueIDs, isFallback: card.isFallback)
            let shown = card.isFallback || picked.isEmpty ? local.venues : picked
            if shown.isEmpty {
                DetailSection(card.title ?? name) {
                    Text("No venues in \(name) yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                CardSection(card.title ?? name, grouped: true) {
                    ForEach(shown) { venue in
                        VenueCardLink(venue: venue, nextEvent: nextEvents[venue.id])
                    }
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

    private var nextEvents: [UUID: Event] { VenuesViewModel.nextEvents(events) }

    private func load() async {
        let layout = cardLayout ?? ScreenLayout(audienceKit: model.audienceKit, screen: .locale,
                                                kinds: Self.cardKinds, fallback: Self.fallbackCards,
                                                appVersion: model.configuration.version)
        cardLayout = layout
        if venues.value == nil { venues = .loading }
        // The page goes by the locale, never where the device is.
        async let cards: Void = layout.load(coordinates: nil, localeID: localeID, force: true)
        let api = model.api
        let localeID = localeID
        async let loadedEvents = try? api.eventList(in: localeID)
        do {
            let audienceVenues = try await model.audienceKit.venues()
            let resolve = model.audienceKit.url(for:)
            allVenues = VenueCollection(audienceVenues: audienceVenues, localeID: nil, resolve: resolve)
            venues = .loaded(VenueCollection(audienceVenues: audienceVenues, localeID: localeID, resolve: resolve))
        } catch is CancellationError {
        } catch let error as AudienceKitError {
            venues = LoadState(catching: APIError(error))
        } catch {
            venues = LoadState(catching: error)
        }
        events = (await loadedEvents) ?? []
        await cards
    }
}
