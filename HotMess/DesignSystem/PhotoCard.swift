//
//  PhotoCard.swift
//  HotMess
//

import Kingfisher
import SwiftUI

enum CardMetrics {
    static let photoHeight: CGFloat = 132
    static let featuredHeight: CGFloat = 180
    static let personHeight: CGFloat = 84
    static let spacing: CGFloat = 12
    /// Venues are full-width strips, so they read differently from event cards.
    static let stripHeight: CGFloat = 104
    static let stripSpacing: CGFloat = 2

    /// `radius-photo`.
    static var cornerRadius: CGFloat { HotMessRadius.photo }
}

/// A rounded card filled by a photo, with its text written over it in whichever
/// colour the photo can carry, like a small hero.
///
/// The area behind `content` is read with the hero's brightness check: white
/// text when it reaches the target, dark text only when the photo needs no
/// scrim, otherwise white text over the lightest scrim that does. `leading` and
/// `trailing` sit in the top corners and bring their own backgrounds. With no
/// photo the card is the accent gradient with white text.
private let photoCardCoordinateSpace = "photoCard"

struct PhotoCard<Content: View, Leading: View, Trailing: View>: View {
    let url: URL?
    var minHeight: CGFloat = CardMetrics.photoHeight
    /// Space kept clear above the text for the corner badges.
    var topClearance: CGFloat = 52
    /// Blurs the photo, for pictures too small or square to fill the card sharply.
    var blur: CGFloat = 0
    var alignment: Alignment = .bottomLeading
    /// `radius-photo`, or `radius-bubble` for an event shared in chat.
    var cornerRadius: CGFloat = CardMetrics.cornerRadius
    @ViewBuilder var content: Content
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var tone = HeroTone.placeholder
    @State private var image: UIImage?
    @State private var size: CGSize = .zero
    @State private var textFrame: CGRect = .zero

