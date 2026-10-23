//
//  VenuesScreen.swift
//  HotMess
//

import AudienceKit
import MapKit
import SwiftUI

/// The venues tab, replacing `VenuesViewController` — a table view controller
/// with a map view wired in through an outlet, which force-unwrapped that
/// outlet on every refresh.
struct VenuesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: VenuesViewModel?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isMapExpanded = false
    /// The cards under the map, ranked by the server.
    @State private var cardLayout: ScreenLayout?

    /// Under the map: every venue, then "help fill your city". The server can
    /// add what's on tonight, what's nearby, announcements and promoted cards.
    static let fallbackCards = [CardKind.venuesAll, CardKind.venuesThinCity]
    static let cardKinds = [CardKind.venuesTonight, CardKind.venuesNearby] + fallbackCards
        + [CardKind.web, CardKind.promoSlot]

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { collection in
            ScrollView {
                VStack(spacing: 24) {
                    map(for: collection)
                        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
                        .padding(.horizontal, 16)

                    // The server sends no list for a city it doesn't know yet; the
                    // screen's own order stands in then.
                    let served = cardLayout?.layout
                    let layout = served?.card(CardKind.venuesAll) != nil ? served! : .fallback(Self.fallbackCards)
                    ForEach(layout.cards) { card in
                        venuesCard(card, collection: collection, layoutID: layout.id)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .fullScreenCover(isPresented: $isMapExpanded) {
                VenuesMapScreen(collection: collection) { pin in
                    isMapExpanded = false
                    model.venuesPath.append(.venue(pin.id))
                }
                .environment(model)
            }
        }
        .navigationTitle(model.location.locale?.name ?? String(localized: "Venues"))
        .task(id: model.location.locale?.id) {
            ensureViewModel()
            async let cards: Void = loadCards(force: true)
            await viewModel?.load(localeID: model.location.locale?.id)
            await cards
        }
        .task {
            // The ranking moves with the night: ask again when it says to.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(cardLayout?.layout.refreshAfter ?? 60))
                await loadCards(force: false)
            }
        }
        .refreshable {
            await model.location.refreshPosition()
            async let cards: Void = loadCards(force: true)
            await viewModel?.load(localeID: model.location.locale?.id)
            await cards
        }
    }

    @ViewBuilder
    private func venuesCard(_ card: LayoutCard, collection: VenueCollection, layoutID: String?) -> some View {
        switch card.kind {
        case CardKind.venuesAll:
            let ranked = ordered(collection.venues, by: card.venueIDs, isFallback: card.isFallback)
            let venues = ranked.isEmpty ? collection.venues : ranked
            if venues.isEmpty {
                DetailSection(card.title ?? model.brand.name) {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                CardSection(card.title ?? model.brand.name, grouped: true) {
                    ForEach(venues) { venue in
                        VenueCardLink(venue: venue, nextEvent: viewModel?.nextEvents[venue.id])
                    }
                }
            }
        case CardKind.venuesTonight, CardKind.venuesNearby:
            // Only the server sends these, with their own heading.
            CardSection(card.title, grouped: true) {
                ForEach(ordered(collection.venues, by: card.venueIDs, isFallback: false)) { venue in
                    VenueCardLink(venue: venue, nextEvent: viewModel?.nextEvents[venue.id])
                }
            }
        case CardKind.venuesThinCity:
            if model.session.isSignedIn {
                ThinCityCard(venueCount: collection.venues.count, cityName: model.location.locale?.name)
            }
        case CardKind.web:
            if let content = card.web { WebCardView(content: content) }
        case CardKind.promoSlot:
            PromoSlotView(card: card, layoutID: layoutID)
        default:
            EmptyView()
        }
    }

    private func loadCards(force: Bool) async {
        await cardLayout?.load(coordinates: model.location.coordinates, localeID: model.location.locale?.id,
                               force: force)
    }

    private var emptyMessage: String {
        if let name = model.location.locale?.name, !name.isEmpty {
            return String(localized: "No venues in \(name) yet.")
        }
        return String(localized: "No venues yet.")
    }

    /// The inline map is a preview: tapping anywhere on it opens the full
    /// screen map, which is where panning and zooming happen.
    private func map(for collection: VenueCollection) -> some View {
        Map(position: $camera, interactionModes: []) {
            ForEach(collection.pins) { pin in
                Marker(pin.name, coordinate: pin.coordinate)
                    .tint(Color.hotMessAccent)
            }
            UserAnnotation()
        }
        .allowsHitTesting(false)
        .overlay {
            Button {
                isMapExpanded = true
            } label: {
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                            .padding(10)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Map of venues"))
            .accessibilityHint(Text("Opens the map full screen"))
        }
        .frame(height: 220)
        .onChange(of: collection) { _, updated in
            updateCamera(for: updated)
        }
        .onAppear { updateCamera(for: collection) }
        .onChange(of: model.location.coordinates) { updateCamera(for: collection) }
    }

    private func updateCamera(for collection: VenueCollection) {
        guard let region = collection.region(including: model.location.coordinates) else { return }
        camera = .region(region)
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = VenuesViewModel(audienceKit: model.audienceKit, api: model.api)
        }
        if cardLayout == nil {
            cardLayout = ScreenLayout(audienceKit: model.audienceKit, screen: .venues, kinds: Self.cardKinds,
                                      fallback: Self.fallbackCards, appVersion: model.configuration.version)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            async let cards: Void = loadCards(force: true)
            await viewModel?.load(localeID: model.location.locale?.id)
            await cards
        }
    }
}

/// The venues map at full screen. Tapping a pin opens that venue; Done closes
/// the map.
private struct VenuesMapScreen: View {
    let collection: VenueCollection
    let open: (VenuePin) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: UUID?

    var body: some View {
        NavigationStack {
            Map(position: $camera, selection: $selection) {
                ForEach(collection.pins) { pin in
                    Marker(pin.name, coordinate: pin.coordinate)
                        .tint(Color.hotMessAccent)
                        .tag(pin.id)
                }
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(Text("Venues"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let pin = selectedPin {
                    Button {
                        open(pin)
                    } label: {
                        Label(pin.name, systemImage: "chevron.right")
                            .labelStyle(.titleAndTrailingIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.hotMessAccent)
                    .controlSize(.large)
                    .padding()
                }
            }
            .task {
                model.location.start()
                await model.location.refreshPosition()
            }
            .onAppear {
                if let region = collection.region(including: model.location.coordinates) {
                    camera = .region(region)
                }
            }
        }
    }

    private var selectedPin: VenuePin? {
        collection.pins.first { $0.id == selection }
    }
}

private struct TitleAndTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.title
            configuration.icon
        }
    }
}

private extension LabelStyle where Self == TitleAndTrailingIconLabelStyle {
    static var titleAndTrailingIcon: TitleAndTrailingIconLabelStyle { .init() }
}
