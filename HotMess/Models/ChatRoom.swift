//
//  ChatRoom.swift
//  HotMess
//

import Foundation

/// A chat room: a venue's, for people at the venue, or a locale's, for
/// people out in the locale who aren't at a venue. Both deliver the same events,
/// so one connection and one screen serve either.
struct ChatRoom: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case venue
        case locale
    }

    let kind: Kind
    let id: UUID
    let name: String
    /// The room's picture: the venue's photo, or the event's banner.
    var photoURL: URL? = nil
    /// The venue the room is in, for its face in the Here now strip and the
    /// "In this room" sheet, even when the room is branded for an event.
    /// `nil` for a locale's room, and from rooms made without one.
    var venueName: String? = nil
    var venuePhotoURL: URL? = nil
    /// The event the room is branded for, when it is.
    var eventName: String? = nil

    static func venue(_ venue: Venue) -> ChatRoom {
        ChatRoom(kind: .venue, id: venue.id, name: venue.name, photoURL: venue.photoURL,
                 venueName: venue.name, venuePhotoURL: venue.photoURL)
    }

    /// The venue's room while the user is at an event there: the same room,
    /// branded for the event, since the host may not be a listed venue.
    static func event(_ event: Event, at venue: Venue) -> ChatRoom {
        ChatRoom(kind: .venue, id: venue.id, name: event.name, photoURL: event.bannerURL ?? venue.photoURL,
                 venueName: venue.name, venuePhotoURL: venue.photoURL, eventName: event.name)
    }

    /// The venue whose room it is, by its ID: a venue's room, or an event's
    /// at it. `nil` for a locale's room.
    var venueID: UUID? {
        kind == .venue ? id : nil
    }

    /// The venue, first in the room's Here now strip: a venue is always in
    /// its own room, an event's included. A locale's room has none.
    var place: HereNowPlace? {
        guard kind == .venue else { return nil }
        return HereNowPlace(name: venueName ?? name, photoURL: venuePhotoURL ?? photoURL)
    }

    static func locale(_ locale: AppLocale) -> ChatRoom {
        ChatRoom(kind: .locale, id: locale.id, name: locale.name)
    }

    /// The GraphQL subscription field that follows the room.
    var channelName: String {
        switch kind {
        case .venue: "venueChat"
        case .locale: "localeChat"
        }
    }

    /// The argument naming the room, to the subscription and to
    /// `sendMyChatMessage`'s input.
    var subscriptionKey: String {
        switch kind {
        case .venue: "venueId"
        case .locale: "localeId"
        }
    }
}
