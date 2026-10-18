//
//  Rows.swift
//  HotMess
//

import SwiftUI

struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: track.artworkURL)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: HotMessRadius.lg))

            VStack(alignment: .leading, spacing: 6) {
                Text(track.title)
                    .font(.hotMess(.headline, semibold: true))
                    .lineLimit(2)

                if let waveformURL = track.waveformURL {
                    RemoteImage(url: waveformURL, contentMode: .fit)
                        .frame(height: 28)
                        .opacity(0.7)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A label-and-value row, replacing the repeated `textLabel`/`detailTextLabel`
/// cell configuration scattered through the old table view controllers.
struct InfoRow: View {
    let title: String
    let value: String?
    var systemImage: String?

    var body: some View {
        LabeledContent {
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
}

/// A person's or venue's link elsewhere, with the network's glyph. Opens the
/// link when it has a URL.
struct SocialLinkRow: View {
    let link: SocialLink

    var body: some View {
        if let url = link.url {
            Link(destination: url) {
                HStack(spacing: 12) {
                    icon
                    Text(verbatim: link.label)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack(spacing: 12) {
                icon
                Text(verbatim: link.label)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let assetName = link.assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(.rect(cornerRadius: HotMessRadius.sm))
        } else {
            Image(systemName: link.systemImage)
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        }
    }
}

/// Someone on at a venue: their photo, their name, and what they're doing
/// ("DJ · until 1 AM").
struct AppearanceRow: View {
    let appearance: Appearance
    /// Up next in the show rather than on now.
    var upNext = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: appearance.person.avatarURL, initials: appearance.person.name.initialsForDisplay, size: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: appearance.name)
                    .font(.hotMess(.headline, semibold: true))
                    .lineLimit(1)

                if let role = appearance.role {
                    Label(role.label, systemImage: role.systemImage)
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let hours = appearance.hours {
                    Text(hours)
                        .font(.hotMess(.subheadline))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if upNext {
                    Text("Up next")
                        .font(.hotMess(.caption, semibold: true))
                        .foregroundStyle(.secondary)
                } else {
                    OnNowBadge()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A break in the venue's show, in the On now list.
struct IntermissionRow: View {
    let intermission: OnNow.Intermission

    private var label: String {
        if let title = intermission.title, !title.isEmpty { return title }
        return String(localized: "Intermission")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.quaternary, in: .circle)
                .accessibilityHidden(true)

            Text(verbatim: label)
                .font(.hotMess(.headline, semibold: true))
                .lineLimit(1)

            Spacer(minLength: 8)
            OnNowBadge()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The green "On now" pill with a waveform, as Velvet's lineup draws it.
struct OnNowBadge: View {
    var body: some View {
        Label(String(localized: "On now"), systemImage: "waveform")
            .font(.hotMess(.caption, semibold: true))
            .foregroundStyle(Color.hotMessSuccess)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.hotMessSuccessSoft, in: .capsule)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Who's on at a venue right now, each opening their page. Like any
/// `DetailSection`, it draws nothing when nobody is on.
struct OnNowSection: View {
    let onNow: OnNow

    var body: some View {
        DetailSection(String(localized: "On now")) {
            ForEach(onNow.acts) { appearance in
                DetailLink(route: .person(appearance.person.id)) {
                    AppearanceRow(appearance: appearance)
                }
            }
            if let intermission = onNow.intermission {
                IntermissionRow(intermission: intermission)
            }
            if let upNext = onNow.upNext {
                DetailLink(route: .person(upNext.person.id)) {
                    AppearanceRow(appearance: upNext, upNext: true)
                }
            }
        }
    }
}
