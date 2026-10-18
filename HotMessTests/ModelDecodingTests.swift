//
//  ModelDecodingTests.swift
//  HotMessTests
//

import CoreLocation
import Foundation
import Testing

@testable import HotMess

private func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
    try JSONDecoder.hotMess.decode(type, from: Data(json.utf8))
}

/// Expected instants are written as UTC rather than epoch numbers so the
/// assertion says what it means.
private func instant(_ iso8601: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: iso8601))
}

@Suite("Venue decoding")
struct VenueDecodingTests {
    @Test("Preserves a public group URL through decoding and encoding")
    func publicGroupLink() throws {
        let link = URL(string: "https://www.facebook.com/groups/123456789")!
        let venue = Venue(id: UUID(), name: "Community", facebookID: FacebookID("123456789"), facebookLink: link)
        let decoded = try JSONDecoder.hotMess.decode(Venue.self, from: JSONEncoder().encode(venue))
        #expect(decoded.facebookURL == link)
        let person = Person(id: UUID(), name: "Community", facebookID: FacebookID("123456789"), facebookLink: link)
        let decodedPerson = try JSONDecoder.hotMess.decode(Person.self, from: JSONEncoder().encode(person))
        #expect(decodedPerson.facebookURL == link)
    }

    @Test("Reads every field the API sends")
    func fullPayload() throws {
        let venue = try decode(Venue.self, from: Fixtures.venue)

        #expect(venue.name == "The Stud")
        #expect(venue.address == "399 9th St")
        #expect(venue.subtitle == "Since 1966.")
        #expect(venue.isLiked)
        #expect(venue.distance == 412.5)
        #expect(venue.facebookID?.rawValue == "112233445566")
        #expect(venue.bannerURL?.lastPathComponent == "stud-hero.jpg")
        #expect(venue.phone == "+14158633373")
    }

    @Test("A venue written out reads back with its profile")
    func roundTrip() throws {
        let venue = try decode(Venue.self, from: Fixtures.venue)
        let again = try JSONDecoder.hotMess.decode(Venue.self, from: JSONEncoder.hotMess.encode(venue))

        #expect(again == venue)
    }

    @Test("`point` maps x to longitude and y to latitude")
    func coordinate() throws {
        let venue = try decode(Venue.self, from: Fixtures.venue)
        let coordinate = try #require(venue.coordinate)

        #expect(coordinate.latitude == 37.7726)
        #expect(coordinate.longitude == -122.4099)
    }

    @Test("`point` also decodes as a GeoJSON point")
    func geoJSONCoordinate() throws {
        let point = try decode(GeoPoint.self, from: #"{ "type": "Point", "coordinates": [-122.4099, 37.7726] }"#)

        #expect(point.coordinate.latitude == 37.7726)
        #expect(point.coordinate.longitude == -122.4099)
    }

    @Test("Survives a payload with only id and name")
    func minimalPayload() throws {
        let venue = try decode(Venue.self, from: Fixtures.minimalVenue)

        #expect(venue.name == "Pop-up")
        #expect(venue.address == nil)
        #expect(venue.coordinate == nil)
        #expect(venue.isLiked == false)
        #expect(venue.facebookURL == nil)
        // The old model substituted the literal string "unknown" here.
        #expect(venue.summary.isEmpty == false)
    }
}

@Suite("Event decoding")
struct EventDecodingTests {
    @Test("Parses the API's offset date format")
    func dates() throws {
        let event = try decode(Event.self, from: Fixtures.event)

        // 21:00 on the 26th at -0700 is 04:00 UTC on the 27th.
        let expectedStart = try instant("2017-04-27T04:00:00Z")
        let expectedEnd = try instant("2017-04-27T09:00:00Z")

        #expect(event.startDate == expectedStart)
        #expect(event.endDate == expectedEnd)
    }

    @Test("Also accepts plain ISO 8601")
    func iso8601Dates() throws {
        let event = try decode(Event.self, from: Fixtures.sparseEvent)

        let expectedStart = try instant("2017-04-27T06:30:00Z")

        #expect(event.startDate == expectedStart)
        #expect(event.endDate == nil)
    }

    @Test("Maps the legacy `decliend` spelling onto `declined`")
    func legacyRSVPSpelling() throws {
        let event = try decode(Event.self, from: Fixtures.event)

        #expect(event.rsvp == .declined)
    }

