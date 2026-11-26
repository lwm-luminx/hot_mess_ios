//
//  RideScreen.swift
//  HotMess
//

import SwiftUI

/// "Get a ride": one row in Get help and Need support that opens the ways
/// home, so the list there stays short however many ride apps a region has.
struct GetARideRow: View {
    let rides: [SupportResources.Ride]
    let pickup: RidePickup?
    /// The venue's name and address when there is one, for the messages.
    let place: String?

    var body: some View {
        NavigationLink {
            RideScreen(rides: rides, pickup: pickup, place: place)
        } label: {
            HelpRow(
                title: String(localized: "Get a ride"),
                subtitle: RideOptions.summary(rides),
                systemImage: "car"
            )
        }
        .accessibilityIdentifier("help.ride")
    }
}

/// The ways home, picked after "Get a ride": each ride app the API lists for
/// the region with the pickup already set, transit directions, asking a
/// friend to send a ride, and sharing where to be picked up. Plain links: an
/// app opens if it's installed, its site if not. Nothing here is sent to
/// Hot Mess.
struct RideScreen: View {
    let rides: [SupportResources.Ride]
    let pickup: RidePickup?
    let place: String?

    var body: some View {
        List {
            if !rides.isEmpty {
                Section {
                    ForEach(rides) { ride in
                        if let url = ride.link(pickup: pickup) {
                            Link(destination: url) {
                                HelpRow(title: ride.name, subtitle: pickupLine, systemImage: "car")
                            }
                            .accessibilityIdentifier("help.ride.\(ride.id)")
                        }
                    }
                } header: {
                    Text("Ride apps")
                }
            }

            Section {
                if let transit = RideOptions.transitURL(from: pickup) {
                    Link(destination: transit) {
                        HelpRow(
                            title: String(localized: "Take transit"),
                            subtitle: String(localized: "Directions by bus or train in Maps."),
                            systemImage: "tram"
                        )
                    }
                    .accessibilityIdentifier("help.ride.transit")
                }
                ShareLink(item: RideOptions.sendMeARide(place: place, pickup: pickup)) {
                    HelpRow(
                        title: String(localized: "Ask a friend to send a ride"),
                        subtitle: String(localized: "They book it in their Uber or Lyft, with you as the rider."),
                        systemImage: "person.2"
                    )
                }
                .accessibilityIdentifier("help.ride.friend")
                ShareLink(item: RideOptions.pickMeUp(place: place, pickup: pickup)) {
                    HelpRow(
                        title: String(localized: "Share where to pick me up"),
                        subtitle: String(localized: "For another ride app, or a friend who can drive."),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .accessibilityIdentifier("help.ride.share")
            } header: {
                Text("Other ways home")
            } footer: {
                Text("Nothing here is sent to Hot Mess.")
            }

            EmergencySection()
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Get a ride"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pickupLine: String {
        guard let pickup else { return String(localized: "Opens the app to set your pickup.") }
        if let name = pickup.name { return String(localized: "Pickup at \(name).") }
        return String(localized: "Pickup where you are now.")
    }
}

/// What "Get a ride" says and links to, kept apart from the views so it can
/// be tested.
enum RideOptions {
    /// "Uber, Lyft or transit", from the apps the region has.
    static func summary(_ rides: [SupportResources.Ride]) -> String {
        let names = rides.map(\.name)
        switch names.count {
        case 0: return String(localized: "Transit, or share where to pick you up.")
        case 1: return String(localized: "\(names[0]), transit, or a friend.")
        default:
            let list = names.dropLast().joined(separator: ", ")
            return String(localized: "\(list), \(names.last!), transit, or a friend.")
        }
    }

    /// Apple Maps directions by transit, starting at the pickup when the app
    /// knows it; the user picks where they're going in Maps.
    static func transitURL(from pickup: RidePickup?) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "dirflg", value: "r")]
        if let pickup {
            items.insert(URLQueryItem(name: "saddr", value: coordinate(pickup.coordinates)), at: 0)
        }
        components?.queryItems = items
        return components?.url
    }

    /// A map link to where the user is, for a message.
    static func mapLink(_ pickup: RidePickup?) -> String? {
        guard let pickup else { return nil }
        return "https://maps.apple.com/?ll=\(coordinate(pickup.coordinates))"
    }

    /// Where to pick the user up, written out: the venue's name and address,
    /// then a map link.
    static func whereIAm(place: String?, pickup: RidePickup?) -> String? {
        let parts = [place, mapLink(pickup)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// For a friend who'll book the ride in their own app: Uber and Lyft both
    /// let the person paying set someone else as the rider.
    static func sendMeARide(place: String?, pickup: RidePickup?) -> String {
        guard let here = whereIAm(place: place, pickup: pickup) else {
            return String(localized: "Can you send me a ride home? In Uber or Lyft you can book it with me as the rider.")
        }
        return String(localized: "Can you send me a ride home? I'm here: \(here). In Uber or Lyft you can book it with me as the rider.")
    }

    /// "Pick me up here", for another app or a friend who can drive.
    static func pickMeUp(place: String?, pickup: RidePickup?) -> String {
        guard let here = whereIAm(place: place, pickup: pickup) else { return String(localized: "Can you pick me up?") }
        return String(localized: "Can you pick me up? I'm here: \(here)")
    }

    private static func coordinate(_ at: Coordinates) -> String {
        String(format: "%.6f,%.6f", at.latitude, at.longitude)
    }
}
