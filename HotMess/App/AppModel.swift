//
//  AppModel.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation
import SwiftUI
import os

/// The app's composition root: it builds the services once and holds the
/// navigation state the rest of the UI reads.
@MainActor
@Observable
final class AppModel {
    let configuration: AppConfiguration
    let api: HotMessAPI
    let audienceKit: AudienceKitClient
    let session: SessionStore
    /// The audience's look, from AudienceKit branding.
    let brand: BrandStore
    let location: LocationProvider
    /// Paying cover and showing passes, over whichever tab asked.
    let checkout: CoverCheckout
    /// Friends seen so far, so chat can show them by their full name.
    let friends = FriendDirectory()
    /// Who the user blocked, and whether they've agreed to the terms.
    let safety: SafetyStore
    /// The venues and talent the user manages, so Me offers Velvet or Backstage.
    let listings: ListingsStore

    /// The user's tribes, and whether the API has tribes.
    let tribes: TribeStore
    /// The user's notifications while the app is in front, shown in the app.
    let notifications: NotificationStream
    /// The app's one realtime connection: every GraphQL subscription (the
    /// notifications above, the chat room on screen) rides this socket. It's
    /// open while any of them runs, which is while the app is in front and
    /// signed in, and closes once they've all ended.
    let cable: AudienceCable
    /// The update prompts (TestFlight and App Store), from the API's release
    /// config and StoreKit's install environment. RootView presents them.
    let updates: AudienceUpdates
    /// Which promoted cards the viewer turned off (on the device only), and
    /// the reports of the ones they saw.
    let cards: CardSettings

    var selectedTab: AppTab = .now

    /// The Get help sheet over every tab: from a venue, or from a push about
    /// one of the user's safety alerts.
    var helpPresentation: HelpPresentation?

    /// One navigation path per tab, so a deep link can push onto the right
    /// stack without disturbing the others.
    var nowPath: [AppRoute] = []
    var eventsPath: [AppRoute] = []
    var venuesPath: [AppRoute] = []
    var peoplePath: [AppRoute] = []

    /// Bumped whenever Pings change somewhere other than Now (a push, the
    /// send sheet on a venue), so Now reloads.
    private(set) var pingRevision = 0

    /// A super admin signed in here (the API's `canSwitchServer`).
    private(set) var serverSwitchAllowed: Bool

    /// Whether testing aids such as "Pretend I'm here" show: test builds, and
    /// the designated App Review account while App Review is on (the API's
    /// `canPretendLocation`). Never for an ordinary App Store user. The
    /// launch-argument and defaults overrides exist only in builds with
    /// `TEST_HOOKS` (Debug and Staging, for the UI tests and screenshots).
    var isReviewMode: Bool {
        if configuration.isTestBuild || safety.canPretendLocation { return true }
        #if TEST_HOOKS
        return ProcessInfo.processInfo.arguments.contains("-HotMessReviewMode")
            || UserDefaults.standard.bool(forKey: "HotMessReviewMode")
        #else
        return false
        #endif
    }

    /// The App Store listing screenshots sign in with a review account but
    /// shouldn't show its testing aids, so `-HotMessHideReviewAids` hides
    /// them. It only ever takes something away, so it works in every build.
    var showsReviewAids: Bool {
        isReviewMode && !ProcessInfo.processInfo.arguments.contains("-HotMessHideReviewAids")
    }

    private static let promptedFacebookOnPingKey = "hasPromptedFacebookOnPing"
    private static let promptedFacebookOnChatKey = "hasPromptedFacebookOnChat"

    /// Whether the user has been told that connecting Facebook is required to see friends when sending a ping.
    var hasPromptedFacebookOnPing: Bool {
        get { UserDefaults.standard.bool(forKey: Self.promptedFacebookOnPingKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.promptedFacebookOnPingKey) }
    }

    /// Whether the user has been told that connecting Facebook is required to see friends in chat.
    var hasPromptedFacebookOnChat: Bool {
        get { UserDefaults.standard.bool(forKey: Self.promptedFacebookOnChatKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.promptedFacebookOnChatKey) }
    }

    static let shared = AppModel()

