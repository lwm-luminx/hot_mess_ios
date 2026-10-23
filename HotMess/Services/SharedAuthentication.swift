import AudienceKit
import Foundation

/// Both products use the SDK's credential format. iOS grants the corresponding
/// parent access to the Clip's keychain on installation (iOS 15.4+).
/// A separate service makes reinstall/login precedence deterministic.
enum HotMessAuthentication {
    static let primaryStore = KeychainCredentialStore(service: "social.hotmess.account", account: "credential")
    static let clipStore = KeychainCredentialStore(service: "social.hotmess.account.clip", account: "credential")
    static let mainStore = ClipCredentialHandoff(primary: primaryStore, clip: clipStore)
}

struct ClipCredentialHandoff: CredentialStore {
    let primary: any CredentialStore
    let clip: any CredentialStore

    func load() throws -> Credential? {
        if let incoming = try clip.load() {
            // Persist before deleting: a failed migration must remain retryable.
            try primary.save(incoming)
            try clip.delete()
            return incoming
        }
        return try primary.load()
    }

    func save(_ credential: Credential) throws {
        try primary.save(credential)
        try clip.delete()
    }

    func delete() throws {
        // Delete the handoff first so signing out cannot resurrect a Clip login.
        try clip.delete()
        try primary.delete()
    }
}

/// `POST /v1/token/apple`. Apple gives the name only the first time someone
/// signs in to the app, so it's sent along then. The authorization code lets
/// the API get a refresh token from Apple, which it revokes when the account
/// is deleted.
struct AppleSignInRequest: Encodable, Sendable {
    let identityToken: String
    var authorizationCode: String? = nil
    let firstName: String?
    let lastName: String?
    let host: String?
    let device: DeviceDescription

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case firstName = "first_name"
        case lastName = "last_name"
        case host
        case device
    }
}
