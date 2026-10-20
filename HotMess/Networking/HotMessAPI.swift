//
//  HotMessAPI.swift
//  HotMess
//

import AudienceKit
import Foundation

/// The typed surface of the Hot Mess API.
///
/// Everything goes through the audience's GraphQL endpoint on the AudienceKit
/// SDK except the client status, which is read before sign-in and isn't part
/// of any audience, and the two REST sign-ins the SDK has no call for. The
/// GraphQL documents alias fields to the snake_case keys the models already
/// decode, so one set of models serves both.
struct HotMessAPI: Sendable {
    let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    var baseURL: URL { client.baseURL }

    private var audienceKit: AudienceKitClient { client.audienceKit }

    // MARK: - Home

    /// Records where the device is and returns what's happening there. With no
    /// position there is nothing to look up, so the screen gets an empty "Now".
    func now(near coordinates: Coordinates?) async throws -> Now {
        guard let coordinates else {
            // Pings don't depend on where you are, so they still show.
            let current = try? await pings()
            return Now(
                title: String(localized: "Now"),
                myPing: current?.myPing,
                friendPings: current?.friendPings ?? []
            )
        }

        return try await query(
            Documents.reportLocation,
            variables: ["position": coordinates.graphQLInput],
            as: ReportLocationResponse.self
        ).reportLocation
    }

    // MARK: - Geofences

    /// Every visible venue's envelope, nearest `coordinates` first, for the
    /// regions the app watches. Only the id, point and radius, so the whole
    /// audience stays a small download.
    func venueFences(near coordinates: Coordinates) async throws -> [VenueFence] {
        try await query(
            Documents.venueFences,
            variables: ["near": coordinates.graphQLInput],
            as: VenueFencesResponse.self
        ).venues
    }

    // MARK: - Locales

    func closestLocale(to coordinates: Coordinates?) async throws -> AppLocale? {
        guard let coordinates else { return nil }

        do {
            guard let locale = try await audienceKit.closestLocale(
                near: coordinates.coordinate, beaconMajor: coordinates.beaconMajor
            ), let id = RecordID.uuid(locale.id) else { return nil }
            return AppLocale(id: id, name: locale.name ?? locale.label ?? "")
        } catch let error as AudienceKitError {
            throw APIError(error)
        }
    }

    // MARK: - People

    func person(_ id: UUID) async throws -> PersonDetail {
        let response = try await query(Documents.person, variables: ["id": .string(id.uuidString)], as: PersonResponse.self)
        guard let person = response.person else { throw APIError.notFound }
        return person
    }

    // MARK: - Venues

    /// The venue with its upcoming events, in one request.
    func venue(_ id: UUID) async throws -> VenueOverview {
        let response = try await query(Documents.venue, variables: ["id": .string(id.uuidString)], as: VenueResponse.self)
        guard let venue = response.venue else { throw APIError.notFound }
        return VenueOverview(
            venue: venue.venue,
            events: venue.events,
            friends: venue.friends,
            socialLinks: venue.socialLinks,
            chatOpen: venue.chatOpen,
            recentMessages: venue.recentMessages,
            coverCharge: venue.coverCharge,
            viewerAdmission: venue.viewerAdmission,
            viewerCoatCheck: venue.viewerCoatCheck,
            onNow: venue.onNow,
            friendPings: venue.friendPings
        )
    }

    // MARK: - Lineup

    /// A venue's lineup tonight with its karaoke singers and the user's
    /// signups, from the SDK, for AudienceKitUI's lineup and karaoke views.
    func lineup(venueID: UUID) async throws -> VenueLineup? {
        do {
            return try await audienceKit.lineup(venueID: venueID.uuidString)
        } catch let error as AudienceKitError {
            throw APIError(error)
        }
    }

    /// Signs the user up to sing at a venue. The server's refusal (not at the
    /// venue, signups closed) comes back worded for the room.
    func signUpToSing(venueID: UUID, _ signup: KaraokeSignup) async throws {
        do {
            try await audienceKit.signUpToSing(venueID: venueID.uuidString, signup)
        } catch let error as AudienceKitError {
            throw APIError(error)
        }
    }

    /// Asks the venue to play a song. The server's refusal (not at the venue,
    /// requests closed) comes back worded for the room.
    func requestSong(venueID: UUID, _ draft: SongRequestDraft) async throws {
        do {
            try await audienceKit.requestSong(
                venueID: venueID.uuidString,
                title: draft.title,
                artist: draft.artist,
                note: draft.note
            )
        } catch let error as AudienceKitError {
            throw APIError(error)
        }
    }

    /// Takes the user off the karaoke list, or a song request off the queue,
    /// while it hasn't been called up.
    func withdrawSongRequest(_ request: SongRequest) async throws {
        do {
            try await audienceKit.withdrawSongRequest(id: request.id)
        } catch let error as AudienceKitError {
            throw APIError(error)
        }
    }

    // MARK: - Events

    func events(in localeID: UUID) async throws -> EventListing {
        EventListing(upcoming: try await eventList(in: localeID))
    }

    /// A locale's events as the API orders them.
    func eventList(in localeID: UUID) async throws -> [Event] {
        let response = try await query(
            Documents.localeEvents,
            variables: ["id": .string(localeID.uuidString)],
            as: LocaleEventsResponse.self
        )
        guard let locale = response.locale else { throw APIError.notFound }
        return locale.events
    }

    func event(_ id: UUID) async throws -> EventDetail {
        let response = try await query(Documents.event, variables: ["id": .string(id.uuidString)], as: EventResponse.self)
        guard let event = response.event else { throw APIError.notFound }
        return event
    }

    func setRSVP(_ rsvp: RSVP, forEvent id: UUID) async throws {
        do {
            try await audienceKit.setRSVP(rsvp.state, forEvent: id.uuidString)
        } catch let error as AudienceKitError {
            throw APIError(error)
        }
    }

    // MARK: - Cover

    /// Starts paying tonight's cover at a venue. Asking again the same night
    /// returns the same pass and payment.
    func buyCover(venueID: UUID, quantity: Int = 1, tier: String? = nil) async throws -> CoverPurchase {
        var variables: [String: GraphQLValue] = [
            "venueId": .string(venueID.uuidString),
            "quantity": .int(quantity),
        ]
        if let tier {
            variables["tier"] = .string(tier)
        }
        return try await query(
            Documents.buyCover,
            variables: variables,
            as: BuyCoverResponse.self
        ).buyCover
    }

    /// Starts paying tonight's coat check at a venue.
    func buyCoatCheck(venueID: UUID, quantity: Int = 1) async throws -> CoverPurchase {
        let variables: [String: GraphQLValue] = [
            "venueId": .string(venueID.uuidString),
            "quantity": .int(quantity),
        ]
        return try await query(
            Documents.buyCoatCheck,
            variables: variables,
            as: BuyCoatCheckResponse.self
        ).buyCoatCheck
    }

