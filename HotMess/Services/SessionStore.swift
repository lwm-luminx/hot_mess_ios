//
//  SessionStore.swift
//  HotMess
//

import AudienceKit
import AuthenticationServices
import FacebookCore
import FacebookLogin
import Foundation
import Observation
import os
import UIKit

enum AuthenticationState: Equatable, Sendable {
    /// Still working out whether there is a usable session.
    case restoring
    case signedOut
    case signingIn
    case signedIn
    case failed(String)
}

enum SessionError: Error, LocalizedError {
    case cancelled
    case configurationUnavailable
    /// Facebook's login sheet wouldn't open, usually because something else
    /// was still on screen.
    case facebookSheetUnavailable
    case missingFacebookToken
    case missingAppleToken
    case invalidReviewCode
    case facebook(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            String(localized: "Sign in was cancelled.")
        case .configurationUnavailable:
            String(localized: "Facebook login isn't set up for Hot Mess yet.")
        case .facebookSheetUnavailable:
            String(localized: "Facebook's login didn't open. Please try again.")
        case .missingFacebookToken:
            String(localized: "Facebook didn't return an access token.")
        case .missingAppleToken:
            String(localized: "Apple didn't return a sign-in token.")
        case .invalidReviewCode:
            String(localized: "That App Review code isn't valid. Check the code in the review notes and try again.")
        case let .facebook(reason):
            reason
        }
    }
}

/// Owns authentication: the Facebook handshake, Sign in with Apple, and the
/// signed-in user.
///
/// The app runs Facebook Login; the AudienceKit SDK exchanges the Facebook
/// token for a session, keeps it in the keychain, and reports when the API
/// ends it (sign-out elsewhere, Facebook deauthorization). An account that
/// signed in with Apple has no Facebook until the person connects it, which
/// is what brings their friends.
@MainActor
@Observable
final class SessionStore {
    /// Whether sign-in asks for `email` and `user_friends` (friends who also use
    /// the app at the same venue). Off while Meta's App Review has both pending
    /// on the Hot Mess Consumer app, so the betas ask only for `public_profile`;
    /// until it's back on, everyone's friends list is empty and no email is
    /// stored. Turn it back on once Meta approves them.
    static let asksForReviewedPermissions = false

    /// Permissions requested at sign-in, on the Hot Mess Consumer app.
    static let requestedPermissions = ["public_profile"] + (asksForReviewedPermissions ? ["email", "user_friends"] : [])

    /// Where the session credential lives: the SDK's keychain store, under
    /// the app's own service. A new account name, because the SDK keeps the
    /// credential JSON there (`token userId audienceId role endpoint`), not
    /// the raw token the previous wrapper stored under `token`; an install
    /// from before reads as signed out and signs in again through Facebook.
    static let credentialStore = HotMessAuthentication.mainStore

    private(set) var state: AuthenticationState = .restoring
    private(set) var user: User?
    /// Why the login screen is showing, when the API ended the session rather
    /// than the person signing out. Cleared by the next sign-in.
    private(set) var endedNotice: String?
    /// Called when the API ends the session, so the app forgets what it
    /// loaded for that user (as signing out does).
    @ObservationIgnored var onSessionEnded: (@MainActor () -> Void)?
    private(set) var versionRequirement: VersionInfo?

    private let api: HotMessAPI
    private let audienceKit: AudienceKitClient
    private let brand: BrandStore
    private let configuration: AppConfiguration
    private let loginManager = LoginManager()
    private var sessionMonitor: Task<Void, Never>?

    init(api: HotMessAPI, audienceKit: AudienceKitClient, brand: BrandStore, configuration: AppConfiguration) {
        self.api = api
        self.audienceKit = audienceKit
        self.brand = brand
        self.configuration = configuration

        watchForEndedSessions()
    }

    var isSignedIn: Bool { state == .signedIn }

    /// Whether a session token is stored, before `start()` has checked it.
    /// Enough for a background launch to report the position.
    var hasStoredSession: Bool {
        get async { await audienceKit.isSignedIn }
    }

    var userID: UUID? { user?.id }

    /// The session token. Needed outside the SDK in exactly one place: the
    /// realtime cable's handshake.
    var bearerToken: String? { try? Self.credentialStore.load()?.token }

    /// True when the API refuses to serve this build any more.
    var requiresUpdate: Bool {
        guard let versionRequirement else { return false }
        return !versionRequirement.allows(version: configuration.version)
    }

    // MARK: - Lifecycle

    /// Called once at launch: checks the minimum supported version, then tries
    /// to turn an existing Facebook token into an API session.
    func start() async {
        await refreshVersionRequirement()

        guard !requiresUpdate else {
            state = .signedOut
            return
        }

        await restoreSession()
    }

