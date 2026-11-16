//
//  ScreenTestSupport.swift
//  HotMessTests
//
//  What the screen tests share: a stand-in API answered from inline fixtures,
//  an AppModel signed in to it without the keychain, and a window that hosts a
//  real SwiftUI screen and reads back what it shows through accessibility.
//
//  Nothing here can reach a real server. The stub's URL session answers every
//  request itself; a request for anything but the stub's own `.invalid` host is
//  refused and fails the test, and so is any request the test didn't stub.
//

import AudienceKit
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import HotMess

// MARK: - Stub API

/// A stand-in for the AudienceKit API: GraphQL answered by operation name, REST
/// by "METHOD /path". Each stub has its own `.invalid` host, so suites can run
/// side by side and nothing can resolve outside the process.
final class StubAPI: @unchecked Sendable {
    struct Request: @unchecked Sendable {
        let key: String
        let operationName: String?
        let query: String
        let variables: [String: Any]
        let url: URL

        func string(_ name: String) -> String? { variables[name] as? String }
    }

    enum Reply: Sendable {
        /// `{"data": <json>}`.
        case data(String)
        /// `{"errors": [...]}`, status 200, as the API refuses an operation.
        case errors([String])
        /// Any status and body.
        case raw(status: Int, body: String)
        /// No response at all: the connection failed.
        case offline

        static func error(_ message: String) -> Reply { .errors([message]) }
    }

    static let domain = "stub.invalid"
    private static let registry = NSLock()
    private struct Weak { weak var stub: StubAPI? }
    nonisolated(unsafe) private static var stubs: [String: Weak] = [:]

    let id = UUID().uuidString.lowercased()
    let audienceID = "00000000-0000-4000-8000-000000000001"
    let userID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!

    private let lock = NSLock()
    private var replies: [String: @Sendable (Request) -> Reply] = [:]
    private var recorded: [Request] = []
    private var unstubbedKeys: [String] = []
    private var foreign: [String] = []
    private var delays: [String: Duration] = [:]
    /// Operations that may come and go with timing (refreshes, side loads) and
    /// answer with an error unless stubbed, without failing the test.
    private var tolerated: Set<String> = []

    init() {
        Self.registry.withLock { Self.stubs[id] = Weak(stub: self) }
    }

    deinit {
        let id = id
        Self.registry.withLock { _ = Self.stubs.removeValue(forKey: id) }
    }

    var baseURL: URL { URL(string: "https://\(id).\(Self.domain)")! }

    /// A session whose every request this stub answers.
    var urlSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }

    /// Answers `key` (a GraphQL operation name, or "GET /v1/status") with `reply`.
    func on(_ key: String, _ reply: Reply) {
        lock.withLock { replies[key] = { _ in reply } }
    }

    /// Answers `key` from a closure, for replies that depend on the variables or change over time.
    func on(_ key: String, respond: @escaping @Sendable (Request) -> Reply) {
        lock.withLock { replies[key] = respond }
    }

    /// Lets `keys` go unstubbed: they get an error reply and don't fail the test.
    func tolerate(_ keys: String...) {
        lock.withLock { tolerated.formUnion(keys) }
    }

    /// Holds `key`'s reply back for `delay`, to catch a screen while it loads.
    func delay(_ key: String, by delay: Duration) {
        lock.withLock { delays[key] = delay }
    }

    var requests: [Request] { lock.withLock { recorded } }
    var operationNames: [String] { requests.map(\.key) }

    func count(_ key: String) -> Int { requests.filter { $0.key == key }.count }
    func last(_ key: String) -> Request? { requests.last { $0.key == key } }

    /// Fails the test for every request nobody stubbed, and for any that left the stub's host.
    func expectEverythingStubbed(sourceLocation: SourceLocation = #_sourceLocation) {
        let (missing, outside) = lock.withLock { (unstubbedKeys, foreign) }
        print("StubAPI asked for: \(Set(operationNames).sorted())")
        for key in Set(missing).sorted() {
            Issue.record("Unstubbed request: \(key)", sourceLocation: sourceLocation)
        }
        for url in outside + StubURLProtocol.takeForeign() {
            Issue.record("Request outside the stub: \(url)", sourceLocation: sourceLocation)
        }
    }

    // MARK: Routing

    static func find(_ host: String) -> StubAPI? {
        guard host.hasSuffix(".\(domain)") else { return nil }
        let id = String(host.dropLast(domain.count + 1))
        return registry.withLock { stubs[id]?.stub }
    }

    func answer(_ request: Request) -> (Reply, Duration?) {
        let (respond, delay): ((@Sendable (Request) -> Reply)?, Duration?) = lock.withLock {
            recorded.append(request)
            let respond = replies[request.key]
            if respond == nil, !tolerated.contains(request.key) { unstubbedKeys.append(request.key) }
            return (respond, delays[request.key])
        }
        guard let respond else {
            return (.errors(["unstubbed \(request.key)"]), delay)
        }
        return (respond(request), delay)
    }

    /// "Venue" for `query Venue($id: ID!) { … }`, from the body's
    /// `operationName` when it has one, else the document's first word after
    /// `query`, `mutation` or `subscription`.
    static func operationName(in body: [String: Any]) -> String? {
        if let name = body["operationName"] as? String, !name.isEmpty { return name }
        guard let query = body["query"] as? String else { return nil }
        let pattern = #"(?:query|mutation|subscription)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query) else { return nil }
        return String(query[range])
    }
}