    /// Pays a Square venue's cover with a payment token (nonce) from Square's
    /// In-App Payments SDK, a card or Apple Pay. The pass comes back paid when
    /// Square took the payment.
    func payCover(admissionID: String, sourceID: String, verificationToken: String? = nil) async throws -> Admission {
        var variables: [String: GraphQLValue] = [
            "admissionId": .string(admissionID),
            "sourceId": .string(sourceID),
        ]
        if let verificationToken {
            variables["verificationToken"] = .string(verificationToken)
        }

        return try await query(
            Documents.payCover,
            variables: variables,
            as: PayCoverResponse.self
        ).payCover.admission
    }

    /// Checks the payment with Stripe after the payment sheet finishes, so the
    /// pass works before Stripe's webhook arrives.
    func confirmCover(admissionID: String) async throws -> Admission {
        try await query(
            Documents.confirmCover,
            variables: ["admissionId": .string(admissionID)],
            as: ConfirmCoverResponse.self
        ).confirmCover.admission
    }

    func refundAdmission(_ admissionID: String) async throws -> Admission {
        try await query(
            Documents.refundAdmission,
            variables: ["admissionId": .string(admissionID)],
            as: RefundAdmissionResponse.self
        ).refundAdmission.admission
    }

    /// The user's cover passes, newest first.
    func admissions() async throws -> [Admission] {
        try await query(Documents.admissions, variables: [:], as: AdmissionsResponse.self).admissions
    }

    // MARK: - Session

    /// The signed-in user with their profile photo, which the SDK's `me`
    /// leaves out. `nil` when the API has no current user. Errors stay
    /// `AudienceKitError`s so the session can tell an ended session (401)
    /// from a network blip.
    func me() async throws -> User? {
        try await audienceKit.graphQL(Documents.me, as: MeResponse.self, decoder: .hotMess).me?.profile?.user
    }

    /// What the API asks of this app: the oldest version it still serves.
    /// `nil` when the status has no iOS row.
    func clientRequirement() async throws -> VersionInfo? {
        try await client.send(Endpoints.status).ios
    }

    /// Trades a Sign in with Apple identity token for a session. The caller
    /// hands the credential to the SDK (`adopt(credential:)`), which stores it.
    func signInWithApple(_ request: AppleSignInRequest) async throws -> Credential {
        try await client.send(Endpoints.appleSignIn(request))
    }

    /// `GET /v1/token/methods`: the ways the audience lets people sign in
    /// now, which AudienceKit's admin chooses. `host` names the audience. An
    /// API from before the setting answers 404.
    func signInMethods(host: String?) async throws -> SignInMethods {
        try await client.send(Endpoints.signInMethods(host: host))
    }

    /// `GET /v1/token/review`: whether the API takes App Review codes now
    /// (only while the audience is in App Review). `host` names the audience.
    func isReviewSignInEnabled(host: String?) async throws -> Bool {
        try await client.send(Endpoints.reviewSignInStatus(host: host)).enabled
    }

    /// Trades the App Review code from the review notes for a session on the
    /// designated reviewer account. A wrong code is a 401. The caller hands
    /// the credential to the SDK (`adopt(credential:)`), as with Apple.
    func signInWithReviewCode(_ request: ReviewSignInRequest) async throws -> Credential {
        try await client.send(Endpoints.reviewSignIn(request))
    }

    /// Connects Facebook to the signed-in account, with the code from
    /// Facebook's login dialog, and returns a new credential for the account.
    /// The caller hands it to the SDK (`adopt(credential:)`), which stores it.
    func connectFacebook(_ request: ConnectFacebookRequest) async throws -> Credential {
        try await client.send(Endpoints.connectFacebook(request))
    }

    /// Stores the APNs token for this device, through the SDK's
    /// `registerDevice`. `appID` is the bundle identifier, which the API sends
    /// pushes to as the APNs topic, and `sandbox` says the token is for APNs'
    /// development environment.
    func registerForPush(deviceToken: Data, appID: String?, sandbox: Bool) async throws {
        do {
            try await audienceKit.registerDevice(token: deviceToken.hexEncodedString, appId: appID, sandbox: sandbox)
        } catch let error as AudienceKitError {
            throw await APIClient.recorded(APIError(error), operation: "graphql mutation RegisterDevice")
        }
    }

    // MARK: - Pings

    /// The user's own active Ping and friends' active Pings, without
    /// reporting a location.
    func pings() async throws -> PingsResponse {
        try await query(Documents.pings, variables: [:], as: AudiencePingsResponse.self).pings
    }

    /// Sends a Ping for tonight, or edits the one already running.
    func sendPing(places: [PingPlace], note: String?, localeID: UUID?, reach: PingReach) async throws -> Ping {
        try await query(
            Documents.sendPing,
            variables: Self.sendPingVariables(places: places, note: note, localeID: localeID, reach: reach),
            as: SendPingResponse.self
        ).sendPing.ping
    }

    /// "I'm in", on one pick or, with no `targetID`, the whole Ping.
    func joinPing(_ pingID: String, targetID: String? = nil) async throws -> Ping {
        try await query(
            Documents.joinPing,
            variables: ["pingId": .string(pingID), "targetId": targetID.map(GraphQLValue.string) ?? .null],
            as: JoinPingResponse.self
        ).joinPing.ping
    }

    func leavePing(_ pingID: String) async throws -> Ping {
        try await query(Documents.leavePing, variables: ["pingId": .string(pingID)], as: LeavePingResponse.self)
            .leavePing.ping
    }

    /// Ends the user's own Ping early.
    func endPing() async throws {
        _ = try await query(Documents.endPing, variables: [:], as: EndPingResponse.self)
    }

    static func sendPingVariables(
        places: [PingPlace],
        note: String?,
        localeID: UUID?,
        reach: PingReach
    ) -> [String: GraphQLValue] {
        var venueIDs: [GraphQLValue] = []
        var eventIDs: [GraphQLValue] = []
        for place in places {
            switch place {
            case let .venue(id): venueIDs.append(.string(id.uuidString.lowercased()))
            case let .event(id): eventIDs.append(.string(id.uuidString.lowercased()))
            }
        }

        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [
            "venueIds": .array(venueIDs),
            "eventIds": .array(eventIDs),
            "note": trimmed.isEmpty ? .null : .string(trimmed),
            "localeId": localeID.map { GraphQLValue.string($0.uuidString.lowercased()) } ?? .null,
            "reach": .string(reach.rawValue),
        ]
    }

    // MARK: - Pair me up