    func restoreSession() async {
        // A stored session is enough on its own; only fall back to the
        // Facebook handshake when there isn't one.
        if await audienceKit.isSignedIn {
            do {
                user = try await currentUser()
                state = .signedIn
                return
            } catch let error as AudienceKitError where error.isUnauthenticated {
                // The SDK has already dropped the credential.
                endedNotice = Self.endedMessage
            } catch {
                // A network blip shouldn't sign the user out; keep the token
                // and let the screens show their own error state.
                state = .signedIn
                return
            }
        }

        guard let facebookToken = AccessToken.current?.tokenString else {
            state = .signedOut
            return
        }

        await exchange(facebookToken: facebookToken)
    }

    func presentDemoLogin() {
        state = .signedOut
    }

    func signIn() async {
        if AppModel.isSafetyDemo, await hasStoredSession {
            await restoreSession()
            if isSignedIn { return }
        }

        state = .signingIn

        do {
            switch try await facebookSignIn().authorize() {
            case let .accessToken(token):
                await exchange(facebookToken: token)
            case let .code(code, redirectURI):
                await exchange { device in
                    try await self.audienceKit.signIn(facebookCode: code, redirectURI: redirectURI, device: device)
                }
            }
        } catch SessionError.cancelled {
            Log.session.info("Facebook sign-in cancelled")
            state = .signedOut
        } catch {
            Log.session.error("Facebook sign-in failed: \(String(describing: error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Signs in with what the Sign in with Apple button returned. The
    /// credential is read here, so only its strings cross into the request.
    func signInWithApple(_ result: Result<ASAuthorization, any Error>) {
        let credential: ASAuthorizationAppleIDCredential
        switch result {
        case let .success(authorization):
            guard let appleID = authorization.credential as? ASAuthorizationAppleIDCredential else {
                state = .failed(SessionError.missingAppleToken.localizedDescription)
                return
            }
            credential = appleID
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                Log.session.info("Apple sign-in cancelled")
                state = .signedOut
            } else {
                Log.session.error("Apple sign-in failed: \(String(describing: error), privacy: .public)")
                state = .failed(error.localizedDescription)
            }
            return
        }

        guard let data = credential.identityToken, let identityToken = String(data: data, encoding: .utf8) else {
            state = .failed(SessionError.missingAppleToken.localizedDescription)
            return
        }

        // Single-use and short-lived; the API trades it for the refresh
        // token it revokes on account deletion.
        let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        // Apple only gives the name the first time; the API keeps it.
        let firstName = credential.fullName?.givenName
        let lastName = credential.fullName?.familyName
        let host = audienceKit.configuration.host

        state = .signingIn
        Task {
            await exchange { device in
                let request = AppleSignInRequest(identityToken: identityToken, authorizationCode: authorizationCode,
                                                 firstName: firstName, lastName: lastName, host: host, device: device)
                return try await self.adopting(self.api.signInWithApple(request))
            }
        }
    }

    /// The ways the audience lets people sign in, or nil when the API can't
    /// say (an API from before the setting, or no connection): the login
    /// screen then offers what it always has.
    func signInMethods() async -> SignInMethods? {
        try? await api.signInMethods(host: audienceKit.configuration.host)
    }

    /// Whether the login screen offers "Have an App Review code?": only while
    /// the API says App Review sign-in is on. Unreachable reads as off.
    func isReviewSignInEnabled() async -> Bool {
        (try? await api.isReviewSignInEnabled(host: audienceKit.configuration.host)) ?? false
    }

    /// Signs in the designated App Review account with the code from the
    /// review notes, the way Sign in with Apple does: the API mints the
    /// credential and the SDK adopts it.
    func signInWithReviewCode(_ code: String) async {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        let host = audienceKit.configuration.host

        state = .signingIn
        await exchange { device in
            do {
                let request = ReviewSignInRequest(code: code, host: host, device: device)
                return try await self.adopting(self.api.signInWithReviewCode(request))
            } catch APIError.unauthorized {
                throw SessionError.invalidReviewCode
            }
        }
    }

    /// Connects Facebook to an account that signed in with Apple, through
    /// Facebook's login dialog. The session that comes back can be a
    /// different account: when the Facebook profile already had one, that
    /// account takes over the Apple sign-in. False when the person cancels.
    func connectFacebook() async throws -> Bool {
        let result: FacebookSignIn.Result
        do {
            result = try await facebookSignIn().authorize()
        } catch SessionError.cancelled {
            return false
        }

        let request = ConnectFacebookRequest(
            result: result,
            host: audienceKit.configuration.host,
            facebookAppID: audienceKit.configuration.facebookAppID,
            device: DeviceInfo.description(for: configuration)
        )
        let session = try await adopting(api.connectFacebook(request))
        // The credential names the account; `me` has the name and photo.
        if let refreshed = try? await currentUser() {
            user = refreshed
        } else if let switched = User(id: session.userId, name: user?.name), switched.id != user?.id {
            user = switched
        }
        return true
    }

    func signOut() {
        loginManager.logOut()
        AccessToken.current = nil
        user = nil
        state = .signedOut

        // Forgets the credential here first, then revokes it on the API; a
        // failed revocation (offline) still leaves this device signed out.
        Task { try? await audienceKit.signOut() }
    }

    /// Signs out like `signOut()`, but waits for the credential to be
    /// forgotten and revoked, for when the app quits straight after.
    func signOutAndWait() async {
        loginManager.logOut()
        AccessToken.current = nil
        user = nil
        state = .signedOut
        try? await audienceKit.signOut()
    }

    /// Wipes cached defaults and images, leaving credentials alone.
    func resetLocalData() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
    }

    func registerForPushNotifications(deviceToken: Data) async {
        do {
            try await api.registerForPush(
                deviceToken: deviceToken,
                appID: Bundle.main.bundleIdentifier,
                sandbox: configuration.isPushSandbox
            )
        } catch {
            // Push registration is best-effort; a failure must not block the UI.
            Log.session.error("Push registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshUser() async {
        guard isSignedIn else { return }
        if let refreshed = try? await currentUser() { user = refreshed }
    }

    // MARK: - Private

    /// The signed-in user, from the audience's GraphQL `me`, with their
    /// profile photo.
    private func currentUser() async throws -> User? {
        try await api.me()
    }

    /// Hands a credential minted outside the SDK (the app's own REST
    /// sign-ins) to the SDK, which stores it and uses it from now on. The
    /// token is kept as the API sent it; the app never reads inside it.
    private func adopting(_ credential: Credential) async throws -> SignInResult {
        try await audienceKit.adopt(credential: credential)
        return SignInResult(credential: credential)
    }

    private func exchange(facebookToken: String) async {
        await exchange { device in
            try await self.audienceKit.signIn(facebookAccessToken: facebookToken, device: device)
        }
    }

    private func exchange(_ signIn: (DeviceDescription) async throws -> SignInResult) async {
        let device = DeviceInfo.description(for: configuration)

        do {
            let session = try await signIn(device)
            // The credential carries only the user's ID; `me` has their name
            // and photo. Until it answers, the ID alone keeps `userID` right.
            user = User(id: session.userId, name: "")
            endedNotice = nil
            state = .signedIn

            if let refreshed = try? await currentUser() { user = refreshed }

            await PushNotifications.requestAuthorizationAndRegister()
        } catch {
            Log.session.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// `GET /v1/status`: the oldest version the API still serves. Unreachable
    /// reads as no requirement, so an offline launch isn't a hard stop.
    private func refreshVersionRequirement() async {
        versionRequirement = (try? await api.clientRequirement()) ?? nil
    }

    /// Facebook's login dialog for this build's Facebook app or, when the
    /// build names none, the one AudienceKit's branding gives the audience
    /// (the app the API picks when sign-in names no app). A Business-type
    /// app needs the Login for Business configuration from the branding, so
    /// branding is loaded first when it hasn't arrived yet. The configuration
    /// is only used when it belongs to the same app.
    private func facebookSignIn() async throws -> FacebookSignIn {
        if brand.branding == nil { await brand.load() }
        let branding = brand.branding

        guard let appID = configuration.facebookAppID ?? branding?.facebookAppID.flatMap({ $0.isEmpty ? nil : $0 }) else {
            throw SessionError.configurationUnavailable
        }
        let configID = branding?.facebookAppID == appID ? branding?.facebookLoginConfigID : nil
        return FacebookSignIn(appID: appID, configID: configID, permissions: Self.requestedPermissions)
    }

    /// Signs out as soon as the API ends the session, wherever in the app the
    /// rejected call was made.
    private func watchForEndedSessions() {
        let events = audienceKit.sessionEvents

        sessionMonitor = Task { [weak self] in
            for await event in events where event == .sessionEnded {
                guard let self else { return }
                self.handleEndedSession()
            }
        }
    }

    /// A realtime socket's server refused `token` (Action Cable's
    /// `unauthorized` disconnect): the session ends as it does when an HTTP
    /// call gets a 401. Ignored unless `token` is still the stored one, so a
    /// refusal from before a new sign-in, or a second socket's, changes nothing.
    func sessionRejected(token: String) async {
        // The SDK forgets the credential only when `token` is still the
        // stored one, and yields `.sessionEnded` once, which
        // `watchForEndedSessions()` turns into the login screen.
        _ = await audienceKit.sessionRejected(token: token)
    }

    static let endedMessage = String(localized: "Your session has ended. Please sign in again.")

    /// Back to the login screen, once, saying why. Only from a signed-in
    /// state: a refusal of the old token during a new sign-in, or while
    /// `restoreSession()` is working (it handles its own), changes nothing.
    private func handleEndedSession() {
        guard state == .signedIn else { return }

        user = nil
        endedNotice = Self.endedMessage
        state = .signedOut
        onSessionEnded?()
    }
}
