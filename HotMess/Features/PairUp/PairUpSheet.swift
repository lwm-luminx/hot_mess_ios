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
    @State private var lookFor = ""
    @State private var showingCode: String?
    @State private var isScanning = false
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?

    var body: some View {
        NavigationStack {
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(String(localized: "Pair me up"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
        .onAppear { lookFor = model.state?.lookFor ?? "" }
        .sheet(item: Binding(get: { showingCode.map { PairUpCode(code: $0) } }, set: { showingCode = $0?.code })) { code in
            PairUpCodeScreen(code: code.code, partnerName: model.state?.match?.partner?.name)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isScanning) {
            PairUpScanner { code in Task { await model.scan(code) } }
        }
        .contentReporting(report: $reportSubject, block: $blockTarget)
        .alert(
            String(localized: "Pair me up"),
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

    @ViewBuilder
    private var content: some View {
        if !model.isLoaded {
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
            Text("We'll pair you with someone else here tonight who also tapped Pair me up, and give you both something to talk about. You only see each other once you both say yes, and either of you can cancel any time.")
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)

            lookForField

            Button {
                Task { await model.join(lookFor: lookFor) }
            } label: {
                Text("Pair me up to chat")
                    .font(.hotMess(.body, semibold: true))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isHere || model.isBusy)

            if !model.isHere {
                Text("Pair me up opens once you're at \(venueName).")
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

            Button(String(localized: "Stop pairing me up"), role: .destructive) {
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

                Text("Found each other? One of you shows a code and the other scans it.")
                    .font(.hotMess(.subheadline))
                HStack(spacing: 12) {
                    Button {
                        Task { showingCode = await model.code() }
                    } label: {
                        Label(String(localized: "Show my code"), systemImage: "qrcode").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        isScanning = true
                    } label: {
                        Label(String(localized: "Scan theirs"), systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)

                cancelButton(match)
            }
        }
        .disabled(model.isBusy)
        .card()
    }

    private func met(_ state: PairUpState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "You met!"), systemImage: "sparkles")
                .font(.hotMess(.title2, semibold: true))
            if let name = state.match?.partner?.name {
                Text("Hope you and \(name) are having fun.")
                    .font(.hotMess(.subheadline))
            }
            badge(state)
            Button {
                Task { await model.join(lookFor: nil) }
            } label: {
                Text("Pair me up again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button(String(localized: "I'm done for tonight")) { Task { await model.leave() } }
        }
        .disabled(model.isBusy)
        .card()
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

private struct PairUpCode: Identifiable {
    let code: String
    var id: String { code }
}

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

/// The night's badge: how many people they met.
struct MetBadge: View {
    let count: Int

    var body: some View {
        Label {
            Text(count == 1 ? String(localized: "Met someone new tonight") : String(localized: "Met \(count) people tonight"))
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

/// The code to show: big, bright, and only for their partner.
private struct PairUpCodeScreen: View {
    let code: String
    let partnerName: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(partnerName.map { String(localized: "Let \($0) scan this") } ?? String(localized: "Let them scan this"))
                    .font(.hotMess(.title3, semibold: true))
                QRCodeImage(text: code)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxWidth: 320)
                Text("It works once, and only for your match.")
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}

private extension View {
    func card() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
