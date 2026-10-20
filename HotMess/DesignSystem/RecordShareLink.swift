//
//  RecordShareLink.swift
//  HotMess
//

import SwiftUI

/// The Share button for a venue or event: a link the API mints and signs to
/// stop working after a month, never one built on the device. Until it
/// arrives, and when the API won't share the record or can't be reached, the
/// button shows but can't be used.
struct RecordShareLink: View {
    /// `/venues/<id>` or `/events/<id>`.
    let path: String

    @Environment(AppModel.self) private var model
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                ShareLink(item: url) { label }
            } else {
                Button {} label: { label }
                    .disabled(true)
            }
        }
        .task(id: path) {
            url = try? await model.api.shareLink(path: path)
        }
    }

    private var label: some View {
        Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
    }
}