    /// Pair me up at a venue: nil where the venue doesn't have it.
    func pairUp(venueID: UUID) async throws -> VenuePairUp? {
        try await query(Documents.venuePairUp, variables: ["id": Self.graphQLID(venueID)], as: VenuePairUpResponse.self)
            .venues?.venue?.pairUp
    }

    /// Opts in at the venue for tonight, or changes the hint; after a
    /// meeting, looks for someone new.
    func joinPairUp(venueID: UUID, lookFor: String?) async throws -> PairUpState? {
        let trimmed = lookFor?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await pairUpMutation(Documents.joinPairUp, [
            "venueId": Self.graphQLID(venueID),
            "lookFor": trimmed.map(GraphQLValue.string) ?? .null,
        ])
    }

    func acceptPairUp(matchID: UUID) async throws -> PairUpState? {
        try await pairUpMutation(Documents.acceptPairUp, ["matchId": Self.graphQLID(matchID)])
    }

    /// A new topic for the two of them, or (`partner`) someone new for both.
    func skipPairUp(matchID: UUID, partner: Bool) async throws -> PairUpState? {
        try await pairUpMutation(Documents.skipPairUp, [
            "matchId": Self.graphQLID(matchID),
            "what": .string(partner ? "PARTNER" : "TOPIC"),
        ])
    }

    /// Cancels a pairing: neither sees the other from then on.
    func cancelPairUp(matchID: UUID) async throws -> PairUpState? {
        try await pairUpMutation(Documents.cancelPairUp, ["matchId": Self.graphQLID(matchID)])
    }

    func leavePairUp(venueID: UUID) async throws -> PairUpState? {
        try await pairUpMutation(Documents.leavePairUp, ["venueId": Self.graphQLID(venueID)])
    }

    /// A fresh single-use code to show the partner.
    func showPairUpCode(matchID: UUID) async throws -> String {
        try await query(Documents.showPairUpCode, variables: ["matchId": Self.graphQLID(matchID)], as: ShowPairUpCodeResponse.self)
            .showPairUpCode.code
    }

    func scanPairUpCode(venueID: UUID, code: String) async throws -> PairUpScan {
        try await query(
            Documents.scanPairUpCode,
            variables: ["venueId": Self.graphQLID(venueID), "code": .string(code)],
            as: ScanPairUpCodeResponse.self
        ).scanPairUpCode
    }

    /// Each Pair me up mutation answers with `{ pairUp }` under its own name.
    private func pairUpMutation(_ document: String, _ variables: [String: GraphQLValue]) async throws -> PairUpState? {
        try await query(document, variables: variables, as: [String: PairUpPayload].self).values.first?.pairUp
    }

    private static func graphQLID(_ id: UUID) -> GraphQLValue {
        .string(id.uuidString.lowercased())
    }

    // MARK: - Safety

    /// Who the user blocked and whether they've agreed to the terms of use.
    func safety() async throws -> SafetyState {
        try await query(Documents.safety, variables: [:], as: SafetyResponse.self).me ?? SafetyState()
    }

    func blockUser(_ id: UUID) async throws -> [BlockedUser] {
        try await query(
            Documents.blockUser,
            variables: ["userId": .string(id.uuidString.lowercased())],
            as: BlockUserResponse.self
        ).blockUser.blockedUsers
    }

    func unblockUser(_ id: UUID) async throws -> [BlockedUser] {
        try await query(
            Documents.unblockUser,
            variables: ["userId": .string(id.uuidString.lowercased())],
            as: UnblockUserResponse.self
        ).unblockUser.blockedUsers
    }

    /// Reports a chat message to the audience's admins, and blocks its sender
    /// too when asked.
    func reportChatMessage(_ id: UUID, reason: String?, block: Bool) async throws {
        _ = try await query(
            Documents.reportChatMessage,
            variables: [
                "messageId": .string(id.uuidString.lowercased()),
                "reason": reason.map(GraphQLValue.string) ?? .null,
                "block": .bool(block),
            ],
            as: ReportChatMessageResponse.self
        )
    }

    /// Reports a person, venue, Ping, photo or message to the audience's
    /// moderators (the same queue as chat reports), and blocks whoever is
    /// behind it too when asked. Returns whether they're now blocked.
    @discardableResult
    func reportContent(_ target: ReportTarget, id: String, reason: String?, block: Bool) async throws -> Bool {
        try await query(
            Documents.reportContent,
            variables: [
                "targetType": .string(target.rawValue),
                "targetId": .string(id),
                "reason": reason.map(GraphQLValue.string) ?? .null,
                "block": .bool(block),
            ],
            as: ReportContentResponse.self
        ).reportContent.blocked
    }

    /// Takes back one of the user's own chat messages. The room drops it for
    /// everyone, the same as when an admin removes it.
    func removeMyChatMessage(_ id: UUID) async throws {
        _ = try await query(
            Documents.removeMyChatMessage,
            variables: ["messageId": .string(id.uuidString.lowercased())],
            as: RemoveMyChatMessageResponse.self
        )
    }

    /// Says something in a chat room as the user. The line also reaches the
    /// room's subscribers, the user's own included, as a `ChatMessagePosted`;
    /// this returns it as the room sees it, so the app can settle its pending
    /// line by ID.
    func sendMyChatMessage(_ body: String, in room: ChatRoom) async throws -> VenueMessage {
        let sent = try await query(
            Documents.sendMyChatMessage,
            variables: Self.sendMyChatMessageVariables(body, in: room),
            as: SendMyChatMessageResponse.self
        )
        return VenueMessage(payload: sent.sendMyChatMessage.message)
    }

    /// `{ input: { venueId | localeId, message } }`.
    static func sendMyChatMessageVariables(_ body: String, in room: ChatRoom) -> [String: GraphQLValue] {
        [
            "input": .object([
                room.subscriptionKey: .string(room.id.uuidString.lowercased()),
                "message": .string(body),
            ]),
        ]
    }

    /// The audience the app's GraphQL goes to: the build's pinned ID, the
    /// session's, or the one that owns the configured host. Chat sockets name
    /// it when they subscribe.
    func audienceID() async throws -> String {
        do {
            return try await audienceKit.audienceID()
        } catch let error as AudienceKitError {
            throw APIError(error)
        }
    }

    func acceptTerms() async throws -> Date? {
        try await query(Documents.acceptTerms, variables: [:], as: AcceptTermsResponse.self)
            .acceptTerms.termsAcceptedAt
    }

    /// Whether the user gets a push when people keep talking in a chat room
    /// they left in the last 30 minutes. Off until they turn it on.
    func recentChatPush() async throws -> Bool {
        try await query(Documents.recentChatPush, variables: [:], as: RecentChatPushResponse.self).me?.recentChatPush ?? false
    }

