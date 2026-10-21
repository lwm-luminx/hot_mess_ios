//
//  SuggestListingScreen.swift
//  HotMess
//

import AudienceKit
import CoreLocation
import SwiftUI

/// "Suggest a venue" or "Suggest an event": something Hot Mess is missing.
/// Only the name and where it is are needed. A person checks it before it
/// goes up; when it's already listed, nothing is filed and the member is
/// shown the listing instead.
struct SuggestListingScreen: View {
    enum Kind: Hashable { case venue, event }

    let kind: Kind
    /// The venue a missing event is at, when it was suggested from its page.
    var venue: Venue?
    /// Closes whatever presented the form; by default the form dismisses itself.
    var finish: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var link = ""
    @State private var note = ""
    @State private var venues: [Venue] = []
    @State private var venueID: UUID?
    @State private var venueName = ""
    @State private var startsAt = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
    @State private var hasEnd = false
    @State private var endsAt = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
    @State private var isSending = false
    @State private var failure: String?
    @State private var alreadyListed: AlreadyListed?
    @State private var sent: SentSuggestion?

    var body: some View {
        Form {
            Section {
                TextField(kind == .venue ? String(localized: "Name of the bar or club") : String(localized: "Name of the night"), text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("suggest.name")
            } header: {
                Text("Name")
            } footer: {
                Text(kind == .venue
                    ? String(localized: "Only the name and where it is are needed.")
                    : String(localized: "Only the name, where and when are needed."))
            }

            switch kind {
            case .venue: venueFields
            case .event: eventFields
            }

            Section {
                TextField(String(localized: "Anything else? (optional)"), text: $note, axis: .vertical)
                    .lineLimit(3...6)
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
        .navigationTitle(kind == .venue ? String(localized: "Suggest a venue") : String(localized: "Suggest an event"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { close() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button(String(localized: "Send")) {
                        Task { await send(notListed: false) }
                    }
                    .disabled(!canSend)
                    .accessibilityIdentifier("suggest.send")
                }
            }
        }
        .task {
            venueID = venue?.id
            guard kind == .event, venue == nil else { return }
            await loadVenues()
        }
        .sheet(item: $alreadyListed) { listed in
            AlreadyListedSheet(
                listed: listed,
                open: {
                    alreadyListed = nil
                    close()
                    model.open(listed.route)
                },
                differentPlace: {
                    alreadyListed = nil
                    Task { await send(notListed: true) }
                }
            )
            .presentationDetents([.medium])
        }
        .alert(String(localized: "Thanks, it's sent"), isPresented: Binding(
            get: { sent != nil },
            set: { if !$0 { sent = nil } }
        )) {
            Button(String(localized: "OK")) { close() }
        } message: {
            Text(sent?.message ?? "")
        }
    }

    private func close() {
        if let finish { finish() } else { dismiss() }
    }

    // MARK: - Fields

    @ViewBuilder
    private var venueFields: some View {
        Section {
            TextField(String(localized: "Street address"), text: $address, axis: .vertical)
                .textContentType(.fullStreetAddress)
                .lineLimit(1...3)
                .accessibilityIdentifier("suggest.address")
        } header: {
            Text("Where is it?")
        }

        Section {
            TextField(String(localized: "Website or Instagram (optional)"), text: $link)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("A link helps us check it faster.")
        }
    }

    @ViewBuilder
    private var eventFields: some View {
        Section {
            if let venue {
                Text(venue.name)
            } else {
                Picker(String(localized: "Venue"), selection: $venueID) {
                    Text("Somewhere not listed").tag(UUID?.none)
                    ForEach(venues) { venue in
                        Text(venue.name).tag(UUID?.some(venue.id))
                    }
                }
                if venueID == nil {
                    TextField(String(localized: "Where is it?"), text: $venueName)
                        .textInputAutocapitalization(.words)
                }
            }
        } header: {
            Text("Where")
        }

        Section {
            DatePicker(String(localized: "Starts"), selection: $startsAt)
            Toggle(String(localized: "Ends"), isOn: $hasEnd)
            if hasEnd {
                DatePicker(String(localized: "Ends at"), selection: $endsAt, in: startsAt...)
            }
        } header: {
            Text("When")
        }

        Section {
            TextField(String(localized: "Ticket or event link (optional)"), text: $link)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("A link helps us check it faster.")
        }
    }

    // MARK: - Sending

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        guard !trimmedName.isEmpty else { return false }
        switch kind {
        case .venue: return !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .event: return venueID != nil || !venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func loadVenues() async {
        let localeID = model.location.locale?.id
        guard let all = try? await model.audienceKit.venues() else { return }
        venues = VenueCollection(audienceVenues: all, localeID: localeID, resolve: model.audienceKit.url(for:)).venues
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func send(notListed: Bool) async {
        isSending = true
        failure = nil
        defer { isSending = false }

        do {
            let suggestion = await request(notListed: notListed)
            switch try await model.api.suggest(suggestion) {
            case let .alreadyListed(listed):
                alreadyListed = listed
            case let .sent(_, merged):
                sent = SentSuggestion(merged: merged)
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func request(notListed: Bool) async -> SuggestionRequest {
        var request = SuggestionRequest(
            kind: kind == .venue ? .missingVenue : .missingEvent,
            localeID: model.location.locale?.id,
            body: note,
            notListed: notListed
        )
        request.proposed["name"] = .string(trimmedName)

        switch kind {
        case .venue:
            let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            request.proposed["address"] = .string(address)
            if let point = await AddressLookup.coordinate(for: address, near: model.location.coordinates) {
                request.proposed["latitude"] = .double(point.latitude)
                request.proposed["longitude"] = .double(point.longitude)
            }
            if !trimmedLink.isEmpty {
                request.proposed["website"] = .string(trimmedLink)
                request.evidence = [SuggestionEvidence(url: trimmedLink)]
            }
        case .event:
            if let venueID {
                request.proposed["venue_id"] = .string(venueID.uuidString.lowercased())
            } else {
                request.proposed["venue_name"] = .string(venueName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            request.proposed["start_at"] = .string(SuggestionFormat.timestamp(startsAt))
            if hasEnd { request.proposed["end_at"] = .string(SuggestionFormat.timestamp(endsAt)) }
            if !trimmedLink.isEmpty {
                request.proposed["ticket_url"] = .string(trimmedLink)
                request.evidence = [SuggestionEvidence(url: trimmedLink)]
            }
        }
        return request
    }
}

/// The confirmation after sending.
struct SentSuggestion: Hashable {
    let merged: Bool

    var message: String {
        merged
            ? String(localized: "Someone else suggested this too. We'll check them together, and let you know in Your suggestions.")
            : String(localized: "We'll let you know in Your suggestions when it's checked.")
    }
}

/// "It's already on Hot Mess": a missing venue or event matched a listing,
/// so nothing was filed.
struct AlreadyListedSheet: View {
    let listed: AlreadyListed
    let open: () -> Void
    let differentPlace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("It's already on Hot Mess")
                .font(.hotMess(.title2, semibold: true))
            Text(listed.kind == .venue
                ? String(localized: "We found a venue with a name like that close by. Is this the one?")
                : String(localized: "We found an event like that at the same place and time. Is this the one?"))
                .foregroundStyle(.secondary)

            Button(action: open) {
                Text("Open \(listed.name)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.hotMessAccent)
            .controlSize(.large)

            Button(action: differentPlace) {
                Text(listed.kind == .venue ? String(localized: "No, it's a different place") : String(localized: "No, it's a different event"))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .accessibilityIdentifier("suggest.differentPlace")
        }
        .padding(24)
    }
}

/// Turning a typed address into a pin.
@MainActor
enum AddressLookup {
    static func coordinate(for address: String, near: Coordinates?) async -> (latitude: Double, longitude: Double)? {
        guard !address.isEmpty else { return nil }
        let geocoder = CLGeocoder()
        let region = near.map {
            CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                radius: 50_000,
                identifier: "near"
            )
        }
        return await withCheckedContinuation { continuation in
            geocoder.geocodeAddressString(address, in: region) { placemarks, _ in
                let coordinate = placemarks?.first?.location?.coordinate
                continuation.resume(returning: coordinate.map { (latitude: $0.latitude, longitude: $0.longitude) })
            }
        }
    }
}

enum SuggestionFormat {
    /// `2026-10-24T21:00:00Z`, as the API casts times.
    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
