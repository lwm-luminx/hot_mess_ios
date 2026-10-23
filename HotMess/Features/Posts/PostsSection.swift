//
//  PostsSection.swift
//  HotMess
//

import SwiftUI

/// A page's posts: the venue's "Posts", an event's "From the venue and hosts",
/// a talent's "Posts". Two cards, then "See all". Loads on its own, and draws
/// nothing while loading, when there are none, or on an API without posts,
/// except for whoever manages the page, who gets "New Post" there.
struct PostsSection: View {
    let title: String
    let subject: PostsSubject
    var limit = 2
    /// On an event page: its venue and the people on it, who may post there.
    var eventName: String?
    var eventVenueID: UUID?
    var eventPeople: [UUID] = []

    @Environment(AppModel.self) private var model
    @State private var postsModel: PostsModel?
    @State private var composing = false

    var body: some View {
        let posts = postsModel?.posts ?? []
        Group {
            if !posts.isEmpty || !authors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title)
                            .font(.hotMess(.subheadline, semibold: true))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !authors.isEmpty {
                            Button {
                                composing = true
                            } label: {
                                Label(String(localized: "New Post"), systemImage: "square.and.pencil")
                                    .font(.hotMess(.subheadline, semibold: true))
                            }
                            .accessibilityIdentifier("posts.new")
                        }
                        if posts.count > limit {
                            NavigationLink(value: AppRoute.posts(subject, title: title)) {
                                Text("See all")
                                    .font(.hotMess(.subheadline, semibold: true))
                            }
                            .accessibilityIdentifier("posts.seeAll")
                        }
                    }
                    .padding(.horizontal, 20)

                    if posts.isEmpty {
                        Text("No posts yet. Post a special, a flyer or a set time; it shows here and in the locale's updates.")
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    } else {
                        PostList(posts: Array(posts.prefix(limit)), postsModel: postsModel, showsEvent: !isEventPage)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $composing) {
            PostComposer(mode: .new(authors: authors, target: target)) { post in
                postsModel?.apply(.updated(post))
            }
        }
        .task {
            if postsModel == nil { postsModel = PostsModel(api: model.api, subject: subject) }
            if model.session.isSignedIn { await model.listings.load() }
            await postsModel?.load()
        }
    }

    /// Who the user can post as here: none for most people.
    private var authors: [PostAuthor] {
        model.listings.listings.authors(for: subject, eventVenueID: eventVenueID, eventPeople: eventPeople)
    }

    private var target: PostTarget {
        if case let .event(id) = subject { return .event(id, name: eventName ?? title) }
        return .page
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

    /// Where a manager's change goes: the list's model by default; the post
    /// screen passes its own.
    var onChange: ((PostChange) -> Void)?

    @Environment(AppModel.self) private var model
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?
    @State private var hiding: PostPoster?
    @State private var editing: Post?
    @State private var deleting: Post?
    @State private var manageError: String?

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
                        hidePoster: { hiding = $0 },
                        manage: { post, action in manage(post, action) }
                    )
                )
            }
        }
        .sheet(item: $editing) { post in
            PostComposer(mode: .edit(post)) { apply(.updated($0)) }
        }
        .confirmationDialog(
            String(localized: "Delete this post?"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { post in
            Button(String(localized: "Delete Post"), role: .destructive) {
                Task { await run { try await model.api.deletePost(post.id); return .deleted(post.id) } }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("It and its comments come off Hot Mess and hotmess.social.")
        }
        .alert(
            String(localized: "Something went wrong"),
            isPresented: Binding(get: { manageError != nil }, set: { if !$0 { manageError = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(manageError ?? "")
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

extension PostList {
    private func manage(_ post: Post, _ action: PostManageAction) {
        let api = model.api
        switch action {
        case .edit: editing = post
        case .delete: deleting = post
        case .togglePin:
            Task { await run { .updated(try await api.updatePost(post.id, pinned: !post.pinned)) } }
        case .toggleComments:
            Task { await run { .updated(try await api.updatePost(post.id, commentsOpen: !post.commentsOpen)) } }
        case .toggleVisibility:
            let visibility: PostVisibility = post.visibility == .public ? .community : .public
            Task { await run { .updated(try await api.updatePost(post.id, visibility: visibility)) } }
        case .toggleHiddenFromEvent:
            Task { await run { .updated(try await api.hidePostFromEvent(post.id, hidden: !post.hiddenFromEvent)) } }
        }
    }

    private func run(_ change: () async throws -> PostChange) async {
        do {
            apply(try await change())
        } catch {
            manageError = NowViewModel.message(for: error)
        }
    }

    private func apply(_ change: PostChange) {
        if let onChange {
            onChange(change)
        } else {
            postsModel?.apply(change)
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
                PostList(
                    posts: posts,
                    postsModel: postsModel,
                    showsPin: subject.floatsPins,
                    showsEvent: !isEventPage,
                    spacing: 20
                )
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
