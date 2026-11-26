//
//  HelpHistory.swift
//  HotMess
//

import Foundation
import Observation

/// Help history: the help requests the user sent and the places shared with
/// them in those threads (a food bank, a shelter, a line), kept on this phone
/// only so they can find them again after the alert closes and the API stops
/// showing it. Nothing here goes to the server.
///
/// DV and stalking resources (`sensitive`) are never kept, so nothing on the
/// phone shows one was shared. Message text isn't kept either: only what the
/// request was about, where, when, and the shared places. The file is left out
/// of backups and is locked with the phone. "Clear history" removes it, and so
/// does signing out.
@MainActor
@Observable
final class HelpHistory {
    struct Entry: Codable, Hashable, Sendable, Identifiable {
        let id: String
        var venueName: String?
        var summary: String
        let createdAt: Date
        var resources: [SafetyAlert.SharedResource]
    }

    static let shared = HelpHistory()

    /// Newest first.
    private(set) var entries: [Entry] = []

    private let fileURL: URL?

    init(fileURL: URL? = HelpHistory.defaultFileURL) {
        self.fileURL = fileURL
        entries = Self.read(fileURL)
    }

    /// Keeps `alert` (or brings its entry up to date): its summary, venue and
    /// the places shared in its thread, minus any sensitive one.
    func record(_ alert: SafetyAlert) {
        let shared = alert.messages.compactMap(\.resource).filter { !$0.sensitive }
        var entry = entries.first { $0.id == alert.id }
            ?? Entry(id: alert.id, venueName: nil, summary: "", createdAt: alert.createdAt, resources: [])
        entry.venueName = alert.venue.name
        entry.summary = alert.summary
        for resource in shared where !entry.resources.contains(where: { $0.id == resource.id }) {
            entry.resources.append(resource)
        }
        guard entries.first(where: { $0.id == alert.id }) != entry else { return }
        entries.removeAll { $0.id == alert.id }
        entries.append(entry)
        entries.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func record(_ alerts: [SafetyAlert]) {
        alerts.forEach(record)
    }

    /// "Clear history": forgets every entry and removes the file.
    func clear() {
        entries = []
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.hotMess.encode(entries).write(to: fileURL, options: [.atomic, .completeFileProtection])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            // History is a convenience: a failed write leaves the last one.
        }
    }

    private static func read(_ fileURL: URL?) -> [Entry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.hotMess.decode([Entry].self, from: data)) ?? []
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("help-history.json")
    }
}