    /// Turns those pushes on or off, and returns the setting after the change.
    func setRecentChatPush(_ enabled: Bool) async throws -> Bool {
        try await query(
            Documents.setRecentChatPush,
            variables: ["enabled": .bool(enabled)],
            as: SetRecentChatPushResponse.self
        ).setRecentChatPush.recentChatPush
    }

    /// Deletes the account and everything the API keeps about the user. It
    /// can't be undone; the session is gone afterwards.
    func deleteAccount() async throws {
        _ = try await query(Documents.deleteAccount, variables: ["confirm": .bool(true)], as: DeleteAccountResponse.self)
    }

    // MARK: - Support

    /// "Report a Problem". Works signed out too, so sign-in trouble can be
    /// reported; the API then finds the audience from `host`.
    @discardableResult
    func reportProblem(_ report: BugReportRequest, signedIn: Bool) async throws -> BugReportResponse {
        try await client.send(Endpoint(
            "/v1/bug_reports",
            method: .post,
            body: JSONBody(report),
            requiresAuthentication: signedIn
        ))
    }

    private func query<Response: Decodable & Sendable>(
        _ document: String,
        variables: [String: GraphQLValue],
        as type: Response.Type
    ) async throws -> Response {
        do {
            return try await audienceKit.graphQL(document, variables: variables, as: type, decoder: .hotMess)
        } catch let error as AudienceKitError {
            throw await APIClient.recorded(APIError(error), operation: Self.operationName(document))
        }
    }

    /// "query Venue" or "mutation SendPing", for error reports: the document's
    /// first line up to its variables or selection.
    static func operationName(_ document: String) -> String {
        let head = document.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0 != "(" && $0 != "{" && $0 != "\n" }
        let name = head.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "graphql" : "graphql \(name)"
    }
}

// MARK: - REST

extension HotMessAPI {
    enum Endpoints {
        /// The client requirements, read-only and open. Read before sign-in,
        /// and not part of any audience, so it stays on REST.
        static let status = Endpoint<ServiceStatus>("/v1/status", method: .get, requiresAuthentication: false)

        /// Sign in with Apple. Sign-in mints the token, so none is sent. The
        /// response is the credential JSON (`token userId audienceId role
        /// endpoint`), which the SDK's `Credential` decodes.
        static func appleSignIn(_ request: AppleSignInRequest) -> Endpoint<Credential> {
            Endpoint("/v1/token/apple", method: .post, body: JSONBody(request), requiresAuthentication: false)
        }

        /// How the audience lets people sign in. Open, like the sign-ins.
        static func signInMethods(host: String?) -> Endpoint<SignInMethods> {
            Endpoint(
                "/v1/token/methods",
                method: .get,
                query: host.map { [URLQueryItem(name: "host", value: $0)] } ?? [],
                requiresAuthentication: false
            )
        }

        /// Whether App Review sign-in is on. Open, like the sign-ins.
        static func reviewSignInStatus(host: String?) -> Endpoint<ReviewSignInStatus> {
            Endpoint(
                "/v1/token/review",
                method: .get,
                query: host.map { [URLQueryItem(name: "host", value: $0)] } ?? [],
                requiresAuthentication: false
            )
        }

        /// App Review sign-in with the reviewer's code; the response is the
        /// same credential JSON as Sign in with Apple's.
        static func reviewSignIn(_ request: ReviewSignInRequest) -> Endpoint<Credential> {
            Endpoint("/v1/token/review", method: .post, body: JSONBody(request), requiresAuthentication: false)
        }

        /// Facebook sign-in with `connect`, sent with the current session so
        /// the API knows which account Facebook joins.
        static func connectFacebook(_ request: ConnectFacebookRequest) -> Endpoint<Credential> {
            Endpoint("/v1/token", method: .post, body: JSONBody(request))
        }
    }
}

/// `POST /v1/token/apple`. Apple gives the name only the first time someone
/// signs in to the app, so it's sent along then. The authorization code lets
/// the API get a refresh token from Apple, which it revokes when the account
/// is deleted.
struct AppleSignInRequest: Encodable, Sendable {
    let identityToken: String
    var authorizationCode: String? = nil
    let firstName: String?
    let lastName: String?
    let host: String?
    let device: DeviceDescription

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case firstName = "first_name"
        case lastName = "last_name"
        case host
        case device
    }
}

/// `GET /v1/token/methods`: `facebook`, `apple`, `google` and, only while
/// App Review codes work, `review_code`, with the warning to show (with
/// Cancel and Continue) before each method that has one.
struct SignInMethods: Decodable, Sendable, Equatable {
    let methods: [String]
    let warnings: [String: String]

    var facebook: Bool { methods.contains("facebook") }
    var apple: Bool { methods.contains("apple") }
    var reviewCode: Bool { methods.contains("review_code") }

    init(methods: [String], warnings: [String: String] = [:]) {
        self.methods = methods
        self.warnings = warnings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        methods = try container.decode([String].self, forKey: .methods)
        // An API from before warnings sends none.
        warnings = try container.decodeIfPresent([String: String].self, forKey: .warnings) ?? [:]
    }

    /// What to say before signing in with `method`, such as "Facebook login
    /// is only for testers"; nil for nothing.
    func warning(for method: String) -> String? {
        guard let warning = warnings[method]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !warning.isEmpty else { return nil }
        return warning
    }

    private enum CodingKeys: String, CodingKey { case methods, warnings }
}

/// `GET /v1/token/review`.
struct ReviewSignInStatus: Decodable, Sendable {
    let enabled: Bool

    private enum CodingKeys: String, CodingKey { case enabled }

    init(enabled: Bool) {
        self.enabled = enabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }
}

/// `POST /v1/token/review`: the code App Review was given in the review notes.
struct ReviewSignInRequest: Encodable, Sendable {
    let code: String
    let host: String?
    let device: DeviceDescription
}

/// `POST /v1/token` with `connect`, for an account that signed in with Apple.
struct ConnectFacebookRequest: Encodable, Sendable {
    /// From the Facebook SDK; otherwise `code` and `redirectURI` from the dialog.
    let facebookToken: String?
    let code: String?
    let redirectURI: String?
    let host: String?
    let facebookAppID: String?
    let device: DeviceDescription
    let connect = true

    init(result: FacebookSignIn.Result, host: String?, facebookAppID: String?, device: DeviceDescription) {
        switch result {
        case let .accessToken(token):
            (facebookToken, code, redirectURI) = (token, nil, nil)
        case let .code(code, redirectURI):
            (facebookToken, self.code, self.redirectURI) = (nil, code, redirectURI)
        }
        self.host = host
        self.facebookAppID = facebookAppID
        self.device = device
    }

