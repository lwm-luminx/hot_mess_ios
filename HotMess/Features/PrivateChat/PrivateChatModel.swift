//
//  PrivateChatModel.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation

/// One Ping or Quickie chat while it's on screen: its lines (in memory only,
/// never saved), new ones over the app's cable (`privateChat`), and sending.
/// `fetch` reads the chat from the ping or pairing; it's nil until there's a
/// chat and again once it has closed.
@MainActor
@Observable
final class PrivateChatModel {
    private(set) var chat: PrivateChat?
    private(set) var messages: [PrivateChatMessage] = []
    private(set) var isLoaded = false
    private(set) var isClosed = false
    private(set) var isSending = false
    var draft = ""
    var errorMessage: String?

    @ObservationIgnored private let api: HotMessAPI
    @ObservationIgnored private let cable: AudienceCable?
    @ObservationIgnored private let fetch: @Sendable (HotMessAPI) async throws -> PrivateChat?

    init(api: HotMessAPI, cable: AudienceCable?, fetch: @escaping @Sendable (HotMessAPI) async throws -> PrivateChat?) {
        self.api = api
        self.cable = cable
        self.fetch = fetch
    }

    func load() async {
        do {
            if let fetched = try await fetch(api) {
                chat = fetched
                messages = PrivateChatMessage.merge(messages, fetched.messages)
            } else if chat != nil {
                // It was open and now isn't: it ended, and what was said is gone.
                close()
            }
        } catch is CancellationError {
        } catch {
            if !isLoaded { errorMessage = NowViewModel.message(for: error) }
        }
        isLoaded = true
    }

    /// Loads, then follows the cable while the view is up, reloading after
    /// every (re)connect and at the closing time.
    func run() async {
        await load()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.watchClosing() }
            group.addTask { await self.follow() }
        }
    }

    private func follow() async {
        guard let cable, let audienceID = try? await api.audienceID() else { return }
        var failures = 0
        while !Task.isCancelled, !isClosed {
            let events = await cable.subscribe(
                query: HotMessAPI.Documents.privateChatSubscription,
                operationName: "PrivateChat",
                audienceID: audienceID
            )
            var connected = false
            loop: for await event in events {
                guard !Task.isCancelled, !isClosed else { break }
                for frame in PrivateChatFrames.frames(from: event) {
                    switch frame {
                    case .connected:
                        connected = true
                        failures = 0
                        await load()
                    case let .message(line):
                        receive(line)
                    case let .closed(chatID):
                        if chatID == chat?.id { close() }
                    case .refused:
                        break loop
                    case let .disconnected(reconnects):
                        if !reconnects { break loop }
                    }
                }
            }
            guard !Task.isCancelled, !isClosed else { return }
            // Ended or refused (an API without chats refuses): try again later, slower each time.
            failures = connected ? 0 : failures + 1
            try? await Task.sleep(for: AudienceCable.reconnectDelay(afterFailures: max(failures, 1)))
        }
    }

    private func watchClosing() async {
        while !Task.isCancelled, !isClosed {
            let closesAt = chat?.closesAt
            let wait = closesAt.map { $0.timeIntervalSinceNow } ?? 60
            try? await Task.sleep(for: .seconds(min(max(wait, 1), 60)))
            if let closesAt, closesAt <= .now { await load() }
        }
    }

    private func receive(_ line: PrivateChatMessage) {
        guard let chat else {
            // The first line opens the chat: read it whole.
            Task { await load() }
            return
        }
        guard line.chatId == chat.id else { return }
        messages = PrivateChatMessage.merge(messages, [line])
    }

    private func close() {
        isClosed = true
        messages = []
    }

    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = chat?.id, !body.isEmpty, !isSending, !isClosed else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await api.sendPrivateChatMessage(chatID: id, body: String(body.prefix(PrivateChatCopy.bodyLimit)))
            messages = PrivateChatMessage.merge(messages, [sent])
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == body { draft = "" }
        } catch {
            errorMessage = NowViewModel.message(for: error)
        }
    }
}

/// What one `privateChat` event on the cable means.
enum PrivateChatFrames {
    enum Frame: Equatable {
        /// Running; sent again after every reconnect, so the chat is refetched then.
        case connected
        case message(PrivateChatMessage)
        case closed(chatID: String)
        case refused
        case disconnected(reconnects: Bool)
    }

    static func frames(from event: AudienceCable.Event) -> [Frame] {
        switch event {
        case .subscribed: [.connected]
        case let .result(data): frames(fromResult: data)
        case .rejected: [.refused]
        case let .disconnected(_, reconnects): [.disconnected(reconnects: reconnects)]
        }
    }

    /// One `{ data, errors }` result: a line, a chat closing, a refusal, or
    /// nothing (the empty first result).
    static func frames(fromResult data: Data) -> [Frame] {
        struct Wire: Decodable {
            let chatId: String
            let closed: Bool
            let message: PrivateChatMessage?
        }
        struct Envelope: Decodable {
            struct Payload: Decodable { let privateChat: Wire? }
            struct Failure: Decodable { let message: String? }
            let data: Payload?
            let errors: [Failure]?
        }
        guard let envelope = try? JSONDecoder.hotMess.decode(Envelope.self, from: data) else { return [] }
        if let wire = envelope.data?.privateChat {
            if wire.closed { return [.closed(chatID: wire.chatId)] }
            return wire.message.map { [.message($0)] } ?? []
        }
        if let errors = envelope.errors, !errors.isEmpty { return [.refused] }
        return []
    }
}