    init(configuration: AppConfiguration = AppConfiguration()) {
        self.configuration = configuration
        serverSwitchAllowed = configuration.canSwitchServer && !configuration.isBetaInstall

        let audienceKit = AudienceKitClient(
            configuration: configuration.audienceKit,
            credentialStore: SessionStore.credentialStore,
            session: .hotMess
        )
        self.audienceKit = audienceKit

        let api = HotMessAPI(client: APIClient(audienceKit: audienceKit))
        self.api = api

        updates = AudienceUpdates.configure(session: audienceKit, appName: String(localized: "Hot Mess"))

        brand = BrandStore(audienceKit: audienceKit)
        cards = CardSettings(audienceKit: audienceKit)
        session = SessionStore(api: api, audienceKit: audienceKit, brand: brand, configuration: configuration)
        location = LocationProvider(api: api, configuration: configuration)
        checkout = CoverCheckout(api: api, applePayMerchantID: configuration.applePayMerchantID, tintColor: UIColor(Color.hotMessAccent))
        safety = SafetyStore(api: api)
        listings = ListingsStore(api: api)
        tribes = TribeStore(api: api)
        // A socket the server refuses as unauthorized signs out the way an
        // HTTP 401 does. The cable reads the credential from the SDK's store
        // whenever it (re)opens, so a new sign-in is picked up, and signs the
        // handshake the way every call is signed (Bearer, API version).
        let credentialStore = SessionStore.credentialStore
        let cable = AudienceCable(
            configuration: configuration.audienceKit,
            url: GraphQLCable.url(for: configuration),
            credential: { try? credentialStore.load() },
            unauthorized: { [session] token in
                guard let token else { return }
                Task { @MainActor in await session.sessionRejected(token: token) }
            },
            openSocket: { request in
                WebSocketTaskSocket(URLSession.realtime.webSocketTask(with: request))
            }
        )
        self.cable = cable
        notifications = NotificationStream(
            cable: cable,
            audienceID: { [configuration, api] in
                if let audienceID = configuration.audienceID { return audienceID }
                return try? await api.audienceID()
            },
            isSignedIn: { [session] in session.isSignedIn }
        )
        notifications.onReceive = { [weak self] notification in
            if notification.ping != nil { self?.pingsChanged() }
        }

        // The API ended the session (a 401, or a socket refused as
        // unauthorized): forget the user's things as signing out does.
        session.onSessionEnded = { [weak self] in self?.forgetUser() }
    }

    func start() async {
        ErrorReporter.shared.start(audienceKit: audienceKit, configuration: configuration)

        // An App Store install that replaced a beta drops the beta's server
        // choice; a session next issued can't be used on production.
        if configuration.hasStaleServerChoice {
            UserDefaults.standard.removeObject(forKey: AppConfiguration.APIServer.defaultsKey)
            if !AppConfiguration.APIServer.production.takes(try? SessionStore.credentialStore.load()) { signOut() }
        }

        // UI tests start from the login screen.
        if ProcessInfo.processInfo.arguments.contains("-HotMessUITestSignedOut") {
            signOut()
        } else if Self.isSafetyDemo {
            session.presentDemoLogin()
        } else {
            await session.start()
        }

        // Branding is public, so the login screen can wear the audience's colours.
        Task { await brand.load() }

        if session.isSignedIn {
            location.start()
            // Re-register every launch: APNs tokens change, and a restored
            // session never went through sign-in's registration.
            Task { await PushNotifications.requestAuthorizationAndRegister() }
        }
    }

    /// The safety walkthrough's `-HotMessSafetyDemo`: start on the login
    /// screen even with a stored session. Only in builds with test hooks.
    static var isSafetyDemo: Bool {
        #if TEST_HOOKS
        ProcessInfo.processInfo.arguments.contains("-HotMessSafetyDemo")
        #else
        false
        #endif
    }

    /// Signs out and forgets what was loaded for the user.
    func signOut() {
        forgetUser()
        session.signOut()
    }

    /// Points a test build, a beta or a super admin's install at the other
    /// API, then quits: every service holds the configuration it launched
    /// with, and the next launch reads the new choice. The session stays when
    /// the other API takes it (``switchKeepsSession(to:)``): production's on
    /// next. Only a session next issued is signed out going to production.
    func switchAPIServer(to server: AppConfiguration.APIServer) async {
        guard canSwitchServer, server != configuration.apiServer else { return }
        if !switchKeepsSession(to: server) {
            forgetUser()
            await session.signOutAndWait()
        }
        UserDefaults.standard.set(server.rawValue, forKey: AppConfiguration.APIServer.defaultsKey)
        exit(0)
    }

    /// Whether switching to `server` keeps the person signed in.
    func switchKeepsSession(to server: AppConfiguration.APIServer) -> Bool {
        server.takes(try? SessionStore.credentialStore.load())
    }

    /// Whether Me offers the Server picker: test builds and betas, and any
    /// install where an AudienceKit super admin is signed in.
    var canSwitchServer: Bool { configuration.isTestBuild || serverSwitchAllowed }