    enum CodingKeys: String, CodingKey {
        case facebookToken = "facebook_token"
        case code
        case redirectURI = "redirect_uri"
        case host
        case facebookAppID = "facebook_app_id"
        case device
        case connect
    }
}

// MARK: - GraphQL

extension HotMessAPI {
    /// The GraphQL documents, with fields aliased to the keys the models decode.
    enum Documents {
        /// `profile` is the venue's profile mixin (see `ListingProfile`).
        static let venueFields = """
        id name distance point photo_url: photoUrl banner_url: bannerUrl \
        profile { address phone facebook { facebook_id: facebookId is_liked: isLiked link } }
        """

        /// `profile` is the person's profile mixin (see `ListingProfile`).
        static let personFields = """
        id name avatar_url: avatarUrl banner_url: bannerUrl \
        profile { facebook { facebook_id: facebookId is_liked: isLiked link } }
        """

        static let friendFields = "id name facebook_id: facebookId presence avatar_url: avatarUrl"

        static let pingJoinFields = "id target_id: targetId user { \(friendFields) }"

        static let pingFields = """
        id note created_at: createdAt expires_at: expiresAt is_mine: isMine joined reach \
        user { \(friendFields) } via { \(friendFields) } \
        targets { id venue { \(venueFields) } event { \(eventFields) } joins { \(pingJoinFields) } } \
        joins { \(pingJoinFields) }
        """

        /// A chat line with everything a rich message and its sender's role
        /// need, aliased to the room frame's keys (see `VenueMessage.Payload`).
        static let messageFields = """
        id message body name user_id: userId avatar_url: avatarUrl sent_at: sentAt \
        role kind title photo_url: photoUrl ends_at: endsAt pinned posted_as_venue: postedAsVenue presence \
        posted_as_person: postedAsPerson person { id } \
        event { id name start_at: startAt } \
        request { id kind title artist singer state }
        """

        /// Enough of a person for a card that links to them.
        static let personSummaryFields = "id name avatar_url: avatarUrl"

        /// An act on a venue's lineup (see `Appearance`): its people for a
        /// duet, and its timing for one on in the show's order.
        static let appearanceFields = """
        id kind title role starts_at: startsAt ends_at: endsAt start_timing: startTiming end_timing: endTiming \
        person { \(personSummaryFields) } people { nodes { \(personSummaryFields) } }
        """

        /// Who is on at a venue right now, and what its show has on stage and
        /// up next, under the venue's people mixin (see `VenuePeopleMixin`).
        static let onNowFields = """
        people { on_now: onNow { nodes { \(appearanceFields) } } \
        on_stage: onStage { id kind title } up_next: upNext { \(appearanceFields) } }
        """

        /// Tonight's whole running order at a venue, merged into the people
        /// mixin `onNowFields` selects, for the venue page's lineup.
        static let lineupFields = """
        people { running_order: runningOrder { nodes { \(appearanceFields) state } } }
        """

        static let socialLinkFields = "id handle provider url"

        /// The social links connection, merged into the profile mixin that
        /// `venueFields` and `personFields` already select.
        static let profileSocialLinks = "profile { social_links: socialLinks { nodes { \(socialLinkFields) } } }"

        /// `venue` is the event's venue mixin: the venue under `venue`, null
        /// while it is to be announced (see `EventVenueMixin`).
        static let eventFields = """
        id name start_at: startAt end_at: endAt facebook_id: facebookId \
        banner_url: bannerUrl is_featured: isFeatured rsvp { mine } \
        karaoke { provider provider_name: providerName session_code: sessionCode own_session_code: ownSessionCode join_url: joinUrl } \
        venue { name venue { \(venueFields) } }
        """

        /// `Money` is `{ cents currency }`; `total` is the all-in price.
        static let moneyFields = "cents currency"

        static let coverChargeFields = """
        amount { \(moneyFields) } fee { \(moneyFields) } total { \(moneyFields) } \
        night from until payable payment_mechanisms: paymentMechanisms \
        tiers { id name amount { \(moneyFields) } total { \(moneyFields) } description } \
        coat_check: coatCheck { amount { \(moneyFields) } fee { \(moneyFields) } total { \(moneyFields) } night payable payment_mechanisms: paymentMechanisms }
        """

        /// `profile` is the buyer: the pass shows their name and avatar.
        static let admissionFields = """
        id status night total { \(moneyFields) } quantity tier kind claim_check_number: claimCheckNumber is_refundable: isRefundable \
        pass_secret: passSecret scan_count: scanCount checked_in_at: checkedInAt \
        profile { id name avatar_url: avatarUrl } \
        venue { id name photo_url: photoUrl } event { id name }
        """

        /// Tonight's cover at a venue and the user's pass for it, under the
        /// venue's cover mixin inside its tickets mixin (see `TicketsMixin`).
        static let venueCoverFields = """
        tickets { cover { \
        cover_charge: charge { \(coverChargeFields) } \
        viewer_admission: viewerAdmission { \(admissionFields) } \
        viewer_coat_check: viewerCoatCheck { \(admissionFields) } \
        } }
        """

        /// How many of a locale's upcoming events Now shows (`Now.localeEventLimit`,
        /// as the document's literal so it can be checked against the schema).
        static let localeEventLimit = "5"

        static let venueFences = """
        query VenueFences($near: CoordinatesInput!) {
          venues { list(near: $near) { nodes { id point distance_tolerance: distanceTolerance } } }
        }
        """

        static let reportLocation = """
        mutation ReportLocation($position: CoordinatesInput!) {
          reportLocation(input: { position: $position }) {
            event { \(eventFields) }
            venue {
              \(venueFields)
              chat { recent_messages: recentMessages(limit: 3) { nodes { \(messageFields) } } }
              \(venueCoverFields)
              \(onNowFields)
              events { upcoming { nodes { \(eventFields) } } }
              friends { list { nodes { \(friendFields) } } }
            }
            nearby_venues: nearbyVenues { \(venueFields) }
            locale {
              id name banner_url: bannerUrl
              chat { open recent_messages: recentMessages(limit: 3) { nodes { \(messageFields) } } }
              events { upcoming(first: \(localeEventLimit)) { nodes { \(eventFields) } } }
              friends {
                list { nodes { \(friendFields) } }
                venues {
                  nodes {
                    venue { \(venueFields) }
                    friend_count: friendCount
                    friends { \(friendFields) }
                  }
                }
              }
            }
            audience {
              me {
                ping {
                  my_ping: myPing { \(pingFields) }
                  friend_pings: friendPings { \(pingFields) }
                }
              }
            }
          }
        }
        """

