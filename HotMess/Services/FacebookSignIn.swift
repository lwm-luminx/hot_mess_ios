//
//  FacebookSignIn.swift
//  HotMess
//

import AuthenticationServices
import Foundation
import UIKit

/// Signs in with Facebook's OAuth dialog and returns the code the API exchanges
/// for a Graph access token and a session:
///
/// 1. With the Facebook app installed, the dialog opened there as
///    `fbauth2://authorize`, the switch the SDK makes, carrying `config_id`.
///    The app forwards incoming URLs to ``handle(_:)`` for the redirect.
/// 2. Otherwise the same dialog in a web authentication sheet.
///
/// Not the Facebook SDK's login: without App Tracking Transparency permission
/// it falls back to Limited Login, whose token the API can't use for the Graph
/// API (sign-in and friends), and Hot Mess doesn't ask for tracking.
///
/// The dialog redirects to `fb<app ID>://authorize/`, which has to be listed in
/// the app's Valid OAuth Redirect URIs.
@MainActor
final class FacebookSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Result: Sendable, Equatable {
        /// A Graph access token, which ``ConnectFacebookRequest`` can also carry.
        case accessToken(String)
        /// From the dialog, for the API to exchange.
        case code(String, redirectURI: String)
    }

    private let appID: String
    private let configID: String?
    private let permissions: [String]
    private var session: ASWebAuthenticationSession?

    /// The sign-in waiting for the Facebook app to switch back, if any.
    private static weak var appSwitching: FacebookSignIn?
    private var appSwitch: CheckedContinuation<AppSwitch, Never>?
    private var activeObserver: NSObjectProtocol?

    private enum AppSwitch {
        case redirected(URL)
        case returnedWithoutRedirect
        case notOpened
    }

    /// - Parameters:
    ///   - configID: the Login for Business configuration. Without one the
    ///     dialog asks for `permissions` instead, as a Consumer app expects.
    init(appID: String, configID: String?, permissions: [String]) {
        self.appID = appID
        self.configID = configID
        self.permissions = permissions
    }

    var redirectURI: String { "fb\(appID)://authorize/" }

    /// The dialog URL. `state` ties the redirect to this request.
    func dialogURL(state: String) -> URL {
        var components = URLComponents(string: "https://www.facebook.com/v26.0/dialog/oauth")!
        var items = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
        ]
        if let configID {
            items.append(URLQueryItem(name: "config_id", value: configID))
        } else {
            items.append(URLQueryItem(name: "scope", value: permissions.joined(separator: ",")))
        }
        components.queryItems = items
        return components.url!
    }

    /// The dialog as the Facebook app takes it, with the SDK's app-switch parameters.
    func facebookAppURL(state: String) -> URL {
        var components = URLComponents(url: dialogURL(state: state), resolvingAgainstBaseURL: false)!
        components.scheme = "fbauth2"
        components.host = "authorize"
        components.path = ""
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "ios_fast_app_switch", value: "true"),
            URLQueryItem(name: "sdk", value: "ios"),
            URLQueryItem(name: "display", value: "touch"),
            URLQueryItem(name: "return_scopes", value: "true"),
        ]
        return components.url!
    }

    func authorize() async throws -> Result {
        let state = UUID().uuidString
        let appURL = facebookAppURL(state: state)
        if Self.registersURLScheme("fb\(appID)"), UIApplication.shared.canOpenURL(appURL) {
            switch await switchToFacebookApp(url: appURL) {
            case let .redirected(callback):
                return try Self.result(from: callback, state: state, redirectURI: redirectURI)
            case .returnedWithoutRedirect:
                throw SessionError.cancelled
            case .notOpened:
                break
            }
        }
        return try await authorizeOnTheWeb(state: state)
    }

    /// Whether the bundle lists `scheme` in `CFBundleURLTypes`. The Facebook
    /// app can only hand the redirect back through a registered scheme; an
    /// app ID from AudienceKit's branding rather than the build has none, so
    /// that sign-in stays in the web sheet, whose callback needs no
    /// registration.
    nonisolated static func registersURLScheme(_ scheme: String, in bundle: Bundle = .main) -> Bool {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(scheme) == true }
    }

    /// Takes the Facebook app's redirect while a sign-in waits for it;
    /// returns whether the URL was one.
    static func handle(_ url: URL) -> Bool {
        guard let login = appSwitching, login.appSwitch != nil, url.scheme == "fb\(login.appID)",
              url.host == "authorize" else { return false }
        login.finishAppSwitch(.redirected(url))
        return true
    }

    // MARK: - Facebook app

    /// Opens the dialog in the Facebook app and waits to come back.
    private func switchToFacebookApp(url: URL) async -> AppSwitch {
        await withCheckedContinuation { continuation in
            appSwitch = continuation
            Self.appSwitching = self
            UIApplication.shared.open(url) { [weak self] opened in
                guard opened else { self?.finishAppSwitch(.notOpened); return }
                // The redirect, when there is one, arrives as the app becomes
                // active; coming back without it (cancelling, or switching back
                // by hand) ends the wait.
                self?.activeObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { _ in
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        self?.finishAppSwitch(.returnedWithoutRedirect)
                    }
                }
            }
        }
    }

    private func finishAppSwitch(_ outcome: AppSwitch) {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        appSwitch?.resume(returning: outcome)
        appSwitch = nil
        if Self.appSwitching === self { Self.appSwitching = nil }
    }

    // MARK: - Web

    private func authorizeOnTheWeb(state: String) async throws -> Result {
        let url = dialogURL(state: state)

        // The sheet refuses to start while an alert or sheet is still going
        // away (the warning's Continue, the terms sheet), so a refused start
        // waits a moment and tries again before giving up.
        var attempt = 0
        while true {
            let callback: URL? = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "fb\(appID)") { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: SessionError.cancelled)
                    } else {
                        continuation.resume(throwing: error ?? SessionError.missingFacebookToken)
                    }
                }
                // Share Safari's cookies, so someone already signed in to Facebook there just continues.
                session.prefersEphemeralWebBrowserSession = false
                session.presentationContextProvider = self
                self.session = session

                if !session.start() {
                    continuation.resume(returning: nil)
                }
            }
            session = nil

            if let callback {
                return try Self.result(from: callback, state: state, redirectURI: redirectURI)
            }
            attempt += 1
            guard attempt < 4 else { throw SessionError.facebookSheetUnavailable }
            try await Task.sleep(for: .milliseconds(400))
        }
    }

    /// Reads the code from the redirect, or the reason Facebook gave instead.
    /// The web dialog puts the parameters in the query; the Facebook app puts
    /// them in the fragment.
    nonisolated static func result(from callback: URL, state: String, redirectURI: String) throws -> Result {
        var items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = callback.fragment {
            items += URLComponents(string: "?" + fragment)?.queryItems ?? []
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let reason = value("error_description") ?? value("error_message") ?? value("error") {
            if value("error_reason") == "user_denied" { throw SessionError.cancelled }
            throw SessionError.facebook(reason.replacingOccurrences(of: "+", with: " "))
        }
        guard value("state") == state else { throw SessionError.facebook("The login response didn't match the request.") }
        guard let code = value("code"), !code.isEmpty else { throw SessionError.missingFacebookToken }

        return .code(code, redirectURI: redirectURI)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
