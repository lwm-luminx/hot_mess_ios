//
//  VenueChatScreen.swift
//  HotMess
//

import SwiftUI
import UIKit

/// A venue's chat room, replacing `VenueConversationViewController` and the
/// 1,300-line `OldVenueConversationViewController` beside it. Both were built
/// around a collection view whose cells were commented out, and the working one
/// dequeued a cell with an empty reuse identifier — a guaranteed crash the
/// moment a message arrived.
///
/// It also serves a locale's room, for people out in the locale who aren't at
/// a venue.
struct VenueChatScreen: View {
    let room: ChatRoom

    init(room: ChatRoom) {
        self.room = room
    }

    init(venue: Venue) {
        room = .venue(venue)
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var model
    @State private var viewModel: VenueChatViewModel?
    /// Whether the user has agreed to the terms is read before the room opens.
    @State private var isCheckingTerms = true
    @State private var reportTarget: ChatThreadMessage?
    /// Reported; thanked once the report sheet has gone.
    @State private var didReport = false
    @State private var blockTarget: ChatThreadMessage?
    @State private var deleteTarget: ChatThreadMessage?
    @State private var failureMessage: String?
    @State private var isPromptingFacebook = false
    @State private var isConnectingFacebook = false
    @State private var isThankingForReport = false
    /// Someone in the Here now strip being reported or blocked.
    @State private var personReport: ReportSubject?
    @State private var personBlock: BlockedUser?
    /// PromptCards the user put away with "Not now", by message ID: hidden
    /// for them only.
    @State private var dismissedPrompts: Set<String> = []
    /// Whose profile sheet is open, from their avatar or name in the thread
    /// or their face in the Here now strip.
    @State private var profileTarget: ChatProfile?
    /// What the profile sheet asked for, done once it has gone: nothing
    /// else can present over it.
    @State private var afterProfile: ProfileFollowUp?
    @State private var isPinging = false
    /// People muted in this room, on this device only (`ChatMutes`).
    @State private var mutedIDs: Set<UUID> = []
    /// Friend requests sent from profile sheets while the room is open. The
    /// room's roster doesn't say who has asked whom.
    @State private var friendRequests: [UUID: FriendRequestStatus] = [:]
    @State private var sendingFriendRequestTo: UUID?
    @State private var friendRequestError: String?

    private enum ProfileFollowUp {
        case ping
        case report(ChatProfile)
        case block(ChatProfile)
    }

    var body: some View {
        Group {
            if isCheckingTerms {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.safety.hasAcceptedTerms {
                ChatTermsPrompt {
                    try await model.safety.acceptTerms()
                }
            } else {
                roomContent(viewModel)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            mutedIDs = ChatMutes(room: room).load()
            await model.safety.load()
            isCheckingTerms = false
        }
        // Rejoin on foregrounding: iOS may suspend the socket while another app is open.
        // Keep the model so the draft and pending lines survive the transition.
        .task(id: model.safety.hasAcceptedTerms && scenePhase == .active) {
            guard model.safety.hasAcceptedTerms else {
                await viewModel?.stop()
                return
            }
            guard scenePhase == .active else {
                await viewModel?.stop()
                return
            }
            let current = viewModel ?? makeViewModel()
            self.viewModel = current
            await current.stop()
            guard !Task.isCancelled else { return }
            await current.run()
        }
        .onDisappear {
            let viewModel = self.viewModel
            Task { await viewModel?.stop() }
        }
        .sheet(item: $reportTarget, onDismiss: thankIfReported) { message in
            ReportSheet(
                question: String(localized: "Why are you reporting this message?"),
                blockable: blockable(message)
            ) { reason, block in
                try await report(message, reason: reason, block: block)
            }
        }
        .alert(
            blockTitle(blockTarget),
            isPresented: isPresenting($blockTarget),
            presenting: blockTarget
        ) { message in
            Button(String(localized: "Block"), role: .destructive) {
                Task { await block(message) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("Their messages will be removed from your feed instantly and our moderation team will be notified to review the content.")
        }
        .confirmationDialog(
            String(localized: "Delete this message?"),
            isPresented: isPresenting($deleteTarget),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { message in
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await delete(message) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("It's removed for everyone in the room.")
        }
        .alert(String(localized: "Thanks for reporting it"), isPresented: $isThankingForReport) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Our moderation team will review it within 24 hours.")
        }
        .contentReporting(report: $personReport, block: $personBlock)
        .sheet(item: $profileTarget, onDismiss: runProfileFollowUp) { profile in
            profileSheet(profile)
        }
        .sheet(isPresented: $isPinging) {
            // There's no ping to one person: it tells the user's friends,
            // with this room's venue picked.
            PingSheet(place: room.kind == .venue ? .venue(room.id) : nil)
                .environment(model)
        }
        .alert(
            String(localized: "Message Not Sent"),
            isPresented: Binding(
                get: { viewModel?.sendError != nil },
                set: { if !$0 { viewModel?.sendError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel?.sendError ?? "")
        }
        .alert(
            String(localized: "Something went wrong"),
            isPresented: isPresenting($failureMessage),
            presenting: failureMessage
        ) { _ in
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert(
            String(localized: "Connect Facebook to See Friends"),
            isPresented: $isPromptingFacebook
        ) {
            Button(String(localized: "Connect Facebook")) {
                Task {
                    isConnectingFacebook = true
                    defer { isConnectingFacebook = false }
                    do {
                        if try await model.connectFacebook() {
                            if let viewModel {
                                performChatSend(viewModel)
                            }
                        }
                    } catch {
                        failureMessage = error.localizedDescription
                    }
                }
            }
            Button(String(localized: "Send Anyway")) {
                if let viewModel {
                    performChatSend(viewModel)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Connecting Facebook is required to see your friends in chat and know when they're out.")
        }
    }

    @ViewBuilder
    private func roomContent(_ viewModel: VenueChatViewModel?) -> some View {
        VStack(spacing: 0) {
            if let viewModel, viewModel.connectionState == .notPresent {
                notPresent(viewModel)
            } else if let viewModel {
                if let kind = bannerKind(viewModel) {
                    RoomBanner(kind: kind, roomName: room.name, isLocale: room.kind == .locale)
                }
                // Who is here: the venue, which is always in its own room,
                // then everyone else, friends first. Above the pinned
                // announcement, which the thread draws at its top.
                let blocked = model.safety.blockedIDs
                let hereNow = viewModel.hereNow.filter { !blocked.contains($0.id) }
                let place = room.kind == .venue ? HereNowPlace(name: room.name, photoURL: room.photoURL) : nil
                if place != nil || !hereNow.isEmpty {
                    HereNowStrip(
                        place: place,
                        people: hereNow,
                        onReport: { person in
                            personReport = ReportSubject(
                                target: .person,
                                targetID: person.id.uuidString.lowercased(),
                                sender: BlockedUser(id: person.id, name: person.name, avatarURL: person.avatarURL)
                            )
                        },
                        onBlock: { person in
                            personBlock = BlockedUser(id: person.id, name: person.name, avatarURL: person.avatarURL)
                        },
                        onSelect: { person in
                            profileTarget = ChatProfile(id: person.id, name: person.name, avatarURL: person.avatarURL)
                        }
                    )
                }
                // Each minute, so a special leaves the room when it ends,
                // and a trivia answer shows at its reveal time.
                TimelineView(.everyMinute) { timeline in
                    let messages = threadMessages(viewModel, at: timeline.date)
                    let prompt = viewModel.pinnedPrompt?.prompt
                    ChatThreadView(
                        messages: messages,
                        roomName: room.name,
                        pinned: pinned(viewModel, in: messages),
                        onRetry: { id in
                            guard let id = UUID(uuidString: id) else { return }
                            Task { await viewModel.resend(id) }
                        },
                        onReport: { reportTarget = $0 },
                        onBlock: { blockTarget = $0 },
                        onDelete: { deleteTarget = $0 },
                        prompt: prompt,
                        promptAnswers: prompt.map { viewModel.answerCount(for: $0) } ?? 0,
                        now: timeline.date,
                        onAnswer: { viewModel.answer($0) },
                        onDismissPrompt: { message in
                            dismissedPrompts.insert(message.id)
                            if viewModel.answering?.id == message.promptCard?.id {
                                viewModel.answering = nil
                            }
                        },
                        clearMark: viewModel.clearMark,
                        onOpenProfile: { openProfile($0) }
                    )
                }
                composer(viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Profile sheet

    private func profileSheet(_ profile: ChatProfile) -> some View {
        ChatProfileSheet(
            profile: profile,
            isOnline: viewModel?.onlineUserIDs.contains(profile.id) == true,
            friendState: friendState(of: profile.id),
            isSendingFriendRequest: sendingFriendRequestTo == profile.id,
            isMuted: mutedIDs.contains(profile.id),
            onPing: { closeProfile(then: .ping) },
            onAddFriend: { Task { await sendFriendRequest(to: profile) } },
            onToggleMute: { toggleMute(profile) },
            onReport: { closeProfile(then: .report(profile)) },
            onBlock: { closeProfile(then: .block(profile)) }
        )
        // Over the sheet, which the screen's own alerts can't show above.
        .alert(
            String(localized: "Couldn't send a friend request"),
            isPresented: isPresenting($friendRequestError),
            presenting: friendRequestError
        ) { _ in
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// Someone's avatar or name in the thread: people posting as themselves
    /// only (`opensProfile`), never the venue, a listing or a prompt.
    private func openProfile(_ message: ChatThreadMessage) {
        guard message.opensProfile, let id = UUID(uuidString: message.authorID) else { return }
        profileTarget = ChatProfile(id: id, name: message.authorName, avatarURL: message.avatarURL, message: message)
    }

    private func friendState(of id: UUID) -> ChatFriendState {
        if model.friends.byID[id] != nil || friendRequests[id] == .accepted { return .friends }
        return friendRequests[id] == nil ? .notFriends : .requested
    }

    private func closeProfile(then followUp: ProfileFollowUp) {
        afterProfile = followUp
        profileTarget = nil
    }

    /// Ping, Report or Block, once the profile sheet has gone. Report and
    /// Block are the room's own: on the message the sheet opened from, or
    /// on the person from the Here now strip.
    private func runProfileFollowUp() {
        guard let followUp = afterProfile else { return }
        afterProfile = nil

        switch followUp {
        case .ping:
            isPinging = true
        case let .report(profile):
            if let message = profile.message {
                reportTarget = message
            } else {
                personReport = ReportSubject(
                    target: .person,
                    targetID: profile.id.uuidString.lowercased(),
                    sender: BlockedUser(id: profile.id, name: profile.name, avatarURL: profile.avatarURL)
                )
            }
        case let .block(profile):
            if let message = profile.message {
                blockTarget = message
            } else {
                personBlock = BlockedUser(id: profile.id, name: profile.name, avatarURL: profile.avatarURL)
            }
        }
    }

    /// "Mute in this chat": hides their messages in this room, on this
    /// device. Nobody else is told.
    private func toggleMute(_ profile: ChatProfile) {
        let muted = !mutedIDs.contains(profile.id)
        mutedIDs = ChatMutes(room: room).set(profile.id, muted: muted)
    }

    private func sendFriendRequest(to profile: ChatProfile) async {
        guard sendingFriendRequestTo == nil else { return }
        sendingFriendRequestTo = profile.id
        defer { sendingFriendRequestTo = nil }

        do {
            friendRequests[profile.id] = try await model.api.sendFriendRequest(to: profile.id)
        } catch APIError.notFound {
            // The API only connects people contact matching found.
            friendRequestError = String(localized: "You can add someone as a friend when you each have the other's number saved.")
        } catch {
            friendRequestError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Reporting and blocking

    /// Files the report from the sheet, blocking the sender too when asked.
    /// Throws when it didn't go through, which the sheet shows.
    private func report(_ message: ChatThreadMessage, reason: ChatReportReason, block: Bool) async throws {
        guard let id = UUID(uuidString: message.id) else { return }
        // A post as the venue (or a prompt, the audience's) has no sender to
        // block; the API ignores `block` for it.
        let author: BlockedUser? = message.isFromPlace || message.isFromAudience ? nil : sender(of: message)
        try await model.safety.report(messageID: id, sender: author, reason: reason, block: block && author != nil)
        didReport = true
    }

    /// Who the sheet offers to block too: the sender, unless it's the venue or they're already blocked.
    private func blockable(_ message: ChatThreadMessage) -> BlockedUser? {
        guard !message.isFromPlace, !message.isFromAudience,
              !model.safety.isBlocked(UUID(uuidString: message.authorID)) else { return nil }
        return sender(of: message)
    }

    private func thankIfReported() {
        if didReport {
            didReport = false
            isThankingForReport = true
        }
    }

    private func block(_ message: ChatThreadMessage) async {
        guard let sender = sender(of: message) else { return }

        do {
            if let id = UUID(uuidString: message.id) {
                try await model.safety.report(messageID: id, sender: sender, reason: .other, block: true)
            } else {
                try await model.safety.block(sender)
            }
        } catch {
            failureMessage = String(localized: "Couldn't block them. Please try again.")
        }
    }

    /// Takes back the user's own message. The room's removal frame drops it
    /// for everyone else; it goes from this screen at once.
    private func delete(_ message: ChatThreadMessage) async {
        guard let id = UUID(uuidString: message.id) else { return }

        do {
            try await model.api.removeMyChatMessage(id)
            viewModel?.applyRemoval(id: id)
        } catch {
            failureMessage = String(localized: "Couldn't delete it. Please try again.")
        }
    }

    private func sender(of message: ChatThreadMessage) -> BlockedUser? {
        UUID(uuidString: message.authorID).map { BlockedUser(id: $0, name: message.authorName, avatarURL: message.avatarURL) }
    }

    private func blockTitle(_ message: ChatThreadMessage?) -> String {
        if let name = message?.authorName, !name.isEmpty {
            return String(localized: "Block \(name)")
        }
        return String(localized: "Block")
    }

    /// A Bool binding for an optional, for dialogs presenting one.
    private func isPresenting<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }

    // MARK: - Pieces

    /// The server only lets people at the venue (or out in the locale) into its room.
    private func notPresent(_ viewModel: VenueChatViewModel) -> some View {
        ContentUnavailableView {
            switch room.kind {
            case .venue:
                Label(String(localized: "Only for people at \(room.name)"), systemImage: "location.slash")
            case .locale:
                Label(String(localized: "Only for people out in \(room.name)"), systemImage: "location.slash")
            }
        } description: {
            switch room.kind {
            case .venue:
                Text("The room opens when you're there. Your location has to be on so Hot Mess can tell.")
            case .locale:
                Text("The room opens when you're out in \(room.name) and not at a venue. Venues have their own chat. Your location has to be on so Hot Mess can tell.")
            }
        } actions: {
            Button(String(localized: "Try again")) {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Admins can join from anywhere; say when they couldn't have otherwise.
    /// That wins over the connection strip.
    private func bannerKind(_ viewModel: VenueChatViewModel) -> RoomBanner.Kind? {
        if viewModel.isOutOfRange { return .range }

        switch viewModel.connectionState {
        case .connecting: return .connecting
        case let .disconnected(reason): return .offline(reason)
        case .connected, .notPresent: return nil
        }
    }

    /// The room's messages, then the reader's own lines still on their way.
    /// Friends show by their full name, everyone in the room now with a green
    /// dot, and friends a notification reaches with a yellow one. Specials that
    /// have ended, and people the user blocked or muted here, are left out, and so are
    /// rotating prompts, which show under the title, and PromptCards the
    /// user said "Not now" to.
    private func threadMessages(_ viewModel: VenueChatViewModel, at date: Date) -> [ChatThreadMessage] {
        let friends = model.friends.byID
        let blocked = model.safety.blockedIDs
        let promptKinds = viewModel.promptKinds
        let muted = mutedIDs
        let sent = viewModel.messages
            .filter { $0.isShowing(at: date) }
            .filter { $0.isFromListing || !blocked.contains($0.userID) }
            // Muted in this room: their own lines, not their posts as a listing.
            .filter { $0.isFromListing || !muted.contains($0.userID) }
            .filter { !$0.isPinnedPrompt && !dismissedPrompts.contains($0.id.uuidString) }
            .map { message in
                message.threadMessage(
                    currentUserID: viewModel.userID,
                    friends: friends,
                    online: viewModel.onlineUserIDs,
                    reachable: viewModel.reachableUserIDs,
                    promptKinds: promptKinds
                )
            }

        let pending = viewModel.pending.map { message in
            ChatThreadMessage(
                id: message.id.uuidString,
                authorID: viewModel.userID?.uuidString ?? "",
                authorName: nil,
                avatarURL: nil,
                text: message.body,
                sentAt: message.createdAt,
                isOwn: true,
                delivery: message.state == .failed ? .failed : .sending,
                promptLabel: message.prompt?.label
            )
        }

        return sent + pending
    }

    /// The pinned announcement, as the thread draws it.
    private func pinned(_ viewModel: VenueChatViewModel, in messages: [ChatThreadMessage]) -> ChatThreadMessage? {
        guard let pinned = viewModel.pinnedAnnouncement else { return nil }
        let id = pinned.id.uuidString
        // A pinned announcement can be older than the lines the room shows.
        return messages.first { $0.id == id && $0.announcementTitle != nil }
            ?? pinned.threadMessage(
                currentUserID: viewModel.userID,
                friends: model.friends.byID,
                online: viewModel.onlineUserIDs,
                reachable: viewModel.reachableUserIDs
            )
    }

    private func composer(_ viewModel: VenueChatViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return ChatComposer(
            text: $viewModel.draft,
            canSend: viewModel.canSend && !isConnectingFacebook,
            answering: viewModel.answering,
            stopAnswering: { viewModel.answering = nil }
        ) {
            handleChatSend(viewModel)
        }
    }

    private func handleChatSend(_ viewModel: VenueChatViewModel) {
        if !model.safety.hasFacebook && !model.hasPromptedFacebookOnChat {
            model.hasPromptedFacebookOnChat = true
            isPromptingFacebook = true
            return
        }
        performChatSend(viewModel)
    }

    private func performChatSend(_ viewModel: VenueChatViewModel) {
        Task { await viewModel.send() }
    }

    private func makeViewModel() -> VenueChatViewModel {
        if let viewModel { return viewModel }

        return VenueChatViewModel(
            room: room,
            configuration: model.configuration,
            userID: model.session.userID,
            cable: model.cable,
            friends: model.friends,
            api: model.api,
            reportPresence: { [location = model.location] in await location.reportCurrentPosition() }
        )
    }
}
