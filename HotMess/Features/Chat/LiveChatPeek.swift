//
//  LiveChatPeek.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// A ChatPeek that follows its room while it's on screen. It watches the
/// room's subscription without being in it (no presence, so nobody sees the
/// user as in chat), so new lines and who's here arrive as they happen, and
/// the panel turns its live ring while the room is joined. Before that, and
/// whenever the room drops, it shows `messages`, the screen's last snapshot.
///
/// At a venue, with tonight's `lineup`, the acts in chat now join the faces
/// after the venue's, and a line says who's in: "The Wildrose, 3 from
/// tonight's lineup and Jordan · 23 here".
struct LiveChatPeek: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    let title: String
    let room: ChatRoom
    /// The screen's snapshot of the room's recent messages, oldest first.
    let messages: [VenueMessage]
    var participants: [ChatPeek.Participant] = []
    /// The venue's name, for the line under the faces; `nil` for a locale's
    /// room, which has none.
    var venueName: String? = nil
    /// Tonight's lineup at the venue, for the acts in chat now.
    var lineup: VenueLineup? = nil
    let route: AppRoute
    /// Called with each line the room says while live, such as the "On now"
    /// announcement advancing the lineup posts.
    var onMessage: ((VenueMessage) -> Void)? = nil

    @State private var viewModel: VenueChatViewModel?

    /// Follows the room while the app is active and the user has accepted the
    /// chat terms, as the room itself does.
    private struct FollowKey: Hashable {
        var room: ChatRoom
        var follows: Bool
    }

    private var isLive: Bool {
        guard let viewModel, viewModel.room == room else { return false }
        return viewModel.connectionState == .connected
    }

    var body: some View {
        ChatPeek(
            title: title,
            roomName: room.name,
            messages: shownMessages.peekMessages(currentUserID: model.session.userID, friends: model.friends.byID),
            online: online,
            participants: shownParticipants,
            summary: RoomSummary.line(
                venue: venueName,
                lineupInChat: lineupInChat.count,
                friend: friendHere,
                count: online.flatMap { $0 > 0 ? $0 : nil }
            ),
            isLive: isLive,
            route: route
        )
        .task(id: FollowKey(room: room, follows: model.safety.hasAcceptedTerms && scenePhase == .active)) {
            await follow()
        }
        .onChange(of: isLive ? viewModel?.messages.last?.id : nil) {
            if isLive, let message = viewModel?.messages.last { onMessage?(message) }
        }
        .onDisappear {
            let viewModel = self.viewModel
            Task { await viewModel?.stop() }
        }
    }

    private var shownMessages: [VenueMessage] {
        guard isLive, let viewModel else { return messages }
        return viewModel.messages
    }

    /// Everyone else in the room now, while live.
    private var online: Int? {
        guard isLive, let viewModel else { return nil }
        var ids = viewModel.onlineUserIDs
        if let userID = model.session.userID { ids.remove(userID) }
        return ids.count
    }

    /// The acts on tonight's lineup in chat now, while live and the room
    /// says (servers without lineup presence don't).
    private var lineupInChat: [HereNowLineupFace] {
        guard isLive, let viewModel, let lineup, let presence = viewModel.lineupPresence else { return [] }
        return HereNowLineupFace.faces(for: lineup, presence: presence).filter { $0.presence == .online }
    }

    /// The screen's faces with the lineup in chat after the venue's: the
    /// venue, the lineup, then the user and friends.
    private var shownParticipants: [ChatPeek.Participant] {
        let acts = lineupInChat.map { face in
            ChatPeek.Participant(
                id: "lineup-\(face.id)", name: face.name,
                avatarURL: face.people.first?.avatarURL,
                presence: .online
            )
        }
        guard !acts.isEmpty else { return participants }
        let places = participants.prefix { $0.isPlace }
        return Array(places) + acts + participants.dropFirst(places.count)
    }

    /// A friend in the room now, by first name, for the line.
    private var friendHere: String? {
        guard isLive, let viewModel else { return nil }
        return viewModel.hereNow.first { $0.isFriend && $0.isHere && !$0.isViewer }?.firstName
    }

    private func follow() async {
        guard model.safety.hasAcceptedTerms, scenePhase == .active else {
            await viewModel?.stop()
            return
        }

        let current: VenueChatViewModel
        if let viewModel, viewModel.room == room {
            current = viewModel
        } else {
            await viewModel?.stop()
            current = VenueChatViewModel(
                room: room,
                watch: true,
                configuration: model.configuration,
                userID: model.session.userID,
                cable: model.cable,
                friends: model.friends,
                api: model.api
            )
            viewModel = current
        }

        await current.stop()
        guard !Task.isCancelled else { return }
        await current.run()
    }
}
