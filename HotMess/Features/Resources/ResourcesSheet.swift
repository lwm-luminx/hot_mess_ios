//
//  ResourcesSheet.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// "Need support?": the support lines for where the user is (they work with
/// no city chosen), then the food, shelter, health, support and safety
/// resources in the city, from the directory fetched whole for the city. "I need…" and the search filter it
/// on this phone, so choosing a need or typing sends nothing anywhere and
/// nothing is logged.
///
/// It's its own full-screen cover with its own navigation, not an app route,
/// so nothing here lands in the app's history, restored state or favorites.
/// "Leave now" is always in reach: it closes everything here at once and
/// lands on Now. Resources for domestic violence or stalking go by their
/// neutral titles in the list and the title bar, and the screen is covered
/// whenever the app isn't in front, so the app switcher shows nothing.
///
/// The order is by urgency: the needs (short labels from the server, only the
/// ones with something listed here), then crisis lines with a call button on
/// the row, then everything else, then the emergency number. No state is a
/// dead end: an empty search still offers the crisis lines and a way back.
struct ResourcesSheet: View {
    let focusResourceID: String?
    /// What staff wrote when they shared this from an alert.
    var sharedNote: String?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var need: ResourceNeed?
    @State private var search = ""
    @State private var opened: CommunityResource?
    /// The crisis and support lines for the region (`supportResources`).
    @State private var support: SupportResources?
    @State private var rides: [SupportResources.Ride] = []

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Need support?"))
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
        .task { await loadSupport() }
        .task {
            model.flyers.prefetchDirectory(localeID: model.location.locale?.id)
            await model.flyers.awaitDirectory()
            if let focusResourceID, opened == nil {
                opened = model.flyers.directory?.resources.first { $0.id == focusResourceID }
            }
        }
    }

    /// The support lines and ride apps for where the phone is: only the
    /// region (US-UT) is sent, as "Need support?" always has.
    private func loadSupport() async {
        let region = await SupportRegion.region(near: model.location.coordinates)
        support = try? await model.api.supportResources(region: region)
        rides = (try? await model.api.supportRides(region: region)) ?? []
    }

    private var pickup: RidePickup? {
        model.location.coordinates.map { RidePickup(coordinates: $0, name: nil) }
    }

    /// Staff's note when they shared this from an alert, first in every state.
    @ViewBuilder
    private var noteSection: some View {
        if let sharedNote, !sharedNote.isEmpty {
            Section {
                Text(sharedNote).font(.hotMess(.body))
            } header: {
                Text("A note from the venue")
            }
        }
    }

    /// The support lines, the way home and the emergency number: what every
    /// state ends with, so none is a dead end.
    @ViewBuilder
    private func alwaysThere(lines: Bool = true) -> some View {
        if lines, let support, !support.lines.isEmpty { SupportLinesSection(resources: support) }
        Section {
            GetARideRow(rides: rides, pickup: pickup, place: nil)
        } header: {
            Text("Get home safe")
        }
        if let support { EmergencySection(number: support.emergency) } else { EmergencySection() }
    }

    private var leaveNow: some View {
        Button(model.flyers.directory?.quickExit ?? String(localized: "Leave now")) {
            need = nil
            search = ""
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
            list(directory)
                // Searched on this phone, over the list already here.
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text("Search this list"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } else if model.location.locale == nil {
            List {
                noteSection
                Section {
                    Label(String(localized: "Choose a city to see food, shelter and health near you."),
                          systemImage: "mappin.slash")
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                }
                alwaysThere()
            }
            .listStyle(.insetGrouped)
        } else if model.flyers.directoryFailed {
            List {
                noteSection
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Couldn't load resources"), systemImage: "wifi.exclamationmark")
                            .font(.hotMess(.headline, semibold: true))
                        Text("Check your connection and try again. The emergency number below works without it.")
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Button(String(localized: "Try again")) {
                        model.flyers.prefetchDirectory(localeID: model.location.locale?.id)
                    }
                }
                alwaysThere()
            }
            .listStyle(.insetGrouped)
        } else {
            List {
                noteSection
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading help near you…").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                alwaysThere()
            }
            .listStyle(.insetGrouped)
        }
    }

    private func list(_ directory: CommunityDirectory) -> some View {
        let results = ResourceBrowser.results(in: directory, need: need, search: search)
        let browsing = need == nil && ResourceBrowser.words(search).isEmpty
        return List {
            noteSection
            Section {
                NeedGrid(needs: ResourceBrowser.offeredNeeds(directory), selected: need) { need = $0 }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            } header: {
                Text("I need…")
            } footer: {
                Text("For \(directory.locale.name). Filtered on your phone: what you tap or type here isn't sent anywhere.")
            }

            if results.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing listed here matches that.")
                            .font(.hotMess(.headline, semibold: true))
                        Text("Try another word, or see everything in \(directory.locale.name).")
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Button(String(localized: "Show everything")) {
                        need = nil
                        search = ""
                    }
                    .accessibilityIdentifier("resources.showEverything")
                }
                // Never a dead end: the crisis lines are still here.
                let lines = ResourceBrowser.urgent(directory.resources)
                if !lines.isEmpty {
                    Section(String(localized: "Help right now")) { rows(lines) }
                }
            } else if browsing, !results.urgent.isEmpty {
                Section(String(localized: "Help right now")) { rows(results.urgent) }
                // The lines that work anywhere sit with the city's crisis lines.
                if let support, !support.lines.isEmpty { SupportLinesSection(resources: support) }
                if !results.rest.isEmpty {
                    Section(String(localized: "More in \(directory.locale.name)")) { rows(results.rest) }
                }
            } else {
                Section(need?.label ?? String(localized: "Results")) { rows(results.urgent + results.rest) }
            }

            if browsing || results.isEmpty {
                alwaysThere(lines: !(browsing && !results.urgent.isEmpty))
            } else if let support {
                EmergencySection(number: support.emergency)
            } else {
                EmergencySection()
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rows(_ resources: [CommunityResource]) -> some View {
        ForEach(resources) { resource in
            ResourceRow(resource: resource, open: { opened = resource }, call: { openURL($0) })
        }
    }
}

