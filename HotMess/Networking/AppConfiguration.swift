//
//  AppConfiguration.swift
//  HotMess
//

import AudienceKit
import Foundation

/// Values baked into the bundle by the per-environment `.xcconfig` files.
///
/// Every lookup has a fallback: the original read these with
/// `Bundle.main.infoDictionary![…] as! String`, so a missing key took the app
/// down on launch.
struct AppConfiguration: Sendable, Hashable {
    let baseURL: URL
    let beaconUUID: UUID?
    let facebookAppID: String?
    /// Names the Hot Mess audience to the AudienceKit API, for sign-in and
    /// branding. See `AUDIENCE_HOST` in the xcconfig files.
    let audienceHost: String?
    /// The audience's ID, when the build pins it; otherwise the SDK works it
    /// out from the session or the host.
    let audienceID: String?
    /// Staging builds tell the API so, which then signs people in with Hot
    /// Mess's staging Facebook app. See `AUDIENCEKIT_ENVIRONMENT`.
    let environment: AudienceKitEnvironment
    /// The Apple Pay merchant ID cover payments use, from
    /// `APPLE_PAY_MERCHANT_ID`. Without one, the payment sheet leaves Apple
    /// Pay out.
    let applePayMerchantID: String?
    let version: String
    let build: Int
    /// The build's `aps-environment`, `development` or `production`, from
    /// `APNS_ENVIRONMENT`.
    let apnsEnvironment: String?
    /// The New Relic mobile app's token, from `NEW_RELIC_TOKEN`. Without one
    /// the agent doesn't start.
    let newRelicToken: String?
    /// A beta install: a build archived for testers (`HOTMESS_BETA_SERVER`
    /// names its default API) that TestFlight installed. Betas get the server
    /// switch in Me, the testing aids and the ribboned icon. The same build
    /// from the App Store, or any main build, is an ordinary install.
    let isBetaInstall: Bool
    /// Whether the Server picker shows and its choice counts: a beta, or an
    /// install where an AudienceKit super admin signed in (the API's
    /// `canSwitchServer`, remembered under ``serverSwitchKey``), App Store
    /// builds included.
    let canSwitchServer: Bool

    /// Remembers that a super admin signed in here, so the server they picked
    /// applies from launch, before anyone has signed in.
    static let serverSwitchKey = "HotMessServerSwitchAllowed"

    static let defaultBaseURL = URL(string: "https://api.audiencekit.com")!
    static let defaultAudienceHost = "hotmess.admin.audiencekit.com"

    /// The two APIs a test build can talk to. Beta installs start on the
    /// build's `HOTMESS_BETA_SERVER` (`next`) and testers switch in Me; an App
    /// Store install never reads the choice.
    enum APIServer: String, CaseIterable, Sendable {
        case next, production

        /// Where the choice is kept between launches.
        static let defaultsKey = "HotMessAPIServer"

        var baseURL: String {
            switch self {
            case .next: "https://api.next.audiencekit.com"
            case .production: "https://api.audiencekit.com"
            }
        }

        /// The other APIs whose sign-ins this one takes: next takes
        /// production's, so switching there keeps the session.
        var trustedCredentialOrigins: [URL] {
            self == .next ? [URL(string: APIServer.production.baseURL)!] : []
        }

        /// Whether a session `credential` belongs to works on this API: one
        /// it issued, or production's on next (the API's
        /// `TRUSTED_API_ORIGIN`). A session next issued doesn't work on
        /// production, so going back there signs out.
        func takes(_ credential: Credential?) -> Bool {
            guard let host = credential?.origin?.host?.lowercased() else { return true }
            return ([URL(string: baseURL)!] + trustedCredentialOrigins).contains { $0.host?.lowercased() == host }
        }

        var audienceHost: String {
            switch self {
            case .next: "hotmess.admin.next.audiencekit.com"
            case .production: AppConfiguration.defaultAudienceHost
            }
        }

        var title: String {
            switch self {
            case .next: String(localized: "Next")
            case .production: String(localized: "Production")
            }
        }

        /// The server picked in Me, if any.
        static func stored(in defaults: UserDefaults = .standard) -> APIServer? {
            defaults.string(forKey: defaultsKey).flatMap(APIServer.init(rawValue:))
        }
    }

