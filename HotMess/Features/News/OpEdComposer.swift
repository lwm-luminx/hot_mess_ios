//
//  OpEdComposer.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// "Write an op-ed": a title, an optional summary and the piece itself, sent to the publication under the reader's
/// name. The publication runs it (edited, bylined to them) or declines it with a note.
struct OpEdComposer: View {
    let publication: Publication
    var onSent: (Article) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                if let guidelines = publication.opEdGuidelines, !guidelines.isEmpty {
                    Section {
                        Text(guidelines)
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("From \(publication.name)")
                    }
                }
                Section {
                    TextField(String(localized: "Title"), text: $title)
                        .accessibilityIdentifier("opEd.title")
                    TextField(String(localized: "Summary (optional)"), text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 240)
                        .accessibilityIdentifier("opEd.body")
                } header: {
                    Text("Your op-ed")
                } footer: {
                    Text("It goes out under your name. \(publication.name) may edit it before it runs.")
                }
            }
            .navigationTitle(SoapboxCopy.writeOpEd)
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
                            .disabled(!canSend)
                            .accessibilityIdentifier("opEd.send")
                    }
                }
            }
            .alert(SoapboxCopy.opEdSent, isPresented: $sent) {
                Button(String(localized: "OK")) { dismiss() }
            }
            .alert(
                String(localized: "Couldn't send it"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .interactiveDismissDisabled(!text.isEmpty)
        }
    }

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let article = try await model.audienceKit.submitOpEd(
                publicationID: publication.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: text,
                summary: trimmedSummary.isEmpty ? nil : trimmedSummary
            )
            onSent(article)
            sent = true
        } catch let error as AudienceKitError {
            // The API says why: three waiting already, or the publication stopped taking op-eds.
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