        static let venue = """
        query Venue($id: ID!) {
          venues { venue(id: $id) {
            \(venueFields)
            events { upcoming { nodes { \(eventFields) } } }
            friends { list { nodes { \(friendFields) } } }
            \(profileSocialLinks)
            chat { open recent_messages: recentMessages(limit: 3) { nodes { \(messageFields) } } }
            \(venueCoverFields)
            \(onNowFields)
            \(lineupFields)
            ping { friend_pings: friendPings { \(pingFields) } }
          } }
        }
        """

        static let localeEvents = """
        query LocaleEvents($id: ID!) {
          locale(id: $id) { events { upcoming { nodes { \(eventFields) } } } }
        }
        """

        static let event = """
        query Event($id: ID!) {
          events { event(id: $id) {
            \(eventFields) people { hosts { nodes { \(personFields) } } lineup { nodes { \(personFields) } } }
            ping { friend_pings: friendPings { \(pingFields) } }
            tickets { cover { cover_charge: charge { \(coverChargeFields) } } }
            venue_cover: venue { venue { \(venueCoverFields) } }
          } }
        }
        """

        static let buyCover = """
        mutation BuyCover($venueId: ID!, $quantity: Int, $tier: String) {
          buyCover(input: { venueId: $venueId, quantity: $quantity, tier: $tier }) {
            admission { \(admissionFields) }
            payment_intent_client_secret: paymentIntentClientSecret
            publishable_key: publishableKey
            stripe_account_id: stripeAccountId
            provider
            square_application_id: squareApplicationId
            square_location_id: squareLocationId
          }
        }
        """

        static let buyCoatCheck = """
        mutation BuyCoatCheck($venueId: ID!, $quantity: Int) {
          buyCoatCheck(input: { venueId: $venueId, quantity: $quantity }) {
            admission { \(admissionFields) }
            payment_intent_client_secret: paymentIntentClientSecret
            publishable_key: publishableKey
            stripe_account_id: stripeAccountId
            provider
            square_application_id: squareApplicationId
            square_location_id: squareLocationId
          }
        }
        """

        static let payCover = """
        mutation PayCover($admissionId: ID!, $sourceId: String!, $verificationToken: String) {
          payCover(input: { admissionId: $admissionId, sourceId: $sourceId, verificationToken: $verificationToken }) {
            admission { \(admissionFields) }
          }
        }
        """

        static let confirmCover = """
        mutation ConfirmCover($admissionId: ID!) {
          confirmCover(input: { admissionId: $admissionId }) { admission { \(admissionFields) } }
        }
        """

        static let refundAdmission = """
        mutation RefundAdmission($admissionId: ID!) {
          refundAdmission(input: { admissionId: $admissionId }) { admission { \(admissionFields) } }
        }
        """

        static let admissions = """
        query Admissions {
          me { cover { admissions { nodes { \(admissionFields) } } } }
        }
        """

        static let person = """
        query Person($id: ID!) {
          people { person(id: $id) {
            \(personFields)
            events { upcoming { nodes { \(eventFields) } } }
            \(profileSocialLinks)
            members { \(personSummaryFields) }
            groups { \(personSummaryFields) }
            music { tracks { nodes { id title provider provider_url: providerUrl waveform_url: waveformUrl artwork_url: artworkUrl } } }
          } }
        }
        """

        static let pings = """
        query Pings {
          me {
            ping {
              my_ping: myPing { \(pingFields) }
              friend_pings: friendPings { \(pingFields) }
            }
          }
        }
        """

        static let sendPing = """
        mutation SendPing($venueIds: [ID!], $eventIds: [ID!], $note: String, $localeId: ID, $reach: PingReach) {
          sendPing(input: { venueIds: $venueIds, eventIds: $eventIds, note: $note, localeId: $localeId, reach: $reach }) {
            ping { \(pingFields) }
          }
        }
        """

        static let joinPing = """
        mutation JoinPing($pingId: ID!, $targetId: ID) {
          joinPing(input: { pingId: $pingId, targetId: $targetId }) { ping { \(pingFields) } }
        }
        """

        static let leavePing = """
        mutation LeavePing($pingId: ID!) {
          leavePing(input: { pingId: $pingId }) { ping { \(pingFields) } }
        }
        """

        static let endPing = """
        mutation EndPing {
          endPing(input: {}) { ended }
        }
        """

        static let pairUpMatchFields = """
        id accepted partnerAccepted bonus metAt endReason topic { key text }
        partner { id name avatarUrl lookFor }
        """

        static let pairUpStateFields = """
        status lookFor metCount match { \(pairUpMatchFields) } bonus { \(pairUpMatchFields) }
        """

        static let venuePairUp = """
        query VenuePairUp($id: ID!) {
          venues { venue(id: $id) { pairUp { here mine { \(pairUpStateFields) } } } }
        }
        """

        static let joinPairUp = """
        mutation JoinPairUp($venueId: ID!, $lookFor: String) {
          joinPairUp(input: { venueId: $venueId, lookFor: $lookFor }) { pairUp { \(pairUpStateFields) } }
        }
        """

        static let acceptPairUp = """
        mutation AcceptPairUp($matchId: ID!) {
          acceptPairUp(input: { matchId: $matchId }) { pairUp { \(pairUpStateFields) } }
        }
        """

        static let skipPairUp = """
        mutation SkipPairUp($matchId: ID!, $what: PairUpSkip!) {
          skipPairUp(input: { matchId: $matchId, what: $what }) { pairUp { \(pairUpStateFields) } }
        }
        """

        static let cancelPairUp = """
        mutation CancelPairUp($matchId: ID!) {
          cancelPairUp(input: { matchId: $matchId }) { pairUp { \(pairUpStateFields) } }
        }
        """

        static let leavePairUp = """
        mutation LeavePairUp($venueId: ID!) {
          leavePairUp(input: { venueId: $venueId }) { pairUp { \(pairUpStateFields) } }
        }
        """

        static let showPairUpCode = """
        mutation ShowPairUpCode($matchId: ID!) {
          showPairUpCode(input: { matchId: $matchId }) { code }
        }
        """

        static let scanPairUpCode = """
        mutation ScanPairUpCode($venueId: ID!, $code: String!) {
          scanPairUpCode(input: { venueId: $venueId, code: $code }) {
            outcome match { \(pairUpMatchFields) } pairUp { \(pairUpStateFields) }
          }
        }
        """

        static let me = """
        query Me {
          me { self { id name first_name: firstName last_name: lastName avatar_url: avatarUrl photo { cdn_url: cdnUrl } } }
        }
        """

        static let blockedUserFields = "id name avatar_url: avatarUrl"

        static let safety = """
        query Safety {
          me {
            terms_accepted_at: termsAcceptedAt blocked_users: blockedUsers { \(blockedUserFields) }
            can_pretend_location: canPretendLocation
            self { has_facebook: hasFacebook }
          }
        }
        """

