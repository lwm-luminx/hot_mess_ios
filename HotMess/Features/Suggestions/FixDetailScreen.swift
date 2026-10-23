//
//  FixDetailScreen.swift
//  HotMess
//

import AudienceKit
import SwiftUI
import UIKit

/// "Fix a detail": the listing's details as they are, any of which the
/// member can change. Only what they change is sent, with links that show
/// it. A changed website or ticket link needs a link to back it up.
struct FixDetailScreen: View {
    let target: SuggestionTarget
    /// Closes whatever presented it once the fix is sent.
    var finish: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text: [String: String] = [:]
    @State private var startsAt = Date.now
    @State private var endsAt = Date.now
    @State private var isCanceled = false
    @State private var links: [String] = []
    @State private var newLink = ""
    @State private var note = ""
    @State private var isSending = false
    @State private var failure: String?
    @State private var sent: SentSuggestion?
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                ForEach(fields, id: \.key) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label)
                            .font(.hotMess(.footnote, semibold: true))
                            .foregroundStyle(.secondary)
                        if let current = field.current, !current.isEmpty, changed(field) {
                            Text("Now \(current)")
                                .font(.hotMess(.footnote))
                                .strikethrough()
                                .foregroundStyle(.secondary)
                        }
                        TextField(field.placeholder, text: binding(field.key), axis: field.multiline ? .vertical : .horizontal)
                            .keyboardType(field.keyboard)
                            .textInputAutocapitalization(field.keyboard == .default ? .sentences : .never)
                            .autocorrectionDisabled(field.keyboard != .default)
                            .lineLimit(field.multiline ? 2...6 : 1...1)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(changed(field) ? Color.hotMessAccentSoft : nil)
                }

                if case let .event(event) = target {
                    DatePicker(String(localized: "Starts"), selection: $startsAt)
                        .listRowBackground(startChanged(event) ? Color.hotMessAccentSoft : nil)
                    if event.endDate != nil {
                        DatePicker(String(localized: "Ends"), selection: $endsAt, in: startsAt...)
                            .listRowBackground(endChanged(event) ? Color.hotMessAccentSoft : nil)
                    }
                    Toggle(String(localized: "It's cancelled"), isOn: $isCanceled)
                        .listRowBackground(isCanceled ? Color.hotMessAccentSoft : nil)
                }
            } header: {
                Text(target.name)
            } footer: {
                Text("Change what's wrong. Only what you change is sent.")
            }

            Section {
                ForEach(links, id: \.self) { link in
                    Text(link)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .onDelete { links.remove(atOffsets: $0) }

                HStack {
                    TextField(String(localized: "Add a link"), text: $newLink)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addLink)
                    Button(String(localized: "Add"), action: addLink)
                        .disabled(trimmedNewLink.isEmpty)
                }
            } header: {
                Text("How do you know?")
            } footer: {
                Text(needsLink
                    ? String(localized: "A new website or ticket link needs a link that shows it, like the venue's own page or post.")
                    : String(localized: "A link to the venue's own page or post helps us check it faster."))
            }

            Section {
                TextField(String(localized: "Anything else? (optional)"), text: $note, axis: .vertical)
                    .lineLimit(2...5)
            } footer: {
                Text("A person checks every suggestion before it goes up. The venue never sees who sent it.")
            }

            if let failure {
                Section {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Text("Fix a detail"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button(sendTitle) {
                        Task { await send() }
                    }
                    .disabled(!canSend)
                    .accessibilityIdentifier("fixDetail.send")
                }
            }
        }
        .onAppear(perform: load)
        .alert(String(localized: "Thanks, it's sent"), isPresented: Binding(
            get: { sent != nil },
            set: { if !$0 { sent = nil } }
        )) {
            Button(String(localized: "OK")) {
                if let finish { finish() } else { dismiss() }
            }
        } message: {
            Text(sent?.message ?? "")
        }
    }

    // MARK: - Fields

    private struct Field {
        let key: String
        let label: String
        let placeholder: String
        let current: String?
        var keyboard: UIKeyboardType = .default
        var multiline = false
    }

    /// What a member may change, from the API's `Contributions::Fields`.
    private var fields: [Field] {
        switch target {
        case let .venue(venue, state):
            [
                Field(key: "name", label: String(localized: "Name"), placeholder: String(localized: "Name"),
                      current: state?.name ?? venue.name),
                Field(key: "phone", label: String(localized: "Phone"), placeholder: String(localized: "Phone number"),
                      current: state?.phone ?? venue.phone, keyboard: .phonePad),
                Field(key: "website", label: String(localized: "Website"), placeholder: String(localized: "https://"),
                      current: state?.website, keyboard: .URL),
                Field(key: "description", label: String(localized: "Description"),
                      placeholder: String(localized: "What it's like"), current: state?.description ?? venue.subtitle,
                      multiline: true),
            ]
        case let .event(event):
            [
                Field(key: "name", label: String(localized: "Name"), placeholder: String(localized: "Name"),
                      current: event.name),
                Field(key: "ticket_url", label: String(localized: "Ticket link"), placeholder: String(localized: "https://"),
                      current: nil, keyboard: .URL),
            ]
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { text[key] ?? "" }, set: { text[key] = $0 })
    }

    private func value(_ field: Field) -> String {
        (text[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func changed(_ field: Field) -> Bool {
        let value = value(field)
        return !value.isEmpty && value != (field.current ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startChanged(_ event: Event) -> Bool {
        abs(startsAt.timeIntervalSince(event.startDate)) >= 60
    }

    private func endChanged(_ event: Event) -> Bool {
        guard let endDate = event.endDate else { return false }
        return abs(endsAt.timeIntervalSince(endDate)) >= 60
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        for field in fields {
            text[field.key] = field.current ?? ""
        }
        if case let .event(event) = target {
            startsAt = event.startDate
            endsAt = event.endDate ?? event.startDate
        }
    }

    // MARK: - Sending

    /// Only the fields that changed, by their API names.
    private var proposed: [String: GraphQLValue] {
        var proposed: [String: GraphQLValue] = [:]
        for field in fields where changed(field) {
            proposed[field.key] = .string(value(field))
        }
        if case let .event(event) = target {
            if startChanged(event) { proposed["start_at"] = .string(SuggestionFormat.timestamp(startsAt)) }
            if endChanged(event) { proposed["end_at"] = .string(SuggestionFormat.timestamp(endsAt)) }
            if isCanceled { proposed["is_canceled"] = .bool(true) }
        }
        return proposed
    }

    private var needsLink: Bool {
        proposed.keys.contains("website") || proposed.keys.contains("ticket_url")
    }

    private var trimmedNewLink: String { newLink.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var evidence: [String] {
        trimmedNewLink.isEmpty ? links : links + [trimmedNewLink]
    }

    private var canSend: Bool {
        !proposed.isEmpty && (!needsLink || !evidence.isEmpty)
    }

    private var sendTitle: String {
        let count = proposed.count
        return count <= 1 ? String(localized: "Send fix") : String(localized: "Send \(count) fixes")
    }

    private func addLink() {
        guard !trimmedNewLink.isEmpty else { return }
        links.append(trimmedNewLink)
        newLink = ""
    }

    private func send() async {
        isSending = true
        failure = nil
        defer { isSending = false }

        let request = SuggestionRequest(
            kind: .correction,
            targetID: target.targetID,
            localeID: model.location.locale?.id,
            proposed: proposed,
            body: note,
            evidence: evidence.map(SuggestionEvidence.init(url:))
        )
        do {
            if case let .sent(_, merged) = try await model.api.suggest(request) {
                sent = SentSuggestion(merged: merged)
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}
