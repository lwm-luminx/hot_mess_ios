//
//  PairUpSheet.swift
//  HotMess
//

import SwiftUI
import UIKit

/// Pair me up to chat: opt in, see a topic, accept or skip, find each other,
/// and confirm the meeting with a QR code. Nothing about the other person
/// shows until both accept, and it disappears the moment either cancels.
struct PairUpSheet: View {
    let model: PairUpModel
    let venueName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    /// Until the API says whether they've agreed to the terms, which come
    /// before anyone joins (the API refuses otherwise).
    @State private var isCheckingTerms = true
    @State private var lookFor = ""
    /// The code on screen, for the match and topic it was issued for; a new topic clears the old code.
    @State private var shownCode: (key: String, code: String)?
    @State private var isScanning = false
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?

    var body: some View {
        NavigationStack {
            Group {
                if asksForTerms {
                    // Your hint and the topic are seen by someone else, so the
                    // terms come first, as in chat.
                    ChatTermsPrompt {
                        try await app.safety.acceptTerms()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if let notice = model.scanNotice {
                                NoticeCard(text: notice) { model.scanNotice = nil }
                            }
                            if let bonus = model.state?.bonus {
                                BonusCard(match: bonus) { Task { await model.cancel(bonus) } }
                            }
                            content
                        }
                        .padding(20)
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(String(localized: "Quickie"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // On the right, out of the way: the end of a quickie is the
                // two choices at the bottom of the "You met!" card.
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
            .overlay {
                if model.celebratedMatchID != nil {
                    MetCelebration(metCount: model.state?.metCount ?? 1) { model.dismissCelebration() }
                }
            }
        }
        .task { await model.poll() }
        .task {
            await app.safety.load()
            isCheckingTerms = false
        }
        .onChange(of: model.needsTerms, initial: true) { _, needed in
            guard needed else { return }
            model.needsTerms = false
            app.safety.termsRefused()
        }
        .onAppear { lookFor = model.state?.lookFor ?? "" }
        .sheet(isPresented: $isScanning) {
            PairUpScanner { code in Task { await model.scan(code) } }
        }
        .contentReporting(report: $reportSubject, block: $blockTarget)
        .alert(
            String(localized: "Quickie"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: model.celebratedMatchID) { _, id in
            if id != nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        .onChange(of: model.state?.status) { _, status in
            if status == .revealed { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        }
    }

    /// About to join (not in yet, or going again after a meeting), and the
    /// API said they haven't agreed to the terms.
    private var asksForTerms: Bool {
        guard model.isLoaded, !isCheckingTerms, app.safety.isLoaded, !app.safety.hasAcceptedTerms else { return false }
        return model.state.map { $0.status == .left || $0.status == .met } ?? true
    }

    @ViewBuilder
    private var content: some View {
        if !model.isLoaded || isCheckingTerms {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if let state = model.state, state.status != .left {
            switch state.status {
            case .searching: searching(state)
            case .proposed, .waiting: proposed(state)
            case .revealed: revealed(state)
            case .met: met(state)
            case .left: EmptyView()
            }
        } else {
            intro
        }
    }

    // MARK: - States

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Meet someone at \(venueName)")
                .font(.hotMess(.title2, semibold: true))
            Text("We'll pair you with someone else here tonight who also tapped Quickie, and give you both something to talk about. You only see each other once you both say yes, and either of you can cancel any time.")
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)

            lookForField

            Button {
                Task { await model.join(lookFor: lookFor) }
            } label: {
                Text("Start a quickie")
                    .font(.hotMess(.body, semibold: true))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isHere || model.isBusy)

            if !model.isHere {
                Text("Quickie opens once you're at \(venueName).")
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var lookForField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How can they spot you? (optional)")
                .font(.hotMess(.footnote, semibold: true))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Red jacket by the bar"), text: $lookFor)
                .textFieldStyle(.roundedBorder)
                .onChange(of: lookFor) { _, value in
                    if value.count > 60 { lookFor = String(value.prefix(60)) }
                }
            Text("Only your match sees this, and only once you both say yes.")
                .font(.hotMess(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private func searching(_ state: PairUpState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.match?.endReason != nil {
                Text("Your last match had to head off. No worries, we're finding someone new.")
                    .font(.hotMess(.subheadline))
            }
            HStack(spacing: 12) {
                ProgressView()
                Text("Finding someone to chat with…")
                    .font(.hotMess(.headline, semibold: true))
            }
            Text("Keep the app open, or we'll send a notification when someone's free.")
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)

            lookForField
            Button(String(localized: "Update hint")) {
                Task { await model.join(lookFor: lookFor) }
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy || lookFor == (state.lookFor ?? ""))

            Button(String(localized: "Leave Quickie"), role: .destructive) {
                Task { await model.leave() }
            }
            .disabled(model.isBusy)
            badge(state)
        }
        .card()
    }

    private func proposed(_ state: PairUpState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let match = state.match {
                TopicCard(topic: match.topic)

                if match.accepted {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Waiting for them to say yes…")
                            .font(.hotMess(.subheadline, semibold: true))
                    }
                } else {
                    Text(match.partnerAccepted
                        ? String(localized: "They're in. Say yes to see who to look for.")
                        : String(localized: "Up for it? Once you both say yes, you'll see who to look for."))
                        .font(.hotMess(.subheadline))
                    Button {
                        Task { await model.accept() }
                    } label: {
                        Text("Yes, let's chat").font(.hotMess(.body, semibold: true)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                HStack(spacing: 12) {
                    Button(String(localized: "New topic")) { Task { await model.skip(partner: false) } }
                        .frame(maxWidth: .infinity)
                    Button(String(localized: "Someone else")) { Task { await model.skip(partner: true) } }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                cancelButton(match)
            }
        }
        .disabled(model.isBusy)
        .card()
    }

    private func revealed(_ state: PairUpState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let match = state.match {
                if let partner = match.partner {
                    PartnerCard(partner: partner) {
                        reportSubject = ReportSubject(
                            target: .person,
                            targetID: partner.id.uuidString.lowercased(),
                            sender: BlockedUser(id: partner.id, name: partner.name)
                        )
                    }
                }
                TopicCard(topic: match.topic)

                Text("Found each other? Either of you scans the other's code.")
                    .font(.hotMess(.subheadline))
                // Both phones show their code straight away, so whoever's
                // quicker scans: no deciding who shows and who scans.
                let key = "\(match.id)-\(match.topic.key)"
                PairUpCodeView(code: shownCode?.key == key ? shownCode?.code : nil)
                    .task(id: key) {
                        if let code = await model.code() { shownCode = (key, code) }
                    }
                Button {
                    isScanning = true
                } label: {
                    Label(String(localized: "Scan theirs"), systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                cancelButton(match)
            }
        }
        .disabled(model.isBusy)
        .card()
    }

    /// The end of a quickie: share it if you both like, then go again or
    /// call it a night. Each person chooses for themselves.
    private func met(_ state: PairUpState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "You met!"), systemImage: "sparkles")
                .font(.hotMess(.title2, semibold: true))
            if let name = state.match?.partner?.name {
                Text("Hope you and \(name) had a good chat.")
                    .font(.hotMess(.subheadline))
            }
            badge(state)
            if let match = state.match {
                shareRow(match)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await model.join(lookFor: nil) }
                } label: {
                    Text("Let's go again").font(.hotMess(.body, semibold: true)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("quickie.again")

                Button {
                    Task {
                        await model.leave()
                        dismiss()
                    }
                } label: {
                    Text("I'm done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("quickie.done")
            }

            if let partner = state.match?.partner {
                Button(String(localized: "Something not right? Report or block")) {
                    reportSubject = ReportSubject(
                        target: .person,
                        targetID: partner.id.uuidString.lowercased(),
                        sender: BlockedUser(id: partner.id, name: partner.name)
                    )
                }
                .font(.hotMess(.footnote))
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(model.isBusy)
        .card()
    }

    /// Nothing names them in the venue's chat unless both say so.
    @ViewBuilder
    private func shareRow(_ match: PairUpMatch) -> some View {
        if match.isShared {
            Label(String(localized: "Shared in the venue chat"), systemImage: "checkmark.bubble")
                .font(.hotMess(.subheadline, semibold: true))
        } else if match.shared {
            Label(String(localized: "Waiting for them to share too"), systemImage: "hourglass")
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await model.share() }
                } label: {
                    Label(String(localized: "Share in the venue chat"), systemImage: "bubble.left.and.text.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text(match.partnerShared
                    ? String(localized: "They'd like to share. If you do too, the chat gets your first names and topic.")
                    : String(localized: "If you both share, the chat gets your first names and what you talked about."))
                    .font(.hotMess(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func badge(_ state: PairUpState) -> some View {
        if state.metCount > 0 {
            MetBadge(count: state.metCount)
        }
    }

    private func cancelButton(_ match: PairUpMatch) -> some View {
        Button(String(localized: "Cancel"), role: .destructive) {
            Task { await model.cancel(match) }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pieces

private struct TopicCard: View {
    let topic: PairUpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your topic")
                .font(.hotMess(.caption, semibold: true))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(topic.text)
                .font(.hotMess(.title3, semibold: true))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hotMessAccentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Who to look for: a deliberately tiny picture, a name and their hint.
private struct PartnerCard: View {
    let partner: PairUpPartner
    let report: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: partner.avatarUrl, initials: partner.initials, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Look for \(partner.name)")
                    .font(.hotMess(.headline, semibold: true))
                if let lookFor = partner.lookFor, !lookFor.isEmpty {
                    Text("“\(lookFor)”")
                        .font(.hotMess(.subheadline))
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button(role: .destructive, action: report) {
                    Label(String(localized: "Report or block…"), systemImage: "exclamationmark.bubble")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.body)
            }
            .accessibilityLabel(String(localized: "More"))
        }
    }
}

private struct BonusCard: View {
    let match: PairUpMatch
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(match.partner.map { String(localized: "A topic for you and \($0.name)") }
                ?? String(localized: "A topic for you two"))
                .font(.hotMess(.subheadline, semibold: true))
            TopicCard(topic: match.topic)
            Button(String(localized: "Done"), action: dismiss)
                .buttonStyle(.bordered)
        }
        .card()
    }
}

private struct NoticeCard: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
            Text(text).font(.hotMess(.subheadline))
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .accessibilityLabel(String(localized: "Dismiss"))
        }
        .card()
    }
}

/// The night's badge: how many conversations they had (the same person
/// twice is two conversations).
struct MetBadge: View {
    let count: Int

    var body: some View {
        Label {
            Text(count == 1
                ? String(localized: "You've had a conversation tonight")
                : String(localized: "You've had \(count) conversations tonight"))
                .font(.hotMess(.subheadline, semibold: true))
        } icon: {
            Image(systemName: "rosette")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.hotMessAccentSoft, in: Capsule())
    }
}

private struct MetCelebration: View {
    let metCount: Int
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, options: .repeat(2))
                Text("You met!")
                    .font(.hotMess(.largeTitle, semibold: true))
                MetBadge(count: metCount)
                Button(String(localized: "Nice"), action: done)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(32)
        }
        .transition(.opacity)
    }
}

/// The code to show, big and bright on white so it scans in a dark room.
/// It works once, and only for their match.
private struct PairUpCodeView: View {
    let code: String?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let code {
                    QRCodeImage(text: code)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: 240, minHeight: 200)
            .aspectRatio(1, contentMode: .fit)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Your code. It works once, and only for your match.")
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    func card() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
