import AudienceKit
import AuthenticationServices
import Observation
import SwiftUI

@MainActor
@Observable
final class ClipSession {
    let client: AudienceKitClient
    let api: ClipAPI
    let checkout: CoverCheckout
    private(set) var signedIn = false
    private(set) var busy = false
    var tipBusy = false
    var paymentBusy: Bool { checkout.isBusy || tipBusy }
    var error: String?

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
        checkout = CoverCheckout(api: api,
                                 applePayMerchantID: info.object(forInfoDictionaryKey: "ApplePayMerchantID") as? String,
                                 tintColor: .systemBlue,
                                 returnURL: "https://hotmess.social/clip/stripe-redirect")
    }

    func observe() async {
        let events = client.sessionEvents
        signedIn = await client.isSignedIn
        for await event in events {
            guard !Task.isCancelled else { return }
            if !busy { signedIn = await client.isSignedIn }
            if event == .sessionEnded { error = "Please sign in again." }
        }
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
        guard !paymentBusy else { return }
        try? await client.signOut()
        signedIn = false
        checkout.presentedPass = nil
    }
}
