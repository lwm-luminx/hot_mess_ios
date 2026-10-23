import AudienceKit
@preconcurrency import StripePaymentSheet
import SwiftUI

@main
struct HotMessClipApp: App {
    @State private var link: ClipLink?
    @State private var receivedLink = false
    @State private var session = ClipSession()

    var body: some Scene {
        WindowGroup {
            ClipView(link: link, receivedLink: receivedLink, session: session)
                .task { await session.observe() }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { receive($0.webpageURL) }
                .onOpenURL { receive($0) }
        }
    }
    private func receive(_ url: URL?) {
        if let url, StripeAPI.handleURLCallback(with: url) { return }
        link = url.flatMap(ClipLink.init(url:))
        receivedLink = true
    }
}

enum ClipAction: String, Identifiable {
    case cover = "Pay cover", tip = "Tip", join = "Join Ping", rsvp = "RSVP"
    var id: String { rawValue }
    static func primary(for kind: String) -> Self {
        switch kind { case "people": .tip; case "pings": .join; case "events": .rsvp; default: .cover }
    }
}

private struct ClipView: View {
    let link: ClipLink?
    let receivedLink: Bool
    @Bindable var session: ClipSession
    @State private var card: ClipCard?
    @State private var invitation: ShareInvitation?
    @State private var message: String?
    @State private var attempt = 0
    @State private var action: ClipAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let link, let card {
                        Text(card.title).font(.largeTitle.bold())
                        Button(ClipAction.primary(for: link.kind).rawValue) {
                            action = ClipAction.primary(for: link.kind)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                        if link.kind == "events" {
                            Button("Pay cover") { action = .cover }.buttonStyle(.bordered)
                        }
                        Text(card.description)
                        if let invitation {
                            ForEach(invitation.targets) { Text($0.name).font(.headline) }
                            Text("Ends \(invitation.expiresAt.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                        if let image = card.image, image.url.scheme == "https" {
                            AsyncImage(url: image.url) { phase in
                                if let photo = phase.image { photo.resizable().scaledToFit() }
                            }.clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityLabel(image.alt)
                        }
                        if session.signedIn {
                            Button("Sign out") { Task { await session.signOut() } }.disabled(session.paymentBusy)
                        }
                    } else if let message {
                        ContentUnavailableView("Couldn't open this link", systemImage: "link", description: Text(message))
                        Button("Try again") { attempt += 1 }
                    } else if link != nil { ProgressView("Opening Hot Mess…") }
                    else {
                        ContentUnavailableView(receivedLink ? "This link isn't supported" : "Welcome to Hot Mess",
                            systemImage: "sparkles", description: Text("Open a venue, performer, Ping or event link to get started."))
                    }
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .navigationTitle("Hot Mess")
            .task(id: TaskID(link: link, attempt: attempt)) { await load() }
            .sheet(item: $action) { action in
                if let link { ClipActionSheet(action: action, link: link, session: session) }
            }
            .onChange(of: link) { _, _ in action = nil }
        }
    }
    private struct TaskID: Equatable { let link: ClipLink?; let attempt: Int }

    @MainActor private func load() async {
        card = nil
        invitation = nil
        message = nil
        guard let link else { return }
        do {
            if link.kind == "pings" {
                guard let token = link.expiry else { throw ClipError.unavailable }
                let preview = try await ShareInvitation.load(path: link.path, token: token, client: session.client)
                try Task.checkCancellation()
                invitation = preview
                card = ClipCard(title: preview.title, description: preview.note ?? "Who's up for going out?", image: nil)
            } else {
                let data = try await session.client.data(for: APIRequest(path: "/v1/share", queryItems: [
                    URLQueryItem(name: "host", value: session.client.configuration.host),
                    URLQueryItem(name: "path", value: link.path)
                ] + (link.expiry.map { [URLQueryItem(name: "e", value: $0)] } ?? []), authenticated: false))
                try Task.checkCancellation()
                card = try JSONDecoder().decode(ClipCard.self, from: data)
            }
        } catch {
            guard !Task.isCancelled else { return }
            message = error.localizedDescription
        }
    }
}
