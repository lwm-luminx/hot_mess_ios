//
//  PrivateChatView.swift
//  HotMess
//

import SwiftUI

/// A Ping or Quickie chat's lines and composer, or why there's nothing to say
/// yet. Long-press someone else's line to report it (and block them).
struct PrivateChatView: View {
    let model: PrivateChatModel
    /// Shown until the chat opens.
    let waiting: String

    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            if !model.isLoaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if model.isClosed {
                Text(PrivateChatCopy.closed).font(.hotMess(.subheadline)).foregroundStyle(.secondary)
            } else if model.chat == nil {
                Text(model.errorMessage ?? waiting).font(.hotMess(.subheadline)).foregroundStyle(.secondary)
            } else {
                lines
                if let error = model.errorMessage {
                    Text(error).font(.hotMess(.footnote)).foregroundStyle(.red)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(PrivateChatCopy.placeholder, text: $model.draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.draft) { _, text in
                            if text.count > PrivateChatCopy.bodyLimit { model.draft = String(text.prefix(PrivateChatCopy.bodyLimit)) }
                            model.errorMessage = nil
                        }
                        .onSubmit { Task { await model.send() } }
                        .accessibilityIdentifier("privateChat.field")
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    }
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
                    .accessibilityLabel(String(localized: "Send"))
                    .accessibilityIdentifier("privateChat.send")
                }
            }
        }
        .contentReporting(report: $reportSubject, block: $blockTarget)
    }

    @ViewBuilder
    private var lines: some View {
        if model.messages.isEmpty {
            Text(PrivateChatCopy.empty).font(.hotMess(.footnote)).foregroundStyle(.secondary)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.messages) { line in
                            bubble(line).id(line.id)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .onAppear { scrollToEnd(proxy) }
                .onChange(of: model.messages.count) {
                    withAnimation { scrollToEnd(proxy) }
                }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private func bubble(_ line: PrivateChatMessage) -> some View {
        HStack {
            if line.isMine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                if !line.isMine {
                    Text(line.sender?.name ?? String(localized: "Someone"))
                        .font(.hotMess(.caption, semibold: true))
                        .foregroundStyle(Color.hotMessAccent)
                }
                Text(line.body).font(.hotMess(.body))
                Text(line.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.hotMess(.caption2))
                    .foregroundStyle(line.isMine ? Color.white.opacity(0.7) : Color.secondary)
            }
            .foregroundStyle(line.isMine ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                line.isMine ? Color.hotMessAccent : Color(.tertiarySystemGroupedBackground),
                in: .rect(cornerRadius: 16)
            )
            .contextMenu {
                if !line.isMine, let sender = line.sender {
                    Button(role: .destructive) {
                        reportSubject = ReportSubject(
                            target: .privateMessage,
                            targetID: line.id,
                            sender: BlockedUser(id: sender.id, name: sender.name)
                        )
                    } label: {
                        Label(String(localized: "Report…"), systemImage: "exclamationmark.bubble")
                    }
                }
            }
            if !line.isMine { Spacer(minLength: 40) }
        }
    }
}

/// The chat with a ping's circle, in a sheet of its own.
struct PingChatSheet: View {
    let pingID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var model: PrivateChatModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(PrivateChatCopy.ephemeral).font(.hotMess(.footnote)).foregroundStyle(.secondary)
                    if let model { PrivateChatView(model: model, waiting: PrivateChatCopy.pingWaiting) }
                }
                .padding(20)
            }
            .navigationTitle(PrivateChatCopy.pingTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
        .task {
            let pingID = pingID
            let model = PrivateChatModel(api: app.api, cable: app.cable) { try await $0.pingChat(pingID: pingID) }
            self.model = model
            await model.run()
        }
    }
}

/// The two of them can talk once both said yes, to find each other, until 30
/// minutes after they meet (or the pairing or night ends).
struct QuickieChatCard: View {
    let venueID: UUID
    let matchID: UUID

    @Environment(AppModel.self) private var app
    @State private var model: PrivateChatModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PrivateChatCopy.quickieTitle).font(.hotMess(.headline, semibold: true))
            Text(PrivateChatCopy.ephemeral).font(.hotMess(.caption)).foregroundStyle(.secondary)
            if let model { PrivateChatView(model: model, waiting: PrivateChatCopy.closed) }
        }
        .task(id: matchID) {
            let venueID = venueID
            let model = PrivateChatModel(api: app.api, cable: app.cable) { try await $0.quickieChat(venueID: venueID) }
            self.model = model
            await model.run()
        }
    }
}
