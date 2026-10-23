//
//  PingSheet.swift
//  HotMess
//

import SwiftUI

/// The send sheet: tonight's events and the locale's venues to pick from,
/// an optional note, who can see it, and "Send ping". Opening it while you
/// have a Ping edits that Ping.
struct PingSheet: View {
    var seed: PingSeed?
    /// A place to pick by ID, when the opener has no Venue or Event to seed
    /// with (a chat room's venue). Picked only if the lists have it.
    var place: PingPlace? = nil
    var onSent: (Ping) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var composer: PingComposer?
    @State private var isPromptingFacebook = false
    @State private var connectErrorMessage: String?

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
                    seed: seed,
                    place: place
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
            guard let ping = await composer?.send() else { return }
            onSent(ping)
            model.pingsChanged()
            dismiss()
        }
    }
}

private struct PingComposerForm: View {
    @Environment(AppModel.self) private var model
    @Bindable var composer: PingComposer
    let send: () -> Void

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