    /// Asks the API whether the signed-in person is a super admin and
    /// remembers it on this device, so their pick applies from the next
    /// launch. Someone else signing in takes it away again; a pick made
    /// meanwhile then counts as stale (``AppConfiguration/hasStaleServerChoice``).
    func refreshServerSwitch() async {
        guard session.isSignedIn, let allowed = try? await api.canSwitchServer() else { return }
        serverSwitchAllowed = allowed
        UserDefaults.standard.set(allowed, forKey: AppConfiguration.serverSwitchKey)
    }

    /// Puts the beta ribbon on a TestFlight install's icon (Next or Beta, by
    /// server), and takes it off an App Store install that replaced a beta.
    /// iOS only changes icons while the app is active, and says so with an
    /// alert, so this runs on activation and only when the icon is wrong:
    /// a beta's first run and the launch after a server switch.
    func updateAppIcon() {
        let application = UIApplication.shared
        let wanted = configuration.alternateIconName
        guard application.supportsAlternateIcons, application.alternateIconName != wanted else { return }
        application.setAlternateIconName(wanted) { error in
            if let error {
                Log.app.error("Couldn't change the app icon to \(wanted ?? "primary", privacy: .public): \(error)")
            }
        }
    }

    /// Forgets what was loaded for the signed-in user.
    private func forgetUser() {
        friends.forget()
        safety.forget()
        listings.forget()
        tribes.forget()
        notifications.reset()
        location.forget()
        UserDefaults.standard.removeObject(forKey: Self.promptedFacebookOnPingKey)
        UserDefaults.standard.removeObject(forKey: Self.promptedFacebookOnChatKey)
        Task { [cable] in await cable.disconnect() }
    }

    /// Core Location launched the app in the background for a venue geofence
    /// or a significant change. Picking the monitor back up is what delivers
    /// the event, which is then reported with the stored session; nothing
    /// else (branding, the version check, the user) is loaded.
    func startInBackground() async {
        guard location.tracksInBackground, await session.hasStoredSession else { return }
        location.startInBackground()
    }

    /// Deletes the account on the server, then signs out here. The API
    /// erases everything it keeps about the user.
    func deleteAccount() async throws {
        try await api.deleteAccount()
        signOut()
    }

    /// Connects Facebook to an account that signed in with Apple, then
    /// re-reads what depends on it. False when the person cancels.
    func connectFacebook() async throws -> Bool {
        guard try await session.connectFacebook() else { return false }

        friends.forget()
        await safety.load(force: true)
        return true
    }

    func pingsChanged() {
        pingRevision += 1
    }

    /// Goes where a tapped notification leads, whether the system showed it
    /// or the app did: the `url` its payload carries (a universal link such as
    /// `https://hotmess.social/pings/<id>`), never its `kind`. A notification
    /// with no route, or one the app has no screen for, opens Now.
    func open(_ notification: PingNotification) {
        if let url = notification.url, open(url) { return }
        openNow()
    }

    /// "I'm in" on a friend's Ping notification: joins the whole Ping.
    func join(_ notification: PingNotification) async {
        guard let pingID = notification.pingID else { return }

        do {
            _ = try await api.joinPing(pingID)
        } catch {
            Log.app.error("Joining a ping from a notification failed: \(error.localizedDescription, privacy: .public)")
        }
        pingsChanged()
    }

    /// Shows Now from the top, for a tapped Ping notification.
    func openNow() {
        selectedTab = .now
        nowPath = []
        pingsChanged()
    }

    /// Jumps to a route, switching tabs and resetting that tab's stack first —
    /// matching the old `popToRootViewController` then `push` behaviour.
    func open(_ route: AppRoute) {
        selectedTab = route.tab

        switch route.tab {
        case .now: nowPath = [route]
        case .events: eventsPath = [route]
        case .venues: venuesPath = [route]
        case .people: peoplePath = [route]
        case .me: break
        }
    }

    /// Pushes a route onto the tab on screen, for a link in a view that
    /// takes a closure rather than a `NavigationLink`.
    func push(_ route: AppRoute) {
        switch selectedTab {
        case .now: nowPath.append(route)
        case .events: eventsPath.append(route)
        case .venues: venuesPath.append(route)
        case .people: peoplePath.append(route)
        case .me: open(route)
        }
    }

    /// Why a share link didn't open, for the alert over every screen
    /// (signed out too). Its title and message.
    var shareLinkError: ShareLinkProblem?
    @ObservationIgnored private var shareLinkTask: Task<Void, Never>?

