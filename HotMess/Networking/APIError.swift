//
//  APIError.swift
//  HotMess
//

import AudienceKit
import Foundation

enum APIError: Error, Equatable, Sendable, LocalizedError {
    /// The device has no usable connection, or the request timed out.
    case offline
    /// The server rejected our credentials; the session needs re-establishing.
    case unauthorized
    case notFound
    case server(status: Int)
    case decoding(String)
    case invalidURL
    case transport(String)
    /// The API refused because the member hasn't agreed to the community
    /// terms yet (FORBIDDEN, reason `terms_not_accepted`): ask, then try again.
    case termsNotAccepted(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            String(localized: "You appear to be offline. Check your connection and try again.")
        case .unauthorized:
            String(localized: "Your session expired. Sign in again to continue.")
        case .notFound:
            String(localized: "That isn't available any more.")
        case let .server(status):
            String(localized: "The server had a problem (\(status)). Try again in a moment.")
        case .decoding:
            String(localized: "The server sent something we didn't understand.")
        case .invalidURL:
            String(localized: "That request couldn't be built.")
        case let .transport(message), let .termsNotAccepted(message):
            message
        }
    }

    /// Whether offering a "Try again" button makes sense.
    var isRetryable: Bool {
        switch self {
        case .offline, .server, .transport: true
        case .unauthorized, .notFound, .decoding, .invalidURL, .termsNotAccepted: false
        }
    }

    /// Maps the SDK's errors onto the ones the screens know how to show, by
    /// their `code` (the API's vocabulary, or one the SDK raised on the
    /// device), then by HTTP status.
    init(_ error: AudienceKitError) {
        if error.code == AudienceKitError.Code.forbidden,
           error.errors.first?.extensions?["reason"] == .string("terms_not_accepted") {
            self = .termsNotAccepted(error.message)
            return
        }
        switch error.code {
        case AudienceKitError.Code.notSignedIn, AudienceKitError.Code.unauthenticated,
             AudienceKitError.Code.signInRejected:
            self = .unauthorized
        case AudienceKitError.Code.notFound:
            self = .notFound
        case AudienceKitError.Code.network:
            self = error.underlying.map(APIError.init(urlError:)) ?? .offline
        case AudienceKitError.Code.decoding:
            self = .decoding(error.message)
        case AudienceKitError.Code.http, AudienceKitError.Code.internalError, AudienceKitError.Code.rateLimited,
             AudienceKitError.Code.unavailable:
            self = error.status.map { APIError.server(status: $0) } ?? .transport(error.localizedDescription)
        default:
            // FORBIDDEN, INVALID (with `fields`), CONFLICT, SIGN_IN_FAILED,
            // GRAPHQL, MISSING_CONFIGURATION, STORAGE, UPDATE_REQUIRED,
            // UNSUPPORTED_API_VERSION and codes a newer API adds: shown as
            // the API worded them.
            if let status = error.status, status >= 500 {
                self = .server(status: status)
            } else {
                self = .transport(error.localizedDescription)
            }
        }
    }

    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .dataNotAllowed,
             .cannotConnectToHost, .cannotFindHost, .internationalRoamingOff:
            self = .offline
        default:
            self = .transport(urlError.localizedDescription)
        }
    }
}

extension AudienceKitError.Code {
    /// The API's eighth code: the service is down (HTTP 503). Not yet among
    /// the SDK's constants.
    static let unavailable = "UNAVAILABLE"
}
