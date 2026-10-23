import AudienceKit
import StoreKit
import SwiftUI

@main
struct HotMessClipApp: App {
    @State private var link: ClipLink?
    @State private var receivedLink = false
    @State private var session = ClipSession()

    var body: some Scene {
        WindowGroup {
            ClipRootView(link: link, receivedLink: receivedLink, session: session)
                .task { await session.observe() }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { receive($0.webpageURL) }
                .onOpenURL { receive($0) }
                .preferredColorScheme(.light)
                .tint(ClipTheme.accentInk)
        }
    }

    private func receive(_ url: URL?) {
        link = url.flatMap(ClipLink.init(url:))
        receivedLink = true
    }
}

/// What the clip can take a payment for. Chosen by the screen's one button.
enum ClipFlow: Identifiable, Hashable {
    case cover
    case tip(preselectedCents: Int?)
    var id: Self { self }
}

/// Loads the public share card for the link and shows the matching screen:
/// loading, the record, expired, unsupported, or an error.
struct ClipRootView: View {
    let link: ClipLink?
    let receivedLink: Bool
    @Bindable var session: ClipSession
    @State private var phase = Phase.loading
    @State private var attempt = 0
    @State private var flow: ClipFlow?
    @State private var showStore = false

    enum Phase {
        case loading
        case ready(ClipCard, ShareInvitation?)
        case expired
        case failed(String)
    }

    var body: some View {
        Group {
            if let link {
                switch phase {
                case .loading:
                    ClipLoadingView(kind: link.kind)
                case let .ready(card, invitation):
                    ClipLandingView(link: link, card: card, invitation: invitation, session: session,
                                    pay: { flow = $0 }, getApp: getApp)
                case .expired:
                    ClipExpiredView(link: link, getApp: getApp)
                case let .failed(message):
                    ClipFailedView(message: message, retry: { attempt += 1 }, getApp: getApp)
                }
            } else {
                ClipUnsupportedView(receivedLink: receivedLink, getApp: getApp)
            }
        }
        .background(ClipTheme.surface.ignoresSafeArea())
        .task(id: LoadID(link: link, attempt: attempt)) { await load() }
        .task(id: DetailsID(link: link, signedIn: session.signedIn)) {
            session.clearDetails()
            if let link { await session.loadDetails(for: link) }
        }
        .sheet(item: $flow) { flow in
            if let link { ClipCheckoutSheet(flow: flow, link: link, session: session, getApp: getApp) }
        }
        .appStoreOverlay(isPresented: $showStore) { SKOverlay.AppClipConfiguration(position: .bottom) }
        .onChange(of: link) { _, _ in flow = nil }
    }

    private struct LoadID: Equatable { let link: ClipLink?; let attempt: Int }
    private struct DetailsID: Equatable { let link: ClipLink?; let signedIn: Bool }

    /// The full app, through StoreKit's overlay. On install, iOS hands the
    /// clip's invocation URL to the app, which opens the same record (and
    /// joins a Ping with its invitation token).
    private func getApp() {
        showStore = true
    }

    @MainActor private func load() async {
        phase = .loading
        guard let link else { return }
        do {
            if link.kind == "pings" {
                guard let token = link.expiry, !token.isEmpty else { throw ClipError.unavailable }
                let invitation = try await ShareInvitation.load(path: link.path, token: token, client: session.client)
                try Task.checkCancellation()
                guard invitation.expiresAt > .now else { phase = .expired; return }
                let card = ClipCard(title: invitation.title,
                                    description: invitation.note ?? "\(invitation.senderName) wants you out tonight.",
                                    image: nil)
                phase = .ready(card, invitation)
            } else {
                let data = try await session.client.data(for: APIRequest(path: "/v1/share", queryItems: [
                    URLQueryItem(name: "host", value: session.client.configuration.host),
                    URLQueryItem(name: "path", value: link.path)
                ] + (link.expiry.map { [URLQueryItem(name: "e", value: $0)] } ?? []), authenticated: false))
                try Task.checkCancellation()
                phase = .ready(try JSONDecoder().decode(ClipCard.self, from: data), nil)
            }
        } catch {
            guard !Task.isCancelled else { return }
            // A signed link the API refuses has run out (or was never valid).
            if link.expiry != nil, let status = (error as? AudienceKitError)?.status, [403, 404, 410].contains(status) {
                phase = .expired
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