    @Test("Defaults a missing RSVP to undecided")
    func missingRSVP() throws {
        let event = try decode(Event.self, from: Fixtures.sparseEvent)

        #expect(event.rsvp == .unsure)
    }

    @Test("Builds a subtitle without a venue instead of crashing")
    func subtitleWithoutVenue() throws {
        let event = try decode(Event.self, from: Fixtures.sparseEvent)

        #expect(event.venue == nil)
        #expect(event.subtitle.hasSuffix(Event.toBeAnnounced))
    }

    @Test("Maps RSVPs onto the GraphQL enum and reads it back")
    func rsvpGraphQL() throws {
        #expect(RSVP.declined.state == .declined)
        #expect(try JSONDecoder().decode(RSVP.self, from: Data(#""MAYBE""#.utf8)) == .maybe)
    }
}

@Suite("Facebook IDs")
struct FacebookIDTests {
    @Test("Accepts a JSON number")
    func numeric() throws {
        let event = try decode(Event.self, from: Fixtures.event)

        #expect(event.facebookID?.rawValue == "998877665544")
    }

    @Test("Accepts a JSON string")
    func string() throws {
        let venue = try decode(Venue.self, from: Fixtures.venue)

        #expect(venue.facebookID?.rawValue == "112233445566")
    }

    @Test("Derives the links the UI needs")
    func derivedLinks() {
        let id = FacebookID("42")

        #expect(id.profileURL?.absoluteString == "https://facebook.com/42")
        #expect(id.eventURL?.absoluteString == "https://facebook.com/events/42")
        #expect(id.messengerURL?.absoluteString == "fb-messenger://user-thread/42")
    }
}

@Suite("Event listing")
struct EventListingTests {
    @Test("Turns the sections dictionary into an ordered list")
    func ordering() throws {
        let listing = try decode(EventListing.self, from: Fixtures.eventListing)

        // "tonight" starts first, "later" second, and the section with no
        // events sorts last — regardless of dictionary iteration order.
        #expect(listing.sections.map(\.id) == ["tonight", "later", "empty"])
        #expect(listing.sections.map(\.title) == ["Tonight", "Later This Week", "Nothing Here"])
    }

    @Test("Is not considered empty while any section has events")
    func emptiness() throws {
        let listing = try decode(EventListing.self, from: Fixtures.eventListing)

        #expect(listing.isEmpty == false)
        #expect(EventListing().isEmpty)
    }
}

@Suite("Now")
struct NowDecodingTests {
    @Test("A missing `venues` key means we don't know where the user is")
    func friendsVariant() throws {
        let now = try decode(Now.self, from: Fixtures.nowWithFriends)

        #expect(now.venues == nil)
        #expect(now.isNearVenues == false)
        #expect(now.friends.count == 1)
        #expect(now.friends.first?.firstName == "Ada")
    }

    @Test("A present `venues` key means we do, even when it is empty")
    func venuesVariant() throws {
        let now = try decode(Now.self, from: Fixtures.nowNearVenues)

        #expect(now.isNearVenues)
        #expect(now.venues?.count == 1)
        #expect(now.title == "Happening Now in SoMa")
        #expect(now.imageURL?.absoluteString == "https://cdn.hotmess.social/now.jpg")
        #expect(now.events.count == 1)
        #expect(now.region != nil)
    }
}

@Suite("Person detail")
struct PersonDetailTests {
    @Test("Flattens the person and its nested collections")
    func nestedCollections() throws {
        let detail = try decode(PersonDetail.self, from: Fixtures.personDetail)

        #expect(detail.name == "Rick Mark")
        #expect(detail.person.role == "Resident")
        #expect(detail.person.facebookID != nil)
        #expect(detail.person.isLiked == false)
        #expect(detail.socialLinks.count == 1)
        #expect(detail.socialLinks.first?.assetName == "Instagram")
        #expect(detail.tracks.count == 1)
        #expect(detail.events.count == 1)
    }

    @Test("Splits tip links from social profiles")
    func tipLinks() throws {
        let detail = try decode(PersonDetail.self, from: """
        { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Trixie",
          "profile": { "social_links": { "nodes": [
            { "id": "1A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "handle": "trixie", "provider": "instagram",
              "url": "https://instagram.com/trixie" },
            { "id": "2A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "handle": "TrixieTips", "provider": "cashapp",
              "url": "https://cash.app/$TrixieTips" },
            null,
            { "id": "3A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "handle": "trixie-tips", "provider": "venmo",
              "url": "https://venmo.com/u/trixie-tips" }
          ] } } }
        """)

        #expect(detail.tipLinks.compactMap(\.tipApp) == ["Cash App", "Venmo"])
        #expect(detail.profileLinks.map(\.provider) == ["instagram"])
    }

