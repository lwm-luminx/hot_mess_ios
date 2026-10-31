//
//  VenueChatViewModel.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation

@MainActor
@Observable
final class VenueChatViewModel {
    enum ConnectionState: Equatable, Sendable {
        case connecting
        case connected
        /// The room is only for people at the venue (or out in the locale), and
        /// the API doesn't have the user there. Reconnecting won't help until they are; "Try again" does.
        case notPresent
        case disconnected(String?)
    }

    /// A line the user sent that the room hasn't shown yet.
    struct PendingMessage: Identifiable, Equatable, Sendable {
        enum State: Equatable, Sendable {
            /// Waiting to join the room, or sent and waiting for the API.
            case sending
            /// `sendMyChatMessage` failed or didn't answer in time, or the
            /// room closed. The user can retry.
            case failed
        }

        let id: UUID
        let body: String
        let createdAt: Date
        var state: State
        /// Counts writes, so a timeout from an earlier try can't fail a resend.
        var attempt = 0
        /// The prompt it answers, sent as `promptId`.
        var prompt: ChatPrompt? = nil
    }

    /// How often to tell the API the user is still here while the room is open.
    /// The API counts a position as present for 15 minutes.
    static let presenceInterval: Duration = .seconds(240)

    /// How long a sent line waits for the API (or the room's echo) before it's shown as failed.
    static let echoTimeout: Duration = .seconds(10)

    private(set) var messages: [VenueMessage] = []
    /// The user's own lines, in the order sent, until the room echoes each one.
    /// They show at the end of the transcript, marked as sending or failed.
    private(set) var pending: [PendingMessage] = []
    private(set) var connectionState: ConnectionState = .connecting
    /// The user is in the room from outside its place, which only admins can do.
    private(set) var isOutOfRange = false
    /// Who is in the room now, by user ID: the roster the room sends on
    /// joining, kept up to date by its presence frames. Empty while offline.
    private(set) var onlineUserIDs: Set<UUID> = []
    /// What the room has said about the people in it, by user ID: names and
    /// avatars from its roster and presence frames. Empty while offline, and
    /// from servers that only send IDs.
    private(set) var roomPeople: [UUID: RoomPerson] = [:]
    /// People not in the room whom a notification still reaches, by user ID:
    /// a yellow dot. The server only says so about the user's friends, and to
    /// admins.
    private(set) var reachableUserIDs: Set<UUID> = []
    /// People who left the room in the last 30 minutes, by user ID, whom it
    /// keeps listing, offline, until each one's `recentUntil`. Nobody here
    /// now is in it.
    private(set) var recentPeople: [UUID: RecentRoomPerson] = [:]
    /// How each person on tonight's lineup can be reached, by their person
    /// (listing) ID lowercased, from the room's roster and lineup frames:
    /// in chat if anyone who manages the listing is, else by push, else
    /// offline. `nil` while offline, and from servers without lineup
    /// presence: the lineup then draws no dots.
    private(set) var lineupPresence: [String: PresenceState]?
    /// The tribes the user and each person here share, by user ID, for the
    /// "You're both" mark: from the roster, arrivals and their lines. Empty
    /// on an API without tribes, and for anyone the user shares none with.
    private(set) var sharedTribes: [UUID: [SharedTribe]] = [:]
    /// The announcement pinned under the room's title, from the history sent
    /// on joining and the room's pin frames; it can be older than the
    /// messages the room shows.
    private(set) var pinned: VenueMessage?
    /// Where the transcript marks what has cleared from what is current: an
    /// admin clearing the room, or (for its admins, who still see them) the
    /// messages older than the room shows everyone else.
    private(set) var clearMark: ChatClearMark?
    var draft: String = ""
    /// The prompt the next line answers, after "Answer" on the PromptBar or
    /// a PromptCard; the composer shows it as an answer chip.
    var answering: ChatPrompt?
    /// Why the API refused the last line, in its words: terms not accepted
    /// yet, or the content filter. The screen shows it, then clears it.
    var sendError: String?

    let room: ChatRoom
    /// Follows the room without being in it, for a ChatPeek: no presence is
    /// reported or recorded, and nothing can be sent.
    let isWatching: Bool

