//
//  HotMessAPI+Posts.swift
//  HotMess
//

import AudienceKit
import Foundation

/// Venue and talent posts: read on venue, event and talent pages, Now and the
/// updates feed, with comments. Each list is its own request, so a page still
/// shows on an API without posts.
extension HotMessAPI {
    /// A page of posts: a venue's, an event's, a person's or a locale's.
    func posts(_ subject: PostsSubject, from filter: PostsFilter = .all, first: Int = 20) async throws -> [Post] {
        var variables: [String: GraphQLValue] = ["first": .int(first)]
        let document: String
        switch subject {
        case let .venue(id):
            variables["id"] = .string(id.uuidString.lowercased())
            document = PostDocuments.venuePosts
        case let .event(id):
            variables["id"] = .string(id.uuidString.lowercased())
            document = PostDocuments.eventPosts
        case let .person(id):
            variables["id"] = .string(id.uuidString.lowercased())
            document = PostDocuments.personPosts
        case let .locale(locale):
            variables["id"] = .string(locale.id.uuidString.lowercased())
            variables["from"] = .string(filter.rawValue)
            document = PostDocuments.localePosts
        }
        return try await query(document, variables: variables, as: PostsResponse.self).posts
    }

    /// One post and its comments, oldest first.
    func post(_ id: UUID) async throws -> (post: Post, comments: [PostComment])? {
        let response = try await query(
            PostDocuments.post,
            variables: ["id": .string(id.uuidString.lowercased())],
            as: PostResponse.self
        )
        return response.posts.post.map { (post: $0.post, comments: $0.comments.nodes) }
    }

    func commentOnPost(_ postID: UUID, body: String) async throws -> PostComment {
        try await query(
            PostDocuments.createComment,
            variables: ["input": .object(["postId": .string(postID.uuidString.lowercased()), "body": .string(body)])],
            as: CreatePostCommentResponse.self
        ).createPostComment.comment
    }

    func removePostComment(_ commentID: UUID) async throws {
        _ = try await query(
            PostDocuments.removeComment,
            variables: ["input": .object(["id": .string(commentID.uuidString.lowercased())])],
            as: RemovePostCommentResponse.self
        )
    }

    /// "Hide posts from {name}", or showing them again.
    func mutePosts(from poster: PostPoster, muted: Bool = true) async throws {
        var input: [String: GraphQLValue] = ["muted": .bool(muted)]
        switch poster {
        case let .venue(id, _): input["venueId"] = .string(id.uuidString.lowercased())
        case let .person(id, _): input["personId"] = .string(id.uuidString.lowercased())
        }
        _ = try await query(PostDocuments.mute, variables: ["input": .object(input)], as: MutePostAuthorResponse.self)
    }

    /// The venues and talent the signed-in user manages, so Me can send them
    /// to Velvet or Backstage. Read on the consumer endpoint, like everything
    /// Hot Mess does: it never calls the staff one. Anything that goes wrong
    /// (signed out, offline) means none.
    func managedListings() async -> ManagedListings {
        guard let response = try? await query(PostDocuments.listings, variables: [:], as: ListingsResponse.self) else { return .none }
        let listings = response.me.listings
        var seen = Set<UUID>()
        let people = (listings.people + listings.troupes).filter { seen.insert($0.id).inserted }
        return ManagedListings(
            venues: listings.venues.map { .init(id: $0.id, name: $0.name) },
            people: people.map { .init(id: $0.id, name: $0.name) }
        )
    }
}

enum PostDocuments {
    static let postFields = """
    id body posterName posterAvatarUrl roleLabel actingPersonName createdAt edited pinned commentsOpen commentCount
    visibility photos { url altText } event { id name startAt } person { id } venue { id }
    """

    static let commentFields = "id authorId authorName authorAvatarUrl body createdAt viewerCanRemove"

    static let venuePosts = """
    query VenuePosts($id: ID!, $first: Int!) {
      venues { venue(id: $id) { posts { list(first: $first) { nodes { \(postFields) } } } } }
    }
    """