        static let blockUser = """
        mutation BlockUser($userId: ID!) {
          blockUser(input: { userId: $userId }) { blocked_users: blockedUsers { \(blockedUserFields) } }
        }
        """

        static let unblockUser = """
        mutation UnblockUser($userId: ID!) {
          unblockUser(input: { userId: $userId }) { blocked_users: blockedUsers { \(blockedUserFields) } }
        }
        """

        /// A chat line as a room delivers it: `messageFields` without
        /// `presence`, which in a room comes from the event's `senderPresence`.
        static let roomMessageFields = """
        id message body name user_id: userId avatar_url: avatarUrl sent_at: sentAt \
        role kind title photo_url: photoUrl ends_at: endsAt pinned posted_as_venue: postedAsVenue \
        posted_as_person: postedAsPerson person { id } \
        event { id name start_at: startAt } \
        request { id kind title artist singer state }
        """

        static let sendMyChatMessage = """
        mutation SendMyChatMessage($input: ChatMessageSendOwnInput!) {
          sendMyChatMessage(input: $input) { message { \(roomMessageFields) } }
        }
        """

        static let reportChatMessage = """
        mutation ReportChatMessage($messageId: ID!, $reason: String, $block: Boolean) {
          reportChatMessage(input: { messageId: $messageId, reason: $reason, block: $block }) { reported blocked }
        }
        """

        static let reportContent = """
        mutation ReportContent($targetType: ReportTarget!, $targetId: ID!, $reason: String, $block: Boolean) {
          reportContent(input: { targetType: $targetType, targetId: $targetId, reason: $reason, block: $block }) { reported blocked }
        }
        """

        static let removeMyChatMessage = """
        mutation RemoveMyChatMessage($messageId: ID!) {
          removeMyChatMessage(input: { messageId: $messageId }) { deletedId }
        }
        """

        static let acceptTerms = """
        mutation AcceptTerms {
          acceptTerms(input: {}) { terms_accepted_at: termsAcceptedAt }
        }
        """

        /// Its own query, not part of `safety`, so the rest of the user's
        /// state still loads from a server without the setting.
        static let recentChatPush = """
        query RecentChatPush {
          me { recent_chat_push: recentChatPush }
        }
        """

        static let setRecentChatPush = """
        mutation SetRecentChatPush($enabled: Boolean!) {
          setRecentChatPush(input: { enabled: $enabled }) { recent_chat_push: recentChatPush }
        }
        """

        static let deleteAccount = """
        mutation DeleteAccount($confirm: Boolean!) {
          deleteAccount(input: { confirm: $confirm }) { deleted }
        }
        """
    }
}

struct ReportLocationResponse: Decodable, Sendable {
    let reportLocation: Now
}

/// `venues { list(near:) { nodes } }` on the root, the audience.
struct VenueFencesResponse: Decodable, Sendable {
    let venues: [VenueFence]

    private enum CodingKeys: String, CodingKey { case venues, list, nodes }

    /// A venue whose location has no point can't be watched; it's skipped
    /// rather than failing the rest.
    private struct Entry: Decodable {
        let fence: VenueFence?
        init(from decoder: any Decoder) throws { fence = try? VenueFence(from: decoder) }
    }

    init(from decoder: any Decoder) throws {
        let list = try decoder.container(keyedBy: CodingKeys.self)
            .nestedContainer(keyedBy: CodingKeys.self, forKey: .venues)
            .nestedContainer(keyedBy: CodingKeys.self, forKey: .list)
        venues = try list.decode([Entry].self, forKey: .nodes).compactMap(\.fence)
    }
}

/// `people { person(id:) }`.
struct PersonResponse: Decodable, Sendable {
    struct People: Decodable, Sendable { let person: PersonDetail? }

    let people: People?

    var person: PersonDetail? { people?.person }
}

/// A venue and its events, which GraphQL returns as one object.
struct VenueWithEvents: Decodable, Sendable {
    let venue: Venue
    let events: [Event]
    let friends: [Friend]
    let socialLinks: [SocialLink]
    let chatOpen: Bool
    /// The last few lines of the chat room, oldest first; empty unless the
    /// viewer is at the venue or an admin.
    let recentMessages: [VenueMessage]
    /// Tonight's cover, or nil when there's none.
    let coverCharge: CoverCharge?
    /// The user's cover tonight, paid or being paid.
    let viewerAdmission: Admission?
    /// The user's coat check tonight, paid or being paid.
    let viewerCoatCheck: Admission?
    /// Who is on there right now, by start.
    let onNow: OnNow
    let friendPings: [Ping]

    private enum CodingKeys: String, CodingKey {
        case events, friends, tickets, profile, ping, chat, people
    }

    init(from decoder: any Decoder) throws {
        venue = try Venue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The tickets mixin (holding the cover mixin) is left out where the
        // audience has neither module, which reads as no cover. A missing
        // events or friends mixin reads as none.
        events = try container.decodeIfPresent(UpcomingEventsMixin.self, forKey: .events)?.upcoming ?? []
        friends = try container.decodeIfPresent(FriendsMixin.self, forKey: .friends)?.list ?? []
        // Links come through the profile mixin; missing reads as none.
        socialLinks = try container.decodeIfPresent(ListingProfile.self, forKey: .profile)?.socialLinks ?? []
        // Whether the user can join the room, and its last lines, come
        // through the chat mixin; missing reads as closed.
        let chat = try container.decodeIfPresent(ChatMixin.self, forKey: .chat)
        chatOpen = chat?.open ?? false
        recentMessages = chat?.recentMessages ?? []
        let cover = try container.decodeIfPresent(TicketsMixin.self, forKey: .tickets)?.cover
        coverCharge = cover?.coverCharge
        viewerAdmission = cover?.viewerAdmission
        viewerCoatCheck = cover?.viewerCoatCheck
        // Who's on comes through the people mixin; missing reads as no one.
        onNow = (try? container.decodeIfPresent(VenuePeopleMixin.self, forKey: .people))?.onNow ?? []
        // Friends' Pings come through the ping mixin; missing reads as none.
        friendPings = try container.decodeIfPresent(PingsResponse.self, forKey: .ping)?.friendPings ?? []
    }
}

/// `venues { venue(id:) }`.
struct VenueResponse: Decodable, Sendable {
    struct Venues: Decodable, Sendable { let venue: VenueWithEvents? }

    let venues: Venues?

    var venue: VenueWithEvents? { venues?.venue }
}

struct LocaleEventsResponse: Decodable, Sendable {
    struct Locale: Decodable, Sendable {
        /// The locale's upcoming events; empty when the mixin is missing.
        var events: [Event] { eventsMixin?.upcoming ?? [] }