/// Answers every request made through `StubAPI.urlSession`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var pending: DispatchWorkItem?
    private static let lock = NSLock()
    nonisolated(unsafe) private static var foreignRequests: [String] = []

    static func takeForeign() -> [String] {
        lock.withLock {
            defer { foreignRequests = [] }
            return foreignRequests
        }
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let stub = StubAPI.find(host) else {
            // Nothing outside the stub is ever let through. A straggler from
            // a finished test (its stub already gone) is refused quietly;
            // anything for another host fails the test.
            let url = request.url?.absoluteString ?? "?"
            if request.url?.host?.hasSuffix(".\(StubAPI.domain)") != true {
                Self.lock.withLock { Self.foreignRequests.append(url) }
            }
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let key: String
        var operationName: String?
        if json["query"] != nil {
            operationName = StubAPI.operationName(in: json)
            key = operationName ?? "graphql"
        } else {
            key = "\(request.httpMethod ?? "GET") \(url.path)"
        }
        let parsed = StubAPI.Request(key: key, operationName: operationName, query: json["query"] as? String ?? "",
                                     variables: json["variables"] as? [String: Any] ?? [:], url: url)
        let (reply, delay) = stub.answer(parsed)

        if let delay {
            let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
            let item = DispatchWorkItem { [weak self] in self?.deliver(reply, url: url) }
            pending = item
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
        } else {
            deliver(reply, url: url)
        }
    }

    override func stopLoading() {
        pending?.cancel()
    }

    private func deliver(_ reply: StubAPI.Reply, url: URL) {
        let status: Int
        let text: String
        switch reply {
        case let .data(data): (status, text) = (200, #"{"data":\#(data)}"#)
        case let .errors(messages):
            let encoded = messages.map { message -> String in
                let data = try? JSONSerialization.data(withJSONObject: ["message": message])
                return data.flatMap { String(data: $0, encoding: .utf8) } ?? #"{"message":"error"}"#
            }
            (status, text) = (200, #"{"errors":[\#(encoded.joined(separator: ","))]}"#)
        case let .raw(code, raw): (status, text) = (code, raw)
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A realtime socket that never connects: chat and notifications stay quiet.
final class SilentSocket: CableSocket, @unchecked Sendable {
    func send(_ text: String) {}
    func receive() async throws -> Data {
        try await Task.sleep(for: .seconds(3_600))
        throw URLError(.cancelled)
    }
    func close() {}
}

// MARK: - App model

extension StubAPI {
    /// What every signed-in screen asks for on the side: the safety state, the
    /// user's Pings and the card order (which falls back to the built-in one).
    func stubSignedInBasics(hasFacebook: Bool = true) {
        on("Safety", .data(#"{"me":{"terms_accepted_at":"2026-01-01T00:00:00Z","blocked_users":[],"can_pretend_location":false,"self":{"has_facebook":\#(hasFacebook)}}}"#))
        on("Pings", .data(#"{"me":{"ping":{"my_ping":null,"friend_pings":[]}}}"#))
        on("Layout", .error("No layout in the stub"))
        on("Me", .data(#"{"me":{"self":{"id":"11111111-2222-4333-8444-555555555555","name":"Test Person","first_name":"Test","last_name":"Person","photo":null}}}"#))
        // Find friends: texting isn't set up in the stub, so Now shows no card unless a test says otherwise.
        on("ContactMatching", .data(#"{"me":{"contactMatching":{"enabled":false,"phoneVerified":false,"phoneNumber":null,"firstName":null,"lastName":null,"contactsChecked":0,"lastCheckedAt":null,"nextCheckAt":null,"textCodesAvailable":false,"matches":[],"incomingRequests":[]}}}"#))
    }
}

extension StubAPI {
    /// An AppModel signed in to this stub: in-memory credential, stubbed
    /// session, no App Attest, a socket that never opens.
    @MainActor
    func appModel(signedIn: Bool = true) -> AppModel {
        // The locale Now last found is remembered across launches; start
        // each test from none, so one test's locale can't leak into the next.
        for key in ["localeId", "localeName"] { UserDefaults.standard.removeObject(forKey: key) }
        let configuration = AppConfiguration(baseURL: baseURL, audienceID: audienceID)
        let endpoint = URL(string: "/graphql", relativeTo: baseURL)!.absoluteURL
        let credential = Credential(token: "stub-token", userId: userID.uuidString.lowercased(),
                                    audienceId: audienceID, role: "member", endpoint: endpoint)
        let store = InMemoryCredentialStore(credential: signedIn ? credential : nil)
        return AppModel(configuration: configuration, credentialStore: store, urlSession: urlSession,
                        deviceAttestor: nil, openSocket: { _ in SilentSocket() })
    }
}

// MARK: - Hosting

/// SwiftUI only builds its accessibility tree once something asks for it
/// (VoiceOver, or UI automation). Turning automation on in this process makes
/// the hosted screens expose their elements the way VoiceOver sees them.
@MainActor
enum AccessibilityAutomation {
    private static var enabled = false

    static func enable() {
        guard !enabled else { return }
        enabled = true
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW) else { return }
        typealias Setter = @convention(c) (Bool) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            if let symbol = dlsym(handle, name) {
                unsafeBitCast(symbol, to: Setter.self)(true)
            }
        }
    }
}

/// A real window hosting a SwiftUI screen, as the app would show it.
@MainActor
final class ScreenHost {
    let window: UIWindow
    let controller: UIViewController

    init<Content: View>(
        _ content: Content,
        size: CGSize = CGSize(width: 402, height: 874),
        colorScheme: ColorScheme = .light,
        dynamicType: DynamicTypeSize = .large,
        inNavigationStack: Bool = true
    ) {
        let root = Group {
            if inNavigationStack {
                NavigationStack { content }
            } else {
                content
            }
        }
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, dynamicType)

        AccessibilityAutomation.enable()
        let controller = UIHostingController(rootView: AnyView(root))
        controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        self.window = window
        self.controller = controller
    }

    /// Lets the screen's tasks run and lays it out again, until `condition`
    /// holds or `timeout` passes. Returns whether it held.
    @discardableResult
    func settle(timeout: Duration = .seconds(1), until condition: () -> Bool = { false }) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        controller.view.layoutIfNeeded()
        return condition()
    }

    /// Waits until some text on screen contains `text`.
    @discardableResult
    ///
    /// The timeout is generous because Xcode Cloud runs the suites side by side
    /// on a busy simulator; a passing wait returns as soon as the text shows.
    /// On a miss it records what the screen did show, so the failure in the
    /// Xcode Cloud report says why (a print only reaches the raw log).
    func waitFor(_ text: String, timeout: Duration = .seconds(20),
                 sourceLocation: SourceLocation = #_sourceLocation) async -> Bool {
        let found = await settle(timeout: timeout) { self.contains(text) }
        if !found {
            Issue.record("No \"\(text)\" on screen; it shows: \(texts)", sourceLocation: sourceLocation)
        }
        return found
    }

    /// Every accessibility element on screen, walking the hosting view's
    /// accessibility tree as VoiceOver would, presented sheets included.
    var elements: [NSObject] {
        var found: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 80, seen.insert(ObjectIdentifier(object)).inserted else { return }
            found.append(object)
            if let elements = object.accessibilityElements as? [NSObject] {
                for element in elements { visit(element, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    for index in 0 ..< count {
                        if let element = object.accessibilityElement(at: index) as? NSObject {
                            visit(element, depth: depth + 1)
                        }
                    }
                }
            }
            if let view = object as? UIView {
                for subview in view.subviews { visit(subview, depth: depth + 1) }
            }
        }
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            where window === self.window || window.windowLevel > .normal {
            visit(window, depth: 0)
        }
        var presented = controller.presentedViewController
        while let current = presented {
            visit(current.view, depth: 0)
            presented = current.presentedViewController
        }
        return found
    }

    /// Every accessibility label, value and identifier on screen.
    var texts: [String] {
        elements.flatMap { object -> [String] in
            var strings: [String] = []
            if let label = object.accessibilityLabel, !label.isEmpty { strings.append(label) }
            if let value = object.accessibilityValue, !value.isEmpty { strings.append(value) }
            if let identifiable = object as? UIAccessibilityIdentification,
               let identifier = identifiable.accessibilityIdentifier, !identifier.isEmpty {
                strings.append(identifier)
            }
            return strings
        }
    }

    /// Activates (as a VoiceOver double tap does) the first element labelled
    /// `label`, or whose identifier is `label`. Returns whether one was found.
    @discardableResult
    func activate(_ label: String, exact: Bool = true) -> Bool {
        let match = elements.first { object in
            let identifier = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier
            let text = object.accessibilityLabel ?? ""
            let labelMatches = exact ? text == label : text.localizedCaseInsensitiveContains(label)
            return (labelMatches || identifier == label) && object.accessibilityTraits.contains(.button)
                || (identifier == label)
        }
        guard let match else { return false }
        if match.accessibilityActivate() { return true }
        if let control = match as? UIControl {
            control.sendActions(for: .touchUpInside)
            return true
        }
        return false
    }

    func contains(_ text: String) -> Bool {
        texts.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    /// Whether the screen drew anything at all.
    var renderedSomething: Bool {
        controller.view.bounds.width > 0 && !controller.view.subviews.isEmpty
    }

    func tearDown() {
        controller.presentedViewController?.dismiss(animated: false)
        controller.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
    }
}

/// Hosts `content` with `model` in its environment, the way RootView does.
@MainActor
/// `size` is the window's; a long List only lays out the rows that fit, so a
/// test that reads rows further down hosts the screen taller.
func host<Content: View>(_ content: Content, model: AppModel, colorScheme: ColorScheme = .light,
                         dynamicType: DynamicTypeSize = .large,
                         size: CGSize = CGSize(width: 402, height: 874)) -> ScreenHost {
    ScreenHost(content.environment(model), size: size, colorScheme: colorScheme, dynamicType: dynamicType)
}

// MARK: - Fixtures

/// Inline GraphQL payloads the screen tests answer with.
enum ScreenFixtures {
    static let venueID = "6f1c2c1e-4d2a-4f6b-9a37-0c1d2e3f4a5b"
    static let eventID = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"
    static let localeID = "4e5f6071-8293-4a41-8d5e-6f7a8b9c0d1e"
    static var venueUUID: UUID { UUID(uuidString: venueID)! }
    static var eventUUID: UUID { UUID(uuidString: eventID)! }
    static var localeUUID: UUID { UUID(uuidString: localeID)! }

    /// An ISO 8601 time `hours` from now, for "tonight".
    static func iso(hoursFromNow hours: Double) -> String {
        ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(hours * 3_600))
    }

    static func event(id: String = eventID, name: String = "Bingo Night", startHours: Double = -1,
                      endHours: Double = 3, rsvp: String = "null", venueName: String = "Nyne") -> String {
        """
        {"id":"\(id)","name":"\(name)","start_at":"\(iso(hoursFromNow: startHours))",
         "end_at":"\(iso(hoursFromNow: endHours))","facebook_id":null,"banner_url":null,
         "is_featured":false,"rsvp":{"mine":\(rsvp)},
         "venue":{"name":"\(venueName)","venue":{"id":"\(venueID)","name":"\(venueName)"}}}
        """
    }

    static func venue(name: String = "Nyne", events: [String] = []) -> String {
        """
        {"id":"\(venueID)","name":"\(name)","distance":null,"point":{"x":-117.41,"y":47.65},
         "photo_url":null,"banner_url":null,
         "profile":{"address":"232 W Sprague","phone":null,"facebook":{"facebook_id":null,"is_liked":false}},
         "chat":{"open":true,"recent_messages":{"nodes":[
            {"id":"1b2c3d4e-5f60-4718-9a2b-3c4d5e6f7a8b","message":"who's here?","name":"Sam",
             "user_id":"2c3d4e5f-6071-4829-8b3c-4d5e6f7a8b9c","avatar_url":null,"sent_at":"\(iso(hoursFromNow: -0.1))"}]}},
         "events":{"upcoming":{"nodes":[\(events.joined(separator: ","))]}},
         "friends":{"list":{"nodes":[{"id":"3d4e5f60-7182-4930-9c4d-5e6f7a8b9c0d","name":"Alex Friend","facebook_id":"4242"}]}}}
        """
    }

    static let locale = #"{"id":"4e5f6071-8293-4a41-8d5e-6f7a8b9c0d1e","name":"Spokane","friends":{"list":{"nodes":[]},"venues":{"nodes":[]}}}"#

    /// Now at a venue with nothing on.
    static var nowAtVenue: String {
        #"{"reportLocation":{"nearby_venues":null,"venue":\#(venue()),"locale":\#(locale)}}"#
    }

    /// Now at an event.
    static var nowAtEvent: String {
        #"{"reportLocation":{"nearby_venues":null,"event":\#(event()),"venue":\#(venue(events: [event()])),"locale":\#(locale)}}"#
    }

    /// Near venues but in none.
    static var nowNearby: String {
        #"{"reportLocation":{"venue":null,"nearby_venues":[\#(venue(name: "The Stud"))],"locale":\#(locale)}}"#
    }
}