    @Test("A person written out reads back with their profile and links")
    func roundTrip() throws {
        let detail = try decode(PersonDetail.self, from: Fixtures.personDetail)
        let again = try JSONDecoder.hotMess.decode(PersonDetail.self, from: JSONEncoder.hotMess.encode(detail))

        #expect(again.person == detail.person)
        #expect(again.socialLinks == detail.socialLinks)
    }

    @Test("Reads the people a person is made of and part of")
    func membersAndGroups() throws {
        let detail = try decode(PersonDetail.self, from: Fixtures.personDetail)

        #expect(detail.members.map(\.name) == ["Ada Lovelace"])
        #expect(detail.members.first?.avatarURL?.lastPathComponent == "ada.jpg")
        #expect(detail.groups.map(\.name) == ["The Haus of Mess"])
        #expect(detail.groups.first?.avatarURL == nil)
    }

    @Test("Reads tracks through the music mixin, dropping null nodes")
    func musicTracks() throws {
        let detail = try decode(PersonDetail.self, from: """
        { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "DJ",
          "music": { "tracks": { "nodes": [
            null,
            { "id": "1A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "title": "Late Night", "provider": "soundcloud" }
          ] } } }
        """)
        let empty = try decode(PersonDetail.self, from: """
        { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "DJ", "music": { "tracks": null } }
        """)

        #expect(detail.tracks.map(\.title) == ["Late Night"])
        #expect(empty.tracks.isEmpty)
    }

    @Test("Leaves collections empty when the API omits them")
    func missingCollections() throws {
        let detail = try decode(PersonDetail.self, from: """
        { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Nobody" }
        """)

        #expect(detail.events.isEmpty)
        #expect(detail.tracks.isEmpty)
        #expect(detail.socialLinks.isEmpty)
        #expect(detail.members.isEmpty)
        #expect(detail.groups.isEmpty)
    }
}

@Suite("Venue detail")
struct VenueDetailTests {
    @Test("Reads the venue's links elsewhere")
    func socialLinks() throws {
        let detail = try decode(VenueWithEvents.self, from: Fixtures.venueDetail)

        #expect(detail.venue.name == "The Stud")
        #expect(detail.chatOpen)
        #expect(detail.events.count == 1)
        #expect(detail.socialLinks.count == 1)
        #expect(detail.socialLinks.first?.assetName == "Instagram")
        #expect(detail.socialLinks.first?.url?.host() == "instagram.com")
        // The venue's own profile fields come from the same mixin.
        #expect(detail.venue.address == "399 9th St")
        #expect(detail.venue.facebookID == nil)
    }

    @Test("Leaves links empty when the API omits them")
    func missingSocialLinks() throws {
        let detail = try decode(VenueWithEvents.self, from: Fixtures.minimalVenue)

        #expect(detail.socialLinks.isEmpty)
        #expect(detail.events.isEmpty)
        #expect(detail.chatOpen == false)
    }
}

@Suite("On now")
struct OnNowDecodingTests {
    /// `onNow` as the `venue` query aliases it, under the venue's people
    /// mixin: GraphQL's uppercase roles and UTC times, and the person's
    /// `avatarUrl` as `avatar_url`.
    static let onNow = """
    "people": { "on_now": { "nodes": [
      { "id": "4D2C1B0A-9E8F-4A7B-8C6D-5E4F3A2B1C0D", "role": "DJ",
        "starts_at": "2026-10-11T04:00:00Z", "ends_at": "2026-10-11T08:00:00Z",
        "person": { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Trixie Mattel",
                    "avatar_url": "https://cdn.hotmess.social/people/trixie.jpg" } },
      { "id": "5D2C1B0A-9E8F-4A7B-8C6D-5E4F3A2B1C0D", "role": "HOST",
        "starts_at": "2026-10-11T03:00:00Z", "ends_at": null,
        "person": { "id": "1A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Kiko Soirée", "avatar_url": null } },
      { "id": "6D2C1B0A-9E8F-4A7B-8C6D-5E4F3A2B1C0D", "role": "HOST",
        "starts_at": "2026-10-11T03:00:00Z",
        "person": { "id": "2A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": null } }
    ] } }
    """

