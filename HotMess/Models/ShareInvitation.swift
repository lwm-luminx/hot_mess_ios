import AudienceKit
import Foundation

struct ShareInvitation: Decodable, Sendable {
    struct Target: Decodable, Sendable, Identifiable {
        let id: String
        let name: String
        let path: String
    }
    let id: String
    let title: String
    let note: String?
    let senderName: String
    let expiresAt: Date
    let targets: [Target]
    enum CodingKeys: String, CodingKey {
        case id, title, note, targets
        case senderName = "sender_name", expiresAt = "expires_at"
    }

    static func load(path: String, token: String, client: AudienceKitClient) async throws -> Self {
        let data = try await client.data(for: APIRequest(path: "/v1/share/invitation", queryItems: [
            URLQueryItem(name: "host", value: client.configuration.host),
            URLQueryItem(name: "path", value: path), URLQueryItem(name: "e", value: token)
        ], authenticated: false))
        return try JSONDecoder.hotMess.decode(Self.self, from: data)
    }
}