    /// The app's one cable, which the room's subscription rides with
    /// everything else realtime. Without it there's no chat.
    private let cable: AudienceCable?
    private let configuration: AppConfiguration
    let userID: UUID?
    /// The app's friends so far. The roster's full list of friends goes in,
    /// so friends show by full name everywhere.
    private let friends: FriendDirectory?
    /// Full names of the user's friends from the room's roster, for when
    /// there's no directory.
    private var rosterFriendNames: [UUID: String] = [:]
    private let reportPresence: @MainActor () async -> Void
    /// Whether to ask the room for shared tribes (`TribeStore.supportsTribes()`).
    private let supportsTribes: @MainActor () async -> Bool
    /// Sends lines (`sendMyChatMessage`) and names the audience the room's
    /// subscription runs in. Without it nothing can be sent.
    private let api: HotMessAPI?
    /// The room's subscription, while one is open.
    private var following: Task<Outcome, Never>?
    private var presenceTask: Task<Void, Never>?
    /// Drops the next of `recentPeople` when the room stops listing them.
    private var pruneTask: Task<Void, Never>?
    /// Bumped by `stop()`, so a `run()` waiting to reconnect knows it's over.
    private var generation = 0

    /// - Parameter reportPresence: reports the device's position, so the API
    ///   lets the user into the room and keeps them in it.
    /// - Parameter watch: follow the room without being in it (`isWatching`).
    init(
        room: ChatRoom,
        watch: Bool = false,
        configuration: AppConfiguration,
        userID: UUID?,
        cable: AudienceCable? = nil,
        friends: FriendDirectory? = nil,
        api: HotMessAPI? = nil,
        reportPresence: @escaping @MainActor () async -> Void = {},
        supportsTribes: @escaping @MainActor () async -> Bool = { false }
    ) {
        self.room = room
        self.isWatching = watch
        self.api = api
        self.configuration = configuration
        self.userID = userID
        self.cable = cable
        self.friends = friends
        self.reportPresence = reportPresence
        self.supportsTribes = supportsTribes
    }

    /// Lines typed while the room is still joining wait in `pending` and go out
    /// once it's joined.
    var canSend: Bool {
        guard !isWatching, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, userID != nil else {
            return false
        }

        switch connectionState {
        case .connecting, .connected: return true
        case .notPresent, .disconnected: return false
        }
    }

    func isOutgoing(_ message: VenueMessage) -> Bool {
        message.isOutgoing(for: userID)
    }

    /// The announcement pinned under the room's title: the one the room said
    /// is pinned, else (from older servers) the latest line marked as pinned.
    var pinnedAnnouncement: VenueMessage? {
        pinned ?? messages.last { $0.isPinned && $0.kind == .announcement }
    }

    /// Tonight's prompt under the room's title: the newest rotating prompt
    /// in the room's history.
    var pinnedPrompt: VenueMessage? {
        messages.last { $0.isPinnedPrompt && $0.prompt != nil }
    }