    static let eventPosts = """
    query EventPosts($id: ID!, $first: Int!) {
      events { event(id: $id) { posts { list(first: $first) { nodes { \(postFields) } } } } }
    }
    """

    static let personPosts = """
    query PersonPosts($id: ID!, $first: Int!) {
      people { person(id: $id) { posts { list(first: $first) { nodes { \(postFields) } } } } }
    }
    """

    static let localePosts = """
    query LocalePosts($id: ID!, $first: Int!, $from: PostsFrom!) {
      locale(id: $id) { posts { list(first: $first, from: $from) { nodes { \(postFields) } } } }
    }
    """

    static let post = """
    query Post($id: ID!) {
      posts { post(id: $id) { \(postFields) comments(first: 100) { nodes { \(commentFields) } } } }
    }
    """

    static let createComment = """
    mutation CreatePostComment($input: PostCommentCreateInput!) {
      createPostComment(input: $input) { comment { \(commentFields) } }
    }
    """

    static let removeComment = """
    mutation RemovePostComment($input: PostCommentRemoveInput!) {
      removePostComment(input: $input) { comment { id } }
    }
    """

    /// The venues and talent the signed-in user manages, on the consumer
    /// endpoint (it grants nothing there).
    static let listings = """
    query ManagedListings {
      me { listings { venues { id name } people { id name } troupes { id name } } }
    }
    """

    static let mute = """
    mutation MutePostAuthor($input: PostAuthorMuteInput!) {
      mutePostAuthor(input: $input) { muted }
    }
    """
}

/// Any of the lists: `{venues|events|people} { <one> { posts { list } } }`, or `locale { posts { list } }`.
struct PostsResponse: Decodable, Sendable {
    let posts: [Post]

    private struct List: Decodable { let list: Nodes<Post> }
    private struct Owner: Decodable { let posts: List }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        // One root ("venues"), holding one field ("venue"), holding the posts; a locale is at the root itself.
        let root = try decoder.container(keyedBy: DynamicKey.self)
        guard let rootKey = root.allKeys.first else { posts = []; return }
        if rootKey.stringValue == "locale" {
            posts = try root.decodeIfPresent(Owner.self, forKey: rootKey)?.posts.list.nodes ?? []
            return
        }
        guard (try? root.decodeNil(forKey: rootKey)) == false else { posts = []; return }
        let parent = try root.nestedContainer(keyedBy: DynamicKey.self, forKey: rootKey)
        guard let ownerKey = parent.allKeys.first else { posts = []; return }
        posts = try parent.decodeIfPresent(Owner.self, forKey: ownerKey)?.posts.list.nodes ?? []
    }
}

struct PostResponse: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let post: Post
        let comments: Nodes<PostComment>

        private enum CodingKeys: String, CodingKey { case comments }

        init(from decoder: any Decoder) throws {
            post = try Post(from: decoder)
            comments = try decoder.container(keyedBy: CodingKeys.self).decode(Nodes<PostComment>.self, forKey: .comments)
        }
    }

    struct Posts: Decodable, Sendable { let post: Detail? }

    let posts: Posts
}

struct CreatePostCommentResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let comment: PostComment }

    let createPostComment: Payload
}

struct RemovePostCommentResponse: Decodable, Sendable {
    struct Comment: Decodable, Sendable { let id: String }
    struct Payload: Decodable, Sendable { let comment: Comment }

    let removePostComment: Payload
}

struct ListingsResponse: Decodable, Sendable {
    struct Listing: Decodable, Sendable {
        let id: UUID
        let name: String

        private enum CodingKeys: String, CodingKey { case id, name }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        }
    }

    struct Listings: Decodable, Sendable {
        let venues: [Listing]
        let people: [Listing]
        let troupes: [Listing]
    }

    struct Me: Decodable, Sendable { let listings: Listings }

    let me: Me
}

struct MutePostAuthorResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let muted: Bool }

    let mutePostAuthor: Payload
}
