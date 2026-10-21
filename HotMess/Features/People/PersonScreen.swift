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
                        HeroHeader(url: detail.person.bannerURL, topInset: proxy.safeAreaInsets.top, tone: $heroTone) {
                            heroText(detail.person)
                        }

                        if !detail.tipLinks.isEmpty {
                            tipButtons(detail)
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
                        } else {
                            CardSection(String(localized: "Events")) {
                                ForEach(detail.events) { event in
                                    EventCardLink(event: event, photoURL: event.photoURL(prioritizing: .venueFirst, personFallback: detail.person))
                                }
                            }
                        }

                        PostsSection(title: String(localized: "Posts"), subject: .person(detail.person.id))

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
                .trackingHeroCollapse($heroCollapsed)
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

    private func heroText(_ person: Person) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            Avatar(
                url: person.avatarURL,
                initials: person.name.initialsForDisplay,
                size: 76
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
        }
    }

    /// One button per app they take tips on; each opens that app on their profile.
    private func tipButtons(_ detail: PersonDetail) -> some View {
        VStack(spacing: 10) {
            ForEach(detail.tipLinks) { link in
                if let url = link.url, let app = link.tipApp {
                    Link(destination: url) {
                        Label(String(localized: "Tip on \(app)"), systemImage: "dollarsign.circle.fill")
                            .font(.hotMess(.body, semibold: true))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(String(localized: "Tip \(detail.name) on \(app)"))
                }
            }
        }
        .padding(.horizontal, 20)
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