    init(bundle: Bundle = .main) {
        var serverBase = bundle.object(forInfoDictionaryKey: "HotMessServerBase") as? String
        var host = (bundle.object(forInfoDictionaryKey: "AudienceKitHost") as? String).nonEmpty
            ?? Self.defaultAudienceHost
        var env = (bundle.object(forInfoDictionaryKey: "AudienceKitEnvironment") as? String)
            .flatMap(AudienceKitEnvironment.init(rawValue:)) ?? .production

        // One bundle ID serves the App Store and TestFlight, so a beta is told
        // apart at run time. Only the API changes: the Facebook app, the
        // environment and APNs stay the release build's on either server (one
        // database, so the production audience app answers on next too).
        let betaServer = (bundle.object(forInfoDictionaryKey: "HotMessBetaServer") as? String)
            .flatMap(APIServer.init(rawValue:))
        let isBeta = betaServer != nil && Self.isTestFlightInstall
        let canSwitch = isBeta || UserDefaults.standard.bool(forKey: Self.serverSwitchKey)
        if canSwitch, let server = APIServer.stored() ?? betaServer {
            serverBase = server.baseURL
            host = server.audienceHost
        }

        // UI tests and screenshots can point a build at the next preview
        // (`-HotMessUseNextAPI`) or another API (`HOTMESS_API_URL`). Only in
        // builds with test hooks (Debug, Staging); an App Store build always
        // talks to the API its xcconfig names.
        #if TEST_HOOKS
        // A server picked in Me wins over the xcconfig. The environment (and
        // so the Facebook app) stays the build's: both APIs share one
        // database, so the audience's staging app answers on either.
        if let server = APIServer.stored() {
            serverBase = server.baseURL
            host = server.audienceHost
        }

        let processInfo = ProcessInfo.processInfo
        let useNextAPI = processInfo.arguments.contains("-HotMessUseNextAPI") ||
            processInfo.environment["HOTMESS_USE_NEXT_API"] == "1" ||
            processInfo.environment["HOTMESS_API_URL"]?.contains("next") == true ||
            processInfo.environment["AK_API_URL"]?.contains("next") == true

        if useNextAPI {
            serverBase = "https://api.next.audiencekit.com"
            host = "hotmess.admin.next.audiencekit.com"
            env = .staging
        } else if let customURL = processInfo.environment["HOTMESS_API_URL"] ?? processInfo.environment["AK_API_URL"],
                  !customURL.isEmpty {
            serverBase = customURL
        }
        #endif

        baseURL = serverBase.flatMap(URL.init(string:)) ?? Self.defaultBaseURL
        beaconUUID = (bundle.object(forInfoDictionaryKey: "HotMessBeaconID") as? String)
            .flatMap(UUID.init(uuidString:))
        facebookAppID = (bundle.object(forInfoDictionaryKey: "FacebookAppID") as? String).nonEmpty
        audienceHost = host
        audienceID = (bundle.object(forInfoDictionaryKey: "AudienceKitAudienceID") as? String).nonEmpty
        environment = env
        newRelicToken = (bundle.object(forInfoDictionaryKey: "NewRelicToken") as? String).nonEmpty
        applePayMerchantID = (bundle.object(forInfoDictionaryKey: "ApplePayMerchantID") as? String).nonEmpty
            .flatMap { $0.hasPrefix("merchant.") ? $0 : nil }
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap(Int.init) ?? 0
        apnsEnvironment = (bundle.object(forInfoDictionaryKey: "HotMessAPNSEnvironment") as? String).nonEmpty
        isBetaInstall = isBeta
        canSwitchServer = canSwitch
    }