    /// The kinds of the prompts the room has shown, by prompt ID, so answers
    /// to trivia are labelled "Trivia".
    var promptKinds: [String: ChatPrompt.Kind] {
        Dictionary(
            messages.compactMap { message in message.prompt.map { ($0.id, $0.kind) } },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// How many lines in the room answer the prompt. The room only knows the
    /// lines it has sent, so on a long night it can be fewer than all of them.
    func answerCount(for prompt: ChatPrompt) -> Int {
        messages.filter { $0.kind == .text && $0.promptID == prompt.id }.count
    }

    /// "Answer": the next line answers the prompt.
    func answer(_ prompt: ChatPrompt) {
        guard !isWatching else { return }
        answering = prompt
    }

    /// The user ("You", while they're in the room), everyone else in the
    /// room now, for the Here now strip, then whoever was here in the last 30
    /// minutes, offline: friends first in each, then everyone else, each by
    /// name. A friend shows by their full name. Without names from the room
    /// (an older server), the name and avatar they last posted with.
    var hereNow: [HereNowPerson] {
        let directory = friends?.byID ?? [:]
        var ids = onlineUserIDs
        // The roster names the user too; a watcher isn't in the room.
        var viewer: HereNowPerson?
        if let userID {
            ids.remove(userID)
            if !isWatching, onlineUserIDs.contains(userID) || connectionState == .connected {
                viewer = HereNowPerson(
                    id: userID,
                    name: roomPeople[userID]?.name,
                    avatarURL: roomPeople[userID]?.avatarURL,
                    isFriend: false,
                    isViewer: true
                )
            }
        }

        func face(_ id: UUID, _ person: RoomPerson?, presence: PresenceState) -> HereNowPerson {
            let friendName = rosterFriendNames[id] ?? directory[id]?.name
            let posted = person?.name == nil || person?.avatarURL == nil
                ? messages.last(where: { $0.userID == id && !$0.isFromListing })
                : nil

            return HereNowPerson(
                id: id,
                name: friendName ?? person?.name ?? posted?.name,
                avatarURL: person?.avatarURL ?? posted?.avatarURL ?? directory[id]?.avatarURL,
                isFriend: person?.isFriend == true || friendName != nil,
                presence: presence,
                sharedTribes: sharedTribes(with: id)
            )
        }

        let now = Date.now
        let here = ids.map { face($0, roomPeople[$0], presence: .online) }
        let recent = recentPeople.values
            .filter { !ids.contains($0.id) && $0.id != userID && $0.recentUntil > now }
            .map { face($0.id, $0.person, presence: $0.presence) }

        return HereNowPerson.sorted(here + recent + (viewer.map { [$0] } ?? []))
    }

    /// Reports the position, subscribes to the room on the app's cable, and
    /// streams messages until the room closes or the server says the user
    /// isn't in the room's place. While it's open, the position is reported
    /// again every few minutes. A dropped or silent socket is the cable's to
    /// reconnect, and it rejoins the room when it does; if the server ends the
    /// room's subscription, this subscribes again after a short wait that
    /// grows with each failure in a row, so the room keeps hearing who arrives.
    func run() async {
        guard let cable else {
            connectionState = .disconnected(String(localized: "Chat isn't available for this build."))
            return
        }

        let generation = self.generation
        var failures = 0
        while !Task.isCancelled, generation == self.generation {
            connectionState = .connecting
            if !isWatching {
                await reportPresence()
                guard !Task.isCancelled, generation == self.generation else { return }
                startReportingPresence()
            }

            let outcome: Outcome
            if let audienceID = await audienceID() {
                outcome = await follow(cable: cable, audienceID: audienceID)
            } else if api == nil {
                connectionState = .disconnected(String(localized: "Chat isn't available for this build."))
                return
            } else {
                outcome = .dropped
            }

            switch outcome {
            case .stopped, .notPresent:
                return
            case .joined:
                failures = 0
            case .dropped:
                failures += 1
            }

            do {
                try await Task.sleep(for: Self.reconnectDelay(afterFailures: failures))
            } catch {
                return
            }
        }
    }

    /// How long to wait before reconnecting: a second after a room that was
    /// joined, then doubling with each failure in a row, up to half a minute.
    nonisolated static func reconnectDelay(afterFailures failures: Int) -> Duration {
        .seconds(min(30, 1 << min(failures, 5)))
    }

    private enum Outcome {
        /// `stop()`, a new run or the session ending ended it.
        case stopped
        case notPresent
        /// The server ended the subscription after the room was joined.
        case joined
        /// It ended before the room was joined.
        case dropped
    }

    /// The audience the room's subscription runs in: the build's pinned ID,
    /// else the API's (from the session or the host). `nil`, with the room
    /// shown as disconnected, when it can't be worked out now.
    private func audienceID() async -> String? {
        if let audienceID = configuration.audienceID { return audienceID }
        guard let api else { return nil }

        do {
            return try await api.audienceID()
        } catch {
            connectionState = .disconnected(error.localizedDescription)
            return nil
        }
    }

    /// One subscription's life: joins the room on the cable and applies its
    /// events until it ends. It runs in a task of its own so `stop()` can end
    /// it; ending the iteration leaves the room, and the cable closes its
    /// socket once nothing else is on it.
    private func follow(cable: AudienceCable, audienceID: String) async -> Outcome {
        following?.cancel()
        let sharedTribes = await supportsTribes()
        let task = Task { [room, isWatching] in
            let subscription = await VenueChatConnection.subscribe(
                to: room, on: cable, audienceID: audienceID, watch: isWatching, sharedTribes: sharedTribes
            )
            return await self.apply(subscription)
        }
        following = task
        let outcome = await task.value
        if following == task { following = nil }
        return outcome
    }

    private func apply(_ subscription: AsyncStream<AudienceCable.Event>) async -> Outcome {
        var joined = false
        for await cableEvent in subscription {
            guard !Task.isCancelled else { return .stopped }
            for event in VenueChatConnection.events(from: cableEvent) {
                switch event {
                case .connected:
                    joined = true
                    connectionState = .connected
                    sendPending()
                case let .received(message):
                    receive(message)
                case let .range(outOfRange):
                    isOutOfRange = outOfRange
                case let .roster(online, people, friends, recent):
                    applyRoster(online: online, people: people, friends: friends, recent: recent)
                case let .presence(userID, online, name, avatarURL):
                    applyPresence(userID: userID, online: online, name: name, avatarURL: avatarURL)
                case let .lineupPresence(presence):
                    applyLineupPresence(presence)
                case let .sharedTribes(tribes):
                    sharedTribes.merge(tribes) { _, latest in latest }
                case let .reachable(userID):
                    applyPresence(userID: userID, online: false, name: nil, avatarURL: nil)
                    reachableUserIDs.insert(userID)
                case let .recent(userID, presence, until):
                    applyRecent(userID: userID, presence: presence, until: until)
                case let .history(messages, pinned, expiresBefore):
                    applyHistory(messages, pinned: pinned, expiresBefore: expiresBefore)
                case let .pin(id, announcement):
                    applyPin(id: id, announcement: announcement)
                case let .removed(id):
                    applyRemoval(id: id)
                case let .cleared(at, expired):
                    applyClear(at: at, expired: expired)
                case .notPresent:
                    connectionState = .notPresent
                    clearRoom()
                    failPending()
                    presenceTask?.cancel()
                    presenceTask = nil
                    generation += 1
                    return .notPresent
                case let .disconnected(reason, reconnects):
                    connectionState = .disconnected(reason)
                    clearRoom()
                    failPending()
                    guard reconnects else { return .stopped }
                    // The cable rejoins on its own; tell the API the user is
                    // still here first, so the room lets them back in.
                    if !isWatching {
                        Task { [reportPresence] in await reportPresence() }
                    }
                }
            }
        }
        if Task.isCancelled { return .stopped }
        return joined ? .joined : .dropped
    }

    /// After "only for people at …": report the position again and reconnect.
    func retry() async {
        await stop()
        await run()
    }

    /// Shows the line straight away as sending. It goes out now if the room is
    /// joined, or as soon as it is.
    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard canSend, !body.isEmpty else { return }

        draft = ""

        let message = PendingMessage(id: UUID(), body: body, createdAt: .now, state: .sending, prompt: answering)
        answering = nil
        pending.append(message)

        if connectionState == .connected {
            await deliver(message.id)
        }
    }

    /// Tries a failed line again, reconnecting first if the room has closed.
    func resend(_ id: UUID) async {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }

        pending[index].state = .sending

        switch connectionState {
        case .connected:
            await deliver(id)
        case .connecting:
            break
        case .disconnected, .notPresent:
            // `run()` sends every pending line once the room is joined again.
            await reconnect()
        }
    }

