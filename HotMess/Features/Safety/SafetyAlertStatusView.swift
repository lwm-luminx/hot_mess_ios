//
//  SafetyAlertStatusView.swift
//  HotMess
//

import SwiftUI

/// The alert once it's sent: the steps (sent, waiting, someone's on the way),
/// what was sent with "Add more", the private thread with the staff on shift,
/// and "I'm OK now". After the escalation window with nobody on it, the
/// other ways to get help come first.
struct SafetyAlertStatusView: View {
    @Bindable var model: SafetyAlertModel
    let alert: SafetyAlert
    let showSupport: () -> Void

    @State private var isAddingMore = false
    @State private var isConfirmingCancel = false
    @State private var reply = ""

    var body: some View {
        List {
            if alert.isUnanswered(at: model.now), !model.keepsWaiting {
                unanswered
            }

            if alert.isActive {
                stepsSection
                sentSection
                threadSection
                cancelSection
            } else {
                endedSection
                if !alert.messages.isEmpty { threadSection }
            }

            if alert.supportSharedAt != nil {
                Section {
                    if let note = alert.supportNote, !note.isEmpty {
                        Text(note)
                            .font(.hotMess(.body))
                    }
                    Button(action: showSupport) {
                        HelpRow(title: String(localized: "Need support?"), systemImage: "heart.text.square")
                    }
                } header: {
                    Text("From the staff at \(alert.venue.name ?? String(localized: "the venue"))")
                }
            }

            EmergencySection()
        }
        .listStyle(.insetGrouped)
        .navigationDestination(isPresented: $isAddingMore) {
            TellStaffForm(model: model, mode: .addMore) { isAddingMore = false }
        }
        .confirmationDialog(
            String(localized: "Cancel your alert?"),
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button(String(localized: "I'm OK now, cancel the alert")) { Task { await model.cancel() } }
            Button(String(localized: "Keep it open"), role: .cancel) {}
        } message: {
            Text("Staff will see that you're OK. You can send another any time.")
        }
    }

    // MARK: - Sections

    /// "Nobody's picked it up yet": friend, ride, tell staff again, support, 911.
    private var unanswered: some View {
        Section {
            Button {
                Task { await model.remind() }
            } label: {
                HelpRow(
                    title: String(localized: "Tell staff again"),
                    subtitle: String(localized: "It goes to the managers too."),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("help.remind")
            HelpEscapeRows(model: model, showSupport: showSupport)
            Button(String(localized: "Keep waiting for staff")) { model.keepsWaiting = true }
        } header: {
            Text("Nobody's picked it up yet")
        } footer: {
            Text("Stay where you feel safest. These can help while you wait.")
        }
    }

    private var stepsSection: some View {
        Section {
            AlertSteps(steps: steps)
        } header: {
            Text(alert.state == .acknowledged ? String(localized: "Someone's on the way") : String(localized: "Staff have your alert"))
        } footer: {
            if alert.state == .open {
                Text("Stay where you feel safest. You'll feel a buzz, with no sound, when someone picks it up. If nobody does in 2 minutes, we'll help you reach a friend, a ride or 911.")
            }
        }
    }

    private var steps: [AlertSteps.Step] {
        let sent = AlertSteps.Step(
            title: String(localized: "Sent to the staff on shift"),
            note: alert.createdAt.formatted(date: .omitted, time: .shortened),
            state: .done
        )
        switch alert.state {
        case .acknowledged:
            let name = alert.acknowledgedByName ?? String(localized: "Someone")
            return [
                sent,
                AlertSteps.Step(title: String(localized: "Seen"), note: nil, state: .done),
                AlertSteps.Step(
                    title: String(localized: "\(name) is on the way"),
                    note: alert.acknowledgedAt?.formatted(date: .omitted, time: .shortened),
                    state: .current
                ),
            ]
        default:
            return [
                sent,
                AlertSteps.Step(
                    title: alert.seen ? String(localized: "Seen by staff") : String(localized: "Waiting for someone to pick it up"),
                    note: nil,
                    state: .current
                ),
                AlertSteps.Step(title: String(localized: "Someone's on the way"), note: nil, state: .upcoming),
            ]
        }
    }

    private var sentSection: some View {
        Section {
            Text(alert.summary)
                .font(.hotMess(.body))
            if let description = alert.description, !description.isEmpty {
                Text(description)
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Button(String(localized: "Add more")) { isAddingMore = true }
                .accessibilityIdentifier("help.addMore")
        } header: {
            Text("What you sent")
        }
    }

    private var threadSection: some View {
        Section {
            ForEach(alert.messages) { message in
                VStack(alignment: message.fromStaff ? .leading : .trailing, spacing: 2) {
                    Text(message.senderName)
                        .font(.hotMess(.caption, semibold: true))
                        .foregroundStyle(.secondary)
                    Text(message.body)
                        .font(.hotMess(.body))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            message.fromStaff ? Color.hotMessControlFill : Color.hotMessAccentSoft,
                            in: RoundedRectangle(cornerRadius: HotMessRadius.bubble)
                        )
                }
                .frame(maxWidth: .infinity, alignment: message.fromStaff ? .leading : .trailing)
                .listRowSeparator(.hidden)
            }
            if alert.isActive {
                HStack {
                    TextField(String(localized: "Message the staff on shift"), text: $reply, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("help.reply")
                    Button {
                        Task { if await model.sendMessage(reply) { reply = "" } }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                    .accessibilityLabel(String(localized: "Send"))
                }
            }
        } header: {
            Text("Private thread")
        } footer: {
            Text("Just you and the staff on shift. This isn't in venue chat.")
        }
    }

    private var cancelSection: some View {
        Section {
            Button(String(localized: "I'm OK now, cancel the alert")) { isConfirmingCancel = true }
                .disabled(model.isBusy)
                .accessibilityIdentifier("help.cancel")
        }
    }

    /// Closed or cancelled. The wording is the same whatever the outcome, so
    /// it never implies blame.
    private var endedSection: some View {
        Section {
            Text(alert.state == .cancelled
                 ? String(localized: "You cancelled your alert. You can send another any time.")
                 : String(localized: "Staff closed your alert. You can send another any time."))
                .font(.hotMess(.body))
        }
    }
}

/// Step dots joined by a line: done (a check on `success`), the current one
/// (an accent ring), and the ones not reached yet.
struct AlertSteps: View {
    enum StepState { case done, current, upcoming }

    struct Step: Hashable {
        let title: String
        let note: String?
        let state: StepState
    }

    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        dot(step.state)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(Color.hotMessBorder)
                                .frame(width: 2, height: 20)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.hotMess(.body, semibold: true))
                            .foregroundStyle(step.state == .upcoming ? .secondary : .primary)
                        if let note = step.note {
                            Text(note)
                                .font(.hotMess(.footnote))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(step.state == .current ? .updatesFrequently : [])
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dot(_ state: StepState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.hotMessSuccess, in: Circle())
        case .current:
            Image(systemName: "clock")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.hotMessAccentInk)
                .frame(width: 24, height: 24)
                .background(Color.hotMessAccentSoft, in: Circle())
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
        case .upcoming:
            Circle()
                .fill(Color.hotMessControlFill)
                .frame(width: 24, height: 24)
        }
    }
}
