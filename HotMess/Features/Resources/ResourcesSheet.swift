//
//  ResourcesSheet.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// Food, shelter, health, support and safety resources in the city, from the
/// directory fetched whole for the city. "I need…" filters it on this phone,
/// so choosing a need sends nothing anywhere and nothing is logged.
///
/// It's its own full-screen cover with its own navigation, not an app route,
/// so nothing here lands in the app's history, restored state or favorites.
/// "Leave now" is always in reach: it closes everything here at once and
/// lands on Now. Resources for domestic violence or stalking go by their
/// neutral titles in the list and the title bar, and the screen is covered
/// whenever the app isn't in front, so the app switcher shows nothing.
struct ResourcesSheet: View {
    let focusResourceID: String?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var need: ResourceNeed?
    @State private var opened: CommunityResource?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Find help nearby"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) { leaveNow }
                }
                .navigationDestination(item: $opened) { resource in
                    ResourceDetail(resource: resource, advocacy: model.flyers.directory?.advocacy ?? [])
                        .toolbar { ToolbarItem(placement: .primaryAction) { leaveNow } }
                }
        }
        .overlay {
            // The app switcher's snapshot is taken once the scene isn't active.
            if scenePhase != .active {
                Color(.systemBackground).ignoresSafeArea()
            }
        }
        .task {
            model.flyers.prefetchDirectory(localeID: model.location.locale?.id)
            await model.flyers.awaitDirectory()
            if let focusResourceID, opened == nil {
                opened = model.flyers.directory?.resources.first { $0.id == focusResourceID }
            }
        }
    }

    private var leaveNow: some View {
        Button(model.flyers.directory?.quickExit ?? String(localized: "Leave now")) {
            need = nil
            opened = nil
            model.selectedTab = .now
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(.systemGray))
        .accessibilityIdentifier("resources.leaveNow")
    }

    @ViewBuilder
    private var content: some View {
        if let directory = model.flyers.directory {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            needChip(nil, label: String(localized: "Everything"))
                            ForEach(directory.needs) { needChip($0, label: $0.label) }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("I need…")
                } footer: {
                    Text("This list is for \(directory.locale.name) and is filtered on your phone. What you choose here isn't sent anywhere.")
                }

                let resources = need.map(directory.resources(for:)) ?? directory.resources
                Section {
                    if resources.isEmpty {
                        Text("Nothing listed for this yet in \(directory.locale.name).")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(resources) { resource in
                        Button {
                            opened = resource
                        } label: {
                            ResourceRow(resource: resource)
                        }
                        .tint(.primary)
                    }
                }

                Section {
                    Text("In danger right now? Call your local emergency number.")
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
        } else if model.location.locale == nil {
            ContentUnavailableView(String(localized: "Choose a city first"), systemImage: "mappin.slash",
                                   description: Text("Resources are listed by city."))
        } else if model.flyers.directoryFailed {
            ContentUnavailableView {
                Label(String(localized: "Couldn't load resources"), systemImage: "wifi.exclamationmark")
            } description: {
                Text("In danger right now? Call your local emergency number.")
            } actions: {
                Button(String(localized: "Try again")) {
                    model.flyers.prefetchDirectory(localeID: model.location.locale?.id)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func needChip(_ choice: ResourceNeed?, label: String) -> some View {
        let selected = need?.key == choice?.key
        return Button(label) { need = choice }
            .buttonStyle(.bordered)
            .tint(selected ? Color.hotMessAccent : Color(.systemGray))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A resource in the list: its title (neutral for DV and stalking), when
/// it's next on, and who it's for.
private struct ResourceRow: View {
    let resource: CommunityResource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(resource.title)
                .font(.hotMess(.headline, semibold: true))
            if let next = ResourceTimes.nextSummary(resource) {
                Text(next)
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            }
            let badges = ResourceTimes.badges(resource)
            if !badges.isEmpty {
                Text(badges.joined(separator: " · "))
                    .font(.hotMess(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A resource's page: like a venue's, with where, when and how to reach it.
private struct ResourceDetail: View {
    let resource: CommunityResource
    let advocacy: [String]

    @State private var browsing: BrowsedLink?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    // The page itself names it; the title bar keeps the neutral title.
                    Text(resource.name)
                        .font(.hotMess(.title2, semibold: true))
                    if let description = resource.description, !description.isEmpty {
                        Text(description)
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    let badges = ResourceTimes.badges(resource)
                    if !badges.isEmpty {
                        Text(badges.joined(separator: " · "))
                            .font(.hotMess(.caption, semibold: true))
                    }
                }
                .padding(.vertical, 4)
                if let note = resource.intakeNote, !note.isEmpty {
                    Label(note, systemImage: "info.circle")
                }
            }

            if resource.sensitive, !advocacy.isEmpty {
                Section {
                    ForEach(advocacy, id: \.self) { Text($0).font(.hotMess(.subheadline)) }
                }
            }

            Section(String(localized: "Get in touch")) {
                if let phone = resource.phone, let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                    Button { openURL(url) } label: { Label(phone, systemImage: "phone") }
                }
                if let text = resource.textNumber, let url = URL(string: "sms:\(text.filter(\.isNumber))") {
                    Button { openURL(url) } label: { Label(String(localized: "Text \(text)"), systemImage: "message") }
                }
                if let link = flyerHTTPS(resource.url) {
                    Button { browsing = BrowsedLink(url: link) } label: {
                        Label(String(localized: "Website"), systemImage: "safari")
                    }
                }
                if let address = resource.address {
                    Button { directions() } label: { Label(address, systemImage: "map") }
                }
            }

            if !resource.hours.isEmpty {
                Section(String(localized: "Hours")) {
                    ForEach(Array(resource.hours.enumerated()), id: \.offset) { ResourceSlotRow(slot: $0.element) }
                }
            }
            if !resource.sessions.isEmpty {
                Section(String(localized: "When and where")) {
                    ForEach(Array(resource.sessions.enumerated()), id: \.offset) { ResourceSlotRow(slot: $0.element) }
                }
            }

            Section {
                if let checked = ResourceTimes.checkedDate(resource) {
                    Text("Last checked \(checked)")
                } else {
                    Text("Details not yet checked. Call ahead before you go.")
                }
                if let source = flyerHTTPS(resource.sourceUrl) {
                    Button(String(localized: "Where this came from")) { browsing = BrowsedLink(url: source) }
                }
            }
            .font(.hotMess(.footnote))
            .foregroundStyle(.secondary)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(resource.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browsing) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }

    /// Opens Apple Maps; the app doesn't learn whether you went.
    private func directions() {
        // A DV or stalking resource's name never goes into Maps' history.
        var items = [URLQueryItem(name: "q", value: resource.address ?? (resource.sensitive ? nil : resource.name))]
        if let latitude = resource.latitude, let longitude = resource.longitude {
            items.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
        }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = items
        if let url = components?.url { openURL(url) }
    }
}

private struct ResourceSlotRow: View {
    let slot: ResourceSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ResourceTimes.describe(slot))
            if let place = slot.place ?? slot.address {
                Text(place).font(.hotMess(.footnote)).foregroundStyle(.secondary)
            }
            if let note = slot.note {
                Text(note).font(.hotMess(.footnote)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Words for when a resource is on, and who it's for.
enum ResourceTimes {
    private static let badgeFacets: [(String, String)] = [
        ("lgbtq-affirming", String(localized: "LGBTQ+ affirming")),
        ("youth-safe", String(localized: "Youth-safe")),
        ("no-id-required", String(localized: "No ID needed")),
        ("faith-based", String(localized: "Faith-based")),
        ("secular", String(localized: "Secular")),
    ]

    static func badges(_ resource: CommunityResource) -> [String] {
        badgeFacets.filter { resource.has($0.0) }.map(\.1)
    }

    /// "Thursday · 10:00–14:00" style, with "Every day" and "Times to be confirmed".
    static func describe(_ slot: ResourceSlot) -> String {
        let names = Calendar.current.weekdaySymbols
        let days = slot.days.isEmpty
            ? String(localized: "Every day")
            : slot.days.sorted().compactMap { names.indices.contains($0) ? names[$0] : nil }.joined(separator: ", ")
        switch (slot.from, slot.until) {
        case let (from?, until?): return "\(days) · \(clock(from))–\(clock(until))"
        case let (from?, nil): return String(localized: "\(days) · from \(clock(from))")
        case let (nil, until?): return String(localized: "\(days) · until \(clock(until))")
        case (nil, nil): return days
        }
    }

    static func nextSummary(_ resource: CommunityResource) -> String? {
        guard let next = resource.nextSession, let starts = date(next.startsAt) else { return nil }
        let when = starts.formatted(.dateTime.weekday(.wide).hour().minute())
        if let ends = date(next.endsAt), starts <= .now, ends > .now { return String(localized: "On now") }
        return String(localized: "Next: \(when)")
    }

    static func checkedDate(_ resource: CommunityResource) -> String? {
        guard let checked = resource.checkedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: checked)?.formatted(date: .abbreviated, time: .omitted) ?? checked
    }

    private static func date(_ iso: String) -> Date? {
        try? Date(iso, strategy: .iso8601)
    }

    /// "18:30" in the phone's own clock style.
    private static func clock(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar.current.date(bySettingHour: parts[0] % 24, minute: parts[1], second: 0, of: .now)
        else { return hhmm }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