    func stop() async {
        generation += 1
        presenceTask?.cancel()
        presenceTask = nil
        following?.cancel()
        following = nil
    }

    // MARK: - Who's here

    /// The room's list of who's in it, sent on joining. Everyone it names is
    /// in the room, even if `online` (from an older server) left them out.
    /// `recent` is who left lately, listed until their `recentUntil`.
    func applyRoster(
        online: Set<UUID>,
        people: [RoomPerson],
        friends roster: [Friend],
        recent: [RecentRoomPerson] = [],
        now: Date = .now
    ) {
        roomPeople = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        onlineUserIDs = online.union(people.map(\.id))
        let here = onlineUserIDs
        recentPeople = Dictionary(
            recent.filter { !here.contains($0.id) && $0.recentUntil > now }.map { ($0.id, $0) },
            uniquingKeysWith: { latest, _ in latest }
        )
        schedulePrune()

        for friend in roster {
            rosterFriendNames[friend.id] = friend.name
        }
        friends?.rememberNames(roster)
    }

    /// The lineup's presence, the whole list each time.
    func applyLineupPresence(_ presence: [String: PresenceState]) {
        lineupPresence = presence
    }

    /// Someone joined or left. A join keeps what's already known about them
    /// unless the frame says otherwise.
    func applyPresence(userID: UUID, online: Bool, name: String?, avatarURL: URL?) {
        reachableUserIDs.remove(userID)
        // Back in the room, or gone for good: either way not "here recently".
        let recent = recentPeople.removeValue(forKey: userID)
        guard online else {
            onlineUserIDs.remove(userID)
            roomPeople[userID] = nil
            return
        }

        onlineUserIDs.insert(userID)
        var person = roomPeople[userID] ?? recent?.person ?? RoomPerson(id: userID)
        if let name { person.name = name }
        if let avatarURL { person.avatarURL = avatarURL }
        roomPeople[userID] = person
    }