    var body: some View {
        content
            .foregroundStyle(tone.textColor)
            .photoTextShadow(tone)
            .animation(HotMessMotion.quick, value: tone)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(photoCardCoordinateSpace)) } action: { textFrame = $0 }
            .padding(.horizontal, 18)
            .padding(.top, topClearance)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .coordinateSpace(.named(photoCardCoordinateSpace))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .background {
                photo
                    .overlay { scrim }
                    .clipped()
            }
            .overlay(alignment: .topLeading) {
                leading.padding(12)
            }
            .overlay(alignment: .topTrailing) {
                trailing.padding(12)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .contentShape(.rect(cornerRadius: cornerRadius))
            .accessibilityElement(children: .combine)
            .task(id: url) { await loadImage() }
            .onChange(of: analysisKey, initial: true) { analyze() }
    }

    // MARK: - Layers

    @ViewBuilder
    private var photo: some View {
        if let url {
            // No fade, for the same reason as the hero: the scrim and text are
            // drawn at once.
            KFImage(url)
                .cancelOnDisappear(true)
                .placeholder { Color.hotMessPhotoPlaceholder }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: blur, opaque: true)
        } else {
            LinearGradient(
                colors: [Color.hotMessAccent, Color.hotMessAccent.mix(with: .black, by: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .environment(\.colorScheme, .light)
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: tone.scrimColor.opacity(tone.scrim), location: 0),
                .init(color: tone.scrimColor.opacity(tone.scrim), location: bandFraction),
                .init(color: tone.scrimColor.opacity(0), location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: scrimHeight)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .animation(HotMessMotion.quick, value: tone)
    }

    // MARK: - Analysis

    private var bandHeight: CGFloat { max(0, size.height - textFrame.minY + 8) }
    private var scrimHeight: CGFloat { min(size.height, bandHeight + 40) }
    private var bandFraction: CGFloat { min(1, bandHeight / max(1, scrimHeight)) }

    private var increasedContrast: Bool { colorSchemeContrast == .increased }
    private var target: Double { increasedContrast ? 7 : 4.5 }
    private var scrimFloor: Double { increasedContrast || reduceTransparency ? ImageTone.accessibleScrimFloor : 0 }

    private var cacheKey: String? {
        url.map { "card|\(minHeight)|\(blur)|\($0.absoluteString)|\(target)|\(scrimFloor)" }
    }

    private struct AnalysisKey: Equatable {
        var hasImage: Bool
        var size: CGSize
        var textFrame: CGRect
        var target: Double
        var scrimFloor: Double
    }

    private var analysisKey: AnalysisKey {
        AnalysisKey(hasImage: image != nil, size: size, textFrame: textFrame, target: target, scrimFloor: scrimFloor)
    }

    private func loadImage() async {
        image = nil
        guard let url else { return }
        if let key = cacheKey, let cached = HeroToneCache.tone(for: key) {
            tone = cached
        }
        image = try? await KingfisherManager.shared.retrieveImage(with: url).image
    }

    private func analyze() {
        guard url != nil else {
            tone = .placeholder
            return
        }
        guard
            let cgImage = image?.cgImage,
            size.width > 0, size.height > 0, textFrame.height > 0
        else { return }

        // A card has no status bar, so the band stands in for the top area too.
        // A blurred photo is judged unblurred, which can only overestimate the
        // brightest pixels, so the scrim errs on the dark side.
        let band = CGRect(x: 14, y: max(0, textFrame.minY - 8), width: size.width - 28, height: bandHeight)
        guard let decided = ImageTone.analyze(
            cgImage,
            viewSize: size,
            top: band,
            band: band,
            target: target,
            scrimFloor: scrimFloor
        ) else { return }

        tone = decided
        if let key = cacheKey { HeroToneCache.store(decided, for: key) }
    }
}

/// Shared presentation for people, venues and events. Screens customize the
/// description (for example a person's next appearance), while record adapters
/// supply photos and badges.
struct RecordCard<Leading: View, Trailing: View>: View {
    let title: String
    var description: String?
    let photoURL: URL?
    var portraitURL: URL?
    var showsPortrait = false
    var minHeight: CGFloat = CardMetrics.photoHeight
    var topClearance: CGFloat = 52
    var titleStyle: Font.TextStyle = .title3
    var descriptionLines = 2
    var trailingClearance: CGFloat = 0
    var cornerRadius: CGFloat = CardMetrics.cornerRadius
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        PhotoCard(
            url: photoURL,
            minHeight: minHeight,
            topClearance: topClearance,
            blur: showsPortrait ? 24 : 0,
            alignment: showsPortrait ? .leading : .bottomLeading,
            cornerRadius: cornerRadius
        ) {
            HStack(spacing: 14) {
                if showsPortrait {
                    Avatar(url: portraitURL, initials: title.initialsForDisplay, size: 56)
                        .overlay { Circle().strokeBorder(Color.hotMessAvatarRing, lineWidth: 2) }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.hotMess(titleStyle, semibold: true))
                        .lineLimit(2)

                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.hotMess(.subheadline, semibold: true))
                            .lineLimit(descriptionLines)
                    }
                }
            }
            .padding(.trailing, trailingClearance)
        } leading: {
            leading
        } trailing: {
            trailing
        }
    }
}

// MARK: - Badges

/// A small label on dark glass, for a card's top corners. It reads on any
/// photo, so it needs no brightness check of its own.
struct GlassPill<PillContent: View>: View {
    var padding = EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
    var shape: AnyShape = AnyShape(Capsule())
    @ViewBuilder var content: PillContent

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(padding)
            .background(Color.hotMessGlass, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .environment(\.colorScheme, .dark)
    }
}

extension GlassPill where PillContent == Text {
    init(_ text: String) {
        self.init {
            Text(text)
                .font(.hotMess(.footnote, semibold: true))
                .monospacedDigit()
        }
    }
}

/// Overlapping friend photos, for the corner of a `VenueCard`.
struct FriendFaces: View {
    let friends: [Friend]
    var limit = 4