        private let eventsMixin: UpcomingEventsMixin?

        private enum CodingKeys: String, CodingKey { case eventsMixin = "events" }
    }

    let locale: Locale?
}

/// `events { event(id:) }`.
struct EventResponse: Decodable, Sendable {
    struct Events: Decodable, Sendable { let event: EventDetail? }

    let events: Events?

    var event: EventDetail? { events?.event }
}

struct BuyCoverResponse: Decodable, Sendable {
    let buyCover: CoverPurchase
}

struct BuyCoatCheckResponse: Decodable, Sendable {
    let buyCoatCheck: CoverPurchase
}

struct AdmissionPayload: Decodable, Sendable {
    let admission: Admission
}

struct ConfirmCoverResponse: Decodable, Sendable {
    let confirmCover: AdmissionPayload
}

struct PayCoverResponse: Decodable, Sendable {
    let payCover: AdmissionPayload
}

struct RefundAdmissionResponse: Decodable, Sendable {
    let refundAdmission: AdmissionPayload
}

/// `cover { admissions { nodes } }`; no cover mixin reads as no passes.
/// `me { cover { admissions } }`: the viewer's passes are theirs, under `me`.
struct AdmissionsResponse: Decodable, Sendable {
    struct Nodes: Decodable, Sendable { let nodes: [Admission] }
    struct Cover: Decodable, Sendable { let admissions: Nodes }
    struct Me: Decodable, Sendable { let cover: Cover? }

    let me: Me?

    var admissions: [Admission] { me?.cover?.admissions.nodes ?? [] }
}

/// `ping { my_ping friend_pings }` on the root, the audience; no ping mixin reads as none.
/// `me { ping }`: the viewer's own ping and their friends', under `me`.
struct AudiencePingsResponse: Decodable, Sendable {
    struct Me: Decodable, Sendable { let ping: PingsResponse? }

    let me: Me?

    var pings: PingsResponse { me?.ping ?? PingsResponse() }
}

struct PingsResponse: Decodable, Sendable {
    let myPing: Ping?
    let friendPings: [Ping]

    private enum CodingKeys: String, CodingKey {
        case myPing = "my_ping"
        case friendPings = "friend_pings"
    }

    init(myPing: Ping? = nil, friendPings: [Ping] = []) {
        self.myPing = myPing
        self.friendPings = friendPings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        myPing = try container.decodeIfPresent(Ping.self, forKey: .myPing)
        friendPings = try container.decodeIfPresent([Ping].self, forKey: .friendPings) ?? []
    }
}

struct PingPayload: Decodable, Sendable {
    let ping: Ping
}

struct SendPingResponse: Decodable, Sendable { let sendPing: PingPayload }
struct JoinPingResponse: Decodable, Sendable { let joinPing: PingPayload }
struct LeavePingResponse: Decodable, Sendable { let leavePing: PingPayload }

struct EndPingResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let ended: Bool }
    let endPing: Payload
}

struct MeResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        struct Photo: Decodable, Sendable {
            let cdnURL: URL?

            private enum CodingKeys: String, CodingKey { case cdnURL = "cdn_url" }
        }

        let id: String
        let name: String?
        let firstName: String?
        let lastName: String?
        let photo: Photo?

        private enum CodingKeys: String, CodingKey {
            case id, name, photo
            case firstName = "first_name"
            case lastName = "last_name"
        }

        var user: User? {
            let name = self.name ?? [firstName, lastName].compactMap(\.self).joined(separator: " ")
            guard var user = User(id: id, name: name) else { return nil }
            user.avatarURL = photo?.cdnURL
            return user
        }
    }

    /// `me` is the viewer's state; `self`, their own profile.
    struct State: Decodable, Sendable {
        let profile: Payload?

        private enum CodingKeys: String, CodingKey { case profile = "self" }
    }

    let me: State?
}

struct SafetyResponse: Decodable, Sendable {
    let me: SafetyState?
}

struct BlockedUsersPayload: Decodable, Sendable {
    let blockedUsers: [BlockedUser]

    private enum CodingKeys: String, CodingKey {
        case blockedUsers = "blocked_users"
    }
}

struct BlockUserResponse: Decodable, Sendable { let blockUser: BlockedUsersPayload }
struct UnblockUserResponse: Decodable, Sendable { let unblockUser: BlockedUsersPayload }

struct ReportChatMessageResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let reported: Bool }
    let reportChatMessage: Payload
}

struct ReportContentResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let reported: Bool
        let blocked: Bool
    }

    let reportContent: Payload
}

struct SendMyChatMessageResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let message: VenueMessage.Payload }
    let sendMyChatMessage: Payload
}

struct RemoveMyChatMessageResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let deletedId: String }
    let removeMyChatMessage: Payload
}

struct AcceptTermsResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let termsAcceptedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case termsAcceptedAt = "terms_accepted_at"
        }
    }

    let acceptTerms: Payload
}

/// `me { recentChatPush }`, and `setRecentChatPush`'s payload.
struct RecentChatPushResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let recentChatPush: Bool

        private enum CodingKeys: String, CodingKey {
            case recentChatPush = "recent_chat_push"
        }
    }

    let me: Payload?
}

struct SetRecentChatPushResponse: Decodable, Sendable {
    let setRecentChatPush: RecentChatPushResponse.Payload
}

struct DeleteAccountResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let deleted: Bool }
    let deleteAccount: Payload
}

extension Coordinates {
    /// The position as the SDK's `Coordinate`, without the beacon.
    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    /// The position as the GraphQL `CoordinatesInput`, with the beacon when
    /// there is one (the SDK leaves a zero beacon out).
    var graphQLInput: GraphQLValue {
        coordinate.coordinatesInput(beaconMajor: beaconMajor, beaconMinor: beaconMinor)
    }
}

extension RSVP {
    var state: RSVPState {
        switch self {
        case .attending: .attending
        case .maybe: .maybe
        case .declined: .declined
        case .unsure: .unsure
        }
    }
}

extension Data {
    /// APNs device tokens are conventionally sent as lowercase hex.
    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Pair me up

/// `venues { venue(id:) { pairUp } }`; a venue without it has no `pairUp`.
struct VenuePairUpResponse: Decodable, Sendable {
    struct Venues: Decodable, Sendable { let venue: Venue? }
    struct Venue: Decodable, Sendable { let pairUp: VenuePairUp? }

    let venues: Venues?
}

struct PairUpPayload: Decodable, Sendable {
    let pairUp: PairUpState?
}

struct ShowPairUpCodeResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { let code: String }

    let showPairUpCode: Payload
}

struct ScanPairUpCodeResponse: Decodable, Sendable {
    let scanPairUpCode: PairUpScan
}
