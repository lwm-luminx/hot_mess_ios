import AudienceKit
import AuthenticationServices
import Observation
import SwiftUI

/// The clip's session: the SDK client on the clip keychain, Sign in with
/// Apple, and the record the link points at once a session can read it.
@MainActor
@Observable
final class ClipSession {
    let client: AudienceKitClient
    let api: ClipAPI
    let checkout: ClipCheckout
    let applePayMerchantID: String?
    private(set) var signedIn = false
    private(set) var busy = false
    var error: String?

    /// `details(for:)` for the current link, loaded after sign-in. The share
    /// card is public; prices, tiers and tip presets need a session.
    private(set) var details: ClipDetails?
    private(set) var detailsError: String?

    init() {
        let info = Bundle.main
        let base = URL(string: info.object(forInfoDictionaryKey: "ClipAPIBase") as? String ?? "")!
        let host = info.object(forInfoDictionaryKey: "ClipAudienceHost") as? String
        let environment = (info.object(forInfoDictionaryKey: "AudienceKitEnvironment") as? String)
            .flatMap(AudienceKitEnvironment.init(rawValue:)) ?? .production
        let client = AudienceKitClient(
            configuration: AudienceKitConfiguration(baseURL: base, host: host, environment: environment),
            credentialStore: HotMessAuthentication.clipStore
        )
        self.client = client
        api = ClipAPI(client: client)
        let merchant = (info.object(forInfoDictionaryKey: "ApplePayMerchantID") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        applePayMerchantID = merchant
        checkout = ClipCheckout(api: api, merchantID: merchant)
    }

    func observe() async {
        let events = client.sessionEvents
        signedIn = await client.isSignedIn
        for await event in events {
            guard !Task.isCancelled else { return }
            if !busy { signedIn = await client.isSignedIn }
            if event == .sessionEnded {
                details = nil
                error = "Please sign in again."
            }
        }
    }

    /// The venue, event or performer behind `link`, for a signed-in session.
    func loadDetails(for link: ClipLink) async {
        guard signedIn, link.kind != "pings" else { return }
        detailsError = nil
        do {
            let loaded = try await api.details(for: link)
            try Task.checkCancellation()
            details = loaded
        } catch {
            guard !Task.isCancelled else { return }
            detailsError = error.localizedDescription
        }
    }

    func clearDetails() {
        details = nil
        detailsError = nil
    }

    func signIn(_ result: Result<ASAuthorization, any Error>) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let authorization = try result.get()
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identity = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
            else { throw ClipError.missingIdentity }
            // IDFV is unavailable in App Clips. This random installation identifier
            // describes a session device; it is not evidence of trust or ban history.
            let defaults = UserDefaults.standard
            let identifier = defaults.string(forKey: "ClipInstallationID") ?? UUID().uuidString
            defaults.set(identifier, forKey: "ClipInstallationID")
            let request = AppleSignInRequest(
                identityToken: identity,
                authorizationCode: apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                firstName: apple.fullName?.givenName, lastName: apple.fullName?.familyName,
                host: client.configuration.host,
                device: DeviceDescription(identifier: identifier, model: UIDevice.current.model,
                    version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
            )
            let data = try await client.data(for: APIRequest(method: "POST", path: "/v1/token/apple",
                body: try JSONEncoder().encode(request), authenticated: false))
            try await client.adopt(credential: JSONDecoder().decode(Credential.self, from: data))
            _ = try await client.graphQL(Self.acceptTerms, as: TermsResponse.self)
            signedIn = true
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled {
                try? await client.signOut()
                signedIn = false
                self.error = error.localizedDescription
            }
        }
    }

    private struct TermsResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let termsAcceptedAt: String? }
        let acceptTerms: Payload
    }
    private static let acceptTerms = """
    mutation ClipAcceptTerms { acceptTerms(input: {}) { termsAcceptedAt } }
    """

    func signOut() async {
        guard !checkout.busy else { return }
        try? await client.signOut()
        signedIn = false
        details = nil
    }
}
