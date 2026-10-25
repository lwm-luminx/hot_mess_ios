//
//  SafetyAlertTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Safety alerts")
struct SafetyAlertTests {
    private let alertJSON = """
    {"id":"6f1c3a5e-1d2b-4c1e-9a77-0b1b2c3d4e5f","state":"OPEN","place":"DANCE_FLOOR","concerns":["BOTHERING"],
     "description":null,"summary":"Dance floor · Someone's bothering them","seen":true,"acknowledgedByName":null,
     "acknowledgedAt":null,"escalatedAt":null,"closedAt":null,"supportSharedAt":null,"supportNote":null,
     "createdAt":"2026-10-23T03:15:00Z","venue":{"id":"8b4f1b60-9a5d-4d0e-9b3f-2c6b3e5d8a11","name":"Purr"},
     "messages":[{"id":"m1","body":"Where are you?","fromStaff":true,"senderName":"Jo","createdAt":"2026-10-23T03:16:00Z"}]}
    """

    @Test("Decodes the alert the API sends the guest")
    func decodes() throws {
        let alert = try JSONDecoder.hotMess.decode(SafetyAlert.self, from: Data(alertJSON.utf8))

        #expect(alert.state == .open)
        #expect(alert.place == .danceFloor)
        #expect(alert.concerns == [.bothering])
        #expect(alert.isActive)
        #expect(alert.messages.first?.fromStaff == true)
    }

    @Test("Offers other ways to get help once nobody picks it up in 2 minutes")
    func unanswered() throws {
        let alert = try JSONDecoder.hotMess.decode(SafetyAlert.self, from: Data(alertJSON.utf8))

        #expect(!alert.isUnanswered(at: alert.createdAt.addingTimeInterval(90)))
        #expect(alert.isUnanswered(at: alert.createdAt.addingTimeInterval(121)))
    }

    @Test("Opens a guest's push about an alert to the alert")
    func deepLink() throws {
        let id = try #require(UUID(uuidString: "6f1c3a5e-1d2b-4c1e-9a77-0b1b2c3d4e5f"))
        let url = try #require(URL(string: "https://hotmess.social/safety-alerts/\(id.uuidString.lowercased())"))

        #expect(DeepLink.destination(for: url) == .safetyAlert(id))
    }

    @Test("Writes support numbers out so they can be read aloud")
    func numbers() throws {
        let json = """
        {"id":"trevor","name":"The Trevor Project","description":null,"phone":"18664887386",
         "textNumber":"678678","textBody":"START","url":null}
        """
        let line = try JSONDecoder.hotMess.decode(SupportResources.Line.self, from: Data(json.utf8))

        #expect(line.numbers == "Call 1-866-488-7386 · Text START to 678678")
        #expect(line.textURL?.absoluteString == "sms:678678?body=START")
        #expect(SupportResources.format("988") == "988")
    }

    @Test("Sets a ride's pickup at the venue, or opens the app plain without one")
    func rideLink() throws {
        let json = """
        {"id":"uber","name":"Uber","url":"https://m.uber.com/ul/",
         "pickupUrl":"https://m.uber.com/ul/?action=setPickup&pickup%5Blatitude%5D={latitude}&pickup%5Blongitude%5D={longitude}&pickup%5Bnickname%5D={name}"}
        """
        let ride = try JSONDecoder.hotMess.decode(SupportResources.Ride.self, from: Data(json.utf8))
        let pickup = RidePickup(coordinates: Coordinates(latitude: 47.6137, longitude: -122.3197), name: "The Wildrose & Co")

        #expect(ride.link(pickup: pickup)?.absoluteString ==
            "https://m.uber.com/ul/?action=setPickup&pickup%5Blatitude%5D=47.613700&pickup%5Blongitude%5D=-122.319700&pickup%5Bnickname%5D=The%20Wildrose%20%26%20Co")
        #expect(ride.link(pickup: nil)?.absoluteString == "https://m.uber.com/ul/")
    }
}
