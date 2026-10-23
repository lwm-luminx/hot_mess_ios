import SwiftUI

/// The record behind a shared link: hero from the public share card, the one
/// payment card for its kind, and the full app underneath.
struct ClipLandingView: View {
    let link: ClipLink
    let card: ClipCard
    let invitation: ShareInvitation?
    @Bindable var session: ClipSession
    let pay: (ClipFlow) -> Void
    let getApp: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ClipHero(card: card, tags: heroTags)
                VStack(alignment: .leading, spacing: 16) {
                    switch link.kind {
                    case "people":
                        ClipTipPanel(session: session, pay: pay)
                    case "pings":
                        if let invitation { ClipPingPanel(invitation: invitation, getApp: getApp) }
                    default:
                        ClipCoverPanel(isEvent: link.kind == "events", session: session, pay: pay)
                    }
                    if !card.description.isEmpty, link.kind != "pings" {
                        ClipPanel {
                            Text(card.description).font(.system(size: 15)).foregroundStyle(ClipTheme.ink)
                        }
                    }
                    if let error = session.detailsError {
                        Text(error).font(.system(size: 13)).foregroundStyle(ClipTheme.warning).padding(.horizontal, 4)
                    }
                    Text(inAppLine).font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted).padding(.horizontal, 4)
                }
                .padding(.horizontal, 12)
                ClipGetAppFooter(title: footerTitle, action: getApp)
                if session.signedIn {
                    Button("Sign out") { Task { await session.signOut() } }
                        .font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
                        .frame(maxWidth: .infinity).disabled(session.checkout.busy)
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .background(ClipTheme.surface)
    }

    private var heroTags: [String] {
        switch link.kind {
        case "events":
            if let event = session.details?.event { return [ClipText.eventDate(event.startAt)] }
            return []
        case "venues":
            if let charge = session.details?.coverCharge, charge.payable, let from = charge.from, let time = CoverFormat.time(from) {
                return ["Doors \(time)"]
            }
            return []
        case "pings":
            return invitation.map { ["From \($0.senderName)"] } ?? []
        default:
            return []
        }
    }

    private var footerTitle: String {
        switch link.kind {
        case "events": "Get Hot Mess to RSVP"
        case "people": "Get Hot Mess to follow \(session.details?.performer?.firstName ?? card.title.firstNameForDisplay)"
        case "pings": "Get Hot Mess to join"
        default: "Get Hot Mess"
        }
    }

    private var inAppLine: String {
        switch link.kind {
        case "events": "RSVPs, the lineup and the chat are in the app."
        case "people": "Follows and posts are in the app. Cover for tonight is on the event."
        case "pings": "Only people who got this link can open it. Joining happens in the app."
        default: "Who's out tonight and the chat are in the app."
        }
    }
}

// MARK: - Hero

struct ClipHero: View {
    let card: ClipCard
    var tags: [String] = []

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = card.image, image.url.scheme == "https" {
                    AsyncImage(url: image.url) { phase in
                        if let photo = phase.image { photo.resizable().scaledToFill() } else { placeholder }
                    }.accessibilityLabel(image.alt)
                } else { placeholder }
            }
            .frame(height: 300).frame(maxWidth: .infinity).clipped()
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.72), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                if !tags.isEmpty {
                    HStack(spacing: 6) { ForEach(tags, id: \.self) { ClipGlassTag(text: $0) } }
                }
                Text(card.title).font(.system(size: 32, weight: .heavy)).kerning(-0.5).lineLimit(2)
                if !card.description.isEmpty {
                    Text(card.description).font(.system(size: 13)).lineLimit(2).opacity(0.92)
                }
            }
            .foregroundStyle(.white).padding(16)
            VStack { HStack { ClipBrandPill(); Spacer() }.padding(.horizontal, 16).padding(.top, 56); Spacer() }
        }
        .frame(height: 300)
        .accessibilityElement(children: .combine)
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color(hex: 0xFFD6E8), Color(hex: 0xC03A8A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Cover

/// Tonight's cover. Price and tiers come with a session; before one, the
/// button says what it does and the sheet signs in first.
struct ClipCoverPanel: View {
    let isEvent: Bool
    @Bindable var session: ClipSession
    let pay: (ClipFlow) -> Void

    var body: some View {
        ClipPanel {
            if let pass = session.details?.viewerPass {
                header("You're on the list", subtitle: "\(pass.nightTitle) · \(pass.tier ?? "General admission")")
                Button("Show my pass") { pay(.cover) }.buttonStyle(ClipAccentButtonStyle())
            } else if let details = session.details {
                if let charge = details.coverCharge, charge.payable {
                    HStack(alignment: .firstTextBaseline) {
                        header("Cover tonight", subtitle: subtitle(charge, venue: details.venue))
                        Spacer()
                        Text(charge.price).font(.system(size: 24, weight: .heavy)).foregroundStyle(ClipTheme.ink)
                    }
                    ClipApplePayButton(label: .checkout) { pay(.cover) }
                    ClipFinePrint(text: Text("Includes fees. Refundable until the door scans it."))
                } else {
                    header("No cover tonight", subtitle: isEvent
                        ? "Nothing to pay ahead at \(details.venue?.name ?? "the venue")."
                        : "Nothing to pay ahead. Come on in.")
                }
            } else {
                header("Cover tonight", subtitle: isEvent
                    ? "Skip the line at the door. Price and tiers show at checkout."
                    : "Pay ahead and skip the line. Price and tiers show at checkout.")
                ClipApplePayButton(label: .checkout) { pay(.cover) }
            }
        }
    }

    private func subtitle(_ charge: CoverCharge, venue: ClipVenue?) -> String {
        var parts = [CoverFormat.night(charge.night)]
        if isEvent, let venue { parts.append(venue.name) }
        if let tiers = charge.tiers, !tiers.isEmpty { parts.append("\(tiers.count + 1) tiers") }
        return parts.joined(separator: " · ")
    }

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(ClipTheme.ink)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
        }
    }
}

