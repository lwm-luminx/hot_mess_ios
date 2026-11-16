//
//  FacebookSignInTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Facebook sign-in")
@MainActor
struct FacebookSignInTests {
    @Test("Opens Login for Business with the configuration instead of permissions")
    func businessDialog() throws {
        let login = FacebookSignIn(appID: "713525445368431", configID: "4085560021745660", permissions: ["email"])
        let items = try #require(URLComponents(url: login.dialogURL(state: "s-1"), resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.contains(URLQueryItem(name: "config_id", value: "4085560021745660")))
        #expect(items.contains(URLQueryItem(name: "redirect_uri", value: "fb713525445368431://authorize/")))
        #expect(items.contains(URLQueryItem(name: "response_type", value: "code")))
        #expect(!items.contains { $0.name == "scope" })
    }

    @Test("Asks for permissions when there's no configuration")
    func consumerDialog() throws {
        let login = FacebookSignIn(appID: "1", configID: nil, permissions: ["public_profile", "email"])
        let items = try #require(URLComponents(url: login.dialogURL(state: "s"), resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.contains(URLQueryItem(name: "scope", value: "public_profile,email")))
    }

    @Test("Asks for the approved permissions, plus email and friends only in debug or the simulator")
    func requestedPermissions() {
        #expect(Array(SessionStore.requestedPermissions.prefix(2)) == ["public_profile", "openid"])
        #if DEBUG || targetEnvironment(simulator)
        #expect(SessionStore.requestedPermissions == ["public_profile", "openid", "email", "user_friends"])
        #else
        #expect(SessionStore.requestedPermissions == ["public_profile", "openid"])
        #endif
    }

    @Test("Reads the code from the redirect")
    func readsCode() throws {
        let callback = try #require(URL(string: "fb1://authorize/?code=abc&state=s-1#_=_"))
        let result = try FacebookSignIn.result(from: callback, state: "s-1", redirectURI: "fb1://authorize/")

        #expect(result == .code("abc", redirectURI: "fb1://authorize/"))
    }

    @Test("Turns Facebook's error into the sign-in failure")
    func readsError() throws {
        let callback = try #require(URL(string: "fb1://authorize/?error=access_denied&error_description=App+not+active"))

        #expect(throws: SessionError.self) {
            try FacebookSignIn.result(from: callback, state: "s-1", redirectURI: "fb1://authorize/")
        }
    }

    @Test("Rejects a redirect for another request")
    func rejectsState() throws {
        let callback = try #require(URL(string: "fb1://authorize/?code=abc&state=other"))

        #expect(throws: SessionError.self) {
            try FacebookSignIn.result(from: callback, state: "s-1", redirectURI: "fb1://authorize/")
        }
    }

    @Test("Opens the same dialog in the Facebook app")
    func facebookAppDialog() throws {
        let login = FacebookSignIn(appID: "1", configID: "42", permissions: [])
        let url = login.facebookAppURL(state: "s-1")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.scheme == "fbauth2")
        #expect(url.host == "authorize")
        #expect(items.contains(URLQueryItem(name: "config_id", value: "42")))
        #expect(items.contains(URLQueryItem(name: "ios_fast_app_switch", value: "true")))
    }

    @Test("Reads the code from the Facebook app's fragment")
    func readsFragmentCode() throws {
        let callback = try #require(URL(string: "fb1://authorize/#granted_scopes=public_profile&code=abc&state=s-1"))
        let result = try FacebookSignIn.result(from: callback, state: "s-1", redirectURI: "fb1://authorize/")

        #expect(result == .code("abc", redirectURI: "fb1://authorize/"))
    }
}
