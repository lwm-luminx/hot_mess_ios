import AudienceCore
import SwiftUI

/// A venue's safety poster opened in the clip (`/help/<code>`): tell the staff
/// on shift, quietly, without the app or an account, then follow the alert.
/// The same flow as hotmess.social/help/<code>, against the same endpoints.
struct ClipSafetyView: View {
    let code: String
    let client: AudienceSession
    let getApp: () -> Void

    @State private var phase = Phase.loading
    @State private var place: String?
    @State private var concerns: Set<String> = []
    @State private var details = ""
    @State private var reply = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmCancel = false

    private let store = ClipSafetyStore()

    enum Phase: Equatable {
        case loading
        case gone(String)
        case form(venueName: String, staffOnShift: Bool, places: [String], concerns: [String])
        case following(ClipSafetyAlert)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ClipBrandPill(onPhoto: false)
                content
                emergency
                Button("Get Hot Mess") { getApp() }.buttonStyle(ClipQuietButtonStyle())
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await start() }
        .task(id: followingID) { await poll() }
        .confirmationDialog("Close this alert?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("I'm OK now", role: .destructive) { Task { await act("cancel") } }
        } message: {
            Text("Staff stop looking for you. If anything changes, tell staff again.")
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ClipPanel { ProgressView("Finding the venue…").frame(maxWidth: .infinity) }
        case let .gone(message):
            ClipPanel {
                Text("This poster isn't working").font(.title3.bold()).foregroundStyle(ClipTheme.ink)
                Text(message).foregroundStyle(ClipTheme.inkMuted)
            }
        case let .failed(message):
            ClipPanel {
                Text("Couldn't reach Hot Mess").font(.title3.bold()).foregroundStyle(ClipTheme.ink)
                Text(message).foregroundStyle(ClipTheme.inkMuted)
                Text("Find any staff member, or ask for an Angel Shot at the bar.").foregroundStyle(ClipTheme.ink)
                Button("Try again") { Task { await start() } }.buttonStyle(ClipAccentButtonStyle())
            }
        case let .form(venueName, staffOnShift, places, allConcerns):
            form(venueName: venueName, staffOnShift: staffOnShift, places: places, allConcerns: allConcerns)
        case let .following(alert):
            following(alert)
        }
    }

    // MARK: - Tell staff

    private func form(venueName: String, staffOnShift: Bool, places: [String], allConcerns: [String]) -> some View {
        ClipPanel {
            ClipOverline(text: venueName)
            Text("Tell staff quietly").font(.title2.bold()).foregroundStyle(ClipTheme.ink)
            Text(staffOnShift
                 ? "The staff on shift get it right away. Nobody else sees it, and you don't need an account."
                 : "Nobody has put themselves on shift in Hot Mess right now, so the venue's managers get it. Find any staff member too.")
                .font(.callout).foregroundStyle(ClipTheme.inkMuted)

            Text("Where are you?").font(.headline).foregroundStyle(ClipTheme.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(places, id: \.self) { item in
                    ClipChip(title: ClipSafetyCoding.placeTitle(item), selected: place == item) {
                        place = place == item ? nil : item
                    }
                }
            }

            Text("What's going on?").font(.headline).foregroundStyle(ClipTheme.ink)
            VStack(spacing: 8) {
                ForEach(allConcerns, id: \.self) { item in
                    ClipChip(title: ClipSafetyCoding.concernTitle(item), selected: concerns.contains(item)) {
                        if concerns.contains(item) { concerns.remove(item) } else { concerns.insert(item) }
                    }
                }
            }

            Text("Anything that helps staff find you or spot them").font(.headline).foregroundStyle(ClipTheme.ink)
            TextField("Optional, like \"red cap by the pool table\"", text: $details, axis: .vertical)
                .lineLimit(2 ... 4)
                .padding(10)
                .background(ClipTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: ClipTheme.controlRadius))

            errorLine
            Button(busy ? "Sending…" : "Tell staff now") { Task { await send() } }
                .buttonStyle(ClipAccentButtonStyle()).disabled(busy)
            Text("Every detail is optional. Sending now is fine.").font(.footnote).foregroundStyle(ClipTheme.inkMuted)
        }
    }

    // MARK: - Following the alert

    @ViewBuilder private func following(_ alert: ClipSafetyAlert) -> some View {
        ClipPanel {
            ClipOverline(text: alert.venue.name)
            Text(headline(alert)).font(.title2.bold()).foregroundStyle(ClipTheme.ink)
            if alert.isActive {
                steps(alert)
                if alert.needsOtherHelp {
                    Text("Nobody has picked it up yet, so it went to the venue's managers. Find any staff member, ask for an Angel Shot at the bar, or call 911 if you're in danger.")
                        .font(.callout).foregroundStyle(ClipTheme.warning)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ClipTheme.warningSoft, in: RoundedRectangle(cornerRadius: ClipTheme.controlRadius))
                }
            }
            if let note = alert.supportNote, !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(ClipTheme.ink)
            }
        }

        ClipPanel {
            Text("Messages with staff").font(.headline).foregroundStyle(ClipTheme.ink)
            if alert.messages.isEmpty {
                Text("Staff can write to you here. Keep this screen open.").font(.callout).foregroundStyle(ClipTheme.inkMuted)
            }
            ForEach(alert.messages) { message in
                VStack(alignment: message.fromStaff ? .leading : .trailing, spacing: 2) {
                    Text(message.fromStaff ? (message.senderName ?? "Staff") : "You")
                        .font(.caption.bold()).foregroundStyle(ClipTheme.inkMuted)
                    Text(message.body).foregroundStyle(ClipTheme.ink)
                        .padding(10)
                        .background(message.fromStaff ? ClipTheme.controlFill : ClipTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: message.fromStaff ? .leading : .trailing)
            }
            if alert.isActive {
                HStack {
                    TextField("Write to staff", text: $reply, axis: .vertical).lineLimit(1 ... 3)
                        .padding(10)
                        .background(ClipTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: ClipTheme.controlRadius))
                    Button("Send") { Task { await sendReply() } }
                        .fontWeight(.semibold).disabled(busy || reply.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            errorLine
        }

        if alert.isActive {
            VStack(spacing: 8) {
                Button("Send it again") { Task { await act("remind") } }
                    .buttonStyle(ClipAccentButtonStyle()).disabled(busy)
                Button("I'm OK now") { confirmCancel = true }.buttonStyle(ClipQuietButtonStyle()).disabled(busy)
            }
        } else {
            Button("Tell staff again") { startOver() }.buttonStyle(ClipAccentButtonStyle())
        }
    }

    private func headline(_ alert: ClipSafetyAlert) -> String {
        switch alert.state {
        case "acknowledged": "\(alert.acknowledgedByName ?? "Staff") is on it"
        case "closed": "Staff closed this alert"
        case "cancelled": "Glad you're OK"
        default: alert.seen ? "Staff have seen it" : "Staff have been told"
        }
    }

    private func steps(_ alert: ClipSafetyAlert) -> some View {
        let items: [(ClipSafetyAlert.Step, String)] = [(.sent, "Sent"), (.seen, "Seen"), (.onIt, "On it")]
        return HStack(spacing: 6) {
            ForEach(items, id: \.0) { step, title in
                let done = step <= alert.step
                Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(done ? .semibold : .regular))
                    .foregroundStyle(done ? ClipTheme.success : ClipTheme.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var errorLine: some View {
        if let error { Text(error).font(.callout).foregroundStyle(ClipTheme.accentInk) }
    }

    private var emergency: some View {
        Link(destination: URL(string: "tel:911")!) {
            Label("In danger right now? Call 911", systemImage: "phone.fill")
                .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(ClipTheme.accentInk)
                .overlay(Capsule().strokeBorder(ClipTheme.accent, lineWidth: 2))
        }
    }

    // MARK: - Calls

    private var followingID: String? {
        if case let .following(alert) = phase, alert.isActive { return alert.id }
        return nil
    }

    private var host: URLQueryItem { URLQueryItem(name: "host", value: client.configuration.host) }

    private func request(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil) -> APIRequest {
        var headers = ["Accept": "application/json"]
        if let token { headers["X-Safety-Token"] = token }
        if body != nil { headers["Content-Type"] = "application/json" }
        return APIRequest(method: method, path: path, queryItems: [host], body: body.flatMap(ClipSafetyCoding.body),
                          authenticated: false, headers: headers)
    }

    /// Picks up an alert this device already sent from this poster, or shows the form.
    @MainActor private func start() async {
        phase = .loading
        error = nil
        if let saved = store.entry(for: code),
           let data = try? await client.data(for: request("GET", "/v1/safety/alerts/\(saved.alertID)", token: saved.token)),
           let alert = try? ClipSafetyCoding.decoder().decode(ClipSafetyAlertResponse.self, from: data).alert,
           alert.isActive {
            phase = .following(alert)
            return
        }
        do {
            let data = try await client.data(for: request("GET", "/v1/safety/posters/\(code)"))
            let poster = try ClipSafetyCoding.decoder().decode(ClipSafetyPoster.self, from: data)
            phase = .form(venueName: poster.venue.name, staffOnShift: poster.staffOnShift,
                          places: poster.places, concerns: poster.concerns)
        } catch {
            if (error as? AudienceKitError)?.status == 404 {
                phase = .gone("This safety poster's code isn't in use any more. Find any staff member for help.")
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor private func send() async {
        busy = true
        error = nil
        defer { busy = false }
        let saved = store.entry(for: code)
        let fields = ClipSafetyCoding.details(place: place, concerns: concerns, description: details)
        do {
            let data = try await client.data(for: request("POST", "/v1/safety/posters/\(code)/alerts",
                                                          token: saved?.token, body: fields))
            let sent = try ClipSafetyCoding.decoder().decode(ClipSafetyAlertResponse.self, from: data)
            if let token = sent.guestToken { store.save(.init(alertID: sent.alert.id, token: token), for: code) }
            phase = .following(sent.alert)
        } catch {
            self.error = message(for: error)
        }
    }

    @MainActor private func sendReply() async {
        let body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        if await act("messages", body: ["body": body]) { reply = "" }
    }

    @discardableResult
    @MainActor private func act(_ verb: String, body: [String: Any] = [:]) async -> Bool {
        guard case let .following(alert) = phase, let saved = store.entry(for: code) else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let data = try await client.data(for: request("POST", "/v1/safety/alerts/\(alert.id)/\(verb)",
                                                          token: saved.token, body: body))
            phase = .following(try ClipSafetyCoding.decoder().decode(ClipSafetyAlertResponse.self, from: data).alert)
            return true
        } catch {
            self.error = message(for: error)
            return false
        }
    }

    /// Refreshes the alert every few seconds while it's open, so the guest sees staff pick it up and reply.
    @MainActor private func poll() async {
        guard followingID != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, case let .following(alert) = phase, let saved = store.entry(for: code),
                  let data = try? await client.data(for: request("GET", "/v1/safety/alerts/\(alert.id)", token: saved.token)),
                  let fresh = try? ClipSafetyCoding.decoder().decode(ClipSafetyAlertResponse.self, from: data).alert
            else { continue }
            if fresh != alert { phase = .following(fresh) }
            if !fresh.isActive { return }
        }
    }

    private func startOver() {
        store.forget(code)
        place = nil
        concerns = []
        details = ""
        Task { await start() }
    }

    private func message(for error: Error) -> String {
        switch (error as? AudienceKitError)?.status {
        case 429: "Too many alerts were just sent from here. Find any staff member for help."
        case 404: "This safety poster's code isn't in use any more. Find any staff member for help."
        case 409: "That didn't go through. Pull down or try again in a moment."
        default: error.localizedDescription
        }
    }
}
