//
//  CheckTheAppScreen.swift
//  HotMess
//

import AudienceKitUI
import SwiftUI

/// Me › Check the app: the SDK's `AppCheckView` running what Hot Mess loads, as the signed-in person, so a screen
/// that comes up empty can be traced to the call behind it. Only reads: it never reports a location or changes
/// anything. "Copy report" includes the recent failed GraphQL requests (`AppModel.operations`).
struct CheckTheAppScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AppCheckView(title: title, log: model.operations) { check in
            await Self.run(check, model: model)
        }
    }

    private var title: String {
        "Hot Mess \(model.configuration.version) (\(model.configuration.build)), \(model.configuration.baseURL.absoluteString)"
    }

    @MainActor
    static func run(_ check: AppCheck, model: AppModel) async {
        let api = model.api

        await check.step(String(localized: "Signed in")) {
            try await api.me().map { "As \($0.firstName)." }
        }

        await check.step(String(localized: "App version is supported")) {
            guard let requirement = try await api.clientRequirement() else { return nil }
            return "Oldest supported \(requirement.minimumVersion), newest \(requirement.latestVersion ?? "unknown")."
        }

        let coordinates = model.location.coordinates
        var localeID: UUID?
        if let coordinates {
            await check.step(String(localized: "Your locale")) {
                let locale = try await api.closestLocale(to: coordinates)
                localeID = locale?.id
                return locale.map(\.name)
            }
            await check.step(String(localized: "Venues nearby")) {
                let fences = try await api.venueFences(near: coordinates)
                return fences.isEmpty ? nil : "\(fences.count) venues."
            }
        } else {
            check.skip(String(localized: "Your locale"), because: "No position yet (Location is off or hasn't found you).")
        }

        if let localeID {
            await check.step(String(localized: "Upcoming events")) {
                let events = try await api.eventList(in: localeID)
                return events.isEmpty ? nil : "\(events.count) upcoming."
            }
        } else {
            check.skip(String(localized: "Upcoming events"), because: "No locale to look in.")
        }

        await check.step(String(localized: "Pings")) {
            let pings = try await api.pings()
            return "\(pings.myPing == nil ? "No ping of yours" : "Your ping is on"), \(pings.friendPings.count) from friends."
        }

        await check.step(String(localized: "Safety")) {
            _ = try await api.safety()
            return "Loaded."
        }
    }
}
