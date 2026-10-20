//
//  RootView.swift
//  HotMess
//

import SwiftUI

/// Chooses between the launch, login, update-required and signed-in states.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.session.requiresUpdate {
                UpdateRequiredView(versionInfo: model.session.versionRequirement)
            } else {
                switch model.session.state {
                case .restoring:
                    LaunchView()
                case .signedOut, .signingIn, .failed:
                    LoginScreen()
                case .signedIn:
                    MainTabView()
                }
            }
        }
        .animation(.default, value: model.session.state)
    }
}

/// Shown while the stored session is being checked, so the app doesn't flash
/// the login screen on every cold start. It matches the launch screen
/// (`UILaunchScreen` in Info.plist): the mark centred on `LaunchBackground`,
/// so the hand-off from the system's launch image doesn't jump.
struct LaunchView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            Image("LaunchMark")
                .accessibilityHidden(true)

            ProgressView()
                .tint(.white)
                .offset(y: 150)
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            Tab(AppTab.now.title, systemImage: AppTab.now.systemImage, value: AppTab.now) {
                NavigationStack(path: $model.nowPath) {
                    NowScreen()
                        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
                }
                .environment(model)
            }

            Tab(AppTab.events.title, systemImage: AppTab.events.systemImage, value: AppTab.events) {
                NavigationStack(path: $model.eventsPath) {
                    EventsScreen()
                        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
                }
                .environment(model)
            }

            Tab(AppTab.venues.title, systemImage: AppTab.venues.systemImage, value: AppTab.venues) {
                NavigationStack(path: $model.venuesPath) {
                    VenuesScreen()
                        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
                }
                .environment(model)
            }

            Tab(AppTab.people.title, systemImage: AppTab.people.systemImage, value: AppTab.people) {
                NavigationStack(path: $model.peoplePath) {
                    PeopleScreen()
                        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
                }
                .environment(model)
            }

            Tab(AppTab.me.title, systemImage: AppTab.me.systemImage, value: AppTab.me) {
                NavigationStack {
                    SettingsScreen()
                }
                .environment(model)
            }
        }
        .environment(model)
        .accessibilityIdentifier("main.tabs")
        .coverPresenter()
        .notificationBannerHost()
        .alert(String(localized: "This link has expired"), isPresented: $model.isShowingExpiredLink) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Ask whoever sent it for a new one, or find it among the venues.")
        }
    }
}

/// Maps a route onto the screen that shows it, so every stack pushes the same
/// destinations.
struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case let .venue(id):
            VenueScreen(venueID: id)
        case let .event(id):
            EventScreen(eventID: id)
        case let .person(id):
            PersonScreen(personID: id)
        case let .venueChat(venue):
            VenueChatScreen(venue: venue)
        case let .karaokeList(venueID):
            KaraokeListScreen(venueID: venueID)
        case let .eventChat(room):
            VenueChatScreen(room: room)
        case let .localeChat(locale):
            VenueChatScreen(room: .locale(locale))
        }
    }
}

/// The hard stop the API can impose on old builds.
struct UpdateRequiredView: View {
    let versionInfo: VersionInfo?

    @Environment(AppModel.self) private var model
    @State private var isTestFlight = false

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "Update Required"), systemImage: "arrow.down.circle")
        } description: {
            Text(description)
        }
        .task {
            isTestFlight = await model.configuration.isTestFlight
        }
    }

    private var description: String {
        let source = isTestFlight
            ? String(localized: "TestFlight")
            : String(localized: "the App Store")

        guard let versionInfo else {
            return String(localized: "Update Hot Mess in \(source) to continue.")
        }

        return String(localized: "Update to version \(versionInfo.minimumVersion) in \(source) to continue.")
    }
}
