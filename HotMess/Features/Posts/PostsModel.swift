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

    /// Posts from the last `hours`, for Now's "Latest from tonight".
    func recent(within hours: Double, now: Date = .now) -> [Post] {
        posts.filter { now.timeIntervalSince($0.createdAt) <= hours * 3600 }
    }
}
