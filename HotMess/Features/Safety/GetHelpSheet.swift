//
//  GetHelpSheet.swift
//  HotMess
//

import SwiftUI

/// "Get help" at a venue, and the alert once it's sent: a digital "Ask for
/// Angela" (api doc/design-system/SafetyAlerts.md). Built so someone looking
/// over the user's shoulder sees nothing alarming: normal surfaces, no red
/// except 911, and nothing here ever shows in chat or on their profile.
struct GetHelpSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SafetyAlertModel
    @State private var isTellingStaff = false
    @State private var isShowingSupport = false

    init(presentation: HelpPresentation, api: HotMessAPI) {
        _model = State(initialValue: SafetyAlertModel(api: api, presentation: presentation))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let alert = model.alert {
                    SafetyAlertStatusView(model: model, alert: alert, showSupport: { isShowingSupport = true })
                } else {
                    options
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isTellingStaff) {
                TellStaffForm(model: model, mode: .send) { isTellingStaff = false }
            }
            .navigationDestination(isPresented: $isShowingSupport) {
                SupportScreen(sharedNote: model.alert?.supportSharedAt != nil ? model.alert?.supportNote : nil)
            }
            .alert(
                String(localized: "Couldn't reach staff"),
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .task { await model.load() }
        .task { await model.keepFresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    private var title: String {
        if let name = model.venue?.name { return String(localized: "Get help at \(name)") }
        return String(localized: "Get help")
    }

    /// The Get help sheet: tell staff, a friend, a ride, support, then 911.
    private var options: some View {
        List {
            Section {
                if model.venue != nil, model.staffOnShift {
                    Button {
                        isTellingStaff = true
                    } label: {
                        HelpRow(
                            title: String(localized: "Tell staff I feel unsafe"),
                            subtitle: String(localized: "The staff on shift hear it quietly and can come find you."),
                            systemImage: "shield.lefthalf.filled"
                        )
                    }
                    .accessibilityIdentifier("help.tellStaff")
                }
                HelpEscapeRows(venue: model.venue, showSupport: { isShowingSupport = true })
            } footer: {
                Text("Nothing here shows in chat or on your profile.")
            }

            EmergencySection()
        }
        .listStyle(.insetGrouped)
    }
}

/// A row in the Get help sheet: an icon on `accent-soft`, a title and a line.
struct HelpRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.hotMessAccentInk)
                .frame(width: 36, height: 36)
                .background(Color.hotMessAccentSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.hotMess(.body, semibold: true))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// "Message a friend", "Get a ride" and "Need support?": what's left when
/// nobody on shift can help, and what the no-answer screen offers.
struct HelpEscapeRows: View {
    let venue: HelpVenue?
    let showSupport: () -> Void

    var body: some View {
        ShareLink(item: friendMessage) {
            HelpRow(
                title: String(localized: "Message a friend"),
                subtitle: String(localized: "Send them where you are."),
                systemImage: "message"
            )
        }
        .accessibilityIdentifier("help.friend")

        ShareLink(item: rideMessage) {
            HelpRow(
                title: String(localized: "Get a ride"),
                subtitle: String(localized: "Share where to pick you up with a ride app."),
                systemImage: "car"
            )
        }
        .accessibilityIdentifier("help.ride")

        Button(action: showSupport) {
            HelpRow(
                title: String(localized: "Need support?"),
                subtitle: String(localized: "Free, confidential lines, any time."),
                systemImage: "heart.text.square"
            )
        }
        .accessibilityIdentifier("help.support")
    }

    private var friendMessage: String {
        let here = venue?.whereIAm ?? ""
        return String(localized: "\(here) Can you come find me?").trimmingCharacters(in: .whitespaces)
    }

    private var rideMessage: String {
        guard let venue else { return String(localized: "Pick me up here.") }
        if let address = venue.address, !address.isEmpty { return "\(venue.name), \(address)" }
        return venue.name
    }
}

/// "In danger right now? Call 911": the one red thing, always last.
struct EmergencySection: View {
    var number = "911"

    var body: some View {
        Section {
            if let url = URL(string: "tel:\(number)") {
                Link(destination: url) {
                    Label(String(localized: "Call \(number)"), systemImage: "phone.fill")
                        .font(.hotMess(.body, semibold: true))
                        .foregroundStyle(.red)
                }
                .listRowBackground(Color.token(\.dangerSoft))
                .accessibilityIdentifier("help.emergency")
            }
        } header: {
            Text("In danger right now?")
        } footer: {
            Text("Hot Mess isn't a crisis service. In an emergency, call \(number).")
        }
    }
}

/// "Tell staff quietly": where, what and anything else, all optional. Also
/// "Add more" once it's sent.
struct TellStaffForm: View {
    enum Mode { case send, addMore }

    @Bindable var model: SafetyAlertModel
    let mode: Mode
    let done: () -> Void

    var body: some View {
        Form {
            Section {
                ChipGrid(items: SafetyPlace.allCases, title: \.title, isSelected: { model.draft.place == $0 }) { place in
                    model.draft.place = model.draft.place == place ? nil : place
                }
            } header: {
                Text("Where are you?")
            }

            Section {
                ChipGrid(items: SafetyConcern.allCases, title: \.title, isSelected: { model.draft.concerns.contains($0) }) { concern in
                    if model.draft.concerns.contains(concern) {
                        model.draft.concerns.remove(concern)
                    } else {
                        model.draft.concerns.insert(concern)
                    }
                }
            } header: {
                Text("What's going on?")
            }

            Section {
                TextField(
                    String(localized: "What they look like, what they're wearing"),
                    text: $model.draft.description,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .accessibilityIdentifier("help.description")
            } header: {
                Text("Anything that helps staff spot them")
            } footer: {
                Text(mode == .send
                     ? String(localized: "You can send without filling anything in. Only staff see who sent this.")
                     : String(localized: "Staff see this straight away."))
            }

            Section {
                Button {
                    Task {
                        if mode == .send { await model.send() } else { await model.addDetails() }
                        if model.errorMessage == nil { done() }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if model.isBusy {
                            ProgressView()
                        } else {
                            Text(mode == .send ? String(localized: "Send to staff") : String(localized: "Add to my alert"))
                                .font(.hotMess(.body, semibold: true))
                        }
                        Spacer()
                    }
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("help.send")
            }
        }
        .navigationTitle(mode == .send ? String(localized: "Tell staff quietly") : String(localized: "Add more"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pill chips that wrap: `accent-soft` with an accent border when chosen.
/// They're toggle buttons for VoiceOver.
struct ChipGrid<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let title: KeyPath<Item, String>
    let isSelected: (Item) -> Bool
    let toggle: (Item) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                let selected = isSelected(item)
                Button {
                    toggle(item)
                } label: {
                    Text(item[keyPath: title])
                        .font(.hotMess(.subheadline, semibold: selected))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .foregroundStyle(selected ? Color.hotMessAccentInk : Color.primary)
                        .background(selected ? Color.hotMessAccentSoft : Color.hotMessControlFill, in: Capsule())
                        .overlay {
                            if selected { Capsule().strokeBorder(Color.accentColor, lineWidth: 1) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Lays its children out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// The quiet way in on a venue the user is at: `ink-muted` with a shield, not
/// a red SOS.
struct GetHelpButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .accessibilityHidden(true)
                Text("Get help")
                    .font(.hotMess(.subheadline, semibold: true))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: HotMessRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Tell staff quietly, reach a friend or a ride, or find support"))
        .accessibilityIdentifier("venue.getHelp")
    }
}
