//
//  YourSuggestionsScreen.swift
//  HotMess
//

import SwiftUI

/// Me → "Your suggestions": what the member suggested, newest first, with
/// where each is. A suggestion that wasn't taken shows the reviewer's
/// reason. It never says whether the venue was asked.
struct YourSuggestionsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[SuggestionSummary]> = .idle

    var body: some View {
        LoadStateView(state: state, retry: { Task { await load() } }) { suggestions in
            List {
                if suggestions.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No suggestions yet"),
                        systemImage: "lightbulb",
                        description: Text("Suggest a missing venue from the Venues tab, or a fix from any venue or event page.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(suggestions) { suggestion in
                            SuggestionRow(suggestion: suggestion) { route in
                                model.open(route)
                            }
                        }
                    } footer: {
                        Text("The venue never sees who sent a suggestion. New accounts can send 3 suggestions a day.")
                    }
                }
            }
        }
        .navigationTitle(Text("Your suggestions"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await model.api.mySuggestions())
        } catch is CancellationError {
        } catch {
            state = LoadState(catching: error)
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: SuggestionSummary
    let open: (AppRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.title)
                    .font(.hotMess(.body, semibold: true))
                    .lineLimit(2)
                Spacer()
                SuggestionBadge(suggestion: suggestion)
            }

            Text(details)
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)

            if let reason = suggestion.rejectionReason, !reason.isEmpty {
                Text(reason)
                    .font(.hotMess(.footnote))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
            }

            if let route = suggestion.addedRoute {
                Button(String(localized: "Open")) { open(route) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        var parts = [suggestion.kind.title, suggestion.createdAt.formatted(.relative(presentation: .named))]
        if suggestion.reporterCount > 1 {
            parts.append(String(localized: "You and \(suggestion.reporterCount - 1) others suggested it"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct SuggestionBadge: View {
    let suggestion: SuggestionSummary

    var body: some View {
        Text(suggestion.badge)
            .font(.hotMess(.caption, semibold: true))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: .capsule)
    }

    private var tint: Color {
        switch suggestion.status {
        case .approved: .green
        case .rejected: .secondary
        default: .blue
        }
    }
}