    @Test("Reads who's on at a venue, dropping someone with no name yet")
    func venue() throws {
        let detail = try decode(VenueWithEvents.self, from: """
        { "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11", "name": "The Stud", \(Self.onNow) }
        """)

        #expect(detail.onNow.map(\.person.name) == ["Trixie Mattel", "Kiko Soirée"])
        #expect(detail.onNow.map(\.role) == [.dj, .host])
        #expect(detail.onNow.first?.person.avatarURL?.lastPathComponent == "trixie.jpg")
        let start = try instant("2026-10-11T04:00:00Z")
        let end = try instant("2026-10-11T08:00:00Z")
        #expect(detail.onNow.first?.startsAt == start)
        #expect(detail.onNow.first?.endsAt == end)
        #expect(detail.onNow.last?.endsAt == nil)
        #expect(detail.onNow.last?.detail == "Hosting")
    }

    @Test("Reads who's on at the venue the user is in")
    func now() throws {
        let now = try decode(Now.self, from: """
        { "title": "Now", "venue": { "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11", "name": "The Stud", \(Self.onNow) } }
        """)

        #expect(now.venue?.name == "The Stud")
        #expect(now.onNow.count == 2)
    }

    @Test("Nobody is on when the API leaves it out or sends something else")
    func missing() throws {
        let older = try decode(VenueWithEvents.self, from: Fixtures.minimalVenue)
        let malformed = try decode(VenueWithEvents.self, from: """
        { "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11", "name": "The Stud", "people": { "on_now": "soon" } }
        """)
        let away = try decode(Now.self, from: Fixtures.nowWithFriends)

        #expect(older.onNow.isEmpty)
        #expect(malformed.onNow.isEmpty)
        #expect(away.onNow.isEmpty)
    }

    @Test("Reads a show the venue advances: a duet on, an intermission, and who's up next")
    func runningOrder() throws {
        let detail = try decode(VenueWithEvents.self, from: """
        { "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11", "name": "The Stud", "people": {
          "on_now": { "nodes": [
            { "id": "4D2C1B0A-9E8F-4A7B-8C6D-5E4F3A2B1C0D", "kind": "ACT", "role": "PERFORMER", "title": null,
              "starts_at": "2026-10-11T05:12:00Z", "ends_at": null, "start_timing": "NONE", "end_timing": "ADVANCE",
              "person": { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Ada" },
              "people": { "nodes": [ { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Ada" },
                                     { "id": "1A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Bo" } ] } }
          ] },
          "on_stage": { "id": "9D2C1B0A-9E8F-4A7B-8C6D-5E4F3A2B1C0D", "kind": "INTERMISSION", "title": "Bar break" },
          "up_next": { "id": "7D2C1B0A-9E8F-4A7B-8C6D-5E4F3A2B1C0D", "kind": "ACT", "role": "PERFORMER",
                       "starts_at": null, "start_timing": "NONE", "end_timing": "ADVANCE",
                       "person": { "id": "2A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Cleo" },
                       "people": { "nodes": [ { "id": "2A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Cleo" } ] } }
        } }
        """)

        #expect(detail.onNow.first?.name == "Ada & Bo")
        #expect(detail.onNow.first?.hours == nil)
        #expect(detail.onNow.intermission?.title == "Bar break")
        #expect(detail.onNow.upNext?.name == "Cleo")
        #expect(detail.onNow.hasAnything)
    }

    @Test("A set without an end runs until close")
    func hoursUntilClose() {
        let person = Person(id: UUID(), name: "Q")
        let start = Date(timeIntervalSince1970: 1_792_133_100)
        let open = Appearance(id: UUID(), person: person, role: .dj, startsAt: start)
        let ended = Appearance(id: UUID(), person: person, role: .dj, startsAt: start, endsAt: start.addingTimeInterval(3600))

        #expect(open.hours?.hasSuffix("– close") == true)
        #expect(ended.hours?.hasSuffix("close") == false)
        #expect(Appearance.Role.dj.systemImage == "headphones")
    }

