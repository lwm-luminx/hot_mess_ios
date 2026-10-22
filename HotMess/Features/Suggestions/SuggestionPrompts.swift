//
//  SuggestionPrompts.swift
//  HotMess
//

import SwiftUI

/// The end of the Venues tab: "Don't see your local spot?", with the forms to
/// suggest a missing venue or event. Prominent where a city has only a few
/// venues listed, a quiet line everywhere else.
struct ThinCityCard: View {
    /// How many venues the city has listed.
    let venueCount: Int
    let cityName: String?

    @Environment(AppModel.self) private var model
    @State private var suggesting: SuggestListingScreen.Kind?

    /// Fewer listed venues than this and the card is the prominent one.
    static let thinCityVenueCount = 5

    var body: some View {
        Group {
            if venueCount < Self.thinCityVenueCount {
                prominent
            } else {
                quiet
            }
        }
        .padding(.horizontal, 16)
        .sheet(item: $suggesting) { kind in
            NavigationStack {
                SuggestListingScreen(kind: kind)
            }
            .environment(model)
        }
    }

    private var prominent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Don't see your local spot?")
                .font(.hotMess(.title3, semibold: true))
            Text(helpLine)
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)

            Button {
                suggesting = .venue
            } label: {
                Text("Suggest a venue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.hotMessAccent)
            .controlSize(.large)
            .accessibilityIdentifier("venues.suggestVenue")

            Button {
                suggesting = .event
            } label: {
                Text("Suggest an event").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text(countLine)
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: CardMetrics.cornerRadius))
    }

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Don't see your local spot?")
                .font(.hotMess(.subheadline, semibold: true))
            HStack(spacing: 12) {
                Button(String(localized: "Suggest a venue")) { suggesting = .venue }
                Button(String(localized: "Suggest an event")) { suggesting = .event }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("venues.suggestVenue")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var helpLine: String {
        if let cityName, !cityName.isEmpty {
            return String(localized: "Help us build out \(cityName). Tell us about a bar, a club or a night we're missing, and we'll check it and add it.")
        }
        return String(localized: "Tell us about a bar, a club or a night we're missing, and we'll check it and add it.")
    }

    private var countLine: String {
        let checked = String(localized: "A person checks every suggestion before it goes up.")
        guard let cityName, !cityName.isEmpty else { return checked }
        let count = venueCount == 1
            ? String(localized: "1 venue so far in \(cityName).")
            : String(localized: "\(venueCount) venues so far in \(cityName).")
        return "\(count) \(checked)"
    }
}

extension SuggestListingScreen.Kind: Identifiable {
    var id: Self { self }
}

/// The note at the top of a venue reported closed: it's left off Tonight
/// while a person checks, and anyone who knows it's still open can say so.
struct ReportedClosedNotice: View {
    let venueID: UUID
    /// Called with whether it's still reported closed after "It's still open".
    let reopened: (Bool) -> Void

    @Environment(AppModel.self) private var model
    @State private var isSending = false
    @State private var didSend = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("People told us it has closed")
                    .font(.hotMess(.subheadline, semibold: true))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text("We're checking. Until we know, it's left off Tonight and Near you. Nothing here has been removed.")
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)

            if didSend {
                Text("Thanks, we'll check")
                    .font(.hotMess(.footnote, semibold: true))
            } else if isSending {
                ProgressView()
            } else {
                Button(String(localized: "It's still open")) {
                    Task { await sayStillOpen() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("venue.stillOpen")
            }

            if let failure {
                Text(failure)
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: CardMetrics.cornerRadius))
        .padding(.horizontal, 16)
    }

    private func sayStillOpen() async {
        isSending = true
        failure = nil
        defer { isSending = false }

        do {
            let stillReported = try await model.api.reportVenueOpen(venueID, note: nil)
            didSend = true
            reopened(stillReported)
        } catch {
            failure = error.localizedDescription
        }
    }
}
