//
//  NotificationStreamTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

/// A `myNotifications` result, as the cable hands it on.
private func frame(_ notification: String) -> AudienceCable.Event {
    .result(Data(#"{ "data": { "notification": \#(notification) } }"#.utf8))
}

private let ping = """
{
  "notificationId": "41",
  "title": "Alex pinged you",
  "body": "Drinks at The Stud?",
  "category": "PING",
  "data": { "url": "https://hotmess.social/pings/ping-1", "kind": "ping", "ping_id": "ping-1", "notification_id": "41" },
  "sentAt": "2026-10-11T03:12:45.123Z",
  "url": "https://hotmess.social/pings/ping-1"
}
"""

private func notification(_ id: String, data: [String: String] = [:]) -> InAppNotification {
    InAppNotification(id: id, title: "Hi", body: nil, category: nil, data: data, sentAt: nil)
}

@Suite("Your notifications")
struct NotificationStreamTests {
    @Test("Decodes a myNotifications result into the notification")
    func decodes() throws {
        let events = NotificationStreamConnection.events(from: frame(ping))
        guard case let .received(notification) = try #require(events.first) else {
            Issue.record("Expected a notification, got \(events)")
            return
        }

        #expect(events.count == 1)
        #expect(notification.id == "41")
        #expect(notification.title == "Alex pinged you")
        #expect(notification.body == "Drinks at The Stud?")
        #expect(notification.category == "PING")
        #expect(notification.data == [
            "url": "https://hotmess.social/pings/ping-1", "kind": "ping", "ping_id": "ping-1", "notification_id": "41",
        ])
        #expect(notification.url == URL(string: "https://hotmess.social/pings/ping-1"))
        #expect(notification.ping == PingNotification(url: URL(string: "https://hotmess.social/pings/ping-1"), pingID: "ping-1"))
        #expect(abs((notification.sentAt?.timeIntervalSince1970 ?? 0) - 1_791_688_365.123) < 0.01)
    }

    @Test("Reads data sent as a JSON string, with numbers, and blank text as absent")
    func lenientData() throws {
        let events = NotificationStreamConnection.events(from: frame("""
        { "notificationId": 7, "title": " ", "body": "In", "data": "{\\"kind\\":\\"ping_join\\",\\"ping_id\\":42}", "sentAt": "nope" }
        """))
        guard case let .received(notification) = try #require(events.first) else {
            Issue.record("Expected a notification, got \(events)")
            return
        }

        #expect(notification.id == "7")
        #expect(notification.title == nil)
        #expect(notification.sentAt == nil)
        #expect(notification.url == nil)
        #expect(notification.ping == PingNotification(pingID: "42"))
    }

    @Test("A refusal stops it; a drop says whether the cable reconnects; results for nobody mean nothing")
    func controlFrames() throws {
        let refused = AudienceCable.Event.result(Data(#"{ "data": null, "errors": [{ "message": "Not allowed" }] }"#.utf8))
        #expect(NotificationStreamConnection.events(from: refused) == [.refused])
        #expect(NotificationStreamConnection.events(from: .rejected) == [.refused])
        #expect(NotificationStreamConnection.events(from: .subscribed) == [.listening])
        #expect(NotificationStreamConnection.events(from: .disconnected(reason: nil, reconnects: true)) == [.disconnected(nil, reconnects: true)])
        #expect(NotificationStreamConnection.events(from: .disconnected(reason: "unauthorized", reconnects: false)) == [.disconnected("unauthorized", reconnects: false)])
        #expect(NotificationStreamConnection.events(from: .result(Data("not json".utf8))).isEmpty)
        // No ID: nothing to dedupe it by, so it isn't shown.
        #expect(NotificationStreamConnection.events(from: frame(#"{ "title": "?" }"#)).isEmpty)
    }

    @Test("Executes MyNotifications with no variables, on GraphQLChannel")
    func execute() throws {
        let data = AudienceCable.executeData(
            query: NotificationStreamConnection.document,
            variables: [:],
            operationName: NotificationStreamConnection.operationName
        )
        let object = try #require(try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any])

        #expect(object["action"] as? String == "execute")
        #expect(object["operationName"] as? String == "MyNotifications")
        #expect((object["variables"] as? [String: Any])?.isEmpty == true)

        let query = try #require(object["query"] as? String)
        #expect(query.split(separator: " ").first == "subscription")
        #expect(query.contains("MyNotifications {"))
        #expect(query.contains("notification: myNotifications { notificationId title body category data sentAt url }"))

        #expect(AudienceCable.graphQLIdentifier(audienceID: "aud", channelID: "c1") == #"{"audience_id":"aud","channel":"GraphQLChannel","channelId":"c1"}"#)
    }

    @Test("Reads a push's notification_id")
    func pushID() {
        #expect(InAppNotification.notificationID(in: ["notification_id": "41", "kind": "ping"]) == "41")
        #expect(InAppNotification.notificationID(in: ["notification_id": 41]) == "41")
        #expect(InAppNotification.notificationID(in: ["notification_id": ""]) == nil)
        #expect(InAppNotification.notificationID(in: ["kind": "ping"]) == nil)
    }

    @Test("Remembers a bounded number of IDs, forgetting the oldest")
    func recentIDs() {
        var recent = RecentNotificationIDs(capacity: 3)
        let first = recent.insert("1")
        let again = recent.insert("1")
        #expect(first)
        #expect(!again)
        recent.insert("2")
        recent.insert("3")
        recent.insert("4")

        #expect(recent.count == 3)
        #expect(!recent.contains("1"))
        #expect(recent.contains("2") && recent.contains("4"))
    }
}

@Suite("Your notifications, shown once")
@MainActor
struct NotificationDedupeTests {
    @Test("The system copy of a notification shown in the app is suppressed")
    func seenSuppressed() async {
        let stream = NotificationStream(cable: nil)
        stream.receive(notification("41"))

        #expect(stream.banner?.id == "41")
        #expect(await stream.shouldPresentSystemCopy(notificationID: "41") == false)
    }

    @Test("An unseen one is presented, and its late in-app copy isn't shown again")
    func unseenPresented() async {
        let stream = NotificationStream(cable: nil)

        #expect(await stream.shouldPresentSystemCopy(notificationID: "42"))
        stream.receive(notification("42"))
        #expect(stream.banner == nil)
    }

    @Test("A push without an ID is always presented")
    func noID() async {
        let stream = NotificationStream(cable: nil)
        #expect(await stream.shouldPresentSystemCopy(notificationID: nil))
        #expect(await stream.shouldPresentSystemCopy(notificationID: nil))
    }

    @Test("While listening, the system copy waits a moment for the in-app copy")
    func window() async {
        let stream = NotificationStream(cable: nil)
        stream.isListening = true
        // Long enough that the in-app copy lands inside it even on a busy CI
        // simulator; it returns as soon as that copy arrives.
        stream.systemCopyWindow = .seconds(15)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            stream.receive(notification("43"))
        }
        #expect(await stream.shouldPresentSystemCopy(notificationID: "43") == false)

        stream.systemCopyWindow = .milliseconds(200)
        #expect(await stream.shouldPresentSystemCopy(notificationID: "44"))
    }

    @Test("Each notification is shown once, and Now hears about Pings")
    func shownOnce() {
        let stream = NotificationStream(cable: nil)
        var received: [String] = []
        stream.onReceive = { received.append($0.id) }

        stream.receive(notification("1", data: ["kind": "ping", "ping_id": "p"]))
        stream.receive(notification("1"))
        stream.dismiss("1")
        #expect(stream.banner == nil)
        stream.receive(notification("2"))

        #expect(received == ["1", "2"])
        #expect(stream.banner?.id == "2")

        stream.reset()
        #expect(stream.banner == nil)
    }

    @Test("Tapping an in-app Ping opens Now from the top, like a tapped push")
    func routing() throws {
        let model = AppModel(configuration: AppConfiguration(baseURL: try #require(URL(string: "https://api.hotmess.social"))))
        model.selectedTab = .venues
        model.nowPath = [.venue(UUID())]
        let revision = model.pingRevision

        let tapped = notification("9", data: ["kind": "ping_join", "ping_id": "p"])
        let ping = try #require(tapped.ping)
        model.open(ping)

        #expect(model.selectedTab == .now)
        #expect(model.nowPath.isEmpty)
        #expect(model.pingRevision == revision + 1)
        #expect(notification("10", data: ["kind": "chat"]).ping == nil)
    }
}
