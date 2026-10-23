import AudienceKit
import SwiftUI
import UIKit

/// Signs before sharing; never silently falls back to an unsigned URL.
struct SignedShareButton: View {
    let path: String
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var prepared: PreparedShare?
    @State private var error: String?

    var body: some View {
        Button { Task { await prepare(lifetime: "DAY") } } label: {
            if busy { ProgressView() }
            else { Label("Share", systemImage: "square.and.arrow.up") }
        }
        .disabled(busy)
        .contextMenu {
            Button("Share for one day") { Task { await prepare(lifetime: "DAY") } }
            if !path.hasPrefix("/pings/") {
                Button("Share for one week") { Task { await prepare(lifetime: "WEEK") } }
                Button("Share for one month") { Task { await prepare(lifetime: "MONTH") } }
            }
        }
        .sheet(item: $prepared) { share in SystemShareSheet(url: share.url) }
        .alert("Couldn't create a share link", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }

    @MainActor private func prepare(lifetime: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let response = try await model.audienceKit.graphQL(Self.document,
                variables: ["path": .string(path), "lifetime": .string(lifetime)], as: Response.self)
            guard let link = response.shareLink else { throw ShareError.unavailable }
            prepared = PreparedShare(url: link.url)
        } catch { self.error = error.localizedDescription }
    }

    private static let document = """
    query ShareInvitation($path: String!, $lifetime: ShareLinkLifetime!) {
      shareLink(path: $path, lifetime: $lifetime) { url expiresAt }
    }
    """
    private struct Response: Decodable, Sendable {
        struct Link: Decodable, Sendable { let url: URL }
        let shareLink: Link?
    }
    private struct PreparedShare: Identifiable { let id = UUID(); let url: URL }
    private enum ShareError: LocalizedError {
        case unavailable
        var errorDescription: String? { "This item can no longer be shared." }
    }
}

private struct SystemShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
