//
//  ConnectGoogleButton.swift
//  HotMess
//

import AudienceKitUI
import AuthenticationServices
import SwiftUI

/// "Connect Google" on Me, for an account that signed in with Facebook or
/// Apple, so it can also sign in with Google. Connecting keeps the same
/// account, or joins it with the account the Google account already had.
struct ConnectGoogleButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isConnecting = false
    @State private var failureMessage: String?

    var body: some View {
        Button {
            Task { await connect() }
        } label: {
            HStack(spacing: 12) {
                if isConnecting {
                    ProgressView()
                } else {
                    Image("Google")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }

                Text(isConnecting ? String(localized: "Connecting…") : GoogleSignInCopy.connect)
            }
        }
        .disabled(isConnecting)
        .accessibilityIdentifier("connectGoogle")
        .alert(
            String(localized: "Couldn't connect Google"),
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(failureMessage ?? "")
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }

        do {
            _ = try await model.connectGoogle(using: webAuthenticationSession)
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}

/// What connecting Google adds, under the button.
struct ConnectGoogleFooter: View {
    var body: some View {
        Text("Connect Google to sign in with your Google account too. Nothing is posted for you.")
    }
}
