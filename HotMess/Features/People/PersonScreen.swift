//
//  PersonScreen.swift
//  HotMess
//

import SwiftUI

/// Person detail, replacing `PersonViewController`.
struct PersonScreen: View {
    let personID: UUID

    @Environment(AppModel.self) private var model
    @State private var viewModel: PersonViewModel?
    @State private var heroTone = HeroTone.placeholder
    @State private var heroCollapsed = false
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?

    var body: some View {
        LoadStateView(state: viewModel?.state ?? .loading, retry: reload) { detail in
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        HeroHeader(
                            url: detail.person.bannerURL,
                            topInset: proxy.safeAreaInsets.top,
                            tone: $heroTone,
                            bodyHeight: HeroMetrics.detailHeight
                        ) {
                            heroText(detail)
                        }

                        DetailSection(String(localized: "Elsewhere")) {
                            ForEach(detail.profileLinks) { link in
                                SocialLinkRow(link: link)
                            }
                        }

                        if !detail.members.isEmpty {
                            CardSection(String(localized: "Members")) {
                                ForEach(detail.members) { member in
                                    PersonCardLink(person: member)
                                }
                            }
                        }

                        if !detail.groups.isEmpty {
                            CardSection(String(localized: "Part of")) {
                                ForEach(detail.groups) { group in
                                    PersonCardLink(person: group)
                                }
                            }
                        }

                        if detail.events.isEmpty {
                            DetailSection(String(localized: "Events")) {
                                Text("No upcoming events.")
                                    .foregroundStyle(.secondary)
                            }
                        } else if detail.events.count > 1 {
                            // The next one is on the hero.
                            CardSection(String(localized: "More Events")) {
                                ForEach(detail.events.dropFirst()) { event in
                                    EventCardLink(event: event, photoURL: event.photoURL(prioritizing: .venueFirst, personFallback: detail.person))
                                }
                            }
                        }

                        PostsSection(title: String(localized: "Posts"), subject: .person(detail.person.id))

                        PhotosSection(subject: .person(detail.person.id), title: String(localized: "On stage"))

                        if !detail.tracks.isEmpty {
                            DetailSection(String(localized: "Tracks")) {
                                ForEach(detail.tracks) { track in
                                    trackRow(track)
                                }
                            } footer: {
                                Image("PoweredBySoundCloud")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 20)
                                    .accessibilityLabel(String(localized: "Powered by SoundCloud"))
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
        }
        .heroNavigationBar(
            title: viewModel?.state.value?.name ?? String(localized: "Person"),
            tone: heroTone,
            collapsed: heroCollapsed || viewModel?.state.value == nil
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        reportSubject = ReportSubject(target: .person, targetID: personID.uuidString.lowercased())
                    } label: {
                        Label(String(localized: "Report Creator…"), systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .accessibilityIdentifier("person.optionsMenu")
            }
        }
        .contentReporting(report: $reportSubject, block: $blockTarget)
        .task {
            ensureViewModel()
            await viewModel?.load()
        }
    }

    // MARK: - Pieces

    private func heroText(_ detail: PersonDetail) -> some View {
        let person = detail.person

        return VStack(alignment: .leading, spacing: 10) {
            Avatar(
                url: person.avatarURL,
                initials: person.name.initialsForDisplay,
                size: 104
            )
            .overlay { Circle().strokeBorder(.foreground, lineWidth: 3) }

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.hotMess(.title, semibold: true))
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)

                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.hotMess(.subheadline, semibold: true))
                }
            }

            if let next = detail.events.first {
                NavigationLink(value: AppRoute.event(next.id)) {
                    HStack(spacing: 6) {
                        Text("Next: \(nextLine(next))")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .heroGlass(fillsWidth: false)
                }
                .buttonStyle(.plain)
            }

            if !detail.tipLinks.isEmpty {
                HeroActionRow {
                    tipButton(detail)
                }
            }
        }
    }

    /// "Tonight · Neighbours", or "Fri · Neighbours" later on.
    private func nextLine(_ event: Event) -> String {
        let day = Calendar.current.isDateInToday(event.startDate)
            ? String(localized: "Tonight")
            : event.startDate.formatted(.dateTime.weekday(.abbreviated))
        let place = event.venue?.name ?? event.name
        return "\(day) · \(place)"
    }

    /// Tip: straight to the app they take tips on, or a choice of apps when
    /// there are several.
    @ViewBuilder
    private func tipButton(_ detail: PersonDetail) -> some View {
        let tips = detail.tipLinks.compactMap(Tip.init)

        if tips.count == 1, let tip = tips.first {
            Link(destination: tip.url) {
                Label(String(localized: "Tip on \(tip.app)"), systemImage: "dollarsign.circle.fill")
                    .heroGlass()
            }
            .accessibilityLabel(String(localized: "Tip \(detail.name) on \(tip.app)"))
        } else if !tips.isEmpty {
            Menu {
                ForEach(tips) { tip in
                    Link(destination: tip.url) {
                        Text("Tip on \(tip.app)")
                    }
                    .accessibilityLabel(String(localized: "Tip \(detail.name) on \(tip.app)"))
                }
            } label: {
                Label(String(localized: "Tip"), systemImage: "dollarsign.circle.fill")
                    .heroGlass()
            }
        }
    }

    private struct Tip: Identifiable {
        let id: UUID
        let url: URL
        let app: String

        init?(_ link: SocialLink) {
            guard let url = link.url, let app = link.tipApp else { return nil }
            id = link.id
            self.url = url
            self.app = app
        }
    }

    @ViewBuilder
    private func trackRow(_ track: Track) -> some View {
        if let url = track.providerURL {
            Link(destination: url) {
                TrackRow(track: track)
            }
            .buttonStyle(.plain)
        } else {
            TrackRow(track: track)
        }
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = PersonViewModel(api: model.api, personID: personID)
        }
    }

    private func reload() {
        Task {
            ensureViewModel()
            await viewModel?.load()
        }
    }
}
