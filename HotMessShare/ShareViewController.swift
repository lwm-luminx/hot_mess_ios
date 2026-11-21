//
//  ShareViewController.swift
//  HotMessShare
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Hot Mess" in Spotify's share sheet: takes the shared song link and leaves
/// it for the app (`SpotifyShareInbox`), which offers to send it to the bar as
/// a song request the next time it opens. The extension doesn't sign in or
/// reach the API, and share extensions have no public way to open their app.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let link = await sharedLink()
            let saved = link.map { SpotifyShareInbox.save($0) } ?? false
            show(ShareConfirmation(state: link == nil ? .notSpotify : (saved ? .saved : .failed),
                                   venueName: SpotifyShareInbox.requestVenue()?.name,
                                   done: { [weak self] in self?.finish() }))
        }
    }

    private func show(_ view: ShareConfirmation) {
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// The first Spotify link among the shared items: a URL, or text holding one.
    private func sharedLink() async -> String? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               let link = SpotifyShareInbox.spotifyLink(in: url.absoluteString) {
                return link
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let link = SpotifyShareInbox.spotifyLink(in: text) {
                return link
            }
        }
        return nil
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

struct ShareConfirmation: View {
    enum State { case saved, notSpotify, failed }

    let state: State
    let venueName: String?
    let done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: state == .saved ? "music.note" : "exclamationmark.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done"), action: done)
                }
            }
        }
    }

    private var title: String {
        switch state {
        case .saved:
            venueName.map { String(localized: "Request it at \($0)") } ?? String(localized: "Request it at the bar")
        case .notSpotify: String(localized: "Share a song from Spotify")
        case .failed: String(localized: "Couldn't save the song")
        }
    }

    private var message: String {
        switch state {
        case .saved: String(localized: "Open Hot Mess next: it asks you to add a note and send it to the host as a song request.")
        case .notSpotify: String(localized: "In Spotify, tap Share on a song and choose Hot Mess.")
        case .failed: String(localized: "Copy the song's link in Spotify, then paste it in Hot Mess.")
        }
    }
}