    func open(_ url: URL) -> Bool {
        guard let destination = DeepLink.destination(for: url) else { return false }
        shareLinkTask?.cancel()
        let tokens = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "e" } ?? []
        guard tokens.count <= 1 else { shareLinkError = .invalid; return false }
        guard let token = tokens.first?.value, !token.isEmpty else { return open(destination) }
        // A link whose own expiry has passed needs no network.
        if ShareLinkToken.hasExpired(token) {
            linkExpired(destination)
            return true
        }
        // Validate the opaque signed token before routing, including links received
        // before sign-in. Never discard expiry or sender attribution on handoff.
        shareLinkTask = Task {
            do {
                let path = url.scheme == "hotmess" ? "/\(url.host ?? "")\(url.path)" : url.path
                _ = try await audienceKit.data(for: APIRequest(path: "/v1/share", queryItems: [
                    URLQueryItem(name: "host", value: audienceKit.configuration.host),
                    URLQueryItem(name: "path", value: path), URLQueryItem(name: "e", value: token)
                ], authenticated: false))
                try Task.checkCancellation()
                _ = open(destination)
            } catch {
                guard !Task.isCancelled else { return }
                switch ShareLinkProblem.from(error) {
                case .some(.expired): linkExpired(destination)
                case let .some(problem): shareLinkError = problem
                // Offline, or the API failed: open it as an older link
                // would; the screen's own load says if something's wrong.
                case .none: _ = open(destination)
                }
            }
        }
        return true
    }

    /// Says the link has expired, on the tab the person can find it from
    /// instead: Now for a Ping, Venues for anything else.
    private func linkExpired(_ destination: DeepLinkDestination) {
        if case .route(.ping) = destination {
            openNow()
        } else {
            selectedTab = .venues
            venuesPath = []
        }
        shareLinkError = .expired
    }

    private func open(_ destination: DeepLinkDestination?) -> Bool {
        switch destination {
        case let .route(route):
            open(route)
            return true
        case .now:
            openNow()
            return true
        case let .venueChat(id):
            openVenueChat(id)
            return true
        case let .localeChat(id):
            if let locale = location.locale, locale.id == id {
                open(.localeChat(locale))
            } else {
                openNow()
            }
            return true
        case let .safetyAlert(id):
            helpPresentation = .alert(id: id.uuidString.lowercased())
            return true
        case let .shortLink(url):
            // Where the site redirects it, opened as that link would be; a
            // code it doesn't know (or no network) leaves the user on Venues.
            shareLinkTask = Task {
                let target = await ShortLink.target(of: url)
                guard !Task.isCancelled else { return }
                if let target, let next = DeepLink.destination(for: target), next != .shortLink(url) {
                    _ = open(next)
                } else {
                    selectedTab = .venues
                    venuesPath = []
                }
            }
            return true
        case nil:
            return false
        }
    }

    /// Opens the venue, then its chat room on top once the venue loads (the
    /// room's route needs the venue), unless the user has gone elsewhere by
    /// then. If it can't load, the venue screen says so.
    private func openVenueChat(_ venueID: UUID) {
        open(.venue(venueID))

        Task {
            guard let overview = try? await api.venue(venueID),
                  selectedTab == .venues, venuesPath == [.venue(venueID)]
            else { return }
            venuesPath.append(.venueChat(overview.venue))
        }
    }
}

/// Why a share link didn't open.
enum ShareLinkProblem: Equatable, Sendable {
    /// Its time is up, or its signature doesn't hold (the API's 410).
    case expired
    /// It carries more than one `e`.
    case invalid
    /// The API won't open it, with its reason (nothing public at the path).
    case unavailable(String)

    var title: String {
        switch self {
        case .expired: String(localized: "This link has expired")
        case .invalid, .unavailable: String(localized: "Couldn't open this share")
        }
    }

    var message: String {
        switch self {
        case .expired: String(localized: "Ask whoever sent it for a new one, or find the place yourself.")
        case .invalid: String(localized: "This share link is invalid.")
        case let .unavailable(reason): reason
        }
    }

    /// What `/v1/share` failing with `error` means for the link, or `nil`
    /// when it says nothing about the link (offline, or the API failed).
    static func from(_ error: Error) -> ShareLinkProblem? {
        guard let error = error as? AudienceKitError else { return nil }
        if error.status == 410 || error.code == "EXPIRED" { return .expired }
        guard let status = error.status, (400..<500).contains(status) else { return nil }
        return .unavailable(error.message)
    }
}
