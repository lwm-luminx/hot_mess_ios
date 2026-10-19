import Foundation
import Testing
@testable import HotMess

@Suite("Karaoke nights")
struct KaraokeTests {
    private func event(karaoke: [String: Any]?) throws -> Event {
        var payload = try #require(JSONSerialization.jsonObject(with: Data(Fixtures.sparseEvent.utf8)) as? [String: Any])
        payload["karaoke"] = karaoke
        return try JSONDecoder.hotMess.decode(Event.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    @Test("Venue control uses the effective session and join URL returned by the API")
    func venueControl() throws {
        let night = try event(karaoke: ["provider": "karafun", "provider_name": "KaraFun", "session_code": "123456",
            "join_url": "https://www.karafun.com/123456/"])
        #expect(night.isKaraoke)
        #expect(night.karaoke?.venueControlled == true)
        #expect(night.karaoke?.joinURL?.absoluteString == "https://www.karafun.com/123456/")
        let reconnected = try event(karaoke: ["session_code": "654321", "join_url": "https://www.karafun.com/654321/"])
        #expect(reconnected.karaoke?.joinURL?.absoluteString == "https://www.karafun.com/654321/")
    }

    @Test("An individual night keeps its own session")
    func ownSession() throws {
        let night = try event(karaoke: ["session_code": "654321", "own_session_code": "654321", "join_url": "https://www.karafun.com/654321/"])
        #expect(night.karaoke?.venueControlled == false)
        #expect(night.karaoke?.sessionCode == "654321")
        let roundTrip = try JSONDecoder.hotMess.decode(Event.self, from: JSONEncoder.hotMess.encode(night))
        #expect(roundTrip.karaoke == night.karaoke)
    }

    @Test("Karaoke remains visible without a connected provider or session")
    func disconnected() throws {
        let night = try event(karaoke: [:])
        #expect(night.isKaraoke)
        #expect(night.karaoke?.joinURL == nil)
        #expect(try event(karaoke: nil).isKaraoke == false)
    }

    @Test("AudienceKit's own karaoke has no session to join; a partner's does")
    func audienceKitKaraoke() throws {
        #expect(try event(karaoke: ["provider": "audiencekit", "provider_name": "Hot Mess"]).karaoke?.isAudienceKit == true)
        #expect(try event(karaoke: ["provider": "karafun", "join_url": "https://www.karafun.com/123456/"]).karaoke?.isAudienceKit == false)
        #expect(try event(karaoke: [:]).karaoke?.isAudienceKit == false)
    }

    @Test("Only safe web links can be opened", arguments: ["javascript:alert(1)", "file:///etc/passwd", "https://user:password@example.com", "not a URL"])
    func invalidLink(link: String) throws {
        #expect(try event(karaoke: ["join_url": link]).karaoke?.joinURL == nil)
    }

    @Test("Every event surface requests the karaoke facet")
    func documents() {
        #expect(HotMessAPI.Documents.eventFields.contains("karaoke {"))
        #expect(HotMessAPI.Documents.eventFields.contains("join_url: joinUrl"))
        #expect(HotMessAPI.Documents.eventFields.contains("own_session_code: ownSessionCode"))
    }
}
