//
//  PingSheet.swift
//  HotMess
//

import SwiftUI

/// The send sheet: tonight's events and the locale's venues to pick from,
/// an optional note, who can see it, contacts to text a link to, and "Send
/// ping". Opening it while you have a Ping edits that Ping.
struct PingSheet: View {
    var seed: PingSeed?
    var onSent: (Ping) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var composer: PingComposer?
    @State private var isPromptingFacebook = false
    @State private var connectErrorMessage: String?
    /// The text to the picked contacts, shown over the sheet once the Ping
    /// is sent; the sheet closes when Messages does.
    @State private var invitation: PingInvitation?
    @State private var invitationErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let composer {
                    PingComposerForm(composer: composer, send: send)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(composer?.isEditing == true ? String(localized: "Edit your ping") : String(localized: "Ping your friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .task {
            async let safetyLoad: Void = model.safety.load()
            if composer == nil {
                composer = PingComposer(
                    api: model.api,
                    audienceKit: model.audienceKit,
                    localeID: model.location.locale?.id,
                    seed: seed
                )
            }
            _ = await (safetyLoad, composer?.load())
        }
        .alert(
            String(localized: "Connect Facebook to See Friends"),
            isPresented: $isPromptingFacebook
        ) {
            Button(String(localized: "Connect Facebook")) {
                Task {
                    do {
                        if try await model.connectFacebook() {
                            performSend()
                        }
                    } catch {
                        connectErrorMessage = error.localizedDescription
                    }
                }
            }
            Button(String(localized: "Send Anyway")) {
                performSend()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Connecting Facebook is required to see your friends and share your pings with them.")
        }
        .sheet(item: $invitation, onDismiss: { dismiss() }) { invitation in
            PingInvitationComposer(invitation: invitation) { self.invitation = nil }
                .ignoresSafeArea()
        }
        .alert(
            String(localized: "Couldn't text your contacts"),
            isPresented: Binding(
                get: { invitationErrorMessage != nil },
                set: { if !$0 { invitationErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { dismiss() }
        } message: {
            Text(invitationErrorMessage ?? "")
        }
        .alert(
            String(localized: "Couldn't connect Facebook"),
            isPresented: Binding(
                get: { connectErrorMessage != nil },
                set: { if !$0 { connectErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(connectErrorMessage ?? "")
        }
    }

    private func send() {
        if !model.safety.hasFacebook && !model.hasPromptedFacebookOnPing {
            model.hasPromptedFacebookOnPing = true
            isPromptingFacebook = true
            return
        }
        performSend()
    }

    private func performSend() {
        Task {
            guard let composer, let ping = await composer.send() else { return }
            onSent(ping)
            model.pingsChanged()
            guard !composer.contacts.isEmpty else {
                dismiss()
                return
            }

            // The Ping is out either way; the sheet stays up for Messages.
            do {
                invitation = try await composer.invitation(for: ping)
            } catch {
                invitationErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct PingComposerForm: View {
    @Environment(AppModel.self) private var model
    @Bindable var composer: PingComposer
    let send: () -> Void
    @State private var isPickingContacts = false

    var body: some View {
        LoadStateView(state: composer.state) { choices in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Where do you want to go?")
                        .font(.hotMess(.headline, semibold: true))
                        .padding(.horizontal, 36)
                        .padding(.top, 8)

                    if choices.isEmpty {
                        DetailSection {
                            Text("There's nothing to pick nearby. Send it anyway to ask where people are heading.")
                                .font(.hotMess(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }

                    DetailSection(String(localized: "Tonight")) {
                        ForEach(choices.events) { event in
                            PingPickRow(
                                title: event.name,
                                detail: event.subtitle,
                                imageURL: event.bannerURL,
                                isSelected: composer.isSelected(.event(event.id))
                            ) {
                                composer.toggle(.event(event.id))
                            }
                        }
                    }

                    DetailSection(String(localized: "Venues")) {
                        ForEach(choices.venues) { venue in
                            PingPickRow(
                                title: venue.name,
                                detail: venue.summary,
                                imageURL: venue.photoURL,
                                isSelected: composer.isSelected(.venue(venue.id))
                            ) {
                                composer.toggle(.venue(venue.id))
                            }
                        }
                    }

                    DetailSection(String(localized: "Note")) {
                        TextField(String(localized: "Add a note (optional)"), text: $composer.note, axis: .vertical)
                            .font(.hotMess(.body))
                            .lineLimit(1 ... 4)
                    }

                    DetailSection(String(localized: "Who can see it")) {
                        Picker(String(localized: "Who can see it"), selection: $composer.reach) {
                            ForEach(PingReach.allCases, id: \.self) { reach in
                                Text(reach.title).tag(reach)
                            }
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text("Anyone who joins can bring their friends.")
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.secondary)
                    }

                    contactsSection
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                sendBar
            }
        }
        .alert(
            String(localized: "Couldn't send ping"),
            isPresented: Binding(
                get: { composer.errorMessage != nil },
                set: { if !$0 { composer.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(composer.errorMessage ?? "")
        }
    }

    /// People from the phone's contacts to text a link to once it's sent,
    /// as chips to take off again.
    private var contactsSection: some View {
        DetailSection(String(localized: "Text a link")) {
            if !composer.contacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(composer.contacts) { contact in
                            PingContactChip(contact: contact) { composer.remove(contact) }
                        }
                    }
                }
            }

            Button {
                isPickingContacts = true
            } label: {
                Label(String(localized: "Add contacts"), systemImage: "person.crop.circle.badge.plus")
                    .font(.hotMess(.body))
            }
        } footer: {
            Text("They'll get a text from you with a link to this ping, even if they're not on Hot Mess.")
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
        }
        .background {
            ContactPicker(isPresented: $isPickingContacts) { composer.add($0) }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var sendBar: some View {
        VStack(spacing: 10) {
            Text("Your friends on Hot Mess will get this. It clears at 5am.")
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: send) {
                Group {
                    if composer.isSending {
                        ProgressView()
                    } else {
                        Text(composer.isEditing ? String(localized: "Update ping") : String(localized: "Send ping"))
                            .font(.hotMess(.headline, semibold: true))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(composer.isSending)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// A contact who'll get the link, with a button to take them off.
private struct PingContactChip: View {
    let contact: PingContact
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(contact.name)
                .font(.hotMess(.subheadline))
                .lineLimit(1)

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove \(contact.name)"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Color.hotMessControlFill, in: .capsule)
    }
}

/// One venue or event in the send sheet, with a check when it's picked.
struct PingPickRow: View {
    let title: String
    let detail: String?
    let imageURL: URL?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RemoteImage(url: imageURL)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.hotMess(.headline, semibold: true))
                        .lineLimit(1)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.hotMessAccent : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