/// The "I need…" choices as tiles: every one on screen at once, no sideways
/// scrolling, each a full-size target. One column at the largest text sizes.
private struct NeedGrid: View {
    let needs: [ResourceNeed]
    let selected: ResourceNeed?
    let choose: (ResourceNeed?) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var tileWidth: CGFloat = 150

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 8)], spacing: 8) {
            tile(nil, key: "everything", label: String(localized: "Everything"))
            ForEach(needs) { tile($0, key: $0.key, label: $0.label) }
        }
    }

    private func tile(_ choice: ResourceNeed?, key: String, label: String) -> some View {
        let isSelected = selected?.key == choice?.key
        return Button {
            choose(choice)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: ResourceBrowser.symbol(forNeed: key))
                    .font(.body)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.hotMess(.subheadline, semibold: isSelected))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .foregroundStyle(isSelected ? Color.hotMessAccentInk : Color.primary)
            .background(isSelected ? Color.hotMessAccentSoft : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text("Filters the list on this phone."))
        .accessibilityIdentifier("resources.need.\(key)")
    }
}

/// A resource in the list: what it is, its title (neutral for DV and
/// stalking), when it's next on and who it's for, with a call button of its
/// own so the phone number is one tap from the list.
private struct ResourceRow: View {
    let resource: CommunityResource
    let open: () -> Void
    let call: (URL) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: ResourceBrowser.symbol(for: resource))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(resource.title)
                            .font(.hotMess(.headline, semibold: true))
                        let about = ResourceBrowser.kinds(resource) + ResourceTimes.badges(resource)
                        if !about.isEmpty {
                            Text(about.joined(separator: " · "))
                                .font(.hotMess(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        if let next = ResourceTimes.nextSummary(resource) {
                            Text(next)
                                .font(.hotMess(.caption, semibold: true))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let phone = resource.phone, let url = ResourceBrowser.callURL(phone) {
                Button {
                    call(url)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.body)
                        .foregroundStyle(Color.hotMessAccentInk)
                        .frame(width: 44, height: 44)
                        .background(Color.hotMessAccentSoft, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Call \(resource.title)"))
            }
        }
        .padding(.vertical, 2)
    }
}

/// A resource's page: like a venue's, with how to reach it first, then when
/// and where.
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
                    let about = ResourceBrowser.kinds(resource) + ResourceTimes.badges(resource)
                    if !about.isEmpty {
                        Text(about.joined(separator: " · "))
                            .font(.hotMess(.caption, semibold: true))
                    }
                }
                .padding(.vertical, 4)
                if let note = resource.intakeNote, !note.isEmpty {
                    Label(note, systemImage: "info.circle")
                }
            }

            Section {
                VStack(spacing: 10) {
                    if let phone = resource.phone, let url = ResourceBrowser.callURL(phone) {
                        Button { openURL(url) } label: {
                            Label(String(localized: "Call \(ResourceBrowser.phoneText(phone))"), systemImage: "phone.fill")
                                .font(.hotMess(.body, semibold: true))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("resource.call")
                    }
                    if let text = resource.textNumber, let url = ResourceBrowser.callURL(text, scheme: "sms") {
                        action(String(localized: "Text \(ResourceBrowser.phoneText(text))"), "message") { openURL(url) }
                    }
                    if resource.address != nil || (resource.latitude != nil && resource.longitude != nil) {
                        action(String(localized: "Directions"), "map") { directions() }
                    }
                    if let link = flyerHTTPS(resource.url) {
                        action(String(localized: "Website"), "safari") { browsing = BrowsedLink(url: link) }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if let address = resource.address { Text(address) }
            }

            if resource.sensitive, !advocacy.isEmpty {
                Section {
                    ForEach(advocacy, id: \.self) { Text($0).font(.hotMess(.subheadline)) }
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

            EmergencySection()
        }
        .listStyle(.insetGrouped)
        .navigationTitle(resource.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browsing) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(.hotMess(.body, semibold: true))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
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

/// How the resource browser filters, orders and names things. All of it runs
/// on the phone over the directory already fetched: nothing here asks the
/// server for anything.
enum ResourceBrowser {
    /// Crisis and any-time lines carry this facet; they lead the list.
    static let urgentFacet = "crisis"

    struct Results: Equatable {
        var urgent: [CommunityResource]
        var rest: [CommunityResource]
        var isEmpty: Bool { urgent.isEmpty && rest.isEmpty }
    }

    /// The needs with at least one resource in this city, so no tile leads to an empty list.
    static func offeredNeeds(_ directory: CommunityDirectory) -> [ResourceNeed] {
        directory.needs.filter { !directory.resources(for: $0).isEmpty }
    }

    static func urgent(_ resources: [CommunityResource]) -> [CommunityResource] {
        resources.filter { $0.has(urgentFacet) }
    }

    /// The resources for a need and a search, crisis lines apart from the rest, each in the server's order.
    static func results(in directory: CommunityDirectory, need: ResourceNeed?, search: String) -> Results {
        let words = words(search)
        let found = (need.map(directory.resources(for:)) ?? directory.resources).filter { matches($0, words: words) }
        return Results(urgent: urgent(found), rest: found.filter { !$0.has(urgentFacet) })
    }

    static func words(_ search: String) -> [String] {
        search.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every word is somewhere in its title, name, description, kinds, badges or address.
    static func matches(_ resource: CommunityResource, words: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let text = ([resource.title, resource.name, resource.description ?? "", resource.address ?? ""]
            + kinds(resource) + ResourceTimes.badges(resource)).joined(separator: " ")
        return words.allSatisfy { text.localizedStandardContains($0) }
    }

    private static let kindFacets: [(String, String)] = [
        ("crisis", String(localized: "Crisis support")),
        ("food", String(localized: "Food")),
        ("shelter", String(localized: "Shelter")),
        ("health-coverage", String(localized: "Health coverage")),
        ("sti-testing", String(localized: "Testing")),
        ("mental-health", String(localized: "Mental health")),
    ]

    /// What it offers, in a word or two. A DV or stalking resource says nothing here: its neutral title is all a
    /// glance at the list should give away.
    static func kinds(_ resource: CommunityResource) -> [String] {
        resource.sensitive ? [] : kindFacets.filter { resource.has($0.0) }.map(\.1)
    }

    /// The row's symbol, by the most urgent thing it offers. Sensitive resources get the same one as any other line.
    static func symbol(for resource: CommunityResource) -> String {
        if resource.sensitive || resource.has("crisis") { return "phone.bubble" }
        if resource.has("food") { return "fork.knife" }
        if resource.has("shelter") { return "bed.double" }
        if resource.has("health-coverage") || resource.has("sti-testing") { return "cross.case" }
        if resource.has("mental-health") { return "bubble.left.and.bubble.right" }
        return "heart"
    }

    static func symbol(forNeed key: String) -> String {
        switch key {
        case "everything": "square.grid.2x2"
        case "food": "fork.knife"
        case "shelter": "bed.double"
        case "health": "cross.case"
        case "talk": "bubble.left.and.bubble.right"
        case "safe": "house"
        default: "heart"
        }
    }

    /// A tel: (or sms:) link for a number as the API stores it: digits, maybe a leading +.
    static func callURL(_ number: String, scheme: String = "tel") -> URL? {
        let digits = number.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return URL(string: "\(scheme):\(number.hasPrefix("+") ? "+" : "")\(digits)")
    }

    /// A number for reading: North American numbers as (801) 264-9999, anything else as stored.
    static func phoneText(_ number: String) -> String {
        var digits = number.filter { $0.isASCII && $0.isNumber }
        if digits.count == 11, digits.hasPrefix("1"), number.hasPrefix("+1") || !number.hasPrefix("+") {
            digits.removeFirst()
        } else if digits.count != 10 || number.hasPrefix("+") {
            return number
        }
        let area = digits.prefix(3), exchange = digits.dropFirst(3).prefix(3), line = digits.suffix(4)
        return "(\(area)) \(exchange)-\(line)"
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
        let days = dayText(slot.days)
        switch (slot.from, slot.until) {
        case let (from?, until?): return "\(days) · \(clock(from))–\(clock(until))"
        case let (from?, nil): return String(localized: "\(days) · from \(clock(from))")
        case let (nil, until?): return String(localized: "\(days) · until \(clock(until))")
        case (nil, nil): return days
        }
    }

    /// "Every day", "Thursday", "Monday–Friday" (three or more days in a row) or "Tuesday, Thursday".
    static func dayText(_ days: [Int]) -> String {
        let names = Calendar.current.weekdaySymbols
        let sorted = Set(days).sorted().filter { names.indices.contains($0) }
        if sorted.isEmpty || sorted.count == 7 { return String(localized: "Every day") }
        let inARow = zip(sorted, sorted.dropFirst()).allSatisfy { $1 == $0 + 1 }
        if inARow, sorted.count > 2, let first = sorted.first, let last = sorted.last {
            return "\(names[first])–\(names[last])"
        }
        return sorted.map { names[$0] }.joined(separator: ", ")
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
