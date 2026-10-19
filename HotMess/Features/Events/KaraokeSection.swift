import SwiftUI

struct KaraokeSection: View {
    let karaoke: KaraokeNight
    /// Where the event is, whose page takes AudienceKit's own karaoke signups.
    var venue: Venue? = nil
    @State private var showingJoinCode = false

    private var joinTitle: String {
        if let provider = karaoke.providerName, !provider.isEmpty {
            return String(localized: "Join \(provider) session")
        }
        return String(localized: "Join karaoke session")
    }

    private var signUpPointer: String {
        if let venue {
            return String(localized: "Sign up to sing on \(venue.name)'s page, or in its chat once you're there.")
        }
        return String(localized: "Sign up to sing on the venue's page, or in its chat once you're there.")
    }

    var body: some View {
        DetailSection(String(localized: "Karaoke")) {
            if let url = karaoke.joinURL {
                Link(destination: url) { Label(joinTitle, systemImage: "music.mic") }
                    .accessibilityIdentifier("karaoke.join")
                Button { showingJoinCode = true } label: {
                    Label(String(localized: "Show join code"), systemImage: "qrcode")
                }
                .accessibilityIdentifier("karaoke.showCode")
            } else if karaoke.isAudienceKit {
                // Signups are on the lineup, from the venue's page or its chat.
                Label(String(localized: "Karaoke night"), systemImage: "music.mic")
                Text(signUpPointer).foregroundStyle(.secondary)
                    .accessibilityIdentifier("karaoke.signUpPointer")
                if let venue {
                    DetailLink(route: .venue(venue.id)) {
                        Label(String(localized: "Sign up at \(venue.name)"), systemImage: "mappin.and.ellipse")
                    }
                }
            } else {
                Label(String(localized: "Karaoke night"), systemImage: "music.mic")
                Text(String(localized: "Ask the host how to join the karaoke session.")).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingJoinCode) {
            if let url = karaoke.joinURL {
                KaraokeJoinCodeSheet(url: url, title: joinTitle, sessionCode: karaoke.sessionCode)
            }
        }
    }
}

/// Full-screen-ish QR so others nearby can scan straight into the session.
private struct KaraokeJoinCodeSheet: View {
    let url: URL
    let title: String
    let sessionCode: String?
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if let image {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 280, maxHeight: 280)
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(String(localized: "Karaoke join QR code"))

                if let sessionCode {
                    Text(sessionCode)
                        .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
                Text(String(localized: "Scan to join"))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .task { image = QRCodeRenderer.image(for: url.absoluteString) }
        }
        .presentationDetents([.medium, .large])
    }
}
