//
//  EventsScreen.swift
//  HotMess
//

import SwiftUI

/// The events tab, replacing `EventsViewController`.
struct EventsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: EventsViewModel?
    /// The night picked on the calendar; nil lists every upcoming event.
    @State private var selectedNight: Date?

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { listing in
            if listing.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Events"),
                    systemImage: "calendar",
                    description: Text("Nothing is scheduled near you just yet.")
                )
            } else {
                let nights = NightCalendar(events: listing.allEvents)

                ScrollView {
                    VStack(spacing: 24) {
                        DetailSection {
                            NightCalendarView(calendar: nights, selection: $selectedNight)
                        }

                        if let night = nights.nights.first(where: { $0.date == selectedNight }) {
                            eventsSection(
                                night.date.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                                events: night.events,
                                empty: String(localized: "Nothing on this night yet.")
                            )
                        } else {
                            ForEach(listing.sections) { section in
                                eventsSection(
                                    section.title,
                                    events: section.events,
                                    empty: String(localized: "No events."),
                                    featured: section.isFeatured
                                )
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(model.location.locale?.name ?? String(localized: "Events"))
        .task(id: model.location.locale?.id) {
            selectedNight = nil
            ensureViewModel()
            await viewModel?.load(localeID: model.location.locale?.id)
        }
        .refreshable {
            await model.location.refreshPosition()
            await viewModel?.load(localeID: model.location.locale?.id)
        }
    }

    @ViewBuilder
    private func eventsSection(_ title: String, events: [Event], empty: String, featured: Bool = false) -> some View {
        if events.isEmpty {
            DetailSection(title) {
                Text(empty)
                    .foregroundStyle(.secondary)
            }
        } else {
            CardSection(title) {
                ForEach(events) { event in
                    // Featured is sized as featured; elsewhere a card goes by the event's own flag.
                    EventCardLink(event: event, featured: featured ? true : nil)
                }
            }
        }
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = EventsViewModel(api: model.api)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            await viewModel?.load(localeID: model.location.locale?.id)
        }
    }
}
