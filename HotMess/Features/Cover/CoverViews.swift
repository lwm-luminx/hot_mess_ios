//
//  CoverViews.swift
//  HotMess
//

import SwiftUI

extension View {
    /// Shows the pass `CoverCheckout` presents, and its payment errors. Attach
    /// once, above the tabs, so any screen can pay cover or open a pass.
    func coverPresenter() -> some View {
        modifier(CoverPresenter())
    }
}

private struct CoverPresenter: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var checkout = model.checkout

        content
            .fullScreenCover(item: $checkout.presentedPass) { pass in
                PassScreen(admission: pass)
                    .environment(model)
            }
            .alert(
                String(localized: "Cover"),
                isPresented: Binding(
                    get: { checkout.errorMessage != nil },
                    set: { if !$0 { checkout.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(checkout.errorMessage ?? "")
            }
    }
}

/// A venue's or event's cover: the price, and a way to pay it, show the pass,
/// or a note that it's paid at the door.
struct CoverSection: View {
    let coverCharge: CoverCharge?
    /// Whether the cover is tonight's, the only one that can be paid now.
    let isTonight: Bool
    /// The user's cover tonight at the venue.
    let admission: Admission?
    let venueID: UUID?
    let venueName: String

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var quantity = 1
    @State private var selectedTierID: String?
    /// What the buyer picked on a sliding scale; nil until they move it, so
    /// it starts at the suggested amount.
    @State private var pickedCents: Int?

    private var isOnlyApplePay: Bool {
        guard let coverCharge else { return false }
        return !coverCharge.hasOtherPaymentMechanisms && coverCharge.supportsApplePay
    }

    private var applePayStatus: ApplePayStatus {
        ApplePayStatus.current()
    }

    private var showsPayCoverButton: Bool {
        // If the cover charge specifies payment mechanisms and there are no other mechanisms besides apple_pay
        if let coverCharge, !coverCharge.hasOtherPaymentMechanisms {
            return false
        }
        return true
    }

    private var showsApplePayButton: Bool {
        guard let coverCharge, coverCharge.supportsApplePay else { return false }
        return applePayStatus == .ready
    }

    private var selectedTier: CoverTier? {
        guard let tiers = coverCharge?.tiers, !tiers.isEmpty else { return nil }
        if let selectedTierID, let tier = tiers.first(where: { $0.id == selectedTierID }) {
            return tier
        }
        return tiers.first
    }

    /// What one cover costs the buyer before fees on a sliding scale, or nil
    /// for a fixed cover.
    private var chosenCents: Int? {
        guard let scale = coverCharge?.scale else { return nil }
        return scale.clamped(pickedCents ?? scale.suggested.cents)
    }

    /// The pay button's price: the picked amount on a sliding scale (fees are
    /// added on the payment sheet), else the all-in total.
    private func payPrice(_ coverCharge: CoverCharge) -> String {
        if let chosenCents {
            let price = CoverFormat.price(cents: chosenCents * quantity, currency: coverCharge.amount.currency)
            return coverCharge.fee.cents > 0 ? String(localized: "\(price) + fees") : price
        }
        return selectedTier?.total(for: quantity).formatted ?? coverCharge.price(for: quantity)
    }

    var body: some View {
        DetailSection(String(localized: "Cover")) {
            if let coverCharge {
                Label(coverCharge.summary(isTonight: isTonight), systemImage: "ticket")
                    .font(.hotMess(.body))
            }

            if let admission, admission.isPaid {
                ShowPassButton(admission: admission)
            } else if isTonight, let coverCharge {
                if coverCharge.payable, let venueID {
                    if isOnlyApplePay && applePayStatus == .unavailable {
                        Text(String(localized: "Pay cash at the door"))
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)
                    } else if isOnlyApplePay && applePayStatus == .needsSetup {
                        VStack(alignment: .leading, spacing: 10) {
                            #if canImport(PassKit)
                            ApplePayButton(type: .setUp, style: .white) {
                                if PKPassLibrary.isPassLibraryAvailable() {
                                    PKPassLibrary().openPaymentSetup()
                                }
                            }
                            .frame(height: 50)
                            .clipShape(Capsule())
                            .accessibilityIdentifier("cover.applePaySetup")
                            #endif

                            Text(String(localized: "Or pay cash at the door"))
                                .font(.hotMess(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if let tiers = coverCharge.tiers, tiers.count > 1 {
                            Picker(String(localized: "Tier"), selection: Binding(
                                get: { selectedTierID ?? tiers.first?.id ?? "" },
                                set: { selectedTierID = $0 }
                            )) {
                                ForEach(tiers) { tier in
                                    Text("\(tier.name) (\(tier.price))").tag(tier.id)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if let scale = coverCharge.scale, let chosenCents {
                            CoverAmountStepper(scale: scale, cents: chosenCents) { pickedCents = $0 }
                        }

                        Stepper(value: $quantity, in: 1...10) {
                            HStack {
                                Text(String(localized: "Quantity"))
                                    .font(.hotMess(.body))
                                Spacer()
                                Text(quantity > 1 ? String(localized: "\(quantity) covers") : String(localized: "1 cover"))
                                    .font(.hotMess(.body, semibold: true))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        let totalPrice = payPrice(coverCharge)
                        // A sliding scale always names the amount, so the buyer sees what they picked.
                        let namesPrice = quantity > 1 || chosenCents != nil

                        if showsPayCoverButton {
                            PayCoverButton(
                                venueID: venueID,
                                venueName: venueName,
                                quantity: quantity,
                                tier: selectedTier?.id,
                                amountCents: chosenCents,
                                title: showsApplePayButton
                                    ? (namesPrice ? String(localized: "Pay \(totalPrice) with card") : String(localized: "Pay with card"))
                                    : (namesPrice ? String(localized: "Pay \(totalPrice)") : String(localized: "Pay cover"))
                            )
                        }

                        #if canImport(PassKit)
                        if showsApplePayButton {
                            ApplePayButton(type: .plain, style: .white) {
                                Task {
                                    await model.checkout.payWithApplePay(
                                        venueID: venueID,
                                        venueName: venueName,
                                        quantity: quantity,
                                        tier: selectedTier?.id,
                                        amountCents: chosenCents
                                    )
                                }
                            }
                            .frame(height: 50)
                            .clipShape(Capsule())
                            .disabled(model.checkout.isBusy)
                            .accessibilityIdentifier("cover.applePay")
                        }
                        #endif
                    }
                    if let coatCheck = coverCharge.coatCheck, coatCheck.payable {
                        Divider()
                        HStack {
                            Label(String(localized: "Coat Check: \(coatCheck.price)"), systemImage: "hanger")
                                .font(.hotMess(.subheadline))
                            Spacer()
                            Button(String(localized: "Check Coat")) {
                                Task {
                                    await model.checkout.payCoatCheck(
                                        venueID: venueID,
                                        venueName: venueName,
                                        quantity: 1
                                    )
                                }
                            }
                            .font(.hotMess(.caption, semibold: true))
                            .buttonStyle(.bordered)
                            .tint(Color.hotMessAccent)
                            .disabled(model.checkout.isBusy)
                            .accessibilityIdentifier("cover.addCoatCheck")
                        }
                    }
                } else if !coverCharge.payable {
                    Text(String(localized: "Pay cash at the door"))
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Tonight's coat check at a venue: the price, and a way to pay it, or show the pass.
struct CoatCheckSection: View {
    let coatCheck: CoatCheckCharge
    let admission: Admission?
    let venueID: UUID
    let venueName: String

    @Environment(AppModel.self) private var model
    @State private var quantity = 1

    private var isOnlyApplePay: Bool {
        !coatCheck.hasOtherPaymentMechanisms && coatCheck.supportsApplePay
    }

    private var applePayStatus: ApplePayStatus {
        ApplePayStatus.current()
    }

    private var showsPayCoatCheckButton: Bool {
        if !coatCheck.hasOtherPaymentMechanisms {
            return false
        }
        return true
    }

    private var showsApplePayButton: Bool {
        guard coatCheck.supportsApplePay else { return false }
        return applePayStatus == .ready
    }

    var body: some View {
        DetailSection(String(localized: "Coat Check")) {
            Label(String(localized: "Coat check \(coatCheck.price) tonight"), systemImage: "hanger")
                .font(.hotMess(.body))

            if let admission, admission.isPaid {
                ShowPassButton(admission: admission, title: String(localized: "Show coat check pass"), systemImage: "hanger")
            } else if coatCheck.payable {
                if isOnlyApplePay && applePayStatus == .unavailable {
                    Text(String(localized: "Pay cash at coat check"))
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                } else if isOnlyApplePay && applePayStatus == .needsSetup {
                    VStack(alignment: .leading, spacing: 10) {
                        #if canImport(PassKit)
                        ApplePayButton(type: .setUp, style: .white) {
                            if PKPassLibrary.isPassLibraryAvailable() {
                                PKPassLibrary().openPaymentSetup()
                            }
                        }
                        .frame(height: 50)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("coatCheck.applePaySetup")
                        #endif

                        Text(String(localized: "Or pay cash at coat check"))
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Stepper(value: $quantity, in: 1...10) {
                        HStack {
                            Text(String(localized: "Coats"))
                                .font(.hotMess(.body))
                            Spacer()
                            Text(quantity > 1 ? String(localized: "\(quantity) coats") : String(localized: "1 coat"))
                                .font(.hotMess(.body, semibold: true))
                                .foregroundStyle(.secondary)
                        }
                    }

                    let totalPrice = coatCheck.price(for: quantity)

                    if showsPayCoatCheckButton {
                        PayCoatCheckButton(
                            venueID: venueID,
                            venueName: venueName,
                            quantity: quantity,
                            title: showsApplePayButton
                                ? (quantity > 1 ? String(localized: "Pay \(totalPrice) with card") : String(localized: "Pay with card"))
                                : (quantity > 1 ? String(localized: "Check \(quantity) coats (\(totalPrice))") : String(localized: "Check coat (\(totalPrice))"))
                        )
                    }

                    #if canImport(PassKit)
                    if showsApplePayButton {
                        ApplePayButton(type: .plain, style: .white) {
                            Task {
                                await model.checkout.payCoatCheckWithApplePay(
                                    venueID: venueID,
                                    venueName: venueName,
                                    quantity: quantity
                                )
                            }
                        }
                        .frame(height: 50)
                        .clipShape(Capsule())
                        .disabled(model.checkout.isBusy)
                        .accessibilityIdentifier("coatCheck.applePay")
                    }
                    #endif
                }
            } else if !coatCheck.payable {
                Text(String(localized: "Pay cash at coat check"))
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Starts paying coat check at a venue.
struct PayCoatCheckButton: View {
    let venueID: UUID
    let venueName: String
    var quantity: Int = 1
    var title: String? = nil

    @Environment(AppModel.self) private var model

    private var buttonTitle: String {
        title ?? String(localized: "Pay coat check")
    }

    var body: some View {
        Button {
            Task {
                await model.checkout.payCoatCheck(
                    venueID: venueID,
                    venueName: venueName,
                    quantity: quantity
                )
            }
        } label: {
            HStack(spacing: 8) {
                if model.checkout.isPaying(for: venueID) {
                    ProgressView()
                        .tint(Color.hotMessOnAccent)
                }
                Text(buttonTitle)
                    .font(.hotMess(.headline, semibold: true))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.hotMessAccent)
        .foregroundStyle(Color.hotMessOnAccent)
        .disabled(model.checkout.isBusy)
        .accessibilityIdentifier("coatCheck.pay")
    }
}

/// A sliding-scale cover's amount: the range, and a stepper that moves a
/// dollar at a time from the suggested amount.
struct CoverAmountStepper: View {
    let scale: CoverScale
    let cents: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stepper {
                HStack {
                    Text(String(localized: "Pay what you can"))
                        .font(.hotMess(.body))
                    Spacer()
                    Text(CoverFormat.price(cents: cents, currency: scale.suggested.currency))
                        .font(.hotMess(.body, semibold: true))
                        .monospacedDigit()
                }
            } onIncrement: {
                onChange(scale.step(cents, by: 1))
            } onDecrement: {
                onChange(scale.step(cents, by: -1))
            }
            .accessibilityIdentifier("cover.amount")
            .accessibilityValue(CoverFormat.price(cents: cents, currency: scale.suggested.currency))

            Text(String(localized: "\(scale.range), \(scale.suggested.formatted) suggested"))
                .font(.hotMess(.caption))
                .foregroundStyle(.secondary)
        }
    }
}

/// Starts paying tonight's cover at a venue.
struct PayCoverButton: View {
    let venueID: UUID
    let venueName: String
    var quantity: Int = 1
    var tier: String? = nil
    /// What the buyer picked for each cover on a sliding scale.
    var amountCents: Int? = nil
    var title: String? = nil

    @Environment(AppModel.self) private var model

    private var buttonTitle: String {
        title ?? String(localized: "Pay cover")
    }

    var body: some View {
        Button {
            Task {
                await model.checkout.pay(
                    venueID: venueID,
                    venueName: venueName,
                    quantity: quantity,
                    tier: tier,
                    amountCents: amountCents
                )
            }
        } label: {
            HStack(spacing: 8) {
                if model.checkout.isPaying(for: venueID) {
                    ProgressView()
                        .tint(Color.hotMessOnAccent)
                }
                Text(buttonTitle)
                    .font(.hotMess(.headline, semibold: true))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.hotMessAccent)
        .foregroundStyle(Color.hotMessOnAccent)
        .disabled(model.checkout.isBusy)
        .accessibilityIdentifier("cover.pay")
    }
}

/// Opens a paid pass.
struct ShowPassButton: View {
    let admission: Admission
    var title: String? = nil
    var systemImage: String? = nil

    @Environment(AppModel.self) private var model

    private var buttonTitle: String {
        title ?? (admission.isCoatCheck ? String(localized: "Show coat check pass") : String(localized: "Show pass"))
    }

    private var icon: String {
        systemImage ?? (admission.isCoatCheck ? "hanger" : "qrcode")
    }

    var body: some View {
        Button {
            model.checkout.show(admission)
        } label: {
            Label(buttonTitle, systemImage: icon)
                .font(.hotMess(.headline, semibold: true))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.hotMessAccent)
        .foregroundStyle(Color.hotMessOnAccent)
        .accessibilityIdentifier(admission.isCoatCheck ? "coatCheck.showPass" : "cover.showPass")
    }
}

/// Now, at a venue whose cover can be paid in the app and isn't yet.
struct SkipTheLineCard: View {
    let venue: Venue
    let coverCharge: CoverCharge

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickedCents: Int?

    /// What the buyer picked on a sliding scale (the suggested amount until
    /// they move it), or nil for a fixed cover.
    private var chosenCents: Int? {
        coverCharge.scale.map { $0.clamped(pickedCents ?? $0.suggested.cents) }
    }

    private var payPrice: String {
        guard let chosenCents else { return coverCharge.price }
        let price = CoverFormat.price(cents: chosenCents, currency: coverCharge.amount.currency)
        return coverCharge.fee.cents > 0 ? String(localized: "\(price) + fees") : price
    }

    private var isOnlyApplePay: Bool {
        !coverCharge.hasOtherPaymentMechanisms && coverCharge.supportsApplePay
    }

    private var applePayStatus: ApplePayStatus {
        ApplePayStatus.current()
    }

    private var showsPayCoverButton: Bool {
        if !coverCharge.hasOtherPaymentMechanisms {
            return false
        }
        return true
    }

    private var showsApplePayButton: Bool {
        guard coverCharge.supportsApplePay else { return false }
        return applePayStatus == .ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                isOnlyApplePay && applePayStatus == .unavailable
                    ? String(localized: "Cover at the door")
                    : String(localized: "Skip the line, pay cover"),
                systemImage: isOnlyApplePay && applePayStatus == .unavailable ? "ticket" : "bolt.fill"
            )
            .font(.hotMess(.headline, semibold: true))
            .foregroundStyle(isOnlyApplePay && applePayStatus == .unavailable ? Color.secondary : Color.hotMessAccent)

            Text(coverCharge.summary(isTonight: true))
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)

            if isOnlyApplePay && applePayStatus == .unavailable {
                Text(String(localized: "Pay cash at the door"))
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            } else if isOnlyApplePay && applePayStatus == .needsSetup {
                #if canImport(PassKit)
                ApplePayButton(type: .setUp, style: .white) {
                    if PKPassLibrary.isPassLibraryAvailable() {
                        PKPassLibrary().openPaymentSetup()
                    }
                }
                .frame(height: 50)
                .clipShape(Capsule())
                .accessibilityIdentifier("cover.applePaySetup")
                #endif

                Text(String(localized: "Or pay cash at the door"))
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                if let scale = coverCharge.scale, let chosenCents {
                    CoverAmountStepper(scale: scale, cents: chosenCents) { pickedCents = $0 }
                }

                if showsPayCoverButton {
                    PayCoverButton(
                        venueID: venue.id,
                        venueName: venue.name,
                        amountCents: chosenCents,
                        title: showsApplePayButton
                            ? (chosenCents != nil ? String(localized: "Pay \(payPrice) with card") : String(localized: "Pay with card"))
                            : String(localized: "Pay \(payPrice)")
                    )
                }

                #if canImport(PassKit)
                if showsApplePayButton {
                    ApplePayButton(type: .plain, style: .white) {
                        Task {
                            await model.checkout.payWithApplePay(
                                venueID: venue.id,
                                venueName: venue.name,
                                amountCents: chosenCents
                            )
                        }
                    }
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .disabled(model.checkout.isBusy)
                    .accessibilityIdentifier("cover.applePay")
                }
                #endif
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isOnlyApplePay && applePayStatus == .unavailable
                ? Color(.secondarySystemGroupedBackground)
                : Color.hotMessAccentSoft,
            in: .rect(cornerRadius: CardMetrics.cornerRadius)
        )
        .padding(.horizontal, 16)
    }
}

/// Now, at a venue with coat check that can be paid in the app and isn't yet.
struct CoatCheckCard: View {
    let venue: Venue
    let coatCheck: CoatCheckCharge

    @Environment(AppModel.self) private var model

    private var isOnlyApplePay: Bool {
        !coatCheck.hasOtherPaymentMechanisms && coatCheck.supportsApplePay
    }

    private var applePayStatus: ApplePayStatus {
        ApplePayStatus.current()
    }

    private var showsPayCoatCheckButton: Bool {
        if !coatCheck.hasOtherPaymentMechanisms { return false }
        return true
    }

    private var showsApplePayButton: Bool {
        guard coatCheck.supportsApplePay else { return false }
        return applePayStatus == .ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(localized: "Coat Check"),
                systemImage: "hanger"
            )
            .font(.hotMess(.headline, semibold: true))
            .foregroundStyle(Color.hotMessAccent)

            Text(String(localized: "\(coatCheck.price) tonight"))
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)

            if isOnlyApplePay && applePayStatus == .unavailable {
                Text(String(localized: "Pay cash at coat check"))
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            } else if isOnlyApplePay && applePayStatus == .needsSetup {
                #if canImport(PassKit)
                ApplePayButton(type: .setUp, style: .white) {
                    if PKPassLibrary.isPassLibraryAvailable() {
                        PKPassLibrary().openPaymentSetup()
                    }
                }
                .frame(height: 50)
                .clipShape(Capsule())
                .accessibilityIdentifier("coatCheck.applePaySetup")
                #endif

                Text(String(localized: "Or pay cash at coat check"))
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                if showsPayCoatCheckButton {
                    PayCoatCheckButton(
                        venueID: venue.id,
                        venueName: venue.name,
                        title: showsApplePayButton
                            ? String(localized: "Pay with card")
                            : String(localized: "Pay \(coatCheck.price)")
                    )
                }

                #if canImport(PassKit)
                if showsApplePayButton {
                    ApplePayButton(type: .plain, style: .white) {
                        Task {
                            await model.checkout.payCoatCheckWithApplePay(
                                venueID: venue.id,
                                venueName: venue.name
                            )
                        }
                    }
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .disabled(model.checkout.isBusy)
                    .accessibilityIdentifier("coatCheck.applePay")
                }
                #endif
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isOnlyApplePay && applePayStatus == .unavailable
                ? Color(.secondarySystemGroupedBackground)
                : Color.hotMessAccentSoft,
            in: .rect(cornerRadius: CardMetrics.cornerRadius)
        )
        .padding(.horizontal, 16)
    }
}

/// Now, with a paid pass for the venue: the live code up front, opening the
/// full pass.
struct TonightPassCard: View {
    let admission: Admission

    @Environment(AppModel.self) private var model

    private var badgeTitle: String {
        admission.isCoatCheck ? String(localized: "Coat Check") : String(localized: "Your pass")
    }

    private var actionTitle: String {
        admission.isCoatCheck ? String(localized: "Show at coat check") : String(localized: "Show at the door")
    }

    private var passTitle: String {
        if admission.isCoatCheck {
            let coats = admission.quantity > 1 ? "\(admission.quantity) coats" : String(localized: "1 coat")
            if let claim = admission.claimCheckNumber, !claim.isEmpty {
                return String(localized: "Hanger #\(claim) (\(coats)) · \(admission.nightTitle)")
            }
            return String(localized: "Paid \(admission.price) (\(coats)) · \(admission.nightTitle)")
        }
        return admission.quantity > 1
            ? String(localized: "Paid \(admission.price) (\(admission.quantity) covers) · \(admission.nightTitle)")
            : String(localized: "Paid \(admission.price) · \(admission.nightTitle)")
    }

    var body: some View {
        Button {
            model.checkout.show(admission)
        } label: {
            VStack(spacing: 0) {
                LiveBand()
                    .frame(height: 6)

                HStack(spacing: 16) {
                    PassCode(admission: admission)
                        .frame(width: 96, height: 96)
                        .padding(6)
                        .background(.white, in: .rect(cornerRadius: HotMessRadius.lg))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(badgeTitle)
                            .font(.hotMess(.footnote, semibold: true))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(admission.venueName)
                            .font(.hotMess(.title3, semibold: true))
                            .lineLimit(2)

                        Text(passTitle)
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Text(actionTitle)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .font(.hotMess(.subheadline, semibold: true))
                        .foregroundStyle(Color.hotMessAccent)
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
            .contentShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(badgeTitle) for \(admission.venueName), \(admission.nightTitle)"))
        .accessibilityHint(String(localized: "Opens the pass."))
        .accessibilityIdentifier(admission.isCoatCheck ? "coatCheck.tonightPass" : "cover.tonightPass")
    }
}

// MARK: - Native Apple Pay Button

#if canImport(PassKit)
import PassKit

extension ApplePayStatus {
    static let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

    static func current() -> ApplePayStatus {
        guard PKPaymentAuthorizationController.canMakePayments() else {
            return .unavailable
        }
        guard PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks) else {
            return .needsSetup
        }
        return .ready
    }
}

/// A native Apple Pay button rendered via PassKit PKPaymentButton.
struct ApplePayButton: UIViewRepresentable {
    var type: PKPaymentButtonType = .plain
    var style: PKPaymentButtonStyle = .white
    var action: () -> Void

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: style)
        button.cornerRadius = 24
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
#else
extension ApplePayStatus {
    static func current() -> ApplePayStatus {
        .unavailable
    }
}
#endif
