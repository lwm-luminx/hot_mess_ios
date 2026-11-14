//
//  AdFreeTip.swift
//  HotMess
//

import AudienceKit
import StoreKit
import SwiftUI

/// "Tip QSaltLake to read without ads": a reader tips a Soapbox publication, all of it the publisher's (Hot Mess takes
/// no cut), and a big enough tip reads that publication here without ads for a while. The ads going away ties the tip
/// to content, so it isn't a gift in App Review's eyes and can't use the in-app payment sheet: the reader pays on the
/// web, in their browser, and the button only shows in US storefronts (``AdFreeTips/isOffered(adFreeOffered:storefrontCountryCode:)``).
struct AdFreeTipButton: View {
    let publicationID: String
    let publicationName: String
    /// The publication's `adFreeOffered`.
    let offered: Bool?
    /// Runs once a tip is paid, to read the publication (or article) again without ads.
    var onPaid: () async -> Void = {}

    @State private var storefront: String?
    @State private var isTipping = false

    var body: some View {
        Group {
            if AdFreeTips.isOffered(adFreeOffered: offered, storefrontCountryCode: storefront) {
                Button {
                    isTipping = true
                } label: {
                    Label(AdFreeTips.button(publicationName: publicationName), systemImage: "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("adFreeTip.button")
            }
        }
        .task(id: offered) {
            guard offered == true else { return }
            storefront = await Storefront.current?.countryCode
        }
        .sheet(isPresented: $isTipping) {
            AdFreeTipSheet(publicationID: publicationID, publicationName: publicationName, onPaid: onPaid)
        }
    }
}

/// Shown where the ads would be once the reader reads a publication without ads.
struct AdFreeThanks: View {
    let publicationName: String
    var until: Date?

    var body: some View {
        Label(AdFreeTips.thanks(publicationName: publicationName, until: until), systemImage: "heart.fill")
            .font(.hotMess(.footnote))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("adFreeTip.thanks")
    }
}

/// Picks an amount, explains the deal, then sends the reader to the web checkout in their browser and checks the tip
/// when they come back to the app.
struct AdFreeTipSheet: View {
    let publicationID: String
    let publicationName: String
    var onPaid: () async -> Void

    private enum Step: Equatable {
        case choosing
        case starting
        /// In the browser; checked when the app comes back.
        case checkingOut(tipID: String)
        case paid(until: Date?)
        case pending(tipID: String)
        case notPaid
        case failed(String)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var publication: Publication?
    @State private var amountCents: Int?
    @State private var step: Step = .choosing

    var body: some View {
        NavigationStack {
            Form {
                if let publication, let tipCents = publication.adFreeTipCents, let days = publication.adFreeDays {
                    Section {
                        Text(AdFreeTips.explanation(publicationName: publicationName, tipCents: tipCents, days: days))
                            .font(.hotMess(.body))
                    }
                    Section(String(localized: "Your tip")) {
                        Picker(String(localized: "Amount"), selection: $amountCents) {
                            ForEach(Self.presets(tipCents), id: \.self) { cents in
                                Text(Self.money(cents)).tag(Optional(cents))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section {
                        stepView
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(publicationName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
        .task { await loadPublication() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            switch step {
            case let .checkingOut(tipID), let .pending(tipID):
                Task { await confirm(tipID) }
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch step {
        case .choosing, .starting, .notPaid, .failed:
            if case .notPaid = step {
                Text(AdFreeTips.notPaid).foregroundStyle(.secondary)
            }
            if case let .failed(message) = step {
                Text(message).foregroundStyle(.red)
            }
            Button {
                Task { await start() }
            } label: {
                Label(AdFreeTips.continueToCheckout, systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(amountCents == nil || step == .starting)
            .accessibilityIdentifier("adFreeTip.checkout")
        case .checkingOut, .pending:
            Text(AdFreeTips.pending).foregroundStyle(.secondary)
        case let .paid(until):
            AdFreeThanks(publicationName: publicationName, until: until)
            Button(String(localized: "Done")) { dismiss() }
        }
    }

    /// The least tip that counts, twice that and four times that, within the $200 limit on a tip.
    static func presets(_ tipCents: Int) -> [Int] {
        [tipCents, tipCents * 2, tipCents * 4].filter { $0 <= 20_000 }
    }

    static func money(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
    }

    private func loadPublication() async {
        guard publication == nil else { return }
        do {
            publication = try await model.audienceKit.publication(id: publicationID)
            amountCents = publication?.adFreeTipCents
        } catch is CancellationError {
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func start() async {
        guard let amountCents else { return }
        step = .starting
        do {
            let checkout = try await model.audienceKit.startAdFreeTip(publicationID: publicationID,
                                                                      amountCents: amountCents)
            step = .checkingOut(tipID: checkout.tipID)
            // The reader's browser, not an in-app web view: this is a web purchase.
            openURL(checkout.checkoutURL)
        } catch is AdFreeTipUnavailable {
            step = .failed(String(localized: "\(publicationName) can't take tips here yet."))
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func confirm(_ tipID: String) async {
        guard let tip = try? await model.audienceKit.confirmTip(id: tipID) else { return }
        switch tip.status {
        case .paid:
            step = .paid(until: tip.readsAdFreeUntil)
            await onPaid()
        case .pending:
            step = .pending(tipID: tipID)
        default:
            step = .notPaid
        }
    }
}
