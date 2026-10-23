import SwiftUI

/// Resolves the specific Ping using the viewer's existing visibility rules.
struct SharedPingScreen: View {
    let pingID: UUID
    let invitationToken: String?
    @State private var invitation: ShareInvitation?
    @Environment(AppModel.self) private var model
    @State private var ping: Ping?
    @State private var loading = true
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let ping {
                    FriendPingCard(ping: ping, userID: model.session.user?.id, isBusy: busy,
                        join: { target in Task { await join(target) } },
                        leave: { Task { await leave() } })
                    if ping.isMine { Text("This is your Ping.").foregroundStyle(.secondary) }
                } else if let invitation {
                    Text(invitation.title).font(.title2.bold())
                    if let note = invitation.note { Text(note) }
                    ForEach(invitation.targets) { Text($0.name) }
                    Text("Ends \(invitation.expiresAt.formatted(date: .omitted, time: .shortened))")
                    Button("I'm in") { Task { await joinInvitation() } }
                        .buttonStyle(.borderedProminent).disabled(busy || invitation.expiresAt <= .now)
                    if let message { Text(message).foregroundStyle(.red) }
                } else if loading { ProgressView("Loading Ping…") }
                else {
                    ContentUnavailableView("Ping unavailable", systemImage: "sparkles",
                        description: Text(message ?? "It may have ended, or its privacy settings don't include you."))
                }
                if ping != nil, let message { Text(message).foregroundStyle(.red) }
            }.padding()
        }
        .navigationTitle("Ping")
        .task(id: pingID) { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do {
            // An ended or altered link still shows the Ping when it's a friend's.
            if let invitationToken {
                do {
                    invitation = try await ShareInvitation.load(path: "/pings/\(pingID.uuidString.lowercased())",
                        token: invitationToken, client: model.audienceKit)
                } catch { message = error.localizedDescription }
            }
            let result = try await model.api.pings()
            ping = ([result.myPing].compactMap { $0 } + result.friendPings)
                .first { UUID(uuidString: $0.id) == pingID }
            if ping != nil { message = nil }
        } catch { message = error.localizedDescription }
    }
    @MainActor private func joinInvitation() async {
        guard !busy, let invitationToken else { return }
        busy = true
        defer { busy = false }
        do {
            ping = try await model.api.joinPing(pingID.uuidString.lowercased(), invitationToken: invitationToken)
            model.pingsChanged()
        } catch { message = error.localizedDescription }
    }
    @MainActor private func join(_ target: PingTarget?) async {
        guard !busy, let ping, !ping.isMine else { return }
        busy = true
        defer { busy = false }
        do {
            self.ping = try await model.api.joinPing(ping.id, targetID: target?.id)
            model.pingsChanged()
        } catch { message = error.localizedDescription }
    }
    @MainActor private func leave() async {
        guard !busy, let ping, !ping.isMine else { return }
        busy = true
        defer { busy = false }
        do {
            self.ping = try await model.api.leavePing(ping.id)
            model.pingsChanged()
        } catch { message = error.localizedDescription }
    }
}
