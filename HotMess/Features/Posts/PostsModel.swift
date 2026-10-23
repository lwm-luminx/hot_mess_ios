//
//  PostsModel.swift
//  HotMess
//

import Foundation
import Observation

/// A list of posts: a page's section, the "See all" screen, or the updates feed.
@MainActor
@Observable
final class PostsModel {
    private(set) var state: LoadState<[Post]> = .idle
    var filter: PostsFilter = .all
    /// Set when hiding a poster didn't go through.
    var errorMessage: String?

    let subject: PostsSubject
    private let api: HotMessAPI

    init(api: HotMessAPI, subject: PostsSubject) {
        self.api = api
        self.subject = subject
    }

    var posts: [Post] { state.value ?? [] }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await api.posts(subject, from: filter))
        } catch is CancellationError {
        } catch {
            state = LoadState(catching: error)
        }
    }

    /// "Hide posts from {name}": mutes them and drops their posts here at once.
    func hide(_ poster: PostPoster) async {
        do {
            try await api.mutePosts(from: poster)
            state = .loaded(posts.filter { $0.poster != poster })
        } catch {
            errorMessage = String(localized: "Couldn't hide their posts. Please try again.")
        }
    }

    /// A manager's change, shown at once: an edit in place (pins re-sorted
    /// where they float), a new post on top, a deleted one gone.
    func apply(_ change: PostChange) {
        var posts = posts
        switch change {
        case let .updated(post):
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = post
            } else {
                posts.insert(post, at: 0)
            }
        case let .deleted(id):
            posts.removeAll { $0.id == id }
        }
        if subject.floatsPins {
            // Stable: pinned first, each group keeping its order.
            posts = posts.filter(\.pinned) + posts.filter { !$0.pinned }
        }
        state = .loaded(posts)
    }

    /// Posts from the last `hours`, for Now's "Latest from tonight".
    func recent(within hours: Double, now: Date = .now) -> [Post] {
        posts.filter { now.timeIntervalSince($0.createdAt) <= hours * 3600 }
    }
}

/// What a manager did to a post, for the lists showing it.
enum PostChange: Hashable, Sendable {
    case updated(Post)
    case deleted(UUID)
}
