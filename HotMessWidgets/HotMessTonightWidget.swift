//
//  HotMessTonightWidget.swift
//  HotMessWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

/// "Hot Mess - Tonight" on the Home Screen and Lock Screen: a card that
/// rotates through the next few events, with where each one is and Going
/// and Ping buttons, then friends' Pings with who's in (and "I'm in" on ones
/// the user hasn't joined).
///
/// It draws what the app last saved (``TonightSnapshot``) and never calls the
/// API itself; the app saves whenever it loads Now, after a button, and in its
/// background refresh. Ended Pings and events drop off on their own, and the
/// card moves to the next event every ``TonightSnapshot/rotation``. Names are
/// as the API gave them and are hidden while the phone is locked.
struct HotMessTonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TonightStore.widgetKind, provider: TonightProvider()) { entry in
            TonightView(entry: entry)
                .containerBackground(for: .widget) { TonightView.background }
        }
        .configurationDisplayName("Hot Mess - Tonight")
        .description("What's coming up and where, with Going and Ping buttons, and friends' Pings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TonightEntry: TimelineEntry {
    let date: Date
    /// Nil before the app has saved anything (signed out, or never opened).
    let snapshot: TonightSnapshot?
    /// Where the user stepped the card with the previous and next buttons.
    var browsing: TonightBrowse?

    /// The event the rotating card shows.
    var featured: TonightSnapshot.Event? { snapshot?.featuredEvent(at: date, browsing: browsing) }
}

/// The large widget's previous and next buttons: show the event before or
/// after the one on the card, for a while (``TonightBrowse/hold``). It runs in
/// the widget extension and only touches the app group, so it needs no app or
/// sign-in; WidgetKit redraws the widget once it returns.
struct StepTonightEventIntent: AppIntent {
    static var title: LocalizedStringResource { "Show another event" }
    static var description: IntentDescription { IntentDescription("Shows the previous or next event on the Tonight widget.") }
    static var isDiscoverable: Bool { false }

    /// -1 for previous, 1 for next.
    @Parameter(title: "Step")
    var step: Int

    init() {}

    init(step: Int) {
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        let now = Date.now
        guard let snapshot = TonightStore.read() else { return .result() }
        let featured = snapshot.featuredEvent(at: now, browsing: TonightStore.readBrowse())
        if let next = snapshot.event(step, from: featured, at: now) {
            TonightStore.writeBrowse(TonightBrowse(eventID: next.id, until: now.addingTimeInterval(TonightBrowse.hold)))
        }
        return .result()
    }
}

struct TonightProvider: TimelineProvider {
    /// How far ahead one timeline rotates before WidgetKit asks for another.
    static let horizon: TimeInterval = 4 * 60 * 60
    /// WidgetKit keeps a timeline's entries in memory; this keeps it small.
    static let maxEntries = 24

    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        let saved = TonightStore.read()
        completion(TonightEntry(
            date: .now, snapshot: context.isPreview && saved == nil ? .sample : saved?.current(at: .now),
            browsing: TonightStore.readBrowse()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        let now = Date.now
        guard let saved = TonightStore.read() else {
            completion(Timeline(entries: [TonightEntry(date: now, snapshot: nil)], policy: .never))
            return
        }
        let browsing = TonightStore.readBrowse().flatMap { $0.until > now ? $0 : nil }
        // The card goes back to rotating when a step's hold runs out.
        let dates = (Self.entryDates(for: saved, from: now) + [browsing?.until].compactMap { $0 }).sorted()
        let entries = dates.map { TonightEntry(date: $0, snapshot: saved.current(at: $0), browsing: browsing) }
        // Rotating: ask again once this run is used up. Otherwise the app
        // reloads it when anything changes.
        // The card may start rotating later (tonight's events come within
        // the window), so a timeline with events always asks again.
        let hasEvents = !saved.current(at: now).events.isEmpty
        completion(Timeline(entries: entries, policy: hasEvents ? .atEnd : .never))
    }

    /// Now, each time the card moves to the next event (while there's more
    /// than one), and each time a Ping or event ends, so they drop off
    /// without the app running.
    static func entryDates(for snapshot: TonightSnapshot, from now: Date) -> [Date] {
        var dates: Set<Date> = [now]
        var date = now
        while dates.count < maxEntries / 2, let next = snapshot.nextChange(after: date) {
            date = next.addingTimeInterval(1)
            dates.insert(date)
        }
        // Every rotation slot within the horizon while there are events: the
        // card rotates once more than one is on tonight, and the time labels
        // ("Tomorrow 9:00 PM") move on with the clock.
        var rotation = now
        while !snapshot.current(at: rotation).events.isEmpty {
            rotation = TonightSnapshot.nextRotation(after: rotation)
            guard rotation < now.addingTimeInterval(horizon) else { break }
            dates.insert(rotation)
        }
        return Array(dates.sorted().prefix(maxEntries))
    }
}

struct TonightView: View {
    let entry: TonightEntry

