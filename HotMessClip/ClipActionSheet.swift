import AudienceKit
import AuthenticationServices
import SwiftUI

struct ClipActionSheet: View {
    let action: ClipAction
    let link: ClipLink
    @Bindable var session: ClipSession
    @Environment(\.dismiss) private var dismiss
    @State private var details: ClipDetails?
    @State private var invitation: ShareInvitation?
    @State private var error: String?
    @State private var busy = false
    @State private var completed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !session.signedIn {
                        ClipSignInView(session: session)
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Try again") { Task { await load() } }
                    } else if action == .join, let invitation {
                        Text(invitation.title).font(.title2.bold())
                        if let note = invitation.note { Text(note) }
                        ForEach(invitation.targets) { Text($0.name) }
                        Button(completed ? "You're in!" : "I'm in") { Task { await join() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy || completed || invitation.expiresAt <= .now)
                    } else if let details {
                        switch action {
                        case .cover:
                            if details.venue?.tickets?.cover?.coverCharge?.payable == true ||
                                details.venue?.tickets?.cover?.viewerAdmission?.isPaid == true {
                                ClipDetailsView(details: details, checkout: session.checkout)
                            } else { Text("Cover isn't available to buy here right now.") }
                        case .rsvp:
                            if let event = details.event {
                                Text(event.name).font(.title2.bold())
                                Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                                if let venue = details.venue { Text(venue.name) }
                                if let description = event.description { Text(description) }
                                Button(completed ? "You're going!" : "I'm going") { Task { await rsvp() } }
                                    .buttonStyle(.borderedProminent).disabled(busy || completed)
                            }
                        case .tip:
                            if let performer = details.performer {
                                ClipTipView(performer: performer, session: session)
                            }
                        case .join: EmptyView()
                        }
                    } else { ProgressView("Loading…") }
                }.padding(24)
            }
            .navigationTitle(action.rawValue)
            .toolbar { Button("Done") { dismiss() }.disabled(session.paymentBusy || busy) }
            .task(id: session.signedIn) { if session.signedIn { await load() } }
            .interactiveDismissDisabled(session.paymentBusy || busy)
            .sheet(item: Binding(get: { session.checkout.presentedPass }, set: { session.checkout.presentedPass = $0 })) {
                ClipPassView(admission: $0)
            }
            .alert("Couldn't pay cover", isPresented: Binding(
                get: { session.checkout.errorMessage != nil },
                set: { if !$0 { session.checkout.errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(session.checkout.errorMessage ?? "") }
        }
    }
    @MainActor private func load() async {
        error = nil
        do {
            if action == .join {
                guard let token = link.expiry else { throw ClipError.unavailable }
                invitation = try await ShareInvitation.load(path: link.path, token: token, client: session.client)
            } else {
                details = try await session.api.details(for: link)
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    @MainActor private func rsvp() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await session.client.setRSVP(.attending, forEvent: link.id); completed = true }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func join() async {
        guard !busy, let token = link.expiry else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await session.client.graphQL(Self.joinDocument,
                variables: ["id": .string(link.id), "token": .string(token)], as: JoinResponse.self)
            completed = true
        } catch { self.error = error.localizedDescription }
    }
    private struct JoinResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { struct Ping: Decodable, Sendable { let id: String }; let ping: Ping }
        let joinPing: Payload
    }
    private static let joinDocument = """
    mutation ClipJoinPing($id: ID!, $token: String!) {
      joinPing(input: {pingId: $id, invitationToken: $token}) { ping { id } }
    }
    """
}

