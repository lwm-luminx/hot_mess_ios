//
//  HotMessTonightWidget.swift
//  HotMessWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

/// "Tonight" on the Home Screen and Lock Screen: friends' Pings with who's in
/// (and "I'm in" on ones the user hasn't joined), then what's on tonight.
///
/// It draws what the app last saved (``TonightSnapshot``) and never calls the
/// API itself; the app saves whenever it loads Now, after a button, and in its
/// background refresh. Ended Pings and events drop off on their own. Names are
/// as the API gave them and are hidden while the phone is locked.
struct HotMessTonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TonightStore.widgetKind, provider: TonightProvider()) { entry in
            TonightView(entry: entry)
                .containerBackground(for: .widget) { TonightView.background }
        }
        .configurationDisplayName("Tonight")
        .description("Friends' Pings and who's in, and what's on tonight.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TonightEntry: TimelineEntry {
    let date: Date
    /// Nil before the app has saved anything (signed out, or never opened).
    let snapshot: TonightSnapshot?
}

struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        let saved = TonightStore.read()
        completion(TonightEntry(date: .now, snapshot: context.isPreview && saved == nil ? .sample : saved?.current(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        let now = Date.now
        guard let saved = TonightStore.read() else {
            completion(Timeline(entries: [TonightEntry(date: now, snapshot: nil)], policy: .never))
            return
        }
        // One entry now and one each time a Ping or event ends, so they drop
        // off without the app running. The app reloads it when anything else
        // changes.
        var entries = [TonightEntry(date: now, snapshot: saved.current(at: now))]
        var date = now
        while entries.count < 8, let next = saved.nextChange(after: date) {
            date = next.addingTimeInterval(1)
            entries.append(TonightEntry(date: date, snapshot: saved.current(at: date)))
        }
        completion(Timeline(entries: entries, policy: .never))
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
        case .systemSmall, .accessoryRectangular: 1
        case .systemMedium: 2
        default: 3
        }
    }

    private var eventLimit: Int {
        switch family {
        case .systemSmall, .accessoryRectangular: 1
        case .systemMedium: 2
        default: 4
        }
    }

    var body: some View {
        if let snapshot = entry.snapshot {
            if family == .accessoryRectangular {
                accessory(snapshot)
            } else {
                content(snapshot)
                    .widgetURL(snapshot.pings.first?.url ?? URL(string: "hotmess://now"))
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header(nil)
                Spacer(minLength: 0)
                Text("Open Hot Mess to see what's on and who's going out.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Home Screen

    private func content(_ snapshot: TonightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snapshot.localeName)
            if snapshot.pings.isEmpty && snapshot.events.isEmpty && snapshot.onNow == nil {
                Spacer(minLength: 0)
                Text("Quiet so far. Send a Ping to get the night going.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            ForEach(snapshot.pings.prefix(pingLimit)) { ping in
                PingRow(ping: ping, showsButton: family != .systemSmall)
            }
            if let onNow = snapshot.onNow, family != .systemSmall {
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
            let events = snapshot.events.prefix(snapshot.pings.isEmpty ? eventLimit + 1 : eventLimit)
            if !events.isEmpty, family != .systemSmall || snapshot.pings.isEmpty {
                ForEach(events) { event in
                    EventRow(event: event)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ locale: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .foregroundStyle(Self.accent)
            Text(locale.map { String(localized: "Tonight in \($0)") } ?? String(localized: "Tonight"))
                .lineLimit(1)
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
            } else if let event = snapshot.events.first {
                Text("Tonight")
                    .font(.headline)
                Text(event.name)
                    .lineLimit(1)
                Text(event.startsAt, style: .time)
            } else {
                Text("Tonight")
                    .font(.headline)
                Text("Nothing yet")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(snapshot.pings.first?.url ?? snapshot.events.first?.url)
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

/// Something on tonight.
private struct EventRow: View {
    let event: TonightSnapshot.Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(event.startsAt, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(TonightView.accent)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let place = event.place {
                    Text(place)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
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
            venueName: "Purr",
            onNow: "Karaoke",
            events: [
                Event(id: "1", name: "Drag Bingo", place: "Purr", startsAt: now.addingTimeInterval(3600), endsAt: nil),
                Event(id: "2", name: "Disco Night", place: "Neighbours", startsAt: now.addingTimeInterval(7200), endsAt: nil),
            ],
            pings: [
                Ping(id: "1", sender: "Sam", place: "Purr", people: ["Alex", "Jo", "Kai"], joined: false, isMine: false,
                     expiresAt: now.addingTimeInterval(6 * 3600)),
            ]
        )
    }
}