    @Test("Keeps someone whose role this build doesn't know, without a label")
    func unknownRole() throws {
        let appearance = try decode(Appearance.self, from: """
        { "id": "4D2C1B0A-9E8F-4A7B-8C6D-5E4F3A2B1C0D", "role": "BARTENDER",
          "person": { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Sam" } }
        """)

        #expect(appearance.role == nil)
        #expect(appearance.startsAt == nil)
        #expect(appearance.hours == nil)
        #expect(Appearance.Role(wire: "performer")?.label == "Performer")
    }
}

@Suite("Chat wire format")
struct VenueMessageTests {
    @Test("Decodes an inbound Action Cable message")
    func inbound() throws {
        let payload = try JSONDecoder().decode(VenueMessage.Payload.self, from: Data("""
        {
          "type": "incoming",
          "message": "who's here",
          "user_id": "6c4d2e80-3a19-4b7f-9e5c-1d0a8b2f3e44",
          "name": "Rick",
          "avatar_url": "https://cdn.hotmess.social/rick",
          "sent_at": "2026-10-06T22:10:00Z"
        }
        """.utf8))

        let message = VenueMessage(payload: payload)

        #expect(message.body == "who's here")
        #expect(message.name == "Rick")
        #expect(message.sentAt == Date(timeIntervalSince1970: 1_791_324_600))
        #expect(message.isOutgoing(for: payload.userID))
        #expect(message.isOutgoing(for: UUID()) == false)
        #expect(message.isOutgoing(for: nil) == false)
        #expect(message.role == nil)
        #expect(message.kind == .text)
        #expect(message.isPinned == false)
        #expect(message.richContent == nil)
    }

    @Test("Decodes a rich message from someone with a role")
    func richFrame() throws {
        let payload = try JSONDecoder().decode(VenueMessage.Payload.self, from: Data("""
        {
          "type": "incoming",
          "id": "1b2c3d4e-5f60-4718-9a2b-3c4d5e6f7a8b",
          "message": "Shared an event: Sunset Social\\nCome through",
          "user_id": "6c4d2e80-3a19-4b7f-9e5c-1d0a8b2f3e44",
          "name": "Kiko M.",
          "avatar_url": null,
          "sent_at": "2026-10-06T22:10:00Z",
          "role": "host",
          "kind": "event",
          "title": null,
          "body": "Come through",
          "photo_url": null,
          "event": { "id": "0a1e0aac-1d01-42d1-9de5-f0279842d9c0", "name": "Sunset Social", "start_at": "2026-10-10T02:00:00Z" },
          "ends_at": null,
          "pinned": false
        }
        """.utf8))

        let message = VenueMessage(payload: payload)

        #expect(message.body == "Shared an event: Sunset Social\nCome through")
        #expect(message.role == .host)
        #expect(message.kind == .event)
        #expect(message.written == "Come through")
        #expect(message.event?.name == "Sunset Social")
        #expect(message.event?.startAt == Date(timeIntervalSince1970: 1_791_597_600))
        #expect(message.isFromPlace == false)
        guard case let .event(event, caption) = message.richContent else {
            Issue.record("Expected an event")
            return
        }
        #expect(event.id == UUID(uuidString: "0A1E0AAC-1D01-42D1-9DE5-F0279842D9C0"))
        #expect(caption == "Come through")
    }

    @Test("Talent posting as their listing: a host with no presence or friend name")
    func personFrame() throws {
        let poster = UUID(uuidString: "6C4D2E80-3A19-4B7F-9E5C-1D0A8B2F3E44")!
        let person = UUID(uuidString: "9E1D2C3B-4A5F-4607-8899-AABBCCDDEEFF")!
        let frame = try JSONDecoder().decode(VenueMessage.Payload.self, from: Data("""
        {
          "type": "incoming",
          "id": "2b2c3d4e-5f60-4718-9a2b-3c4d5e6f7a8b",
          "message": "Doors at nine",
          "user_id": "6c4d2e80-3a19-4b7f-9e5c-1d0a8b2f3e44",
          "name": "Miss Texas",
          "sent_at": "2026-10-11T04:00:00Z",
          "role": "host",
          "kind": "text",
          "presence": "online",
          "posted_as_person": true,
          "person_id": "9e1d2c3b-4a5f-4607-8899-aabbccddeeff"
        }
        """.utf8))
        let message = VenueMessage(payload: frame)
        #expect(message.personID == person)
        #expect(message.isFromListing)
        #expect(!message.isFromPlace)

        let line = message.threadMessage(currentUserID: nil, friends: [poster: HotMess.Friend(id: poster, name: "Ty Lee")])
        #expect(line.authorName == "Miss Texas")
        #expect(line.authorID == "person:\(person.uuidString)")
        #expect(line.presence == nil)

        let graphQL = try JSONDecoder().decode(VenueMessage.Payload.self, from: Data("""
        { "message": "Hi", "user_id": "6c4d2e80-3a19-4b7f-9e5c-1d0a8b2f3e44", "role": "HOST",
          "posted_as_person": true, "person": { "id": "9e1d2c3b-4a5f-4607-8899-aabbccddeeff" } }
        """.utf8))
        #expect(VenueMessage(payload: graphQL).personID == person)
    }

