//
//  PostsSection.swift
//  HotMess
//

import SwiftUI

/// A page's posts: the venue's "Posts", an event's "From the venue and hosts",
/// a talent's "Posts". Two cards, then "See all". Loads on its own, and draws
/// nothing while loading, when there are none, or on an API without posts.
struct PostsSection: View {
    let title: String
    let subject: PostsSubject
    var limit = 2

    @Environment(AppModel.self) private var model
    @State private var postsModel: PostsModel?

    var body: some View {
        let posts = postsModel?.posts ?? []
        Group {
            if !posts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title)
                            .font(.hotMess(.subheadline, semibold: true))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if posts.count > limit {
                            NavigationLink(value: AppRoute.posts(subject, title: title)) {
                                Text("See all")
                                    .font(.hotMess(.subheadline, semibold: true))
                            }
                            .accessibilityIdentifier("posts.seeAll")
                        }
                    }
                    .padding(.horizontal, 20)

                    PostList(posts: Array(posts.prefix(limit)), postsModel: postsModel, showsEvent: !isEventPage)
                }
                .padding(.horizontal, 16)
            }
        }
        .task {
            if postsModel == nil { postsModel = PostsModel(api: model.api, subject: subject) }
            await postsModel?.load()
        }
    }

    private var isEventPage: Bool {
        if case .event = subject { return true }
        return false
    }
}

/// Cards with their report and hide flows, `space-4` apart.
struct PostList: View {
    let posts: [Post]
    let postsModel: PostsModel?
    var showsPin = true
    var showsEvent = true
    /// The full text, on the post screen.
    var isExpanded = false
    var spacing: CGFloat = 16

    @Environment(AppModel.self) private var model
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?
    @State private var hiding: PostPoster?

    var body: some View {
        LazyVStack(spacing: spacing) {
            ForEach(posts) { post in
                PostCard(
                    post: post,
                    showsPin: showsPin,
                    showsEvent: showsEvent,
                    isExpanded: isExpanded,
                    actions: PostActions(
                        report: { reportSubject = ReportSubject(target: .post, targetID: $0.id.uuidString.lowercased()) },
                        hidePoster: { hiding = $0 }
                    )
                )
            }
        }
        .contentReporting(report: $reportSubject, block: $blockTarget)
        .confirmationDialog(
            hiding.map { String(localized: "Hide posts from \($0.name)?") } ?? "",
            isPresented: Binding(get: { hiding != nil }, set: { if !$0 { hiding = nil } }),
            titleVisibility: .visible,
            presenting: hiding
        ) { poster in
            Button(String(localized: "Hide Posts"), role: .destructive) {
                Task {
                    if let postsModel {
                        await postsModel.hide(poster)
                    } else {
                        // The post screen: nothing to drop, just mute them.
                        try? await model.api.mutePosts(from: poster)
                    }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("You won't see their posts in Hot Mess. Their page and chat stay as they are.")
        }
        .alert(
            String(localized: "Something went wrong"),
            isPresented: Binding(
                get: { postsModel?.errorMessage != nil },
                set: { if !$0 { postsModel?.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(postsModel?.errorMessage ?? "")
        }
    }
}

/// Every post on a page, from its section's "See all".
struct PostsScreen: View {
    let subject: PostsSubject
    let title: String

    @Environment(AppModel.self) private var model
    @State private var postsModel: PostsModel?

    var body: some View {
        LoadStateView(state: postsModel?.state ?? .loading, retry: reload) { posts in
            ScrollView {
                PostList(posts: posts, postsModel: postsModel, showsPin: subject.floatsPins, showsEvent: !isEventPage, spacing: 20)
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .refreshable { await postsModel?.load() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }

    private var isEventPage: Bool {
        if case .event = subject { return true }
        return false
    }

    private func reload() {
        if postsModel == nil { postsModel = PostsModel(api: model.api, subject: subject) }
        Task { await postsModel?.load() }
    }
}

/// Now's posts as compact rows: "Latest from tonight" at an event or venue
/// (the last 24 hours), "Updates in {locale}" away from them. Two rows and
/// "See all"; left out when there are none.
struct NowPostsSection: View {
    let title: String
    let subject: PostsSubject
    /// Only posts this recent, in hours; nil for the feed's own window.
    var withinHours: Double?
    /// Where "See all" goes.
    let seeAll: AppRoute

    @Environment(AppModel.self) private var model
    @State private var postsModel: PostsModel?

    var body: some View {
        let posts = Array(shown.prefix(2))
        DetailSection(title) {
            ForEach(posts) { post in
                NavigationLink(value: AppRoute.post(post.id)) {
                    PostRow(post: post)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("now.post")
            }
            if !posts.isEmpty {
                DetailLink(route: seeAll) {
                    Text("See all")
                        .font(.hotMess(.subheadline, semibold: true))
                }
            }
        }
        .task(id: subject) {
            postsModel = PostsModel(api: model.api, subject: subject)
            await postsModel?.load()
        }
    }

    private var shown: [Post] {
        guard let postsModel else { return [] }
        return withinHours.map { postsModel.recent(within: $0) } ?? postsModel.posts
    }
}
