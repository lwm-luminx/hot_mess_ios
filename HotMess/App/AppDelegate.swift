//
//  AppDelegate.swift
//  HotMess
//

import FacebookCore
import Foundation
import NewRelic
import os
import UIKit
import UserNotifications

/// What is genuinely left for UIKit to do: boot the Facebook SDK, receive
/// push tokens and pick location back up after a background launch. Everything the old 160-line delegate did — deep links, version
/// gating, login presentation, location start/stop — now lives in SwiftUI or in
/// a service.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // First, so it sees the launch and any crash after it.
        if let token = AppConfiguration().newRelicToken {
            NewRelic.start(withApplicationToken: token)
        }

        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        // Ensure the Facebook SDK makes no tracking or event calls beyond login
        Settings.shared.isAutoLogAppEventsEnabled = false
        Settings.shared.isAdvertiserIDCollectionEnabled = false

        // Set before launch finishes, so a tap or an action that launched
        // the app is delivered here.
        UNUserNotificationCenter.current().delegate = self
        PushNotifications.registerCategories()

        // A venue geofence or a significant change may have relaunched the
        // app with nothing on screen, so SwiftUI won't start anything. A
        // scene-based app often reads as background here on a normal launch
        // too; that's fine, as starting is idempotent and needs Always and a
        // stored session.
        if launchOptions?[.location] != nil || application.applicationState == .background {
            Task { await AppModel.shared.startInBackground() }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let session = AppModel.shared.session

        Task { await session.registerForPushNotifications(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Log.app.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - Notifications

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// While the app is open the system shows nothing; Now picks up a Ping's
    /// change, and the in-app copy (over `myNotifications`) is the only banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        if PingNotification(userInfo: userInfo)?.isPing == true {
            await AppDelegate.pingsChanged()
        }
        return []
    }

    /// "I'm in" from a Ping push joins the whole Ping in the background;
    /// tapping a push opens the `url` its payload carries.
    ///
    /// The completion-handler form, not `async`: the system may call this off
    /// the main thread, and the `async` form's thunk then calls UIKit's
    /// completion handler from that thread too, which UIKit asserts against
    /// (TestFlight crash in `_performBlockAfterCATransactionCommitSynchronizes`).
    /// Here the work and the completion both run on the main actor.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        nonisolated(unsafe) let completion = completionHandler
        let action = response.actionIdentifier
        let notification = PingNotification(userInfo: response.notification.request.content.userInfo)

        Task { @MainActor in
            if let notification {
                if action == PingNotification.joinAction {
                    await AppDelegate.join(notification)
                } else if action == UNNotificationDefaultActionIdentifier {
                    AppDelegate.open(notification)
                }
            }
            completion()
        }
    }

    @MainActor
    private static func join(_ notification: PingNotification) async {
        await AppModel.shared.join(notification)
    }

    @MainActor
    private static func open(_ notification: PingNotification) {
        AppModel.shared.open(notification)
    }

    @MainActor
    private static func pingsChanged() {
        AppModel.shared.pingsChanged()
    }
}
