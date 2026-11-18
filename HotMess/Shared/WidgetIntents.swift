//
//  WidgetIntents.swift
//  HotMess
//
//  Shared with the HotMessWidgets extension, whose Live Activity and Tonight
//  widget draw these as buttons. They are Live Activity intents, so iOS runs
//  them in the app's process (launching it in the background if need be),
//  where the app has the user's session; the extension never calls the API.
//

import AppIntents
import Foundation

/// What the buttons ask the app to do. The app sets these as it launches
/// (`AppModel`); in the widget extension they stay nil.
@MainActor
enum WidgetActions {
    struct Handlers: Sendable {
        /// "I'm in" on a friend's Ping, as a whole.
        var joinPing: @Sendable (_ pingID: String) async throws -> Void
        /// Says yes to the Quickie's topic.
        var acceptQuickie: @Sendable (_ venueID: UUID, _ matchID: UUID) async throws -> Void
        /// Asks for a new topic for the two of them (both say yes again).
        var newQuickieTopic: @Sendable (_ venueID: UUID, _ matchID: UUID) async throws -> Void
    }

    static var handlers: Handlers?
}

/// The app wasn't there to run a button: signed out, or (never expected) the
/// intent ran in the extension.
struct WidgetActionUnavailable: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "Open Hot Mess to do that." }
}

struct JoinPingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Join a Ping" }
    static var description: IntentDescription { IntentDescription("Says you're in on a friend's Ping tonight.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Ping")
    var pingID: String

    init() {}

    init(pingID: String) {
        self.pingID = pingID
    }

    func perform() async throws -> some IntentResult {
        guard let handlers = await WidgetActions.handlers else { throw WidgetActionUnavailable() }
        try await handlers.joinPing(pingID)
        return .result()
    }
}

struct AcceptQuickieIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Say yes to a Quickie" }
    static var description: IntentDescription { IntentDescription("Says yes to your Quickie's topic.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Venue")
    var venueID: String
    @Parameter(title: "Pairing")
    var matchID: String

    init() {}

    init(venueID: String, matchID: String) {
        self.venueID = venueID
        self.matchID = matchID
    }

    func perform() async throws -> some IntentResult {
        guard let handlers = await WidgetActions.handlers,
              let venue = UUID(uuidString: venueID), let match = UUID(uuidString: matchID)
        else { throw WidgetActionUnavailable() }
        try await handlers.acceptQuickie(venue, match)
        return .result()
    }
}

struct NewQuickieTopicIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "New Quickie topic" }
    static var description: IntentDescription { IntentDescription("Asks for a new topic for your Quickie.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Venue")
    var venueID: String
    @Parameter(title: "Pairing")
    var matchID: String

    init() {}

    init(venueID: String, matchID: String) {
        self.venueID = venueID
        self.matchID = matchID
    }

    func perform() async throws -> some IntentResult {
        guard let handlers = await WidgetActions.handlers,
              let venue = UUID(uuidString: venueID), let match = UUID(uuidString: matchID)
        else { throw WidgetActionUnavailable() }
        try await handlers.newQuickieTopic(venue, match)
        return .result()
    }
}
