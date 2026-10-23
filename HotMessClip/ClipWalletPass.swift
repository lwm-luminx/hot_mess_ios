import AudienceKit
import PassKit
import SwiftUI

/// "Add to Apple Wallet" on the door pass. The API signs the pass
/// (`GET /v1/admissions/{id}/pass.pkpass`, authenticated); the clip only adds
/// it. Until that endpoint exists the request 404s and the button stays hidden,
/// so the screen degrades to the rotating QR alone.
struct ClipWalletPassButton: View {
    let admission: Admission
    let client: AudienceKitClient
    @State private var pass: PKPass?
    @State private var added = false

    var body: some View {
        if PKPassLibrary.isPassLibraryAvailable(), let pass, !added {
            AddPassToWalletButton([pass])
                .addPassToWalletButtonStyle(.black)
                .frame(height: 50)
                .onChange(of: pass.passTypeIdentifier) { _, _ in refreshAdded(pass) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshAdded(pass) }
        } else {
            Color.clear.frame(height: 0).task { await load() }
        }
    }

    @MainActor private func load() async {
        guard pass == nil, admission.isPaid, PKPassLibrary.isPassLibraryAvailable() else { return }
        do {
            let data = try await client.data(for: APIRequest(path: "/v1/admissions/\(admission.id)/pass.pkpass", authenticated: true))
            let loaded = try PKPass(data: data)
            refreshAdded(loaded)
            pass = loaded
        } catch {
            // No Wallet pass for this admission (yet): the QR on screen is the pass.
        }
    }

    private func refreshAdded(_ pass: PKPass) {
        added = PKPassLibrary().containsPass(pass)
    }
}
