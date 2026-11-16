//
//  FindFriendsSheet.swift
//  HotMess
//

import AudienceKitUI
import SwiftUI

/// Find friends from contacts, over any tab: the opt-in for someone who
/// hasn't turned it on (what happens, their number, the code, their
/// contacts), or the people it found for someone who has. The screens and
/// their copy are AudienceKitUI's, so Android and other apps match.
struct FindFriendsSheet: View {
    @ObservedObject var friends: ContactMatchingModel
    /// The profile's name, which the match name starts from.
    let name: String?
    let onDone: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if friends.state?.enabled == true {
                    ContactMatchesView(model: friends, appName: String(localized: "Hot Mess"), onDone: onDone)
                } else {
                    FindFriendsFlow(model: friends, appName: String(localized: "Hot Mess"),
                                    firstName: Self.names(from: name).first, lastName: Self.names(from: name).last,
                                    onDone: onDone)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close"), action: onDone)
                        .accessibilityIdentifier("findFriends.close")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await friends.load() }
    }

    /// "Danny Ortiz Reyes" as a first name and the rest, to start the match
    /// name from; the person can change both.
    static func names(from name: String?) -> (first: String, last: String) {
        let words = (name ?? "").split(separator: " ").map(String.init)
        guard let first = words.first else { return ("", "") }
        return (first, words.dropFirst().joined(separator: " "))
    }
}
