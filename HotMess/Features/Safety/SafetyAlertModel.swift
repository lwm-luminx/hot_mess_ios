//
//  SafetyAlertModel.swift
//  HotMess
//

import Foundation
import Observation
import UIKit

/// Where "Get help" was opened from: a venue the user is at, or one of their
/// alerts (a push, or Me > Your safety alerts).
enum HelpPresentation: Identifiable, Hashable, Sendable {
    case venue(HelpVenue)
    case alert(id: String)

    var id: String {
        switch self {
        case let .venue(venue): "venue-\(venue.id.uuidString)"
        case let .alert(id): "alert-\(id)"
        }
    }
}

/// The venue "Get help" is about, with what "Message a friend" and "Get a
/// ride" say.
struct HelpVenue: Hashable, Sendable {
    let id: UUID
    let name: String
    let address: String?
    /// Where it is, for a ride's pickup.
    var coordinates: Coordinates?

    /// "I'm at The Wildrose, 1001 E Pike St." for a friend or a ride.
    var whereIAm: String {
        if let address, !address.isEmpty {
            return String(localized: "I'm at \(name), \(address).")
        }
        return String(localized: "I'm at \(name).")
    }
}

extension HelpVenue {
    init(_ venue: Venue) {
        self.init(id: venue.id, name: venue.name, address: venue.address)
        if let coordinate = venue.coordinate {
            coordinates = Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}

/// One "Get help" sheet: what the user fills in, the alert once it's sent,
/// and keeping it fresh while they wait. There's no subscription for alerts,
/// so it reads the alert again every few seconds while the sheet is open.
@MainActor
@Observable
final class SafetyAlertModel {
    private(set) var alert: SafetyAlert?
    private(set) var venue: HelpVenue?
    /// Whether anyone on shift hears alerts at the venue: without them the
    /// sheet leads with friend, ride, support and 911.
    private(set) var staffOnShift = true
    var draft = SafetyAlertDraft()
    private(set) var isBusy = false
    var errorMessage: String?
    /// Moves on every second, so the waiting screen notices the escalation
    /// window passing.
    private(set) var now = Date()
    /// The user chose "Keep waiting for staff" on the no-answer screen.
    var keepsWaiting = false
    /// "Get a ride": the ride apps for where the user is.
    private(set) var rides: [SupportResources.Ride] = []
    /// Where a ride picks them up: the venue, else where the phone is.
    private(set) var pickup: RidePickup?

    private let api: HotMessAPI

    init(api: HotMessAPI, presentation: HelpPresentation) {
        self.api = api
        if case let .venue(venue) = presentation { self.venue = venue }
        if case let .alert(id) = presentation { pendingAlertID = id }
    }

    private var pendingAlertID: String?

    /// Loads what the sheet needs: the venue's shift, the user's open alert
    /// there if they already sent one, or the alert it was opened for.
    func load() async {
        if let id = pendingAlertID ?? alert?.id {
            if let fresh = try? await api.safetyAlert(id) { apply(fresh) }
            pendingAlertID = nil
            return
        }
        guard let venue else { return }
        if let safety = try? await api.venueSafety(venue.id) { staffOnShift = safety.staffOnShift }
        let venueID = venue.id.uuidString.lowercased()
        if let open = try? await api.safetyAlerts().first(where: { $0.isActive && $0.venue.id.lowercased() == venueID }) {
            apply(open)
        }
    }

    /// The ride apps for where the user is, with the pickup at the venue
    /// when the app knows where it is, else at the phone's last position.
    func loadRides(near coordinates: Coordinates?) async {
        if let at = venue?.coordinates {
            pickup = RidePickup(coordinates: at, name: venue?.name)
        } else if let coordinates {
            pickup = RidePickup(coordinates: coordinates, name: nil)
        }
        let region = await SupportScreen.region(near: pickup?.coordinates ?? coordinates)
        rides = (try? await api.supportRides(region: region)) ?? []
    }

    /// Reads the alert every few seconds while it's open, and ticks the clock.
    func keepFresh() async {
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            now = Date()
            ticks += 1
            guard ticks.isMultiple(of: 5), let id = alert?.id, alert?.isActive == true else { continue }
            if let fresh = try? await api.safetyAlert(id) { apply(fresh) }
        }
    }

    func send() async {
        guard let venue else { return }
        await run { try await self.api.sendSafetyAlert(venueID: venue.id, self.draft) }
        if alert != nil { draft = SafetyAlertDraft() }
    }

    func addDetails() async {
        guard let id = alert?.id else { return }
        await run { try await self.api.updateSafetyAlert(id, self.draft) }
        if errorMessage == nil { draft = SafetyAlertDraft() }
    }

    func remind() async {
        guard let id = alert?.id else { return }
        keepsWaiting = true
        await run { try await self.api.remindSafetyAlert(id) }
    }

    func cancel() async {
        guard let id = alert?.id else { return }
        await run { try await self.api.cancelSafetyAlert(id) }
    }

    /// Sends a message in the private thread. Returns whether it went.
    func sendMessage(_ body: String) async -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = alert?.id, !text.isEmpty else { return false }
        await run { try await self.api.sendSafetyAlertMessage(id, body: text) }
        return errorMessage == nil
    }

    private func run(_ action: @escaping () async throws -> SafetyAlert) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            apply(try await action())
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "That didn't go through. Try again, or find a member of staff.")
        }
    }

    private func apply(_ fresh: SafetyAlert) {
        // Picked up: a buzz with no sound, as the waiting screen promised.
        if alert?.state == .open, fresh.state == .acknowledged {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        alert = fresh
        if venue == nil, let id = UUID(uuidString: fresh.venue.id) {
            venue = HelpVenue(id: id, name: fresh.venue.name ?? String(localized: "the venue"), address: nil)
        }
    }
}
