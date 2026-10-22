//
//  UpdatesScreen.swift
//  HotMess
//

import SwiftUI

/// "Updates in {locale}", from Now's "See all": the locale's posts from the
/// last 14 days, newest first, filtered to All, Venues, Talent or the events
/// you're going to. Pins don't float here.
struct UpdatesScreen: View {
    let locale: AppLocale

    @Environment(AppModel.self) private var model
    @State private var postsModel: PostsModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterChips

                switch postsModel?.state ?? .loading {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case let .failed(message, _):
                    ContentUnavailableView {
                        Label(String(localized: "Couldn't load updates"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button(String(localized: "Try Again")) { Task { await postsModel?.load() } }
                    }
                case let .loaded(posts) where posts.isEmpty:
                    ContentUnavailableView(
                        String(localized: "No updates yet"),
                        systemImage: "megaphone",
                        description: Text(emptyText)
                    )
                case let .loaded(posts):
                    PostList(posts: posts, postsModel: postsModel, showsPin: false, spacing: 20)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .refreshable { await postsModel?.load() }
        .navigationTitle(String(localized: "Updates in \(locale.name)"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if postsModel == nil { postsModel = PostsModel(api: model.api, subject: .locale(locale)) }
            await postsModel?.load()
        }
    }

    private var filters: [PostsFilter] {
        // Going needs someone signed in to have RSVP'd.
        model.session.isSignedIn ? PostsFilter.allCases : PostsFilter.allCases.filter { $0 != .going }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    let selected = postsModel?.filter == filter
                    Button {
                        guard let postsModel, postsModel.filter != filter else { return }
                        postsModel.filter = filter
                        Task { await postsModel.load() }
                    } label: {
                        Text(filter.title)
                            .font(.hotMess(.subheadline, semibold: true))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .foregroundStyle(selected ? Color.hotMessAccentInk : .primary)
                            .background(selected ? Color.hotMessAccentSoft : Color.hotMessControlFill, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("updates.filter.\(filter.rawValue.lowercased())")
                }
            }
        }
    }

    private var emptyText: String {
        switch postsModel?.filter ?? .all {
        case .all: String(localized: "Posts from venues and talent in \(locale.name) show here.")
        case .venues: String(localized: "No venue posts in the last two weeks.")
        case .talent: String(localized: "No talent posts in the last two weeks.")
        case .going: String(localized: "Posts on events you're going to show here.")
        }
    }
}
