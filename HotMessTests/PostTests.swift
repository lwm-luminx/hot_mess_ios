//
//  PostTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

private enum PostFixtures {
    static let wildrose = "6f1c2c1e-4d2a-4f6b-9a37-0c1d2e3f4a5b"
    static let kiki = "7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d"
    static let bingo = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"

    static let venuePost = """
    {"id":"11111111-2222-4333-8444-555555555555","body":"Two-for-one wells until 10.","posterName":"The Wildrose",
     "posterAvatarUrl":"https://cdn.example.com/w.jpg","roleLabel":"Venue","actingPersonName":null,
     "createdAt":"2026-10-21T18:00:00Z","edited":true,"pinned":true,"commentsOpen":true,"commentCount":3,
     "photos":[{"url":"https://cdn.example.com/1.jpg","altText":"The bar"},{"url":null,"altText":null}],
     "event":{"id":"\(bingo)","name":"Drag Bingo","startAt":"2026-10-24T04:00:00Z"},
     "person":null,"venue":{"id":"\(wildrose)"}}
    """

    static let talentPost = """
    {"id":"22222222-3333-4444-8555-666666666666","body":"See you tonight!","posterName":"House of Lux",
     "posterAvatarUrl":null,"roleLabel":"Troupe","actingPersonName":"Kiki Riot for House of Lux",
     "createdAt":"2026-10-21T19:00:00Z","edited":false,"pinned":false,"commentsOpen":false,"commentCount":0,
     "photos":[],"event":null,"person":{"id":"\(kiki)"},"venue":null}
    """
}

@Suite("Posts")
struct PostTests {
    private func decode(_ json: String) throws -> Post {
        try JSONDecoder.hotMess.decode(Post.self, from: Data(json.utf8))
    }

    @Test("Reads a venue's post, dropping photos without a URL")
    func venuePost() throws {
        let post = try decode(PostFixtures.venuePost)

        #expect(post.isVenuePost)
        #expect(post.posterRoute == .venue(UUID(uuidString: PostFixtures.wildrose)!))
        #expect(post.photos.count == 1)
        #expect(post.photos.first?.altText == "The bar")
        #expect(post.event?.name == "Drag Bingo")
        #expect(post.poster == .venue(UUID(uuidString: PostFixtures.wildrose)!, name: "The Wildrose"))
    }

    @Test("Reads a troupe's post written by a member")
    func talentPost() throws {
        let post = try decode(PostFixtures.talentPost)

        #expect(!post.isVenuePost)
        #expect(post.posterRoute == .person(UUID(uuidString: PostFixtures.kiki)!))
        #expect(post.actingPersonName == "Kiki Riot for House of Lux")
        #expect(!post.commentsOpen)
    }

    @Test("Metadata says pinned, when, edited and the event, as the page needs")
    func metadata() throws {
        let post = try decode(PostFixtures.venuePost)
        let now = post.createdAt.addingTimeInterval(2 * 3600)

        #expect(post.metadata(relativeTo: now) == "Pinned · 2h · Edited · on Drag Bingo")
        #expect(post.metadata(relativeTo: now, showsPin: false, showsEvent: false) == "2h · Edited")
    }

    @Test("Relative times step from now to minutes, hours and days")
    func relativeTime() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        #expect(Post.relativeTime(date, now: date.addingTimeInterval(30)) == "now")
        #expect(Post.relativeTime(date, now: date.addingTimeInterval(5 * 60)) == "5m")
        #expect(Post.relativeTime(date, now: date.addingTimeInterval(3 * 86400)) == "3d")
    }

    @Test("Reads a list of posts under any page's root")
    func list() throws {
        let json = """
        {"venues":{"venue":{"posts":{"list":{"nodes":[\(PostFixtures.venuePost),\(PostFixtures.talentPost)]}}}}}
        """
        let response = try JSONDecoder.hotMess.decode(PostsResponse.self, from: Data(json.utf8))
        #expect(response.posts.count == 2)

        let missing = try JSONDecoder.hotMess.decode(PostsResponse.self, from: Data(#"{"venues":{"venue":null}}"#.utf8))
        #expect(missing.posts.isEmpty)
    }

    @Test("Makes web links in a post tappable")
    func links() {
        let text = PostBodyText.linked("Tickets at https://example.com/tix tonight")
        #expect(text.runs.contains { $0.link == URL(string: "https://example.com/tix") })
    }

    @Test("Opens a post from its link")
    func deepLink() {
        let id = UUID()
        let url = URL(string: "https://hotmess.social/posts/\(id.uuidString.lowercased())")!
        #expect(DeepLink.route(for: url) == .post(id))
    }

    @Test("Reads Public or Community, Community when the API doesn't say")
    func visibility() throws {
        #expect(try decode(PostFixtures.venuePost).visibility == .community)
        let publicPost = PostFixtures.venuePost.replacingOccurrences(
            of: #""edited":true"#,
            with: #""edited":true,"visibility":"PUBLIC""#
        )
        #expect(try decode(publicPost).visibility == .public)
    }

    @Test("Shares the post's own page")
    func shareURL() throws {
        let post = try decode(PostFixtures.venuePost)
        #expect(post.shareURL == URL(string: "https://hotmess.social/posts/11111111-2222-4333-8444-555555555555"))
    }

    @Test("Lets a manager manage their own posts and hide talent posts from their venue's events")
    func managedListings() throws {
        let wildrose = UUID(uuidString: PostFixtures.wildrose)!
        let kiki = UUID(uuidString: PostFixtures.kiki)!
        let venuePost = try decode(PostFixtures.venuePost)
        let talentOnEvent = try decode(PostFixtures.talentPost.replacingOccurrences(
            of: #""event":null"#,
            with: #""event":{"id":"\#(PostFixtures.bingo)","name":"Drag Bingo"}"#
        ).replacingOccurrences(of: #""venue":null"#, with: #""venue":{"id":"\#(PostFixtures.wildrose)"}"#))

        let venueManager = ManagedListings(venues: [.venue(wildrose, name: "The Wildrose")])
        #expect(venueManager.canManage(venuePost))
        #expect(!venueManager.canManage(talentOnEvent))
        #expect(venueManager.canHideFromEvent(talentOnEvent))
        #expect(!venueManager.canHideFromEvent(venuePost))

        let talent = ManagedListings(people: [.person(kiki, name: "House of Lux")])
        #expect(talent.canManage(talentOnEvent))
        #expect(!talent.canHideFromEvent(talentOnEvent))
        #expect(ManagedListings.none.authors(for: .venue(wildrose)).isEmpty)

        let bingo = UUID(uuidString: PostFixtures.bingo)!
        let both = ManagedListings(venues: venueManager.venues, people: talent.people)
        #expect(both.authors(for: .event(bingo), eventVenueID: wildrose, eventPeople: [kiki]).map(\.id) == [wildrose, kiki])
        #expect(both.authors(for: .person(kiki)).map(\.id) == [kiki])
    }
}
