#if TEST_HOOKS
import SwiftUI

/// A deterministic UI fixture that exercises the production card, section and Link without changing a live session.
struct KaraokeUITestScreen: View {
    let mode: String
    @State private var openedURL: String?
    var body: some View {
        let code = mode == "own" ? "654321" : "123456"
        let json = mode == "disconnected" ? "{}" : mode == "audiencekit" ? #"{"provider":"audiencekit","provider_name":"Hot Mess"}"# : """
            {"provider_name":"KaraFun","session_code":"\(code)","own_session_code":\(mode == "own" ? "\"654321\"" : "null"),"join_url":"https://www.karafun.com/\(code)/"}
            """
        let karaoke = mode == "none" ? nil : try? JSONDecoder().decode(KaraokeNight.self, from: Data(json.utf8))
        let event = Event(id: UUID(), name: "Karaoke test night", startDate: Date(), karaoke: karaoke)
        NavigationStack {
            ScrollView {
                EventCard(event: event)
                if let karaoke { KaraokeSection(karaoke: karaoke) }
                if let openedURL { Text(openedURL).accessibilityIdentifier("karaoke.opened") }
            }.navigationTitle("Karaoke test")
        }.environment(\.openURL, OpenURLAction { url in openedURL = url.absoluteString; return .handled })
    }
}
#endif
