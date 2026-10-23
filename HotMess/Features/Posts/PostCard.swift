//
//  PostCard.swift
//  HotMess
//

import SwiftUI

/// What a card's `…` menu asks its list to do.
struct PostActions {
    var report: (Post) -> Void = { _ in }
    var hidePoster: (PostPoster) -> Void = { _ in }
}

/// A post as a full card (design system "Post card"): byline, metadata, body,
/// photos, the event chip and the comments footer, on `surface-raised`.
struct PostCard: View {
    let post: Post
    /// Off where pins don't float (the updates feed).
    var showsPin = true
    /// Off on the event's own page.
    var showsEvent = true
    /// The full text, on the post screen; six lines then "More" in lists.
    var isExpanded = false
    var actions = PostActions()

    @Environment(AppModel.self) private var model
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostByline(post: post, showsPin: showsPin, showsEvent: showsEvent) {
                optionsMenu
            }

            if !post.body.isEmpty {
                PostBodyText(text: post.body, lineLimit: isExpanded || showsAll ? nil : 6) {
                    showsAll = true
                }
            }

            if !post.photos.isEmpty {
                PostPhotoGrid(photos: post.photos)
                    .padding(.horizontal, -16)
            }

            if showsEvent, let event = post.event {
                PostEventChip(event: event)
            }

            footer
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: CardMetrics.cornerRadius))
        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                .strokeBorder(Color.hotMessBorder, lineWidth: 1)
                .opacity(0.6)
        }
        .accessibilityIdentifier("post.card")
    }

    private var footer: some View {
        HStack(spacing: 20) {
            if !isExpanded {
                NavigationLink(value: AppRoute.post(post.id)) {
                    Label(commentsTitle, systemImage: "bubble.left")
                }
                .accessibilityIdentifier("post.comments")
            }

            if let shareURL = post.shareURL {
                ShareLink(item: shareURL, message: Text(post.body)) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
            }

            Spacer(minLength: 0)
        }
        .font(.hotMess(.subheadline, semibold: true))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    private var commentsTitle: String {
        switch post.commentCount {
        case 0: post.commentsOpen ? String(localized: "Comment") : String(localized: "Comments off")
        case 1: String(localized: "1 comment")
        default: String(localized: "\(post.commentCount) comments")
        }
    }

    private var optionsMenu: some View {
        Menu {
            if let shareURL = post.shareURL {
                ShareLink(item: shareURL, message: Text(post.body)) {
                    Label(String(localized: "Share Post"), systemImage: "square.and.arrow.up")
                }
            }
            if model.session.isSignedIn {
                if let poster = post.poster {
                    Button {
                        actions.hidePoster(poster)
                    } label: {
                        Label(String(localized: "Hide Posts from \(poster.name)"), systemImage: "eye.slash")
                    }
                }
                Button(role: .destructive) {
                    actions.report(post)
                } label: {
                    Label(String(localized: "Report Post…"), systemImage: "exclamationmark.bubble")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .accessibilityLabel(String(localized: "Post options"))
        .accessibilityIdentifier("post.options")
    }
}

/// The poster's face, name, tag and the metadata line.
struct PostByline<Trailing: View>: View {
    let post: Post
    var showsPin = true
    var showsEvent = true
    var avatarSize: CGFloat = 40
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            posterLink {
                Avatar(
                    url: post.posterAvatarURL,
                    initials: Self.initials(post.posterName),
                    size: avatarSize,
                    isPlace: post.isVenuePost
                )
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    posterLink {
                        Text(post.posterName)
                            .font(.hotMess(.subheadline, semibold: true))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if let roleLabel = post.roleLabel {
                        PostRoleTag(label: roleLabel, isVenue: post.isVenuePost)
                    }
                    if post.pinned, showsPin {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.hotMessAccentInk)
                            .accessibilityHidden(true)
                    }
                }

                Text(post.metadata(showsPin: showsPin, showsEvent: showsEvent))
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let actingPersonName = post.actingPersonName {
                    Text(actingPersonName)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            trailing
        }
    }

    @ViewBuilder
    private func posterLink<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        if let route = post.posterRoute {
            NavigationLink(value: route) { label() }
                .buttonStyle(.plain)
        } else {
            label()
        }
    }

    static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// "Venue" in the accent; a talent's part on the event in `accent-soft`, as
/// chat's `RoleTag` draws the venue and its hosts.
struct PostRoleTag: View {
    let label: String
    let isVenue: Bool

    var body: some View {
        Text(label)
            .font(.hotMess(fixedSize: 11, semibold: true))
            .tracking(0.2)
            .foregroundStyle(isVenue ? Color.hotMessOnAccent : Color.hotMessAccentInk)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minHeight: 16)
            .background(isVenue ? Color.hotMessAccent : Color.hotMessAccentSoft, in: .capsule)
            .fixedSize()
    }
}

/// The post's text, links tappable, up to `lineLimit` lines then "More".
struct PostBodyText: View {
    let text: String
    var lineLimit: Int?
    var onMore: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.linked(text))
                .font(.hotMess(.body))
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)

            if let lineLimit, Self.isLong(text, lines: lineLimit) {
                Button(String(localized: "More"), action: onMore)
                    .font(.hotMess(.subheadline, semibold: true))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
    }

    /// Whether the text likely runs past `lines` on a phone: more line breaks
    /// than that, or more than about 45 characters a line.
    static func isLong(_ text: String, lines: Int) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).count > lines || text.count > lines * 45
    }

    /// Plain text with its web links made tappable; no other formatting.
    nonisolated static func linked(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, url.scheme == "http" || url.scheme == "https",
                  let textRange = Range(match.range, in: text),
                  let start = AttributedString.Index(textRange.lowerBound, within: attributed),
                  let end = AttributedString.Index(textRange.upperBound, within: attributed) else { continue }
            attributed[start..<end].link = url
        }
        return attributed
    }
}

