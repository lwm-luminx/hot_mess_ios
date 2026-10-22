//
//  SuggestFixSheet.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// The listing a fix is about.
enum SuggestionTarget: Hashable, Identifiable {
    /// A venue, with what the venue page loaded about it for suggestions.
    case venue(Venue, VenueSuggestionState?)
    case event(Event)

    var id: String { targetID }

    var targetID: String {
        switch self {
        case let .venue(venue, _): venue.id.uuidString.lowercased()
        case let .event(event): event.id.uuidString.lowercased()
        }
    }

    var name: String {
        switch self {
        case let .venue(venue, state): state?.name ?? venue.name
        case let .event(event): event.name
        }
    }
}

/// "Suggest a fix for …": what's wrong with a venue or event. A person
/// checks it first, and the venue never sees who sent it.
struct SuggestFixSheet: View {
    let target: SuggestionTarget

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClosed = false
    @State private var isSending = false
    @State private var failure: String?
    @State private var sent: SentSuggestion?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FixDetailScreen(target: target, finish: { dismiss() })
                    } label: {
                        option(
                            String(localized: "Fix a detail"),
                            help: helpForDetails,
                            systemImage: "pencil"
                        )
                    }
                    .accessibilityIdentifier("suggestFix.detail")

                    if case let .venue(venue, _) = target {
                        Button {
                            confirmsClosed = true
                        } label: {
                            option(
                                String(localized: "It's closed for good"),
                                help: String(localized: "Not just tonight: it has shut for good"),
                                systemImage: "xmark.octagon",
                                tint: .red
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending)
                        .accessibilityIdentifier("suggestFix.closed")

                        NavigationLink {
                            SuggestListingScreen(kind: .event, venue: venue, finish: { dismiss() })
                        } label: {
                            option(
                                String(localized: "Add a missing event"),
                                help: String(localized: "A night here that isn't listed"),
                                systemImage: "calendar.badge.plus"
                            )
                        }
                    }
                } footer: {
                    Text("A person checks it first. \(target.name) never sees who sent it.")
                }

                if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(Text("Suggest a fix"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .confirmationDialog(
                String(localized: "Not just tonight?"),
                isPresented: $confirmsClosed,
                titleVisibility: .visible
            ) {
                Button(String(localized: "It's closed for good"), role: .destructive) {
                    Task { await reportClosed() }
                }
            } message: {
                Text("We'll check before anything changes.")
            }
            .alert(String(localized: "Thanks, it's sent"), isPresented: Binding(
                get: { sent != nil },
                set: { if !$0 { sent = nil } }
            )) {
                Button(String(localized: "OK")) { dismiss() }
            } message: {
                Text(sent?.message ?? "")
            }
        }
    }

    private var helpForDetails: String {
        switch target {
        case .venue: String(localized: "Name, phone, website or description")
        case .event: String(localized: "Name, times, ticket link or cancelled")
        }
    }

    private func option(_ title: String, help: String, systemImage: String, tint: Color = Color.hotMessAccent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.hotMess(.body, semibold: true))
                Text(help)
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .padding(.vertical, 4)
    }

    private func reportClosed() async {
        isSending = true
        failure = nil
        defer { isSending = false }

        do {
            let request = SuggestionRequest(kind: .closed, targetID: target.targetID, localeID: model.location.locale?.id)
            if case let .sent(_, merged) = try await model.api.suggest(request) {
                sent = SentSuggestion(merged: merged)
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}
