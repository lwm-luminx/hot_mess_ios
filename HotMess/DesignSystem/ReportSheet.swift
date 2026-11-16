//
//  ReportSheet.swift
//  HotMess
//

import SwiftUI

/// Reporting, as a full sheet rather than an action sheet: pick why, choose
/// whether to block whoever is behind it too, then send. Used for chat
/// messages (`VenueChatScreen`) and everything else (`contentReporting`).
struct ReportSheet: View {
    /// "Why are you reporting this …?"
    let question: String
    /// The person behind it, when blocking them makes sense and they aren't
    /// blocked yet: offers "Block them too".
    let blockable: BlockedUser?
    /// Files the report; throws when it didn't go through. The sheet closes
    /// once it returns.
    let onSubmit: (ChatReportReason, _ block: Bool) async throws -> Void
    /// Sends a test report instead, for a moderation test line: offers "Send
    /// test report", which files nothing, so the moderators' queue never
    /// sees it. `nil` for anything else.
    var onTest: ((ChatReportReason) async throws -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ChatReportReason?
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                if onTest != nil {
                    Section {
                        Button {
                            Task { await sendTest() }
                        } label: {
                            Label(String(localized: "Send test report"), systemImage: "testtube.2")
                        }
                        .disabled(isSending)
                        .accessibilityIdentifier("report.test")
                    } header: {
                        Text("This is a moderation test")
                    } footer: {
                        Text("A test report goes through every check but nothing is filed, so the moderators' queue never sees it.")
                    }
                }

                Section {
                    ForEach(ChatReportReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityAddTraits(reason == option ? .isSelected : [])
                    }
                } header: {
                    Text(question)
                } footer: {
                    Text("Reports are reviewed within 24 hours. Objectionable content will be removed and offending users ejected.")
                }

                if let blockable {
                    Section {
                        Toggle(Self.blockTitle(blockable), isOn: $alsoBlock)
                            .accessibilityIdentifier("report.block")
                    } footer: {
                        Text("They'll be removed from your feed instantly and our moderation team will be notified.")
                    }
                }
            }
            .navigationTitle(String(localized: "Report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button(String(localized: "Send")) { Task { await send() } }
                            .fontWeight(.semibold)
                            .disabled(reason == nil)
                            .accessibilityIdentifier("report.submit")
                    }
                }
            }
            .alert(String(localized: "Something went wrong"), isPresented: $failed) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text("The report didn't go through. Please try again.")
            }
            .interactiveDismissDisabled(isSending)
        }
    }

    private func send() async {
        guard let reason, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await onSubmit(reason, alsoBlock)
            dismiss()
        } catch {
            failed = true
        }
    }

    private func sendTest() async {
        guard let onTest, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await onTest(reason ?? .other)
            dismiss()
        } catch {
            failed = true
        }
    }

    static func blockTitle(_ person: BlockedUser) -> String {
        if let name = person.name, !name.isEmpty {
            return String(localized: "Block \(name) too")
        }
        return String(localized: "Block them too")
    }
}
