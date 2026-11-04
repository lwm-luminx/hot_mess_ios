//
//  User.swift
//  HotMess
//

import AudienceCore
import Foundation

struct User: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let name: String
    /// Their profile photo, from `me { photo }`; `nil` until it's loaded or
    /// when they have none, and the avatar shows their initials.
    var avatarURL: URL?

    var firstName: String { name.firstNameForDisplay }

    var initials: String { name.initialsForDisplay }

    init(id: UUID, name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }

    /// From the IDs and names AudienceKit sends, which are optional there.
    init?(id: String, name: String?) {
        guard let uuid = RecordID.uuid(id) else { return nil }
        self.init(id: uuid, name: name ?? "")
    }
}

/// Someone as the API shows them to others: `Profile { id name avatarUrl }`,
/// the buyer on a cover pass, a blocked user.
struct Profile: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let avatarURL: URL?

    init(id: UUID, name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        avatarURL = try container.decodeURLIfPresent(forKey: .avatarURL)
    }
}

/// AudienceKit GraphQL objects carry their record's UUID as `id`, the same value
/// `node(id:)`, the REST endpoints and deep links take.
enum RecordID {
    static func uuid(_ id: String) -> UUID? {
        UUID(uuidString: id)
    }
}