    @Test("Reads GraphQL's uppercase enums")
    func graphQLEnums() throws {
        let payload = try JSONDecoder().decode(VenueMessage.Payload.self, from: Data("""
        {
          "message": "Announcement: Coat check closes at midnight",
          "body": "",
          "user_id": "6c4d2e80-3a19-4b7f-9e5c-1d0a8b2f3e44",
          "name": "Neighbours",
          "role": "VENUE",
          "kind": "ANNOUNCEMENT",
          "title": "Coat check closes at midnight",
          "pinned": true,
          "posted_as_venue": true,
          "presence": "ONLINE",
          "event": null
        }
        """.utf8))

        let message = VenueMessage(payload: payload)

        #expect(message.role == .venue)
        #expect(message.kind == .announcement)
        #expect(message.isPinned)
        #expect(message.postedAsVenue)
        #expect(message.isFromPlace)
        #expect(message.presence == .online)
        #expect(message.richContent == .announcement(
            title: "Coat check closes at midnight", body: nil, photoURL: nil, isPinned: true
        ))
    }

    @Test("Shows an unknown or incomplete rich message as its summary")
    func unknownKind() throws {
        let payload = try JSONDecoder().decode(VenueMessage.Payload.self, from: Data("""
        {
          "message": "Shared a photo",
          "user_id": "6c4d2e80-3a19-4b7f-9e5c-1d0a8b2f3e44",
          "role": "dj",
          "kind": "photo",
          "photo_url": "",
          "pinned": "yes"
        }
        """.utf8))

        let message = VenueMessage(payload: payload)

        #expect(message.role == nil)
        #expect(message.kind == .photo)
        #expect(message.isPinned == false)
        #expect(message.richContent == nil)
        #expect(message.threadMessage(currentUserID: nil).text == "Shared a photo")
    }

    @Test("A special stops showing at its end")
    func specialEnds() {
        var message = VenueMessage(body: "Special: Two for one", userID: UUID())
        message.kind = .special
        message.title = "Two for one"
        message.endsAt = Date(timeIntervalSince1970: 1_000)

        #expect(message.isShowing(at: Date(timeIntervalSince1970: 999)))
        #expect(message.isShowing(at: Date(timeIntervalSince1970: 1_000)) == false)
    }

    @Test("Shows friends by their full name, and who's online in the room")
    func friendNamesAndPresence() throws {
        let userID = UUID()
        let message = VenueMessage(body: "hi", userID: userID, name: "Aurora B.")
        let friend = HotMess.Friend(id: userID, name: "Aurora Borealis")

        let stranger = message.threadMessage(currentUserID: nil, online: [])
        let known = message.threadMessage(currentUserID: nil, friends: [userID: friend], online: [userID])

        #expect(stranger.authorName == "Aurora B.")
        #expect(stranger.presence == nil)
        #expect(known.authorName == "Aurora Borealis")
        #expect(known.presence == .online)
    }

    @Test("A post as the venue keeps the venue's name and has no presence")
    func placeKeepsItsName() {
        let userID = UUID()
        var message = VenueMessage(body: "Doors at 9", userID: userID, name: "Neighbours")
        message.role = .venue
        let friend = HotMess.Friend(id: userID, name: "Aurora Borealis")

        let thread = message.threadMessage(currentUserID: nil, friends: [userID: friend], online: [userID])

        #expect(thread.authorName == "Neighbours")
        #expect(thread.presence == nil)
        #expect(thread.isFromPlace)
        #expect(thread.authorID != userID.uuidString)
    }

    @Test("Rich messages stand alone in the thread")
    func richMessagesStandAlone() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func message(_ id: String, rich: ChatRichContent? = nil, minutes: Double) -> ChatThreadMessage {
            ChatThreadMessage(
                id: id, authorID: "kiko", authorName: "Kiko", avatarURL: nil, text: id,
                sentAt: start.addingTimeInterval(minutes * 60), isOwn: false, rich: rich
            )
        }

        let rows = ChatThreadRow.rows(for: [
            message("a", minutes: 0),
            message("b", rich: .special(title: "Two for one", body: nil, endsAt: nil), minutes: 1),
            message("c", minutes: 2),
            message("d", minutes: 3),
        ])

        #expect(rows.map(\.isFirstInGroup) == [true, true, true, false])
        #expect(rows.map(\.isLastInGroup) == [true, true, false, true])
    }

    @Test("Reads a friend's presence")
    func friendPresence() throws {
        let friends = try decode([HotMess.Friend].self, from: """
        [
          {"id":"6c4d2e80-3a19-4b7f-9e5c-1d0a8b2f3e44","name":"Aurora Borealis","presence":"ONLINE"},
          {"id":"0a1e0aac-1d01-42d1-9de5-f0279842d9c0","name":"Sam Oak","presence":"PUSH"},
          {"id":"1b2c3d4e-5f60-4718-9a2b-3c4d5e6f7a8b","name":"Jo","presence":"OFFLINE"},
          {"id":"2b2c3d4e-5f60-4718-9a2b-3c4d5e6f7a8b","name":"Older API"}
        ]
        """)

        #expect(friends.map(\.presence) == [.online, .push, nil, nil])
    }
}

