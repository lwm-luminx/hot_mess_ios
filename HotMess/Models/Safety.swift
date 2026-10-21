//
//  Safety.swift
//  HotMess
//

import Foundation

/// Someone the user blocked. Chat rooms leave them out, and the API stops
/// sending the user their messages and presence.
struct BlockedUser: Decodable, Hashable, Sendable, Identifiable {
    let id: UUID
    /// The short form rooms show strangers ("Aurora B.").
    let name: String?
    let avatarURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
    }

    init(id: UUID, name: String?, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// What the API keeps about the user's own safety settings, and how their
/// account signs in.
struct SafetyState: Decodable, Sendable {
    var termsAcceptedAt: Date?
    var blockedUsers: [BlockedUser]
    /// False for an account that signed in with Apple and hasn't connected
    /// Facebook, so has no friends to show.
    var hasFacebook: Bool
    /// True only for the designated App Review account while the audience is
    /// in App Review: the reviewer can pretend to be at a venue, like a test
    /// build.
    var canPretendLocation: Bool

    /// `me`: the viewer's state, with their own profile (`self`), where `hasFacebook` is.
    private enum CodingKeys: String, CodingKey {
        case termsAcceptedAt = "terms_accepted_at"
        case blockedUsers = "blocked_users"
        case canPretendLocation = "can_pretend_location"
        case profile = "self"
    }

    private enum ProfileKeys: String, CodingKey {
        case hasFacebook = "has_facebook"
    }

    init(
        termsAcceptedAt: Date? = nil,
        blockedUsers: [BlockedUser] = [],
        hasFacebook: Bool = true,
        canPretendLocation: Bool = false
    ) {
        self.termsAcceptedAt = termsAcceptedAt
        self.blockedUsers = blockedUsers
        self.hasFacebook = hasFacebook
        self.canPretendLocation = canPretendLocation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termsAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .termsAcceptedAt)
        blockedUsers = try container.decodeIfPresent([BlockedUser].self, forKey: .blockedUsers) ?? []
        // An API from before Sign in with Apple only had Facebook accounts.
        if (try? container.decodeNil(forKey: .profile)) == false {
            let profile = try container.nestedContainer(keyedBy: ProfileKeys.self, forKey: .profile)
            hasFacebook = try profile.decodeIfPresent(Bool.self, forKey: .hasFacebook) ?? true
        } else {
            hasFacebook = true
        }
        canPretendLocation = try container.decodeIfPresent(Bool.self, forKey: .canPretendLocation) ?? false
    }
}

/// Why someone reports a chat message. The raw value is what the room's
/// admins read.
enum ChatReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam = "Spam"
    case harassment = "Harassment or hate"
    case sexual = "Sexual content"
    case danger = "Threats or danger"
    case other = "Something else"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: String(localized: "Spam")
        case .harassment: String(localized: "Harassment or hate")
        case .sexual: String(localized: "Sexual content")
        case .danger: String(localized: "Threats or danger")
        case .other: String(localized: "Something else")
        }
    }
}

/// What `reportContent` can be told about: the API's `ReportTarget`.
enum ReportTarget: String, Hashable, Sendable {
    case person = "PERSON"
    case venue = "VENUE"
    case ping = "PING"
    case photo = "PHOTO"
    case message = "MESSAGE"
    case post = "POST"
    case postComment = "POST_COMMENT"
}

/// Something the user is reporting: what it is, its ID, and the person behind
/// it when blocking them makes sense (a Ping's sender, someone here now). A
/// venue or a creator's profile has no one to block.
struct ReportSubject: Identifiable, Hashable, Sendable {
    let target: ReportTarget
    let targetID: String
    /// Who to offer to block once it's reported.
    var sender: BlockedUser? = nil

    var id: String { "\(target.rawValue):\(targetID)" }

    /// The reason picker's question.
    var question: String {
        switch target {
        case .person: String(localized: "Why are you reporting this person?")
        case .venue: String(localized: "Why are you reporting this venue?")
        case .ping: String(localized: "Why are you reporting this ping?")
        case .photo: String(localized: "Why are you reporting this photo?")
        case .message: String(localized: "Why are you reporting this message?")
        case .post: String(localized: "Why are you reporting this post?")
        case .postComment: String(localized: "Why are you reporting this comment?")
        }
    }
}

/// The audience's legal pages, linked from Settings and the terms prompt.
enum LegalLinks {
    static let terms = URL(string: "https://audiencekit.com/terms/")!
    static let privacy = URL(string: "https://audiencekit.com/privacy/")!
}
