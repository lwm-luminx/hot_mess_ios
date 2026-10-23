//
//  VenueChatScreen.swift
//  HotMess
//

import AudienceKitUI
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
    /// The venue's group trivia, for the round card above the composer.
    @State private var trivia: VenueTriviaModel?

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
        // The venue's group trivia, while the room is open.
        .task(id: room.kind == .venue && model.safety.hasAcceptedTerms && scenePhase == .active) {
            guard room.kind == .venue, model.safety.hasAcceptedTerms, scenePhase == .active else { return }
            let current = trivia ?? VenueTriviaModel(api: model.api, venueID: room.id)
            trivia = current
            await current.run()
        }
        .alert(
            String(localized: "Your vote didn't count"),
            isPresented: Binding(
                get: { trivia?.voteError != nil },
                set: { if !$0 { trivia?.voteError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(trivia?.voteError ?? "")
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
                        clearMark: viewModel.clearMark
                    )
                }
                // A venue post may be a trivia round going up or its reveal.
                .onChange(of: viewModel.messages.last?.id) {
                    Task { await trivia?.refresh() }
                }
                if let trivia, let round = trivia.round {
                    TriviaRoundCard(
                        round: round,
                        onVote: viewModel.connectionState == .notPresent ? nil : { await trivia.vote($0) }
                    )
                    .audiencePreset(model.brand.preset)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                composer(viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
    /// have ended, and people the user blocked, are left out, and so are
    /// rotating prompts, which show under the title, and PromptCards the
    /// user said "Not now" to.
    private func threadMessages(_ viewModel: VenueChatViewModel, at date: Date) -> [ChatThreadMessage] {
        let friends = model.friends.byID
        let blocked = model.safety.blockedIDs
        let promptKinds = viewModel.promptKinds
        let sent = viewModel.messages
            .filter { $0.isShowing(at: date) }
            .filter { $0.isFromListing || !blocked.contains($0.userID) }
            .filter { !$0.isPinnedPrompt && !dismissedPrompts.contains($0.id.uuidString) }
            // The trivia round being shown has its card above the composer.
            .filter { $0.id.uuidString.lowercased() != trivia?.round?.messageID?.lowercased() }
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
