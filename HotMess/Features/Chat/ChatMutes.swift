//
//  ChatMutes.swift
//  HotMess
//

import Foundation

/// People the user muted in one chat room, from the profile sheet's "Mute in
/// this chat". It's only on this device: their messages are hidden in this
/// room and nowhere else, nobody is told, and the API never hears of it.
struct ChatMutes {
    private let defaults: UserDefaults
    private let key: String

    init(room: ChatRoom, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = Self.key(for: room)
    }

    /// "chat.muted.venue.<id>" or "chat.muted.locale.<id>".
    static func key(for room: ChatRoom) -> String {
        let kind = switch room.kind {
        case .venue: "venue"
        case .locale: "locale"
        }
        return "chat.muted.\(kind).\(room.id.uuidString.lowercased())"
    }

    /// Who is muted in the room.
    func load() -> Set<UUID> {
        let ids = defaults.stringArray(forKey: key) ?? []
        return Set(ids.compactMap(UUID.init(uuidString:)))
    }

    /// Mutes or unmutes someone in the room, and returns who is muted after.
    @discardableResult
    func set(_ id: UUID, muted: Bool) -> Set<UUID> {
        var ids = load()
        if muted {
            ids.insert(id)
        } else {
            ids.remove(id)
        }

        if ids.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(ids.map { $0.uuidString.lowercased() }.sorted(), forKey: key)
        }
        return ids
    }
}