private struct ClipSignInView: View {
    @Bindable var session: ClipSession
    @State private var adult = AgeGate.isConfirmed
    @State private var minor = false
    @State private var acceptedTerms = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in to continue").font(.title2.bold())
            if minor { Text("Hot Mess is for people 18 and older.") }
            else {
                Toggle("I am 18 or older", isOn: $adult)
                Toggle("I accept the Terms and Privacy Policy", isOn: $acceptedTerms)
                HStack {
                    Link("Terms", destination: URL(string: "https://hotmess.social/terms/")!)
                    Link("Privacy", destination: URL(string: "https://hotmess.social/privacy/")!)
                }
                SignInWithAppleButton(.signIn) { $0.requestedScopes = [.fullName, .email] } onCompletion: { result in
                    guard adult, acceptedTerms, !minor else { return }
                    AgeGate.confirm()
                    Task { await session.signIn(result) }
                }
                .frame(height: 48).disabled(!adult || !acceptedTerms || session.busy)
                if session.busy { ProgressView("Signing in…") }
                if let error = session.error { Text(error).foregroundStyle(.red) }
            }
        }
        .task {
            let verdict = await AgeGate.requestDeclaredAge()
            minor = verdict == .minor
            if verdict == .adult { adult = true }
        }
    }
}

private struct ClipTipView: View {
    let performer: ClipPerformer
    @Bindable var session: ClipSession
    @State private var checkout = ClipTipCheckout()
    @State private var amount = 0
    @State private var quote: Quote?
    @State private var error: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(performer.name ?? "Performer").font(.title2.bold())
            if let tipping = performer.tipping, !tipping.options.isEmpty {
                ForEach(tipping.options.filter { !$0.isInApp }) { option in
                    if let url = option.url, ["https", "http"].contains(url.scheme ?? "") {
                        Link("Tip with \(option.name)", destination: url).buttonStyle(.bordered)
                    }
                }
                if tipping.options.contains(where: \.isInApp) {
                    Picker("Tip amount", selection: $amount) {
                        ForEach(tipping.presetCents.filter { $0 >= tipping.minimumCents && $0 <= tipping.maximumCents }, id: \.self) {
                            Text(Money(cents: $0, currency: tipping.currency).formatted).tag($0)
                        }
                    }.disabled(checkout.busy)
                    if let quote {
                        Text("Tip \(quote.amount.formatted) + \(quote.fee.formatted) fee = \(quote.total.formatted)")
                        Button("Pay \(quote.total.formatted)") {
                            Task { await checkout.pay(personID: performer.id, amount: amount,
                                name: performer.name ?? "Performer", session: session) }
                        }.buttonStyle(.borderedProminent).disabled(checkout.busy || checkout.paid)
                    } else if let error { Text(error) }
                    else { ProgressView("Getting total…") }
                }
            } else { Text("This performer hasn't enabled tips yet.") }
            if let message = checkout.message { Text(message) }
        }
        .onAppear {
            if let tipping = performer.tipping {
                amount = tipping.presetCents.first(where: { $0 >= tipping.minimumCents && $0 <= tipping.maximumCents }) ?? 0
            }
        }
        .task(id: amount) { await loadQuote() }
        .interactiveDismissDisabled(checkout.busy)
    }
    @MainActor private func loadQuote() async {
        quote = nil
        error = nil
        guard amount > 0 else { error = "No tip amounts are available right now."; return }
        do {
            let response = try await session.client.graphQL(Self.document,
                variables: ["id": .string(performer.id.uuidString), "amount": .int(amount)], as: Response.self)
            try Task.checkCancellation()
            quote = response.people.person?.tipping?.quote
            if quote == nil { error = "This tip amount isn't available." }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private struct Quote: Decodable, Sendable { let amount: Money; let fee: Money; let total: Money }
    private struct Response: Decodable, Sendable {
        struct People: Decodable, Sendable {
            struct Person: Decodable, Sendable { struct Tipping: Decodable, Sendable { let quote: Quote? }; let tipping: Tipping? }
            let person: Person?
        }
        let people: People
    }
    private static let document = """
    query ClipTipQuote($id: ID!, $amount: Int!) {
      people { person(id: $id) { tipping { quote(amountCents: $amount) {
        amount { cents currency } fee { cents currency } total { cents currency }
      } } } }
    }
    """
}
