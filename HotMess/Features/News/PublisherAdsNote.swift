//
//  PublisherAdsNote.swift
//  HotMess
//

import AudienceKit
import SwiftUI

extension AppModel {
    /// Whether the signed-in person has acknowledged that publishers run their own ads. A guest's counts until the app
    /// quits.
    var hasAcknowledgedPublisherAds: Bool {
        guard let userID = session.userID else { return publisherAdsAcknowledgedAsGuest }
        return publisherAds.isAcknowledged(by: userID.uuidString)
    }

    func acknowledgePublisherAds() {
        guard let userID = session.userID else { publisherAdsAcknowledgedAsGuest = true; return }
        publisherAds.acknowledge(userID: userID.uuidString)
    }
}

/// The one-time note before a reader's first Soapbox story: the publisher chooses and answers for the ads in its
/// stories so it can keep paying writers, Hot Mess takes no cut, its own sponsored spots are separate and marked
/// Promoted, and no data goes to a publisher's advertisers. Shown while `pending` is set; "I understand" records it
/// for this person and runs `pending`, "Not now" drops it and calls `onDecline`.
struct PublisherAdsNote: ViewModifier {
    @Binding var pending: (() -> Void)?
    var onDecline: () -> Void = {}

    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert(
            PublisherAdsCopy.title,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button(PublisherAdsCopy.decline, role: .cancel) {
                pending = nil
                onDecline()
            }
            Button(PublisherAdsCopy.accept) {
                model.acknowledgePublisherAds()
                let action = pending
                pending = nil
                action?()
            }
            .accessibilityIdentifier("publisherAds.accept")
        } message: {
            Text(PublisherAdsCopy.body(appName: String(localized: "Hot Mess")))
        }
    }
}
