//
//  SettingsScreen.swift
//  HotMess
//

import Kingfisher
import SwiftUI
import UIKit

/// The "Me" tab, replacing `SettingsViewController` — which built its rows from
/// nested `indexPath` switches and masked a Facebook profile view with a
/// `CAShapeLayer` sized from a frame that hadn't been laid out yet.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var isConfirmingSignOut = false
    @State private var isConfirmingReset = false
    @State private var didReset = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteFailed = false
    /// Pushes about rooms the user just left: `nil` until it loads, and while
    /// the API can't say, which hides the toggle.
    @State private var recentChatPush: Bool?
    @State private var isSavingRecentChatPush = false

    var body: some View {
        List {
            profileSection
            chatPhotoSection
            tribesSection
            facebookSection
            coverSection
            locationSection
            notificationsSection
            helpSection
            privacySection
            feedbackSection
            aboutSection
            dangerSection
            deleteSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Me"))
        .task { await model.session.refreshUser() }
        .task { await model.safety.load() }
        .task(id: model.session.isSignedIn) { if model.session.isSignedIn { await model.tribes.load() } }
        .task(id: model.session.isSignedIn) { await loadRecentChatPush() }
        .confirmationDialog(
            String(localized: "Sign out of Hot Mess?"),
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Sign Out"), role: .destructive) {
                model.signOut()
            }
        }
        .confirmationDialog(
            String(localized: "Reset all local data?"),
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Reset"), role: .destructive, action: resetLocalData)
        } message: {
            Text("This clears cached images and preferences. You stay signed in.")
        }
        .alert(String(localized: "Local Data Cleared"), isPresented: $didReset) {
            Button(String(localized: "OK"), role: .cancel) {}
        }
        .alert(String(localized: "Delete your account?"), isPresented: $isConfirmingDelete) {
            Button(String(localized: "Delete Account"), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This permanently deletes your Hot Mess account, your messages, RSVPs, Pings and friends list, and signs you out. Cover passes you bought stay with the venue. It can't be undone.")
        }
        .alert(String(localized: "Couldn't delete your account"), isPresented: $deleteFailed) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Please try again, or email feedback@hotmess.social and we'll delete it for you.")
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                Avatar(
                    url: model.session.user?.avatarURL,
                    initials: model.session.user?.initials,
                    size: 64
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.session.user?.name ?? String(localized: "Signed in"))
                        .font(.hotMess(.headline, semibold: true))

                    if let locale = model.location.locale {
                        Text(locale.name)
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// How the user looks in chat, and initials instead of their photo. The
    /// setting is on their account, so only for someone signed in.
    @ViewBuilder
    private var chatPhotoSection: some View {
        if model.session.isSignedIn {
            Section {
                NavigationLink {
                    ChatPhotoScreen()
                } label: {
                    Label(String(localized: "Chat Photo"), systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("me.chatPhoto")
            }
        }
    }

    /// "Your tribes", for someone signed in, where the API has tribes.
    @ViewBuilder
    private var tribesSection: some View {
        if model.session.isSignedIn, model.tribes.isSupported != false {
            Section {
                NavigationLink {
                    TribePickerScreen()
                } label: {
                    LabeledContent {
                        if let choices = model.tribes.choices, !choices.picked.isEmpty {
                            Text("\(choices.picked.count)")
                        }
                    } label: {
                        Label(String(localized: "Your tribes"), systemImage: "person.2.circle")
                    }
                }
                .accessibilityIdentifier("me.tribes")
            } footer: {
                Text("Only someone in a venue chat who picked the same one sees it.")
            }
        }
    }

    /// For an account that signed in with Apple and hasn't connected Facebook.
    @ViewBuilder
    private var facebookSection: some View {
        if !model.safety.hasFacebook {
            Section {
                ConnectFacebookButton()
            } footer: {
                ConnectFacebookFooter()
            }
        }
    }

    private var coverSection: some View {
        Section {
            NavigationLink {
                PassesScreen()
            } label: {
                Label(String(localized: "Passes"), systemImage: "ticket")
            }
            .accessibilityIdentifier("me.passes")
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section(String(localized: "Location")) {
            InfoRow(
                title: String(localized: "Access"),
                value: locationStatusText,
                systemImage: "location"
            )

            if model.location.isDenied {
                Button(String(localized: "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
    }

    /// Only for someone signed in: the setting is on their account.
    @ViewBuilder
    private var notificationsSection: some View {
        if model.session.isSignedIn, let recentChatPush {
            Section {
                Toggle(isOn: Binding(
                    get: { recentChatPush },
                    set: { enabled in Task { await setRecentChatPush(enabled) } }
                )) {
                    Label(String(localized: "Rooms You Just Left"), systemImage: "bubble.left.and.bubble.right")
                }
                .disabled(isSavingRecentChatPush)
                .accessibilityIdentifier("me.recentChatPush")
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get a push when people keep talking in a chat room you left in the last 30 minutes.")
            }
        }
    }

    /// "Need support?" is here whether or not the user is out; the venue's
    /// Get help is only on the venue they're at.
    private var helpSection: some View {
        Section(String(localized: "Help and Safety")) {
            NavigationLink {
                SupportScreen()
            } label: {
                Label(String(localized: "Need Support?"), systemImage: "heart.text.square")
            }
            .accessibilityIdentifier("me.support")

            NavigationLink {
                GettingHelpScreen()
            } label: {
                Label(String(localized: "Getting Help at a Venue"), systemImage: "shield.lefthalf.filled")
            }

            NavigationLink {
                YourSafetyAlertsScreen()
            } label: {
                Label(String(localized: "Your Safety Alerts"), systemImage: "bell.badge")
            }
            .accessibilityIdentifier("me.safetyAlerts")
        }
    }

    private var privacySection: some View {
        Section(String(localized: "Privacy & Safety")) {
            NavigationLink {
                BlockedPeopleScreen()
            } label: {
                Label(String(localized: "Blocked People"), systemImage: "hand.raised")
            }
            .accessibilityIdentifier("me.blocked")

            // Promoted cards the viewer turned off: kept on their devices, never sent.
            NavigationLink {
                CardsYouSeeScreen()
            } label: {
                Label(String(localized: "Cards You See"), systemImage: "rectangle.stack")
            }
            .accessibilityIdentifier("me.cardsYouSee")

            Link(destination: LegalLinks.privacy) {
                Label(String(localized: "Privacy Policy"), systemImage: "hand.raised.square")
            }

            Link(destination: LegalLinks.terms) {
                Label(String(localized: "Terms of Use"), systemImage: "doc.text")
            }
        }
    }

    private var feedbackSection: some View {
        Section {
            NavigationLink {
                YourSuggestionsScreen()
            } label: {
                Label(String(localized: "Your Suggestions"), systemImage: "lightbulb")
            }
            .accessibilityIdentifier("me.suggestions")

            NavigationLink {
                ReportProblemScreen()
            } label: {
                Label(String(localized: "Report a Problem"), systemImage: "exclamationmark.bubble")
            }
            .accessibilityIdentifier("me.reportProblem")

            if let url = feedbackURL {
                Link(destination: url) {
                    Label(String(localized: "Submit Feedback"), systemImage: "envelope")
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            InfoRow(
                title: String(localized: "Version"),
                value: "\(model.configuration.version) (\(model.configuration.build))"
            )
            // Installed from, Beta updates / Updates, Last checked, Check
            // for updates and Open in TestFlight / on the App Store.
            AboutUpdateRows(updates: model.updates)
            // Which Facebook app and API a build talks to matters only to
            // testers; App Store builds leave it out.
            if model.configuration.isTestBuild {
                InfoRow(
                    title: String(localized: "Facebook"),
                    value: model.configuration.facebookEnvironment
                )
                InfoRow(
                    title: String(localized: "Server"),
                    value: model.configuration.baseURL.absoluteString
                )
            }
        } header: {
            Text("About")
        } footer: {
            AboutUpdateFootnote(updates: model.updates)
        }
    }

    private var dangerSection: some View {
        Section {
            Button(String(localized: "Reset All Data"), role: .destructive) {
                isConfirmingReset = true
            }

            Button(String(localized: "Sign Out"), role: .destructive) {
                isConfirmingSignOut = true
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                if isDeleting {
                    HStack {
                        Text("Deleting Account…")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Text("Delete Account")
                }
            }
            .disabled(isDeleting)
            .accessibilityIdentifier("me.deleteAccount")
        } footer: {
            Text("Deletes your account and everything Hot Mess keeps about you.")
        }
    }

    // MARK: - Helpers

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await model.deleteAccount()
        } catch {
            deleteFailed = true
        }
    }

    private func loadRecentChatPush() async {
        guard model.session.isSignedIn else {
            recentChatPush = nil
            return
        }
        recentChatPush = try? await model.api.recentChatPush()
    }

    /// Shows the change at once, and puts it back if the API refuses it.
    private func setRecentChatPush(_ enabled: Bool) async {
        let previous = recentChatPush
        recentChatPush = enabled
        isSavingRecentChatPush = true
        defer { isSavingRecentChatPush = false }

        do {
            recentChatPush = try await model.api.setRecentChatPush(enabled)
        } catch {
            recentChatPush = previous
        }
    }

    private var locationStatusText: String {
        if model.location.isAuthorized { return String(localized: "Allowed") }
        if model.location.isDenied { return String(localized: "Denied") }
        return String(localized: "Not requested")
    }

    /// A `mailto:` link works with whatever mail client the user actually has;
    /// `MFMailComposeViewController` only handles Apple Mail.
    private var feedbackURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "feedback@hotmess.social"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Hot Mess: Feedback"),
            URLQueryItem(
                name: "body",
                value: "\n\n---\nVersion \(model.configuration.version) (\(model.configuration.build))"
            ),
        ]

        return components.url
    }

    private func resetLocalData() {
        model.session.resetLocalData()
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
        didReset = true
    }
}
