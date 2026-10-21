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
    /// Pings show as banners in the foreground too, and Now picks up the
    /// change. A notification the app already showed itself (its in-app copy
    /// came over `myNotifications`, now or within a moment) isn't shown again.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let notificationID = InAppNotification.notificationID(in: userInfo)

        if PingNotification(userInfo: userInfo)?.isPing == true {
            await AppDelegate.pingsChanged()
        }
        guard await AppDelegate.shouldPresentSystemCopy(notificationID: notificationID) else { return [] }

        return [.banner, .list, .sound]
    }

    /// "I'm in" from a Ping push joins the whole Ping in the background;
    /// tapping a push opens the `url` its payload carries.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard let notification = PingNotification(userInfo: response.notification.request.content.userInfo) else {
            return
        }

        if action == PingNotification.joinAction {
            await AppDelegate.join(notification)
        } else if action == UNNotificationDefaultActionIdentifier {
            await AppDelegate.open(notification)
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
    private static func shouldPresentSystemCopy(notificationID: String?) async -> Bool {
        await AppModel.shared.notifications.shouldPresentSystemCopy(notificationID: notificationID)
    }

    @MainActor
    private static func pingsChanged() {
        AppModel.shared.pingsChanged()
    }
}
