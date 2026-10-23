//
//  InThisRoomSheet.swift
//  HotMess
//

import SwiftUI

/// Everyone in a chat room, from the Here now strip's See everyone or its
/// "+N on the lineup" chip: tonight's lineup (the venue, then each act as the
/// lineup's rows draw them, with whether they're in chat), then the guests
/// here now and here recently, whom the user can report or block as from the
/// strip. Acts open their page.
struct InThisRoomSheet: View {
    /// "Drag Bingo · The Wildrose", under the title.
    let subtitle: String
    var place: HereNowPlace? = nil
    var lineup: [HereNowLineupFace] = []
    /// Everyone else, the user included, as the strip orders them.
    let people: [HereNowPerson]
    /// Opens an act's page; the sheet closes first.
    var onSelectLineup: ((HereNowLineupFace) -> Void)? = nil
    /// Opens someone's profile sheet; the sheet closes first. Never the user.
    var onSelectPerson: ((HereNowPerson) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var personReport: ReportSubject?
    @State private var personBlock: BlockedUser?

    var body: some View {
        NavigationStack {
            List {
                if place != nil || !lineup.isEmpty {
                    Section(String(localized: "Tonight's lineup")) {
                        if let place {
                            placeRow(place)
                        }
                        ForEach(lineup) { face in
                            lineupRow(face)
                        }
                    }
                }

                let here = people.filter(\.isHere)
                if !here.isEmpty {
                    Section(String(localized: "Here now · \(here.count)")) {
                        ForEach(here) { guestRow($0) }
                    }
                }

                let recent = people.filter { !$0.isHere }
                if !recent.isEmpty {
                    Section(String(localized: "Here recently")) {
                        ForEach(recent) { guestRow($0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("In this room")
                            .font(.hotMess(.headline, semibold: true))
                            .accessibilityAddTraits(.isHeader)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.hotMess(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .contentReporting(report: $personReport, block: $personBlock)
        .accessibilityIdentifier("chat.inThisRoom")
    }

    // MARK: - Rows

    /// The venue: always in its own room.
    private func placeRow(_ place: HereNowPlace) -> some View {
        HStack(spacing: 12) {
            Avatar(url: place.photoURL, initials: place.name.initialsForDisplay, size: 44, isPlace: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.name)
                    .font(.hotMess(.headline, semibold: true))
                    .lineLimit(1)
                Text("Venue · always in its room")
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(place.name), venue"))
    }

    @ViewBuilder
    private func lineupRow(_ face: HereNowLineupFace) -> some View {
        if let onSelectLineup, face.personID != nil {
            Button {
                dismiss()
                onSelectLineup(face)
            } label: {
                LineupActRow(face: face)
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Opens their page"))
        } else {
            LineupActRow(face: face)
        }
    }

    private func guestRow(_ person: HereNowPerson) -> some View {
        HStack(spacing: 12) {
            if let onSelectPerson, !person.isViewer {
                Button {
                    dismiss()
                    onSelectPerson(person)
                } label: {
                    guestIdentity(person).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "Opens their profile"))
            } else {
                guestIdentity(person)
            }

            // Nobody reports or blocks themself.
            if !person.isViewer {
                Menu {
                    safetyActions(for: person)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.hotMess(.body))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(String(localized: "More for \(person.firstName)"))
            }
        }
        .contextMenu {
            if !person.isViewer { safetyActions(for: person) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(person.accessibilityLabel)
        .accessibilityActions {
            if let onSelectPerson, !person.isViewer {
                Button(String(localized: "Open profile")) {
                    dismiss()
                    onSelectPerson(person)
                }
            }
            if !person.isViewer { safetyActions(for: person) }
        }
    }

    /// The avatar and name, which open their profile sheet.
    private func guestIdentity(_ person: HereNowPerson) -> some View {
        HStack(spacing: 12) {
            Avatar(
                url: person.avatarURL,
                initials: person.name?.initialsForDisplay,
                size: 36,
                presence: person.presence,
                tintsInitials: true
            )
            .opacity(person.isHere ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: person.displayName)
                    .font(.hotMess(.body, semibold: person.isFriend))
                    .foregroundStyle(person.isFriend ? Color.hotMessAccentInk : Color.primary)
                    .lineLimit(1)
                if person.isFriend {
                    Text("Friend")
                        .font(.hotMess(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func safetyActions(for person: HereNowPerson) -> some View {
        Button {
            personReport = ReportSubject(
                target: .person,
                targetID: person.id.uuidString.lowercased(),
                sender: BlockedUser(id: person.id, name: person.name, avatarURL: person.avatarURL)
            )
        } label: {
            Label(String(localized: "Report \(person.firstName)…"), systemImage: "exclamationmark.bubble")
        }
        Button(role: .destructive) {
            personBlock = BlockedUser(id: person.id, name: person.name, avatarURL: person.avatarURL)
        } label: {
            Label(String(localized: "Block \(person.firstName)"), systemImage: "hand.raised")
        }
    }
}

/// An act on tonight's lineup as a row, as AudienceKitUI's lineup lists it at
/// accessibility sizes: a 44 avatar, the billing, the role word and set time,
/// whether they're in chat in words, and On now, Up next or Done at the
/// trailing edge. Done acts are at half strength.
struct LineupActRow: View {
    let face: HereNowLineupFace

    var body: some View {
        HStack(spacing: 12) {
            if face.isIntermission {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.hotMessSuccess)
                    .frame(width: 44, height: 44)
                    .background(Color.hotMessSuccessSoft, in: .circle)
            } else {
                LineupAvatars(face: face, size: 44)
                    .opacity(face.isDone ? 0.5 : 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: face.name)
                    .font(.hotMess(.headline, semibold: true))
                    .foregroundStyle(face.isDone ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let roleLine {
                    Text(verbatim: roleLine)
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let presence = face.presenceText {
                    Text(verbatim: presence)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(face.presence == .online ? Color.hotMessSuccess : Color.secondary)
                }
            }

            Spacer(minLength: 8)

            LineupStatusBadge(status: face.status)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.accessibilityLabel)
    }

    /// "Host · 9:00 PM – close"; the set time only for a hard start.
    private var roleLine: String? {
        let parts = [face.isIntermission ? String(localized: "Intermission") : face.role?.title, face.setTime]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