// MARK: - Tip

struct ClipTipPanel: View {
    @Bindable var session: ClipSession
    let pay: (ClipFlow) -> Void
    @State private var selected: Int?

    private var performer: ClipPerformer? { session.details?.performer }
    private var tipping: ClipPerformer.Tipping? { performer?.tipping }

    var body: some View {
        ClipPanel {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tip \(performer?.firstName ?? "the performer")").font(.system(size: 17, weight: .bold)).foregroundStyle(ClipTheme.ink)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
            }
            if let tipping, tipping.acceptsInApp {
                let amounts = tipping.amounts
                let chips = Array(amounts.chips.prefix(3))
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { cents in
                        ClipChip(title: ClipTipAmounts.whole(cents, amounts.currency), selected: selected == cents) { selected = cents }
                    }
                    ClipChip(title: "Other", selected: selected == nil && !chips.isEmpty) { selected = nil }
                }
                .onAppear { if selected == nil { selected = amounts.suggested } }
                ClipApplePayButton(label: .tip) { pay(.tip(preselectedCents: selected)) }
            } else if let tipping {
                ForEach(tipping.options.filter { !$0.isInApp }) { option in
                    if let url = option.url, ["https", "http"].contains(url.scheme ?? "") {
                        Link("Tip with \(option.name)", destination: url).buttonStyle(ClipQuietButtonStyle())
                    }
                }
            } else if session.details == nil {
                ClipApplePayButton(label: .tip) { pay(.tip(preselectedCents: nil)) }
            }
        }
    }

    private var subtitle: String {
        if let tipping, tipping.acceptsInApp {
            "Goes to \(performer?.firstName ?? "them") through Hot Mess."
        } else if tipping != nil {
            "\(performer?.firstName ?? "They") takes tips outside Hot Mess."
        } else if session.details != nil {
            "\(performer?.firstName ?? "They") hasn't set up tips yet."
        } else {
            "Pick an amount at checkout. Goes to them through Hot Mess."
        }
    }
}

// MARK: - Ping

struct ClipPingPanel: View {
    let invitation: ShareInvitation
    let getApp: () -> Void

    var body: some View {
        ClipPanel {
            HStack(spacing: 12) {
                Text(invitation.senderName.initialsForDisplay).font(.system(size: 17, weight: .heavy)).foregroundStyle(ClipTheme.accentInk)
                    .frame(width: 48, height: 48).background(ClipTheme.accentSoft, in: Circle())
                    .overlay(Circle().strokeBorder(AngularGradient(colors: ClipTheme.spectrum + [ClipTheme.spectrum[0]], center: .center), lineWidth: 3))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(invitation.senderName) invited you").font(.system(size: 17, weight: .bold)).foregroundStyle(ClipTheme.ink)
                    Text("Ends \(invitation.expiresAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
                }
            }
            if let note = invitation.note, !note.isEmpty {
                Text("“\(note)”").font(.system(size: 15)).foregroundStyle(ClipTheme.ink)
            }
            ForEach(invitation.targets) { target in
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(ClipTheme.accentInk)
                        .frame(width: 36, height: 36).background(ClipTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(target.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(ClipTheme.ink)
                }
            }
        }
        ClipPanel {
            Text("Tell \(invitation.senderName.firstNameForDisplay) you're in").font(.system(size: 17, weight: .bold)).foregroundStyle(ClipTheme.ink)
            Text("Joining happens in the app, so \(invitation.senderName.firstNameForDisplay) sees who's coming and you see who else is out. This link carries your invitation into the app.")
                .font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
            Button("I'm in · Get Hot Mess") { getApp() }.buttonStyle(ClipAccentButtonStyle())
        }
    }
}

// MARK: - Footer and states

struct ClipGetAppFooter: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(ClipQuietButtonStyle()).padding(.horizontal, 12).padding(.top, 8)
    }
}