@Test func musicLinksNameTheirService() {
    let spotify = SocialLink(id: UUID(), handle: "artist/4Z8W4fKeB5YxbusRsdQVPb", provider: "spotify")
    let appleMusic = SocialLink(id: UUID(), handle: "us/artist/1", provider: "apple_music")
    let soundCloud = SocialLink(id: UUID(), handle: "dj-dugan", provider: "soundcloud")

    #expect(spotify.label == "Spotify")
    #expect(appleMusic.label == "Apple Music")
    #expect(soundCloud.label == "/dj-dugan")
    #expect(spotify.systemImage == "music.note")
    #expect(soundCloud.systemImage == "link")
}

@Suite("Safety decoding")
struct SafetyDecodingTests {
    @Test("Reads who the user blocked and when they agreed to the terms")
    func fullPayload() throws {
        let state = try decode(SafetyState.self, from: """
        {
          "terms_accepted_at": "2026-10-08T22:00:00Z",
          "blocked_users": [
            { "id": "6f2c1c1e-5e0a-4f0e-9a49-0b7f4a3c2d10", "name": "Aurora B.", "avatar_url": "https://example.com/a.jpg" }
          ]
        }
        """)

        #expect(state.termsAcceptedAt == (try instant("2026-10-08T22:00:00Z")))
        #expect(state.blockedUsers.map(\.name) == ["Aurora B."])
        #expect(state.blockedUsers.first?.avatarURL == URL(string: "https://example.com/a.jpg"))
    }

    @Test("Treats a user who never agreed or blocked anyone as neither")
    func emptyPayload() throws {
        let state = try decode(SafetyState.self, from: #"{ "terms_accepted_at": null }"#)

        #expect(state.termsAcceptedAt == nil)
        #expect(state.blockedUsers.isEmpty)
        #expect(state.hasFacebook, "an API without the field only has Facebook accounts")
        #expect(!state.canPretendLocation)
    }

    @Test("Reads an Apple account without Facebook, in App Review")
    func appleAccount() throws {
        let state = try decode(SafetyState.self, from: """
        { "terms_accepted_at": null, "blocked_users": [], "can_pretend_location": true, "self": { "has_facebook": false } }
        """)

        #expect(!state.hasFacebook)
        #expect(state.canPretendLocation)
    }
}

@Suite("Mixins")
struct MixinDecodingTests {
    static let admission: String = CoverDecodingTests.admission

    static let charge = """
    { "amount": { "cents": 1000, "currency": "usd" }, "fee": { "cents": 112, "currency": "usd" }, "total": { "cents": 1112, "currency": "usd" }, "night": "2026-10-09", "from": "21:00", "payable": true }
    """

    @Test("Reads an event's venue from its venue mixin")
    func eventVenue() throws {
        let event = try decode(Event.self, from: Fixtures.event)

        #expect(event.venue?.id == UUID(uuidString: "1E0B9F3C-6F42-4B8E-9C7A-0D5E4A2B7C90"))
        #expect(event.venue?.name == "Pop-up")
    }

