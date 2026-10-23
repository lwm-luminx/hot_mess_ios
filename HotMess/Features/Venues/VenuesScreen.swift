//
//  VenuesScreen.swift
//  HotMess
//

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

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { collection in
            ScrollView {
                VStack(spacing: 24) {
                    map(for: collection)
                        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
                        .padding(.horizontal, 16)

                    if collection.venues.isEmpty {
                        DetailSection(model.brand.name) {
                            Text(emptyMessage)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        CardSection(model.brand.name, edgeToEdge: true) {
                            ForEach(collection.venues) { venue in
                                VenueCardLink(venue: venue)
                            }
                        }
                    }

                    if model.session.isSignedIn {
                        ThinCityCard(venueCount: collection.venues.count, cityName: model.location.locale?.name)
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
            await viewModel?.load(localeID: model.location.locale?.id)
        }
        .refreshable {
            await model.location.refreshPosition()
            await viewModel?.load(localeID: model.location.locale?.id)
        }
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
            viewModel = VenuesViewModel(audienceKit: model.audienceKit)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            await viewModel?.load(localeID: model.location.locale?.id)
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
