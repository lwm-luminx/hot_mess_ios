//
//  PrivacyChoicesScreen.swift
//  HotMess
//

import AudienceKit
import StoreKit
import SwiftUI

/// "Your privacy choices": what the member chooses about their data in Hot Mess (the API's doc/PRIVACY_CHOICES.md).
/// Each free choice is one switch, the same either way, and the server enforces it. Where Hot Mess sells a privacy
/// pass, it's paid on the web in the browser, so it only shows in US storefronts, as with tips to read without ads.
struct PrivacyChoicesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var offer: PrivacyOffer?
    @State private var choices: PrivacyChoices = .defaults
    @State private var storefront: String?
    @State private var saving: PrivacyChoiceKey?
    @State private var checkingOut = false
    @State private var error: String?

    private let appName = String(localized: "Hot Mess")

    var body: some View {
        List {
            if let offer {
                Section {
                    ForEach(offer.choices.filter { $0 != .privacyPass }, id: \.self) { key in
                        toggle(key)
                    }
                } header: {
                    Text(PrivacyChoicesCopy.intro(appName: appName))
                        .textCase(nil)
                }

                if PrivacyChoicesCopy.isPassOffered(offer, storefrontCountryCode: storefront),
                   let cents = offer.passCents
                {
                    passSection(cents: cents, days: offer.passDays)
                } else if let until = choices.privacyPassUntil {
                    Section { Text(PrivacyChoicesCopy.passRunning(until: until)) }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(PrivacyChoicesCopy.title)
        .task {
            await load()
            storefront = await Storefront.current?.countryCode
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the browser's checkout: read the pass again.
            if phase == .active, checkingOut { Task { await load() } }
        }
    }

    private func toggle(_ key: PrivacyChoiceKey) -> some View {
        Toggle(isOn: Binding(
            get: { choices.isOn(key) },
            set: { on in Task { await set(key, on: on) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PrivacyChoicesCopy.label(key))
                Text(PrivacyChoicesCopy.detail(key, appName: appName))
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
                if key == .saleShareOptOut, choices.saleShareOptOutSource == .globalPrivacyControl {
                    Text(PrivacyChoicesCopy.fromGlobalPrivacyControl)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(Color.hotMessAccent)
        .disabled(saving == key || !model.session.isSignedIn)
        .accessibilityIdentifier("privacy.\(key.rawValue)")
    }

    private func passSection(cents: Int, days: Int) -> some View {
        Section {
            if let until = choices.privacyPassUntil {
                Text(PrivacyChoicesCopy.passRunning(until: until))
            }
            if checkingOut, choices.privacyPassUntil == nil {
                Text(PrivacyChoicesCopy.pending).foregroundStyle(.secondary)
            }
            Button {
                Task { await startPass() }
            } label: {
                Label(PrivacyChoicesCopy.passButton(cents: cents, days: days), systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.session.isSignedIn)
            .accessibilityIdentifier("privacy.pass")
        } header: {
            Text(PrivacyChoicesCopy.label(.privacyPass))
        } footer: {
            Text(PrivacyChoicesCopy.passExplanation(days: days))
        }
    }

    private func load() async {
        do {
            let result = try await model.audienceKit.privacy()
            offer = result.offer
            choices = result.choices
            if choices.privacyPassUntil != nil { checkingOut = false }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = String(localized: "Your privacy choices couldn't load. Try again in a moment.")
        }
    }

    private func set(_ key: PrivacyChoiceKey, on: Bool) async {
        saving = key
        defer { saving = nil }
        do {
            choices = try await model.audienceKit.setPrivacyChoice(key, on: on)
            error = nil
        } catch {
            self.error = String(localized: "That didn't save. Try again.")
        }
    }

    private func startPass() async {
        do {
            let checkout = try await model.audienceKit.startPrivacyPass(returnURL: "hotmess://privacy")
            checkingOut = true
            // The browser, not an in-app web view: this is a web purchase.
            openURL(checkout.checkoutURL)
        } catch {
            self.error = String(localized: "The privacy pass isn't available right now.")
        }
    }
}