    @Environment(\.widgetFamily) private var family

    static let accent = Color(red: 1.0, green: 0.27, blue: 0.58)
    static let background = LinearGradient(
        colors: [Color(red: 0.16, green: 0.04, blue: 0.14), Color(red: 0.05, green: 0.02, blue: 0.08)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private var pingLimit: Int {
        switch family {
        case .systemSmall, .accessoryRectangular, .systemMedium: 1
        default: 2
        }
    }

    var body: some View {
        if let snapshot = entry.snapshot {
            if family == .accessoryRectangular {
                accessory(snapshot)
            } else {
                content(snapshot)
                    .widgetURL(entry.featured?.url ?? snapshot.pings.first?.url ?? URL(string: "hotmess://now"))
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header(nil, snapshot: nil)
                Spacer(minLength: 0)
                Text("Open Hot Mess to see what's on and who's going out.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Home Screen

    @ViewBuilder
    private func content(_ snapshot: TonightSnapshot) -> some View {
        let featured = entry.featured
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
            // The small widget has no room for the city beside the dots.
            header(family == .systemSmall ? nil : snapshot.localeName, snapshot: snapshot)
            if let featured {
                FeaturedEventCard(event: featured, date: entry.date, compact: family == .systemSmall)
                if family == .systemLarge, snapshot.events.count > 1 {
                    EventStepper(events: snapshot.events, featuredID: featured.id)
                }
            }
            if snapshot.pings.isEmpty && featured == nil && snapshot.onNow == nil {
                Spacer(minLength: 0)
                Text("Quiet so far. Send a Ping to get the night going.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if family != .systemSmall || featured == nil {
                ForEach(snapshot.pings.prefix(pingLimit)) { ping in
                    PingRow(ping: ping, showsButton: family != .systemSmall)
                }
            }
            if family == .systemLarge, let onNow = snapshot.onNow {
                Label {
                    Text(snapshot.venueName.map { String(localized: "On now at \($0): \(onNow)") }
                        ?? String(localized: "On now: \(onNow)"))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "music.mic")
                        .foregroundStyle(Self.accent)
                }
                .font(.caption)
                .foregroundStyle(.white)
            }
            if family == .systemLarge || family == .systemMedium {
                // As many of the rest as fit the space left, soonest first.
                ComingUpList(
                    events: snapshot.events.filter { $0.id != featured?.id },
                    date: entry.date,
                    showsTitle: family == .systemLarge
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ locale: String?, snapshot: TonightSnapshot?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .foregroundStyle(Self.accent)
            Text(locale.map { String(localized: "Tonight in \($0)") } ?? String(localized: "Tonight"))
                .lineLimit(1)
            Spacer(minLength: 4)
            // The large widget has its dots beside the previous and next buttons.
            if family != .systemLarge, let snapshot, let featured = entry.featured, snapshot.rotates(at: entry.date) {
                RotationDots(events: snapshot.featuredEvents(at: entry.date), featuredID: featured.id)
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func accessory(_ snapshot: TonightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let ping = snapshot.pings.first {
                Text(ping.isMine ? String(localized: "Your Ping") : String(localized: "\(ping.sender)'s Ping"))
                    .font(.headline)
                    .privacySensitive()
                Text(ping.place ?? String(localized: "Anywhere tonight"))
                    .lineLimit(1)
                Text(ping.peopleLine.map { String(localized: "\($0) in") } ?? String(localized: "Nobody in yet"))
                    .lineLimit(1)
                    .privacySensitive()
            } else if let event = entry.featured {
                accessoryEvent(event)
            } else {
                Text("Tonight")
                    .font(.headline)
                Text("Nothing yet")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(snapshot.pings.first?.url ?? entry.featured?.url)
    }

    /// The Lock Screen card is only about half the screen wide, so most event
    /// names don't fit on one line. A name that fits gets one line with the
    /// time and place under it; a longer one gets two lines (shrinking a
    /// little if it must) and the time, and the place gives way.
    private func accessoryEvent(_ event: TonightSnapshot.Event) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(EventTime.label(for: event, at: entry.date))
                    .lineLimit(1)
                    .modifier(NoIdealWidth())
                if let location = event.location {
                    Text(location)
                        .lineLimit(1)
                        .modifier(NoIdealWidth())
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(EventTime.label(for: event, at: entry.date))
                    .lineLimit(1)
                    .modifier(NoIdealWidth())
            }
        }
    }
}

/// Lets a line truncate without counting toward the width `ViewThatFits`
/// measures, so only the event name decides which layout is used.
private struct NoIdealWidth: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// The rotating card: when, what, where, and the Going and Ping buttons
/// (Ping only for something tonight, since a Ping ends at 5am).
private struct FeaturedEventCard: View {
    let event: TonightSnapshot.Event
    let date: Date
    /// The small widget: buttons as icons under the text.
    let compact: Bool

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                details(nameLines: 2)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    goingButton(iconOnly: true)
                    if event.isPingable(at: date) { pingButton(iconOnly: true) }
                }
            }
        } else {
            // Labelled buttons when the name fits on one line beside them;
            // otherwise icon buttons, which leave the name room for two lines.
            ViewThatFits(in: .horizontal) {
                row(nameLines: 1, iconOnly: false)
                row(nameLines: 2, iconOnly: true)
            }
            .padding(8)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func row(nameLines: Int, iconOnly: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            details(nameLines: nameLines)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                goingButton(iconOnly: iconOnly)
                if event.isPingable(at: date) { pingButton(iconOnly: iconOnly) }
            }
            .fixedSize()
        }
    }

    private func details(nameLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(EventTime.label(for: event, at: date))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(TonightView.accent)
                .lineLimit(1)
                .modifier(NoIdealWidth())
            Text(event.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(nameLines)
                .minimumScaleFactor(0.85)
            if let location = event.location {
                Label {
                    Text(location)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .labelStyle(TightLabel())
                .modifier(NoIdealWidth())
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func goingButton(iconOnly: Bool) -> some View {
        Button(intent: SetGoingIntent(eventID: event.id, going: !event.isGoing)) {
            if iconOnly {
                Image(systemName: event.isGoing ? "checkmark.circle.fill" : "plus.circle")
                    .accessibilityLabel(event.isGoing ? Text("Going") : Text("I'm going"))
            } else {
                Label("Going", systemImage: event.isGoing ? "checkmark" : "plus")
            }
        }
        .modifier(WidgetButtonStyle(filled: event.isGoing))
    }

    private func pingButton(iconOnly: Bool) -> some View {
        Button(intent: PingEventIntent(eventID: event.id)) {
            if iconOnly {
                Image(systemName: event.isPinged ? "hand.wave.fill" : "hand.wave")
                    .accessibilityLabel(event.isPinged ? Text("Pinged") : Text("Ping friends"))
            } else {
                Label(
                    event.isPinged ? LocalizedStringKey("Pinged") : LocalizedStringKey("Ping"),
                    systemImage: event.isPinged ? "hand.wave.fill" : "hand.wave"
                )
            }
        }
        .modifier(WidgetButtonStyle(filled: event.isPinged))
        .disabled(event.isPinged)
    }
}

/// Accent-filled once done (Going, Pinged), outlined before.
private struct WidgetButtonStyle: ViewModifier {
    let filled: Bool

    func body(content: Content) -> some View {
        if filled {
            content
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(TonightView.accent)
        } else {
            content
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(TonightView.accent)
        }
    }
}

/// An icon close to its text, for the small location line.
private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// The large widget's previous and next buttons, with a dot per event (the
/// one on the card lit) between them. Widgets can't take swipes, so these are
/// how to look through everything coming up.
private struct EventStepper: View {
    let events: [TonightSnapshot.Event]
    let featuredID: String

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: StepTonightEventIntent(step: -1)) {
                Label("Previous", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(Text("Previous event"))
            RotationDots(events: events, featuredID: featuredID)
                .layoutPriority(1)
            Button(intent: StepTonightEventIntent(step: 1)) {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(Text("Next event"))
        }
        .font(.subheadline.weight(.bold))
        .buttonStyle(.bordered)
        .tint(TonightView.accent)
    }
}

/// One dot per event, the featured one lit, so it reads as rotating.
private struct RotationDots: View {
    let events: [TonightSnapshot.Event]
    let featuredID: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(events) { event in
                Circle()
                    .fill(event.id == featuredID ? TonightView.accent : .white.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// When an event is, said against the entry's date: "On now", "9:00 PM",
/// "Tomorrow 9:00 PM", "Fri 9:00 PM", or "Fri, Dec 5".
enum EventTime {
    static func label(for event: TonightSnapshot.Event, at date: Date, calendar: Calendar = .current) -> String {
        if event.startsAt <= date { return String(localized: "On now") }
        let time = event.startsAt.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(event.startsAt, inSameDayAs: date) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
           calendar.isDate(event.startsAt, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow \(time)")
        }
        if event.startsAt < date.addingTimeInterval(6 * 24 * 60 * 60) {
            let day = event.startsAt.formatted(.dateTime.weekday(.abbreviated))
            return "\(day) \(time)"
        }
        return event.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// A friend's Ping (or the user's): who sent it, where, and who's in.
private struct PingRow: View {
    let ping: TonightSnapshot.Ping
    let showsButton: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "hand.wave.fill")
                .foregroundStyle(TonightView.accent)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .privacySensitive()
                Text(ping.peopleLine.map { String(localized: "\($0) in") } ?? String(localized: "Nobody in yet"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .privacySensitive()
            }
            Spacer(minLength: 0)
            if showsButton {
                if ping.canJoin {
                    Button(intent: JoinPingIntent(pingID: ping.id)) {
                        Text("I'm in")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TonightView.accent)
                } else if ping.joined || ping.isMine {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(TonightView.accent)
                }
            }
        }
        .modifier(LinkTo(url: ping.url, enabled: showsButton))
    }

    private var title: String {
        let who = ping.isMine ? String(localized: "Your Ping") : String(localized: "\(ping.sender)'s Ping")
        guard let place = ping.place else { return who }
        return "\(who) · \(place)"
    }
}

/// The events after the featured one, as many as fit the space the widget
/// has left: the large widget fills its lower half (more on a taller phone,
/// fewer when Pings take room), the medium one adds a row when the card leaves
/// space for it.
private struct ComingUpList: View {
    let events: [TonightSnapshot.Event]
    let date: Date
    let showsTitle: Bool

    var body: some View {
        if events.isEmpty {
            Color.clear
        } else {
            // ViewThatFits takes the first that fits, so the longest goes first.
            ViewThatFits(in: .vertical) {
                list(8)
                list(7)
                list(6)
                list(5)
                list(4)
                list(3)
                list(2)
                list(1)
                Color.clear.frame(height: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The title and the first `count` rows (all of them when there are fewer).
    private func list(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsTitle {
                Text("Coming up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
            }
            ForEach(events.prefix(count)) { event in
                EventRow(event: event, date: date)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Another event coming up, in the medium and large widgets' list.
private struct EventRow: View {
    let event: TonightSnapshot.Event
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(EventTime.label(for: event, at: date))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(TonightView.accent)
                .lineLimit(2)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let location = event.location {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if event.isGoing {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(TonightView.accent)
            }
        }
        .modifier(LinkTo(url: event.url, enabled: true))
    }
}

/// Makes a row open its own link (medium and large widgets); the small one
/// opens one link for the whole widget.
private struct LinkTo: ViewModifier {
    let url: URL?
    let enabled: Bool

    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        if enabled, family != .systemSmall, let url {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

extension TonightSnapshot {
    /// For the widget gallery.
    static var sample: TonightSnapshot {
        let now = Date.now
        return TonightSnapshot(
            updatedAt: now,
            localeName: "Seattle",
            events: [
                Event(id: "1", name: "Drag Bingo", place: "Purr", startsAt: now.addingTimeInterval(3600),
                      address: "1518 11th Ave, Seattle", going: true),
                Event(id: "2", name: "Disco Night", place: "Neighbours", startsAt: now.addingTimeInterval(7200),
                      address: "1509 Broadway, Seattle"),
                Event(id: "3", name: "Bear Brunch", place: "The Cuff", startsAt: now.addingTimeInterval(26 * 3600),
                      address: "1533 13th Ave, Seattle"),
            ],
            pings: [
                Ping(id: "1", sender: "Sam", place: "Purr", people: ["Alex", "Jo", "Kai"], joined: false, isMine: false,
                     expiresAt: now.addingTimeInterval(6 * 3600)),
            ]
        )
    }
}