    var body: some View {
        HStack(spacing: -7) {
            ForEach(Array(friends.prefix(limit).enumerated()), id: \.element.id) { index, friend in
                Avatar(
                    url: friend.avatarURL,
                    initials: friend.name.initialsForDisplay,
                    size: 26
                )
                .overlay { Circle().strokeBorder(Color.hotMessAvatarRing, lineWidth: 2) }
                // Drawn over the ring, which would otherwise cover half of it.
                .overlay(alignment: .bottomTrailing) {
                    if let presence = friend.presence {
                        PresenceDot(state: presence, size: 8, ringColor: Color.hotMessAvatarRing)
                            .offset(x: 1, y: 1)
                    }
                }
                // Each face over the next, so its presence dot isn't hidden.
                .zIndex(Double(limit - index))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Venues

/// A venue as a photo card: its name and summary over its photo, with a pill
/// top right (a distance, a friend count) and `corner` top left (friend faces).
struct VenueCard<Corner: View>: View {
    let venue: Venue
    var description: String?
    var pill: String?
    @ViewBuilder var corner: Corner

    var body: some View {
        RecordCard(
            title: venue.name,
            description: description ?? venue.summary,
            photoURL: venue.bannerURL ?? venue.photoURL,
            minHeight: CardMetrics.stripHeight,
            topClearance: 44,
            cornerRadius: 0
        ) {
            corner
        } trailing: {
            if let pill {
                GlassPill(pill)
            }
        }
    }
}

extension VenueCard where Corner == EmptyView {
    init(venue: Venue, description: String? = nil, pill: String?) {
        self.init(venue: venue, description: description, pill: pill) { EmptyView() }
    }

    /// The card for a venue list: its summary, and how far away it is.
    init(venue: Venue) {
        self.init(
            venue: venue,
            pill: venue.distance.map { DistanceFormat.string(fromMetres: $0) }
        )
    }
}

/// A `VenueCard` that opens the venue.
struct VenueCardLink<Card: View>: View {
    let venue: Venue
    @ViewBuilder var card: Card

    var body: some View {
        NavigationLink(value: AppRoute.venue(venue.id)) {
            card
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.venue.\(venue.id)")
    }
}

extension VenueCardLink where Card == VenueCard<EmptyView> {
    init(venue: Venue) {
        self.init(venue: venue) { VenueCard(venue: venue) }
    }
}

// MARK: - Events

/// An event as a photo card over its cover: the date top left, your RSVP top
/// right, and the name with when and where at the bottom. Featured events are taller.
struct EventCard: View {
    let event: Event
    var description: String?
    var photoURL: URL?

    var body: some View {
        RecordCard(
            title: event.name,
            description: description ?? event.subtitle,
            photoURL: photoURL ?? event.bannerURL,
            minHeight: event.isFeatured ? CardMetrics.featuredHeight : CardMetrics.photoHeight,
            topClearance: 68,
            titleStyle: event.isFeatured ? .title2 : .title3,
            descriptionLines: 1
        ) {
            GlassPill(padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8), shape: AnyShape(RoundedRectangle(cornerRadius: HotMessRadius.md))) {
                VStack(spacing: 0) {
                    Text(event.startDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.hotMess(.caption2, semibold: true))
                    Text(event.startDate.formatted(.dateTime.day()))
                        .font(.hotMess(.title3, semibold: true))
                        .monospacedDigit()
                }
                .frame(minWidth: 30)
            }
            .accessibilityLabel(event.startDate.formatted(date: .abbreviated, time: .omitted))
        } trailing: {
            VStack(alignment: .trailing, spacing: 6) {
                RSVPBadge(rsvp: event.rsvp)
                if event.isKaraoke {
                    Label(String(localized: "Karaoke"), systemImage: "music.mic")
                        .font(.hotMess(.caption, semibold: true))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityIdentifier("karaoke.badge")
                }
            }
        }
    }
}

/// An `EventCard` that opens the event.
struct EventCardLink: View {
    let event: Event
    var description: String?
    var photoURL: URL?

    var body: some View {
        NavigationLink(value: AppRoute.event(event.id)) {
            EventCard(event: event, description: description, photoURL: photoURL)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.event.\(event.id)")
    }
}

/// An event shared in a chat room (RichMessage "event"): a card for the
/// event, an optional caption, and "See event". The room sends only the
/// event's name and start, so the card wears the accent rather than a photo.
/// Tapping the card or the button opens the event.
struct SharedEventMessage: View {
    let event: SharedEvent
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: AppRoute.event(event.id)) {
                card
            }
            .buttonStyle(.plain)

            if let caption {
                Text(caption)
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .textSelection(.enabled)
            }

            NavigationLink(value: AppRoute.event(event.id)) {
                Text("See event")
                    .font(.hotMess(.subheadline, semibold: true))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Color.hotMessAccentInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var name: String {
        event.name.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "An event")
    }

    private var card: some View {
        RecordCard(
            title: name,
            description: event.startAt.map { $0.formatted(.dateTime.weekday(.wide).hour().minute()) },
            photoURL: nil,
            minHeight: 112,
            topClearance: event.startAt == nil ? 14 : 64,
            descriptionLines: 1,
            cornerRadius: ChatMetrics.bubbleRadius
        ) {
            if let startAt = event.startAt {
                GlassPill(padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8), shape: AnyShape(RoundedRectangle(cornerRadius: HotMessRadius.md))) {
                    VStack(spacing: 0) {
                        Text(startAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.hotMess(.caption2, semibold: true))
                        Text(startAt.formatted(.dateTime.day()))
                            .font(.hotMess(.title3, semibold: true))
                            .monospacedDigit()
                    }
                    .frame(minWidth: 30)
                }
                .accessibilityLabel(startAt.formatted(date: .abbreviated, time: .omitted))
            }
        } trailing: {
            EmptyView()
        }
    }
}

// MARK: - People

/// A person as a shorter card: their picture enlarged and blurred behind a sharp
/// round avatar, with their name and role (or `description`) beside it, and `friends`
/// with them top right. Profile pictures are small square faces, so filling a
/// wide card with one sharply would crop the head and show the pixels.
struct PersonCard: View {
    let person: Person
    var description: String?
    var friends: [Friend] = []

    var body: some View {
        RecordCard(
            title: person.name,
            description: description ?? person.role,
            photoURL: person.avatarURL,
            portraitURL: person.avatarURL,
            showsPortrait: true,
            minHeight: CardMetrics.personHeight,
            topClearance: 14,
            titleStyle: .headline,
            descriptionLines: 1,
            trailingClearance: friends.isEmpty ? 0 : 64
        ) {
            EmptyView()
        } trailing: {
            if !friends.isEmpty {
                FriendFaces(friends: friends, limit: 3)
            }
        }
        .accessibilityValue(friendsSummary)
    }

    private var friendsSummary: String {
        guard !friends.isEmpty else { return "" }
        let names = friends.map(\.name).formatted(.list(type: .and))
        return String(localized: "With \(names)")
    }
}

/// A `PersonCard` that opens the person.
struct PersonCardLink: View {
    let person: Person
    var description: String?
    var friends: [Friend] = []

    var body: some View {
        NavigationLink(value: AppRoute.person(person.id)) {
            PersonCard(person: person, description: description, friends: friends)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.person.\(person.id)")
    }
}

// MARK: - Sections

/// A titled stack of cards for screens that scroll in a `ScrollView`. Unlike
/// `DetailSection` the rows bring their own background. A section with no rows
/// draws nothing, header included. `edgeToEdge` lays the rows out as full-width
/// strips with a hairline gap, as venues use.
struct CardSection<Content: View>: View {
    let title: String?
    var edgeToEdge = false
    let content: Content

    init(_ title: String? = nil, edgeToEdge: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.edgeToEdge = edgeToEdge
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { rows in
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(.hotMess(.subheadline, semibold: true))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 36)
                    }

                    LazyVStack(spacing: edgeToEdge ? CardMetrics.stripSpacing : CardMetrics.spacing) {
                        ForEach(rows) { $0 }
                    }
                    .padding(.horizontal, edgeToEdge ? 0 : 16)
                }
            }
        }
    }
}
