//
//  ManagedListingNotice.swift
//  HotMess
//

import AudienceKitUI
import SwiftUI

/// "You manage this venue · Open in Velvet" on a venue the signed-in person
/// manages, and the same with Backstage on their person page. Hot Mess
/// doesn't edit pages; the staff app does. On a phone without the app the
/// button gets it instead ("Join the Velvet beta", "Get Backstage").
/// On an event at a venue they manage it opens Velvet on that event.
/// Shows nothing on anyone else's page.
struct ManagedListingNotice: View {
    enum Kind {
        case venue, person
    }

    let kind: Kind
    let id: UUID
    /// The event at venue `id` this is on, for Velvet to open on.
    var eventID: UUID?

    @Environment(AppModel.self) private var model

    var body: some View {
        if isManaged {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.hotMess(.subheadline, semibold: true))
                    Text(subtitle)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                StaffAppLink(app, url: url) { title, _ in
                    Text(title)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("\(eventID != nil ? "event" : kind == .venue ? "venue" : "person").openInStaffApp")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: CardMetrics.cornerRadius))
            .padding(.horizontal, 16)
        }
    }

    private var isManaged: Bool {
        let listings = model.listings.listings
        return (kind == .venue ? listings.venues : listings.people).contains { $0.id == id }
    }

    private var app: StaffApp { kind == .venue ? .velvet : .backstage }

    private var title: String {
        if eventID != nil { return String(localized: "This is at a venue you manage") }
        return kind == .venue ? String(localized: "You manage this venue") : String(localized: "You manage this page")
    }

    private var subtitle: String {
        eventID != nil
            ? String(localized: "Edit it in \(app.name).")
            : String(localized: "Post and manage it in \(app.name).")
    }

    private var url: URL {
        let id = id.uuidString.lowercased()
        let audienceID = model.configuration.audienceID
        return kind == .venue
            ? StaffApp.velvet(venueID: id, audienceID: audienceID, eventID: eventID?.uuidString.lowercased())
            : StaffApp.backstage(personID: id, audienceID: audienceID)
    }
}
