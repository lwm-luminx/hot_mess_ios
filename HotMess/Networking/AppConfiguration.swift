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

    static let defaultBaseURL = URL(string: "https://api.audiencekit.com")!
    static let defaultAudienceHost = "hotmess.admin.audiencekit.com"

    init(bundle: Bundle = .main) {
        var serverBase = bundle.object(forInfoDictionaryKey: "HotMessServerBase") as? String
        var host = (bundle.object(forInfoDictionaryKey: "AudienceKitHost") as? String).nonEmpty
            ?? Self.defaultAudienceHost
        var env = (bundle.object(forInfoDictionaryKey: "AudienceKitEnvironment") as? String)
            .flatMap(AudienceKitEnvironment.init(rawValue:)) ?? .production

        // UI tests and screenshots can point a build at the next preview
        // (`-HotMessUseNextAPI`) or another API (`HOTMESS_API_URL`). Only in
        // builds with test hooks (Debug, Staging); an App Store build always
        // talks to the API its xcconfig names.
        #if TEST_HOOKS
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
        newRelicToken: String? = nil
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

    /// Staging and debug builds, which get testing aids such as pretending to
    /// be at a venue. App Store builds never show them.
    var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        return environment != .production
        #endif
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
            feeLabel: String(localized: "Service fee")
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
