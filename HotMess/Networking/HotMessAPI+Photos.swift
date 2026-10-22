//
//  HotMessAPI+Photos.swift
//  HotMess
//

import AudienceKit
import Foundation

/// Photos of venues, events and the people on stage: photographers' and the
/// ones members take with the app's camera at a venue. Its own request, so a
/// page still shows on an API without them.
extension HotMessAPI {
    /// The newest photos of a venue, an event or a person (the ones they were
    /// on stage in). None for a locale.
    func photos(_ subject: PostsSubject, first: Int = 20) async throws -> [EventPhoto] {
        let document: String
        let id: UUID
        switch subject {
        case let .venue(venueID):
            id = venueID
            document = PhotoDocuments.venuePhotos
        case let .event(eventID):
            id = eventID
            document = PhotoDocuments.eventPhotos
        case let .person(personID):
            id = personID
            document = PhotoDocuments.personPhotos
        case .locale:
            return []
        }
        return try await query(
            document,
            variables: ["id": .string(id.uuidString.lowercased()), "first": .int(first)],
            as: PhotosResponse.self
        ).photos
    }

    /// Adds a photo just taken with the camera at the venue the user is at.
    /// The server tags whoever is on stage and puts it on the event under way.
    func takePhoto(venueID: UUID, jpeg: Data, altText: String?) async throws -> EventPhoto {
        var input: [String: GraphQLValue] = [
            "venueId": .string(venueID.uuidString.lowercased()),
            "photo": .string("data:image/jpeg;base64,\(jpeg.base64EncodedString())")
        ]
        if let altText, !altText.isEmpty { input["altText"] = .string(altText) }
        return try await query(
            PhotoDocuments.take,
            variables: ["input": .object(input)],
            as: AddEventPhotoResponse.self
        ).addEventPhoto.photo
    }

    /// Removes a photo the user took.
    func removePhoto(_ id: UUID) async throws {
        _ = try await query(
            PhotoDocuments.remove,
            variables: ["input": .object(["id": .string(id.uuidString.lowercased())])],
            as: RemoveEventPhotoResponse.self
        )
    }
}

enum PhotoDocuments {
    static let photoFields = """
    id url altText caption source takenBy takenAt viewUrl viewerCanRemove people { id name } event { id name }
    """

    static let venuePhotos = """
    query VenuePhotos($id: ID!, $first: Int!) {
      venues { venue(id: $id) { posts { photos(first: $first) { nodes { \(photoFields) } } } } }
    }
    """

    static let eventPhotos = """
    query EventPhotos($id: ID!, $first: Int!) {
      events { event(id: $id) { posts { photos(first: $first) { nodes { \(photoFields) } } } } }
    }
    """

    static let personPhotos = """
    query PersonPhotos($id: ID!, $first: Int!) {
      people { person(id: $id) { posts { photos(first: $first) { nodes { \(photoFields) } } } } }
    }
    """

    static let take = """
    mutation AddEventPhoto($input: EventPhotoTakeInput!) {
      addEventPhoto(input: $input) { photo { \(photoFields) } }
    }
    """

    static let remove = """
    mutation RemoveEventPhoto($input: EventPhotoRemoveInput!) {
      removeEventPhoto(input: $input) { id }
    }
    """
}

/// `{venues|events|people} { <one> { posts { photos } } }`.
struct PhotosResponse: Decodable, Sendable {
    let photos: [EventPhoto]

    private struct Posts: Decodable { let photos: Nodes<EventPhoto> }
    private struct Owner: Decodable { let posts: Posts }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        // One root ("venues"), holding one field ("venue"), holding the photos.
        let root = try decoder.container(keyedBy: DynamicKey.self)
        guard let rootKey = root.allKeys.first else { photos = []; return }
        let parent = try root.nestedContainer(keyedBy: DynamicKey.self, forKey: rootKey)
        guard let ownerKey = parent.allKeys.first else { photos = []; return }
        photos = try parent.decodeIfPresent(Owner.self, forKey: ownerKey)?.posts.photos.nodes ?? []
    }
}

struct AddEventPhotoResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let photo: EventPhoto }
    let addEventPhoto: Payload
}

struct RemoveEventPhotoResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let id: UUID }
    let removeEventPhoto: Payload?
}