    /// Someone's last connection left: they're out of the room, but it keeps
    /// listing them (with what's known about them) until `until`, offline,
    /// or with the yellow dot when a notification still reaches them.
    func applyRecent(userID: UUID, presence: PresenceState, until: Date, now: Date = .now) {
        let person = roomPeople[userID] ?? recentPeople[userID]?.person ?? RoomPerson(id: userID)
        applyPresence(userID: userID, online: false, name: nil, avatarURL: nil)
        if presence == .push {
            reachableUserIDs.insert(userID)
        }
        guard until > now, userID != self.userID else { return }

        recentPeople[userID] = RecentRoomPerson(person: person, presence: presence, lastSeenAt: now, recentUntil: until)
        schedulePrune()
    }

    /// Drops whoever the room has stopped listing by `now`.
    func pruneRecent(now: Date = .now) {
        recentPeople = recentPeople.filter { $0.value.recentUntil > now }
        schedulePrune()
    }

    /// Wakes when the next of `recentPeople` is due to go, so the strip drops
    /// them on time without another frame from the room. A host's can be
    /// hours away; the sleep's clock keeps counting while the app is
    /// suspended, so it fires (late at worst) on coming back, and `hereNow`
    /// leaves out anyone past their time meanwhile.
    private func schedulePrune() {
        pruneTask?.cancel()
        guard let next = recentPeople.values.map(\.recentUntil).min() else {
            pruneTask = nil
            return
        }

        pruneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.pruneRecent()
        }
    }

    // MARK: - History and pins

    /// What the room sent on joining: it replaces what was shown before, so a
    /// reconnect doesn't repeat lines. The user's own lines still on their
    /// way stay pending.
    func applyHistory(_ history: [VenueMessage], pinned: VenueMessage?, expiresBefore: Date? = nil) {
        messages = history
        self.pinned = pinned
        // Only admins are sent lines older than the room shows: they get the
        // divider between those and tonight's.
        clearMark = expiresBefore.flatMap { cutoff in
            history.contains { $0.sentAt < cutoff } ? ChatClearMark(at: cutoff, kind: .expired) : nil
        }
        reachableUserIDs = Set(history.filter { $0.presence == .push && !$0.isFromListing }.map(\.userID))
        history.forEach(noteSharedTribes)
    }

    /// The tribes the user shares with the sender of a line, when the room
    /// said. A post as the venue or a listing says nothing about the person.
    private func noteSharedTribes(_ message: VenueMessage) {
        guard let tribes = message.sharedTribes, !message.isFromListing, !isOutgoing(message) else { return }
        sharedTribes[message.userID] = tribes
    }

    /// What the user shares with someone here, for the mark and the line.
    func sharedTribes(with userID: UUID) -> [SharedTribe] {
        userID == self.userID ? [] : sharedTribes[userID] ?? []
    }

    /// An announcement was pinned, replacing whichever was, or unpinned.
    func applyPin(id: UUID, announcement: VenueMessage?) {
        for index in messages.indices where messages[index].isPinned || messages[index].id == id {
            messages[index].isPinned = announcement != nil && messages[index].id == id
        }

        if let announcement {
            pinned = announcement
        } else if pinned?.id == id {
            pinned = nil
        }
    }

    /// An admin removed a message: it goes from the transcript, and from under
    /// the room's title if it was the pinned announcement.
    func applyRemoval(id: UUID) {
        messages.removeAll { $0.id == id }
        if pinned?.id == id {
            pinned = nil
        }
    }

    /// An admin cleared the room: every line sent up to `at` goes, the pinned
    /// announcement too, and the transcript marks where it was cleared. Lines
    /// that expired go quietly, leaving the pin. The user's own unsent lines
    /// stay either way.
    func applyClear(at: Date? = nil, expired: Bool = false) {
        if let at {
            messages.removeAll { $0.sentAt <= at }
        } else {
            messages = []
        }
        if expired {
            if let mark = clearMark, !messages.contains(where: { $0.sentAt < mark.at }) {
                clearMark = nil
            }
        } else {
            pinned = nil
            clearMark = ChatClearMark(at: at ?? .now, kind: .cleared)
        }
    }

    private func clearRoom() {
        onlineUserIDs = []
        roomPeople = [:]
        reachableUserIDs = []
        recentPeople = [:]
        lineupPresence = nil
        sharedTribes = [:]
        pruneTask?.cancel()
        pruneTask = nil
    }

    // MARK: - Sending

    private func reconnect() async {
        await stop()
        Task { await run() }
    }

    /// Sends the lines that waited for the room, in order, without holding
    /// up the room's events while the API answers.
    private func sendPending() {
        let ids = pending.filter { $0.state == .sending }.map(\.id)
        guard !ids.isEmpty else { return }

        Task {
            for id in ids {
                await deliver(id)
            }
        }
    }

    /// Sends the line with `sendMyChatMessage`, and fails it if the API
    /// refuses it or hasn't answered in time.
    private func deliver(_ id: UUID) async {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }

        pending[index].attempt += 1
        let attempt = pending[index].attempt
        let body = pending[index].body
        let promptID = pending[index].prompt?.id

        guard let api else {
            markFailed(id, attempt: attempt)
            return
        }

        Task { [weak self] in
            try? await Task.sleep(for: Self.echoTimeout)
            self?.markFailed(id, attempt: attempt)
        }

        do {
            settle(id, with: try await api.sendMyChatMessage(body, in: room, promptID: promptID))
        } catch {
            Log.realtime.error("Chat line not sent: \(error.localizedDescription, privacy: .public)")
            markFailed(id, attempt: attempt)
            if let refusal = Self.refusalMessage(for: error) {
                sendError = refusal
            }
        }
    }

    /// What the API said when it refused a line on purpose (the terms gate,
    /// the content filter), which is worth showing; `nil` for being offline
    /// or a server fault, which the line's "Not sent. Tap to retry." covers.
    static func refusalMessage(for error: any Error) -> String? {
        let message: String
        switch error as? APIError {
        case let .transport(text)?, let .termsNotAccepted(text)?: message = text
        default: return nil
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The API took the line: it leaves `pending` and shows as the room will
    /// show it, unless the room's echo got here first.
    func settle(_ id: UUID, with message: VenueMessage) {
        pending.removeAll { $0.id == id }
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
        }
    }

    /// A line the API hasn't answered for yet can come back from the room
    /// first. Nothing in it names the pending line beyond who sent it, so it
    /// settles the oldest pending line with the same text. Once a line is
    /// shown (the mutation answered first), its echo only updates it.
    func receive(_ message: VenueMessage) {
        if isOutgoing(message),
           !messages.contains(where: { $0.id == message.id }),
           let index = pending.firstIndex(where: { $0.body == message.body }) {
            pending.remove(at: index)
        }

        switch message.presence {
        case .push where !message.isFromListing: reachableUserIDs.insert(message.userID)
        case .online: reachableUserIDs.remove(message.userID)
        default: break
        }
        if message.isPinned, message.kind == .announcement {
            pinned = message
        }
        noteSharedTribes(message)

        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func markFailed(_ id: UUID, attempt: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }),
              pending[index].state == .sending,
              pending[index].attempt == attempt
        else { return }

        pending[index].state = .failed
    }

    private func failPending() {
        for index in pending.indices where pending[index].state == .sending {
            pending[index].state = .failed
        }
    }

    private func startReportingPresence() {
        presenceTask?.cancel()
        presenceTask = Task { [reportPresence] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.presenceInterval)
                guard !Task.isCancelled else { return }
                await reportPresence()
            }
        }
    }
}
