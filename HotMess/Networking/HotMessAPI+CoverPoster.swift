//
//  HotMessAPI+CoverPoster.swift
//  HotMess
//

import AudienceKit
import Foundation

/// A venue's lobby cover poster (`/cover/<code>`, api doc/DIGITAL_COVER_CHARGE.md
/// "Cover poster"): its code is the venue's short code, and the API says which
/// venue it is. The app opens that venue, whose Cover section pays tonight's
/// cover (or shows the next night's price).
extension HotMessAPI {
    /// The venue a cover poster's code names (public, no sign-in), or nil for
    /// a code that names none.
    func coverPosterVenue(_ code: String) async throws -> UUID? {
        do {
            let data = try await client.audienceKit.data(for: APIRequest(path: "/v1/cover/\(code)", queryItems: [
                URLQueryItem(name: "host", value: client.audienceKit.configuration.host)
            ], authenticated: false))
            return try JSONDecoder().decode(CoverPosterResponse.self, from: data).venue.id
        } catch let error as AudienceKitError where error.status == 404 {
            return nil
        }
    }
}

private struct CoverPosterResponse: Decodable, Sendable {
    struct Venue: Decodable, Sendable { let id: UUID }
    let venue: Venue
}
