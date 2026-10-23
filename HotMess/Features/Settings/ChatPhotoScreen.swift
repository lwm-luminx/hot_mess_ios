//
//  ChatPhotoScreen.swift
//  HotMess
//

import SwiftUI

/// Me › Chat photo: how the user looks in chat rooms, at the size everyone
/// sees, why it's that small, and "Use my initials instead"
/// (`setChatInitials`, read back as `me.chatInitials`), which sends no photo
/// to chat at all. Photos come from Facebook, so there's nothing to change here.
struct ChatPhotoScreen: View {
    @Environment(AppModel.self) private var model

    /// `nil` until it loads, and while the API can't say, which hides the toggle.
    @State private var chatInitials: Bool?
    @State private var isSaving = false
    @State private var didFail = false

    private static let sampleText = String(localized: "anyone know who's on next?")

    var body: some View {
        List {
            Section {
                sample
                    .listRowBackground(Color.hotMessSurfaceSunken)

                VStack(alignment: .leading, spacing: 8) {
                    Text("In chat, everyone sees your photo this small, on purpose. It's enough for friends to spot you, and not enough for strangers to judge you.")
                        .font(.hotMess(.subheadline))
                    Text("We keep only a small copy for chat rooms. Nobody in a chat can open a bigger one.")
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                sizes
            } header: {
                Text("How you look in chat")
            }

            if let chatInitials {
                Section {
                    Toggle(isOn: Binding(
                        get: { chatInitials },
                        set: { enabled in Task { await setChatInitials(enabled) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use my initials instead")
                                .font(.hotMess(.body))
                            Text("Show \"\(initials)\" on a colour, no photo")
                                .font(.hotMess(.footnote))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("me.chatInitials")
                } footer: {
                    Text("Talent on a verified listing: your listing photo shows as it does today when you post as your listing.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Chat Photo"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.session.isSignedIn) { await load() }
        .alert(String(localized: "Couldn't change your chat photo"), isPresented: $didFail) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    // MARK: - Pieces

    private var user: User? { model.session.user }

    private var initials: String {
        let initials = user?.initials ?? ""
        return initials.isEmpty ? "?" : initials
    }

    /// The photo chat shows, or none with initials on.
    private var photoURL: URL? {
        chatInitials == true ? nil : user?.avatarURL
    }

    /// One of the user's messages as a room shows it to everyone else, at real size.
    private var sample: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Avatar(url: photoURL, initials: user?.initials, size: ChatMetrics.avatarSize, tintsInitials: true)

            VStack(alignment: .leading, spacing: 2) {
                ChatSenderLine(name: sampleName, role: nil)
                    .padding(.leading, 12)
                ChatBubble(text: Self.sampleText, isOwn: false, isSelectable: false)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Example of your message in a chat room"))
    }

    /// "First L.", as rooms name the user to anyone but their friends.
    private var sampleName: String? {
        guard let name = user?.name, !name.isEmpty else { return nil }
        let words = name.split(separator: " ")
        guard words.count > 1, let last = words.last?.first else { return name }
        return "\(words[0]) \(last)."
    }

    /// The sizes chat draws them at.
    private var sizes: some View {
        HStack(alignment: .bottom, spacing: 28) {
            sizeSample(String(localized: "In a room")) {
                Avatar(url: photoURL, initials: user?.initials, size: ChatMetrics.avatarSize, tintsInitials: true)
            }
            sizeSample(String(localized: "In a preview")) {
                Avatar(url: photoURL, initials: user?.initials, size: ChatMetrics.peekAvatarSize, tintsInitials: true)
            }
            sizeSample(String(localized: "With initials")) {
                Avatar(url: nil, initials: user?.initials, size: ChatMetrics.avatarSize, tintsInitials: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private func sizeSample<Content: View>(_ title: String, @ViewBuilder avatar: () -> Content) -> some View {
        VStack(spacing: 8) {
            avatar()
            Text(title)
                .font(.hotMess(.caption))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Setting

    private func load() async {
        guard model.session.isSignedIn else {
            chatInitials = nil
            return
        }
        chatInitials = try? await model.api.chatInitials()
    }

    /// Shows the change at once, and puts it back if the API refuses it.
    private func setChatInitials(_ enabled: Bool) async {
        let previous = chatInitials
        chatInitials = enabled
        isSaving = true
        defer { isSaving = false }

        do {
            chatInitials = try await model.api.setChatInitials(enabled)
        } catch {
            chatInitials = previous
            didFail = true
        }
    }
}