/// Photos edge to edge: one at 4:3, two side by side, three or four in a 2×2 grid.
struct PostPhotoGrid: View {
    let photos: [PostPhoto]

    var body: some View {
        let shown = Array(photos.prefix(4))
        Group {
            switch shown.count {
            case 1:
                tile(shown[0]).aspectRatio(4 / 3, contentMode: .fit)
            case 2:
                HStack(spacing: 2) { ForEach(shown.indices, id: \.self) { tile(shown[$0]) } }
                    .aspectRatio(2, contentMode: .fit)
            default:
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow { tile(shown[0]); tile(shown[1]) }
                    GridRow {
                        tile(shown[2])
                        if shown.count > 3 { tile(shown[3]) } else { Color.clear }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tile(_ photo: PostPhoto) -> some View {
        Color.hotMessPhotoPlaceholder
            .overlay { RemoteImage(url: photo.url) }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(photo.altText ?? String(localized: "Photo"))
            .accessibilityAddTraits(.isImage)
    }
}

/// The event a post is on: date tile, name and time, to the event.
struct PostEventChip: View {
    let event: Post.EventLink

    var body: some View {
        NavigationLink(value: AppRoute.event(event.id)) {
            HStack(spacing: 12) {
                if let startAt = event.startAt {
                    VStack(spacing: 0) {
                        Text(startAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.hotMess(fixedSize: 10, semibold: true))
                            .foregroundStyle(Color.hotMessAccentInk)
                        Text(startAt.formatted(.dateTime.day()))
                            .font(.hotMess(fixedSize: 18, semibold: true))
                    }
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name)
                        .font(.hotMess(.subheadline, semibold: true))
                        .lineLimit(1)
                    if let startAt = event.startAt {
                        Text(startAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color.hotMessControlFill, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("post.event")
    }
}

/// A post as a compact row for Now: face, name, tag, time, two lines and a
/// thumbnail.
struct PostRow: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(
                url: post.posterAvatarURL,
                initials: PostByline<EmptyView>.initials(post.posterName),
                size: 32,
                isPlace: post.isVenuePost
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.posterName)
                        .font(.hotMess(.subheadline, semibold: true))
                        .lineLimit(1)
                    if let roleLabel = post.roleLabel {
                        PostRoleTag(label: roleLabel, isVenue: post.isVenuePost)
                    }
                    Text(Post.relativeTime(post.createdAt))
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
                Text(post.body)
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let photo = post.photos.first {
                RemoteImage(url: photo.url)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: HotMessRadius.sm))
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }
}