/// Skeleton in the shell's shapes, with the brand pill from the first frame.
struct ClipLoadingView: View {
    let kind: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                ClipTheme.photoPlaceholder
                VStack(alignment: .leading, spacing: 10) {
                    bone(width: 120, height: 26, light: 0.14)
                    bone(width: 220, height: 32, light: 0.22)
                    bone(width: 180, height: 14, light: 0.14)
                }.padding(16)
                VStack { HStack { ClipBrandPill(); Spacer() }.padding(.horizontal, 16).padding(.top, 56); Spacer() }
            }
            .frame(height: 300)
            ClipPanel {
                HStack { VStack(alignment: .leading, spacing: 8) { grey(110, 18); grey(200, 12) }; Spacer(); grey(48, 28) }
                RoundedRectangle(cornerRadius: 25).fill(ClipTheme.controlFill).frame(height: 50)
            }.padding(.horizontal, 12)
            ClipPanel { grey(160, 14); grey(120, 12) }.padding(.horizontal, 12)
            Spacer()
            HStack(spacing: 10) {
                ClipSpectrumBar().frame(width: 48)
                Text("Getting tonight's details").font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
            }.frame(maxWidth: .infinity).padding(.bottom, 28)
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel("Loading")
    }
    private func bone(width: CGFloat, height: CGFloat, light: Double) -> some View {
        RoundedRectangle(cornerRadius: height / 2).fill(.white.opacity(light)).frame(width: width, height: height)
    }
    private func grey(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6).fill(ClipTheme.controlFill).frame(width: width, height: height)
    }
}

/// A signed invitation that has run out.
struct ClipExpiredView: View {
    let link: ClipLink
    let getApp: () -> Void
    var body: some View {
        ClipStateShell(symbol: "clock.badge.xmark", title: "This invitation has expired",
                       message: "Ping invitations last a day. Ask whoever sent it for a fresh one, or see what's on without it.") {
            Link("See it on hotmess.social", destination: URL(string: "https://hotmess.social\(link.path)")!)
                .buttonStyle(ClipQuietButtonStyle())
            Button("Get Hot Mess") { getApp() }.buttonStyle(ClipAccentButtonStyle())
        }
    }
}

/// Chat, locale and unknown links: that one's in the app.
struct ClipUnsupportedView: View {
    let receivedLink: Bool
    let getApp: () -> Void
    var body: some View {
        ClipStateShell(symbol: "sparkles", title: receivedLink ? "That one's in the app" : "Welcome to Hot Mess",
                       message: receivedLink
                           ? "This link opens something the clip can't show. Hot Mess has it, with tonight's venues, events and people."
                           : "Open a venue, event, performer or Ping link to see what's on and pay cover.") {
            Link("Open hotmess.social", destination: URL(string: "https://hotmess.social/")!).buttonStyle(ClipQuietButtonStyle())
            Button("Get Hot Mess") { getApp() }.buttonStyle(ClipAccentButtonStyle())
        }
    }
}

struct ClipFailedView: View {
    let message: String
    let retry: () -> Void
    let getApp: () -> Void
    var body: some View {
        ClipStateShell(symbol: "wifi.exclamationmark", title: "Couldn't open this link", message: message) {
            Button("Try again", action: retry).buttonStyle(ClipAccentButtonStyle())
            Button("Get Hot Mess") { getApp() }.buttonStyle(ClipQuietButtonStyle())
        }
    }
}

private struct ClipStateShell<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 16) {
            HStack { ClipBrandPill(onPhoto: false); Spacer() }
            Spacer()
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(ClipTheme.accentInk)
            Text(title).font(.system(size: 28, weight: .heavy)).kerning(-0.5).multilineTextAlignment(.center).foregroundStyle(ClipTheme.ink)
            Text(message).font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(ClipTheme.inkMuted)
            Spacer()
            ClipSpectrumBar().frame(width: 48)
            VStack(spacing: 10) { actions }
        }
        .padding(16).padding(.bottom, 12)
        .background(ClipTheme.surface)
    }
}

enum ClipText {
    static func eventDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Tonight · \(date.formatted(date: .omitted, time: .shortened))" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow · \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}