    @Test("A to-be-announced venue or a null mixin is no venue")
    func eventWithoutVenue() throws {
        let base = String(Fixtures.sparseEvent.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
        let announced = try decode(Event.self, from: base + #", "venue": { "name": "To be announced", "venue": null } }"#)
        let off = try decode(Event.self, from: base + #", "venue": null }"#)

        #expect(announced.venue == nil)
        #expect(off.venue == nil)
    }

    @Test("An event written out reads back with its venue")
    func eventRoundTrip() throws {
        let event = try decode(Event.self, from: Fixtures.event)
        let data = try JSONEncoder.hotMess.encode(event)
        let again = try JSONDecoder.hotMess.decode(Event.self, from: data)

        #expect(again.venue == event.venue)
        #expect(again.id == event.id)
    }

    @Test("Null events and missing tickets mixins read as none")
    func nullMixins() throws {
        let venue = try decode(VenueWithEvents.self, from: """
        { "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11", "name": "The Stud", "events": null }
        """)
        let person = try decode(PersonDetail.self, from: """
        { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Nobody", "events": null }
        """)
        let locale = try decode(LocaleEventsResponse.self, from: #"{ "locale": { "events": null } }"#)

        #expect(venue.events.isEmpty)
        #expect(venue.coverCharge == nil)
        #expect(venue.viewerAdmission == nil)
        #expect(person.events.isEmpty)
        #expect(locale.locale?.events.isEmpty == true)
    }

    @Test("Reads a locale's upcoming events")
    func localeEvents() throws {
        let response = try decode(LocaleEventsResponse.self, from: """
        { "locale": { "events": { "upcoming": { "nodes": [\(Fixtures.event), \(Fixtures.sparseEvent)] } } } }
        """)

        #expect(response.locale?.events.map(\.name) == ["Some Thing", "Afters"])
    }

    @Test("Reads a venue's cover mixin")
    func venueCover() throws {
        let venue = try decode(VenueWithEvents.self, from: """
        { "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11", "name": "The Stud",
          "tickets": { "cover": { "cover_charge": \(Self.charge), "viewer_admission": \(Self.admission) } } }
        """)

        #expect(venue.coverCharge?.total.cents == 1112)
        #expect(venue.viewerAdmission?.isPaid == true)
    }

    @Test("Reads an event's cover and its venue's cover tonight")
    func eventCover() throws {
        let base = String(Fixtures.sparseEvent.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
        let detail = try decode(EventDetail.self, from: base + """
        , "tickets": { "cover": { "cover_charge": \(Self.charge) } },
          "venue_cover": { "venue": { "tickets": { "cover": { "cover_charge": \(Self.charge), "viewer_admission": \(Self.admission) } } } } }
        """)

        #expect(detail.coverCharge?.night == "2026-10-09")
        #expect(detail.venueCoverTonight?.night == "2026-10-09")
        #expect(detail.isCoverTonight)
        #expect(detail.viewerAdmission?.isPaid == true)
    }

    @Test("Shows an event's hosts as hosts and keeps them out of its lineup")
    func eventHosts() throws {
        let base = String(Fixtures.sparseEvent.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
        let host = #"{ "id": "1A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "SLC Leather Pride", "avatar_url": null }"#
        let act = #"{ "id": "2B2C3D4E-5F60-4B7C-9DAE-1F2A3B4C5D6E", "name": "Kiko Soirée", "avatar_url": null }"#
        let detail = try decode(EventDetail.self, from: base + """
        , "people": { "hosts": { "nodes": [\(host)] }, "lineup": { "nodes": [\(host), \(act)] } } }
        """)

        #expect(detail.hosts.map(\.name) == ["SLC Leather Pride"])
        #expect(detail.people.map(\.name) == ["Kiko Soirée"])

        let lineupOnly = try decode(EventDetail.self, from: base + #", "people": { "lineup": { "nodes": [\#(act)] } } }"#)
        #expect(lineupOnly.hosts.isEmpty)
        #expect(lineupOnly.people.map(\.name) == ["Kiko Soirée"])
    }

    @Test("An event with no venue or no cover module has no venue cover")
    func eventWithoutVenueCover() throws {
        let base = String(Fixtures.sparseEvent.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
        let tba = try decode(EventDetail.self, from: base + #", "tickets": { "cover": { "cover_charge": null } }, "venue_cover": { "venue": null } }"#)
        let off = try decode(EventDetail.self, from: base + #", "venue_cover": null }"#)

        #expect(tba.coverCharge == nil)
        #expect(tba.venueCoverTonight == nil)
        #expect(off.viewerAdmission == nil)
    }
}
