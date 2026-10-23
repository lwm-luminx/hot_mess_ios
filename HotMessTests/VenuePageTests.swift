//
//  VenuePageTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

@Suite("Venue page")
struct VenuePageTests {
    private let banner = URL(string: "https://cdn.example.com/google.jpg")!
    private let first = URL(string: "https://cdn.example.com/1.jpg")!
    private let second = URL(string: "https://cdn.example.com/2.jpg")!
    private let photo = URL(string: "https://cdn.example.com/photo.jpg")!

    private func venue(banner: URL? = nil, photo: URL? = nil, facebookLink: URL? = nil) -> Venue {
        Venue(id: UUID(), name: "Club Triangles", facebookLink: facebookLink, photoURL: photo, bannerURL: banner)
    }

    @Test("The hero rotates through the banner and then the banner images, once each")
    func heroPhotos() {
        let overview = VenueOverview(venue: venue(banner: first, photo: photo), bannerPhotos: [first, second])
        #expect(overview.heroPhotos == [first, second])

        let google = VenueOverview(venue: venue(banner: banner), bannerPhotos: [first, second])
        #expect(google.heroPhotos == [banner, first, second])

        #expect(VenueOverview(venue: venue(photo: photo)).heroPhotos == [photo])
        #expect(VenueOverview(venue: venue()).heroPhotos.isEmpty)
    }

    @Test("The next event is on the hero, the two after it up top, and the rest below")
    func comingUp() {
        let events = (0..<5).map { day in
            Event(id: UUID(), name: "Night \(day)", startDate: .now.addingTimeInterval(Double(day) * 86_400))
        }
        let overview = VenueOverview(venue: venue(), events: events)
        #expect(overview.nextEvent?.id == events[0].id)
        #expect(overview.comingUp.map(\.id) == events[1...2].map(\.id))
        #expect(overview.laterEvents.map(\.id) == events.dropFirst(3).map(\.id))
    }

    @Test("About lists every link once, Facebook first, then Instagram")
    func aboutLinks() {
        let page = URL(string: "https://www.facebook.com/clubtriangles")!
        let instagram = SocialLink(id: UUID(), handle: "clubtriangles", provider: "instagram",
                                   url: URL(string: "https://instagram.com/clubtriangles"))
        let tiktok = SocialLink(id: UUID(), handle: "triangles", provider: "tiktok",
                                url: URL(string: "https://tiktok.com/@triangles"))
        let venmo = SocialLink(id: UUID(), handle: "triangles", provider: "venmo",
                               url: URL(string: "https://venmo.com/triangles"))
        let noURL = SocialLink(id: UUID(), handle: "x", provider: "x")

        let links = SocialLink.aboutLinks([tiktok, instagram, instagram, venmo, noURL], facebookURL: page)
        #expect(links.map(\.provider) == ["facebook", "instagram", "tiktok"])
        #expect(links.first?.url == page)
        #expect(links.first?.serviceName == "Facebook")

        // A listed Facebook profile wins over the page's own link.
        let listed = SocialLink(id: UUID(), handle: "triangles.sf", provider: "facebook",
                                url: URL(string: "https://facebook.com/triangles.sf"))
        let withListed = SocialLink.aboutLinks([instagram, listed], facebookURL: page)
        #expect(withListed.map(\.id) == [listed.id, instagram.id])
    }
}
