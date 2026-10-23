//
//  HotMessAPI+Posts.swift
//  HotMess
//

import AudienceKit
import Foundation

/// Venue and talent posts: read on venue, event and talent pages, Now and the
/// updates feed, with comments. Each list is its own request, so a page still
/// shows on an API without posts.
///
/// Writing and managing them goes to the staff view (staffql) with the same
/// sign-in, as Velvet and Backstage do: the consumer view only ever lets a
/// member change their own records, so it has no post mutations.
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

    // MARK: - Managing

    /// The venues and talent the user manages here. The staff view turns away
    /// anyone who manages none, which is most people, so any failure reads as
    /// none and isn't reported.
    func managedListings() async -> ManagedListings {
        guard let response = try? await audienceKit.graphQL(
            PostDocuments.listings, endpoint: .staff, as: ListingsResponse.self, decoder: .hotMess
        ) else { return .none }
        let listings = response.me.listings
        let people = (listings.people + listings.troupes).reduce(into: [PostAuthor]()) { authors, person in
            if !authors.contains(where: { $0.id == person.id }) { authors.append(.person(person.id, name: person.name)) }
        }
        return ManagedListings(venues: listings.venues.map { .venue($0.id, name: $0.name) }, people: people)
    }

    /// Posts as a venue or a talent listing, on its page or an event.
    func createPost(
        as author: PostAuthor,
        on target: PostTarget,
        body: String,
        photos: [(jpeg: Data, altText: String)] = [],
        pinned: Bool = false,
        commentsOpen: Bool = true,
        visibility: PostVisibility = .community
    ) async throws -> Post {
        var input: [String: GraphQLValue] = [
            "body": .string(body), "pinned": .bool(pinned), "commentsOpen": .bool(commentsOpen),
            "visibility": .string(visibility.rawValue)
        ]
        switch (author, target) {
        case let (.venue(id, _), .page): input["venueId"] = .string(id.uuidString.lowercased())
        case let (.person(id, _), .page):
            input["asPersonId"] = .string(id.uuidString.lowercased())
            input["personId"] = .string(id.uuidString.lowercased())
        case let (.venue, .event(eventID, _)): input["eventId"] = .string(eventID.uuidString.lowercased())
        case let (.person(id, _), .event(eventID, _)):
            input["asPersonId"] = .string(id.uuidString.lowercased())
            input["eventId"] = .string(eventID.uuidString.lowercased())
        }
        if !photos.isEmpty {
            input["photos"] = .array(photos.prefix(Self.maxPostPhotos).map { photo in
                let uri = "data:image/jpeg;base64,\(photo.jpeg.base64EncodedString())"
                var fields: [String: GraphQLValue] = ["photo": .string(uri)]
                let alt = photo.altText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !alt.isEmpty { fields["altText"] = .string(alt) }
                return .object(fields)
            })
        }
        guard let post = try await staffQuery(
            PostDocuments.create, variables: ["input": .object(input)], as: CreatePostResponse.self
        ).createPost.post else { throw APIError.decoding("The post was missing") }
        return post
    }

    /// Changes a post; nil leaves a field as it is.
    func updatePost(
        _ id: UUID,
        body: String? = nil,
        pinned: Bool? = nil,
        commentsOpen: Bool? = nil,
        visibility: PostVisibility? = nil
    ) async throws -> Post {
        var input: [String: GraphQLValue] = ["id": .string(id.uuidString.lowercased())]
        if let visibility { input["visibility"] = .string(visibility.rawValue) }
        if let body { input["body"] = .string(body) }
        if let pinned { input["pinned"] = .bool(pinned) }
        if let commentsOpen { input["commentsOpen"] = .bool(commentsOpen) }
        guard let post = try await staffQuery(
            PostDocuments.update, variables: ["input": .object(input)], as: UpdatePostResponse.self
        ).updatePost.post else { throw APIError.decoding("The post was missing") }
        return post
    }

    /// Takes a post and its comments out of the apps.
    func deletePost(_ id: UUID) async throws {
        _ = try await staffQuery(
            PostDocuments.delete,
            variables: ["input": .object(["id": .string(id.uuidString.lowercased())])],
            as: DeletePostResponse.self
        )
    }

    /// The event venue's "Hide from This Event" on a talent post, or showing
    /// it there again. It stays on the person's page either way.
    func hidePostFromEvent(_ id: UUID, hidden: Bool = true) async throws -> Post {
        try await staffQuery(
            PostDocuments.hideFromEvent,
            variables: ["input": .object(["id": .string(id.uuidString.lowercased()), "hidden": .bool(hidden)])],
            as: HidePostFromEventResponse.self
        ).hidePostFromEvent.post
    }

    /// The most photos one post holds.
    static let maxPostPhotos = 4

    private func staffQuery<Response: Decodable & Sendable>(
        _ document: String,
        variables: [String: GraphQLValue],
        as type: Response.Type
    ) async throws -> Response {
        do {
            return try await audienceKit.graphQL(document, variables: variables, endpoint: .staff, as: type, decoder: .hotMess)
        } catch let error as AudienceKitError {
            throw await APIClient.recorded(APIError(error), operation: Self.operationName(document))
        }
    }
}

enum PostDocuments {
    static let postFields = """
    id body posterName posterAvatarUrl roleLabel actingPersonName createdAt edited pinned commentsOpen commentCount
    hiddenFromEvent visibility photos { url altText } event { id name startAt } person { id } venue { id }
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

    static let mute = """
    mutation MutePostAuthor($input: PostAuthorMuteInput!) {
      mutePostAuthor(input: $input) { muted }
    }
    """

    // Staff view (staffql).

    static let listings = """
    # endpoint: staff
    query ManagedListings {
      me { listings { venues { id name } people { id name } troupes { id name } } }
    }
    """

    static let create = """
    # endpoint: staff
    mutation CreatePost($input: PostCreateInput!) {
      createPost(input: $input) { post { \(postFields) } }
    }
    """

    static let update = """
    # endpoint: staff
    mutation UpdatePost($input: PostUpdateInput!) {
      updatePost(input: $input) { post { \(postFields) } }
    }
    """

    static let delete = """
    # endpoint: staff
    mutation DeletePost($input: PostDeleteInput!) {
      deletePost(input: $input) { deletedId }
    }
    """

    static let hideFromEvent = """
    # endpoint: staff
    mutation HidePostFromEvent($input: PostHideFromEventInput!) {
      hidePostFromEvent(input: $input) { post { \(postFields) } }
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

struct MutePostAuthorResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let muted: Bool }

    let mutePostAuthor: Payload
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

struct CreatePostResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let post: Post? }

    let createPost: Payload
}

struct UpdatePostResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let post: Post? }

    let updatePost: Payload
}

struct DeletePostResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let deletedId: String }

    let deletePost: Payload
}

struct HidePostFromEventResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let post: Post }

    let hidePostFromEvent: Payload
}