    init(
        baseURL: URL,
        beaconUUID: UUID? = nil,
        facebookAppID: String? = nil,
        audienceHost: String? = defaultAudienceHost,
        audienceID: String? = nil,
        environment: AudienceKitEnvironment = .production,
        applePayMerchantID: String? = nil,
        version: String = "0.0",
        build: Int = 0,
        apnsEnvironment: String? = nil,
        newRelicToken: String? = nil,
        isBetaInstall: Bool = false,
        canSwitchServer: Bool? = nil
    ) {
        self.baseURL = baseURL
        self.beaconUUID = beaconUUID
        self.facebookAppID = facebookAppID
        self.audienceHost = audienceHost
        self.audienceID = audienceID
        self.environment = environment
        self.applePayMerchantID = applePayMerchantID
        self.version = version
        self.build = build
        self.apnsEnvironment = apnsEnvironment
        self.newRelicToken = newRelicToken
        self.isBetaInstall = isBetaInstall
        self.canSwitchServer = canSwitchServer ?? isBetaInstall
    }

    /// Whether TestFlight installed this copy: its receipt is a sandbox one.
    /// Read synchronously because the API is chosen before anything else
    /// runs; the SDK's `InstallSource` (StoreKit's `AppTransaction`) is async.
    /// Xcode installs have a sandbox receipt too, so the check only counts in
    /// builds that set `HOTMESS_BETA_SERVER`, which Xcode Cloud does for
    /// branches other than main. App Review also installs into the sandbox,
    /// and only main builds are submitted, so review never sees a beta.
    static var isTestFlightInstall: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Whether a server picked earlier outlived the right to pick it: the
    /// install is no longer a beta (the App Store version replaced
    /// TestFlight's) and no super admin signed in here, so the choice is
    /// ignored and the session, which the other API issued, has to go.
    var hasStaleServerChoice: Bool {
        #if TEST_HOOKS
        return false
        #else
        return !canSwitchServer && APIServer.stored() != nil
        #endif
    }

    /// The icon this install should wear: the Next icon with its ribbon for a
    /// beta on the next API, the usual one with a Beta ribbon for a beta on
    /// production, and the primary icon for everything else (but a super
    /// admin's install on next).
    var alternateIconName: String? {
        if isBetaInstall { return apiServer == .next ? "AppIconNext" : "AppIconBeta" }
        // A super admin's App Store install keeps its icon on production and
        // wears the Next ribbon on next, so it's never mistaken for the other.
        return canSwitchServer && apiServer == .next ? "AppIconNext" : nil
    }

    /// Whether this build's push tokens belong to APNs' sandbox: the
    /// entitlement says `development`. When the key is missing, debug builds
    /// are taken to be development-signed.
    var isPushSandbox: Bool {
        guard let apnsEnvironment else {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        return apnsEnvironment == "development"
    }

    /// Staging and debug builds and beta installs, which get testing aids
    /// such as pretending to be at a venue and the server switch. App Store
    /// installs never show them.
    var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        return environment != .production || isBetaInstall
        #endif
    }

    /// Which of the two APIs `baseURL` is, for the server switch in Me.
    var apiServer: APIServer {
        baseURL.host?.hasSuffix(".next.audiencekit.com") == true ? .next : .production
    }

    /// How the AudienceKit SDK should reach the Hot Mess audience.
    var audienceKit: AudienceKitConfiguration {
        AudienceKitConfiguration(
            baseURL: baseURL,
            host: audienceHost,
            audienceID: audienceID,
            facebookAppID: facebookAppID,
            environment: environment,
            coverPassPrefix: CoverPass.prefix,
            feeLabel: String(localized: "Service fee"),
            trustedCredentialOrigins: apiServer.trustedCredentialOrigins
        )
    }

    /// Which Facebook app the build is pointed at, for the settings screen.
    var facebookEnvironment: String {
        switch facebookAppID ?? "" {
        case "1168782378316790": String(localized: "production")
        case "713525445368431": String(localized: "AudienceKit service")
        case "1660272792277019": String(localized: "staging")
        case "842337999153841": String(localized: "development")
        default: String(localized: "unknown")
        }
    }

    /// The websocket endpoint, derived from the HTTP base so the two can never
    /// drift apart. `URLSessionWebSocketTask` requires a `ws`/`wss` scheme,
    /// which the old Starscream-based client papered over.
    var realtimeURL: URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme == "http" ? "ws" : "wss"

        let base = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = base + "/connection"

        return components.url
    }
}

private extension Optional where Wrapped == String {
    /// `nil` for a missing or blank Info.plist value (an unset xcconfig variable).
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}
