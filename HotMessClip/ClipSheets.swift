import AudienceKit
import AuthenticationServices
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The sheet over the record: sign in if there's no session (the API needs
/// one for prices, tiers and payments), pick a tier or an amount, pay with
/// Apple Pay, then the pass or the receipt with the app underneath.
struct ClipCheckoutSheet: View {
    let flow: ClipFlow
    let link: ClipLink
    @Bindable var session: ClipSession
    let getApp: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.loading
    @State private var failure: String?

    enum Step {
        case loading
        case signIn
        case cover(ClipDetails)
        case tip(ClipPerformer, preselected: Int?)
        case pass(Admission)
        case thanks(ClipTip, ClipPerformer)
        case unavailable(String)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch step {
                case .loading:
                    ProgressView().tint(ClipTheme.accentInk).frame(maxWidth: .infinity, minHeight: 240)
                case .signIn:
                    ClipSignInView(session: session, flow: flow)
                case let .cover(details):
                    ClipCoverPicker(details: details, checkout: session.checkout) { result in
                        switch result {
                        case let .paid(admission): step = .pass(admission)
                        case .canceled: break
                        case let .failed(message): failure = message
                        }
                    }
                case let .tip(performer, preselected):
                    ClipTipPicker(performer: performer, preselected: preselected, session: session) { result in
                        switch result {
                        case let .paid(tip): step = .thanks(tip, performer)
                        case .canceled: break
                        case let .failed(message): failure = message
                        }
                    }
                case let .pass(admission):
                    ClipPassView(admission: admission, session: session, getApp: getApp)
                case let .thanks(tip, performer):
                    ClipThanksView(tip: tip, performer: performer, getApp: getApp)
                case let .unavailable(message):
                    VStack(spacing: 16) {
                        Text(message).font(.system(size: 15)).foregroundStyle(ClipTheme.ink).multilineTextAlignment(.center)
                        Button("Get Hot Mess") { getApp() }.buttonStyle(ClipAccentButtonStyle())
                    }.padding(.top, 40)
                }
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            if !isPass {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(ClipTheme.ink)
                        .frame(width: 32, height: 32).background(ClipTheme.controlFill, in: Circle())
                }
                .accessibilityLabel("Close").padding(12).disabled(session.checkout.busy || session.busy)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(isPass ? ClipTheme.night : ClipTheme.surfaceRaised)
        .interactiveDismissDisabled(session.checkout.busy || session.busy)
        .task(id: session.signedIn) { await advance() }
        .alert("Couldn't take the payment", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    private var isPass: Bool { if case .pass = step { true } else { false } }

    @MainActor private func advance() async {
        switch step {
        case .pass, .thanks: return
        default: break
        }
        guard session.signedIn else { step = .signIn; return }
        step = .loading
        if session.details == nil { await session.loadDetails(for: link) }
        guard !Task.isCancelled else { return }
        guard let details = session.details else {
            step = .unavailable(session.detailsError ?? ClipError.unavailable.localizedDescription)
            return
        }
        switch flow {
        case .cover:
            if details.viewerPass != nil || (details.coverCharge?.payable ?? false), details.venue != nil {
                step = .cover(details)
            } else {
                step = .unavailable("Cover isn't available to buy here right now.")
            }
        case let .tip(preselected):
            if let performer = details.performer, performer.tipping?.acceptsInApp == true {
                step = .tip(performer, preselected: preselected)
            } else {
                step = .unavailable("\(details.performer?.firstName ?? "This performer") isn't taking tips through Hot Mess right now.")
            }
        }
    }
}

// MARK: - Sign in

/// One sentence of consent and the Apple button. Sign in with Apple is the
/// clip's only sign-in; Hide My Email is fine.
struct ClipSignInView: View {
    @Bindable var session: ClipSession
    let flow: ClipFlow
    @State private var verdict: AgeGate.Verdict?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClipOverline(text: "Almost there")
            Text(title).font(.system(size: 24, weight: .bold)).kerning(-0.3).foregroundStyle(ClipTheme.ink)
            Text(body_).font(.system(size: 15)).foregroundStyle(ClipTheme.inkMuted)
            if verdict == .minor {
                Text("Hot Mess is for people 18 and older.").font(.system(size: 15, weight: .semibold)).foregroundStyle(ClipTheme.warning)
            } else {
                SignInWithAppleButton(.continue) { $0.requestedScopes = [.fullName, .email] } onCompletion: { result in
                    AgeGate.confirm()
                    Task { await session.signIn(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50).clipShape(Capsule())
                .disabled(session.busy)
                if session.busy { ProgressView("Signing in…").tint(ClipTheme.accentInk).font(.system(size: 13)) }
                if let error = session.error { Text(error).font(.system(size: 13)).foregroundStyle(ClipTheme.warning) }
                ClipFinePrint(text: Text("By continuing you confirm you're 18 or older and accept the [Terms](https://hotmess.social/terms/) and [Privacy Policy](https://hotmess.social/privacy/). Hide My Email is fine."))
            }
        }
        .task { verdict = await AgeGate.requestDeclaredAge() }
    }

    private var title: String {
        switch flow {
        case .cover: "Sign in to pay cover"
        case .tip: "Sign in to tip"
        }
    }
    private var body_: String {
        switch flow {
        case .cover: "Apple Pay takes the payment. Signing in puts the pass on your account, so the door can scan it and it's waiting in Hot Mess."
        case .tip: "Apple Pay takes the payment. Signing in is how the tip reaches them with your first name on it."
        }
    }
}

// MARK: - Cover

struct ClipCoverPicker: View {
    let details: ClipDetails
    @Bindable var checkout: ClipCheckout
    let done: (ClipCheckout.CoverResult) -> Void
    @State private var tier: CoverTier?

    private var charge: CoverCharge? { details.coverCharge }
    private var venue: ClipVenue? { details.venue }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let pass = details.viewerPass {
                ClipOverline(text: "You're on the list")
                Text(pass.venueName).font(.system(size: 24, weight: .bold)).kerning(-0.3).foregroundStyle(ClipTheme.ink)
                Text("\(pass.nightTitle) · \(pass.tier ?? "General admission")").font(.system(size: 15)).foregroundStyle(ClipTheme.inkMuted)
                Button("Show my pass") { done(.paid(pass)) }.buttonStyle(ClipAccentButtonStyle())
            } else if let charge, let venue {
                // buyCover is the venue's current night, not an event ticket. Say so.
                ClipOverline(text: "Cover · \(CoverFormat.night(charge.night))")
                Text(venue.name).font(.system(size: 24, weight: .bold)).kerning(-0.3).foregroundStyle(ClipTheme.ink)
                if let from = charge.from.flatMap(CoverFormat.time) {
                    Text("Doors \(from)\(charge.until.flatMap(CoverFormat.time).map { " · until \($0)" } ?? "")")
                        .font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
                }
                VStack(spacing: 8) {
                    tierRow(name: "General admission", detail: nil, price: charge.price, selected: tier == nil) { tier = nil }
                    ForEach(charge.tiers ?? []) { item in
                        tierRow(name: item.name, detail: item.description, price: item.price, selected: tier == item) { tier = item }
                    }
                }
                let total = tier?.total ?? charge.total
                let fee = tier.map { Money(cents: $0.total.cents - $0.amount.cents, currency: $0.total.currency) } ?? charge.fee
                HStack {
                    Text("1 person").font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
                    Spacer()
                    Text(fee.cents > 0 ? "\(total.formatted) total, includes a \(fee.formatted) fee" : "\(total.formatted) total")
                        .font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
                }
                if checkout.busy {
                    ProgressView("Processing…").tint(ClipTheme.accentInk).frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    ClipApplePayButton(label: .checkout) {
                        Task { done(await checkout.payCover(venue: venue, tier: tier)) }
                    }
                }
                ClipFinePrint(text: Text("Refundable until the door scans it. Paid to \(venue.name) through Hot Mess. [Terms](https://hotmess.social/terms/)"))
            }
        }
    }

    private func tierRow(name: String, detail: String?, price: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().strokeBorder(selected ? ClipTheme.accent : ClipTheme.borderStrong, lineWidth: selected ? 7 : 1.5)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(ClipTheme.ink)
                    if let detail, !detail.isEmpty { Text(detail).font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted).lineLimit(2) }
                }
                Spacer()
                Text(price).font(.system(size: 15, weight: .bold)).foregroundStyle(ClipTheme.ink)
            }
            .padding(12)
            .background(selected ? ClipTheme.accentSoft : ClipTheme.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: ClipTheme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ClipTheme.controlRadius, style: .continuous)
                .strokeBorder(ClipTheme.accent, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .disabled(checkout.busy)
    }
}

// MARK: - Tip

struct ClipTipPicker: View {
    let performer: ClipPerformer
    let preselected: Int?
    @Bindable var session: ClipSession
    let done: (ClipCheckout.TipResult) -> Void
    @State private var selected: Int?
    @State private var typed = ""
    @State private var quote: ClipTipQuote?
    @State private var quoteError: String?
    @FocusState private var typing: Bool

    private var amounts: ClipTipAmounts { performer.tipping?.amounts ?? ClipTipAmounts(presetCents: [], minimumCents: 0, maximumCents: 0, currency: "usd") }
    private var amountCents: Int? { selected ?? amounts.cents(fromTyped: typed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClipOverline(text: "Tip")
            Text("Tip \(performer.displayName)").font(.system(size: 24, weight: .bold)).kerning(-0.3).foregroundStyle(ClipTheme.ink)
            let chips = amounts.chips
            if !chips.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(chips.count, 4)), spacing: 8) {
                    ForEach(chips, id: \.self) { cents in
                        ClipChip(title: ClipTipAmounts.whole(cents, amounts.currency), selected: selected == cents, height: 56) {
                            selected = cents
                            typed = ""
                            typing = false
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Or another amount").font(.system(size: 13, weight: .semibold)).foregroundStyle(ClipTheme.inkMuted)
                HStack(spacing: 6) {
                    Text(amounts.currency.lowercased() == "usd" ? "$" : amounts.currency.uppercased())
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(ClipTheme.inkMuted)
                    TextField("0", text: $typed).keyboardType(.decimalPad).focused($typing).font(.system(size: 15))
                        .onChange(of: typed) { _, _ in if !typed.isEmpty { selected = nil } }
                }
                .padding(.horizontal, 12).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(typing ? ClipTheme.accent : ClipTheme.borderStrong))
                Text(amounts.boundsText).font(.system(size: 12)).foregroundStyle(ClipTheme.inkMuted)
            }
            if let quote {
                Text(quote.fee.cents > 0 ? "\(quote.amount.formatted) tip + \(quote.fee.formatted) fee = \(quote.total.formatted)" : "\(quote.total.formatted) total")
                    .font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
            } else if let quoteError {
                Text(quoteError).font(.system(size: 13)).foregroundStyle(ClipTheme.warning)
            } else if amountCents != nil {
                ProgressView().tint(ClipTheme.accentInk)
            }
            if session.checkout.busy {
                ProgressView("Processing…").tint(ClipTheme.accentInk).frame(maxWidth: .infinity).frame(height: 50)
            } else if let amountCents, quote != nil {
                ClipApplePayButton(label: .tip) {
                    typing = false
                    Task { done(await session.checkout.payTip(performer: performer, amountCents: amountCents)) }
                }
            } else {
                Text("Pick an amount").font(.system(size: 17, weight: .semibold)).foregroundStyle(ClipTheme.inkMuted)
                    .frame(maxWidth: .infinity).frame(height: 50).background(ClipTheme.controlFill, in: Capsule())
            }
            ClipFinePrint(text: Text("Paid to \(performer.firstName) through Hot Mess with your first name. Tips aren't refundable. [Terms](https://hotmess.social/terms/)"))
        }
        .onAppear { selected = preselected.flatMap { amounts.isAllowed($0) ? $0 : nil } ?? amounts.suggested }
        .task(id: amountCents) { await loadQuote() }
    }

    @MainActor private func loadQuote() async {
        quote = nil
        quoteError = nil
        guard let amountCents else { return }
        do {
            let loaded = try await session.api.tipQuote(personID: performer.id, amountCents: amountCents)
            try Task.checkCancellation()
            quote = loaded
        } catch { if !Task.isCancelled { quoteError = error.localizedDescription } }
    }
}

// MARK: - Pass

/// Dark screen for the door: the rotating QR, what it's for, and the app.
struct ClipPassView: View {
    @State var admission: Admission
    @Bindable var session: ClipSession
    let getApp: () -> Void
    @State private var confirmRefund = false
    @State private var refunding = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ClipSpectrumBar(height: 4).padding(.top, 4)
                VStack(spacing: 4) {
                    ClipOverline(text: admission.status == .refunded ? "Refunded" : "Cover pass", color: Color(hex: 0xF7B6D5))
                    Text(admission.venueName).font(.system(size: 28, weight: .heavy)).kerning(-0.5).foregroundStyle(.white).multilineTextAlignment(.center)
                    Text(admission.nightTitle).font(.system(size: 15)).foregroundStyle(.white.opacity(0.75))
                }
                if admission.isPaid {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 10) {
                            if let code = admission.passCode(at: context.date), let image = qr(code) {
                                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                    .frame(maxWidth: 240).padding(16)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .accessibilityLabel("Admission QR code")
                                Text("Refreshes in \(CoverPass.secondsRemaining(at: context.date))s · screenshots won't scan")
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                            } else {
                                Text("Your pass isn't ready yet. Try again in a moment.").foregroundStyle(.white)
                            }
                        }
                    }
                } else {
                    Text(admission.status.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(spacing: 0) {
                    row("Tier", admission.tier ?? "General admission")
                    row("Guest", admission.profile?.name ?? "You")
                    row("Paid", "\(admission.quantity) admission · \(admission.price)")
                    row("Valid", admission.nightTitle)
                }
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(Color(hex: 0xFFC9A3)) }
                Button("Keep this pass in Hot Mess") { getApp() }.buttonStyle(ClipAccentButtonStyle())
                if admission.isPaid, admission.isRefundable {
                    Button("Refund") { confirmRefund = true }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).disabled(refunding)
                        .confirmationDialog("Refund this cover?", isPresented: $confirmRefund, titleVisibility: .visible) {
                            Button("Refund \(admission.price)", role: .destructive) { Task { await refund() } }
                        } message: { Text("The pass stops working right away. The refund goes back to your card.") }
                }
                Text("Show this at the door. The pass moves into Hot Mess when you install it.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(minHeight: 40)
    }

    @MainActor private func refund() async {
        refunding = true
        defer { refunding = false }
        do { admission = try await session.api.refundAdmission(admission.id) } catch { self.error = error.localizedDescription }
    }

    private func qr(_ code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Tip receipt

struct ClipThanksView: View {
    let tip: ClipTip
    let performer: ClipPerformer
    let getApp: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClipSpectrumBar(height: 4)
            ClipOverline(text: tip.isPaid ? "Sent" : "Processing")
            Text(tip.isPaid ? "Thank you!" : "Almost there").font(.system(size: 28, weight: .heavy)).kerning(-0.5).foregroundStyle(ClipTheme.ink)
            Text(tip.isPaid
                 ? "\(tip.amount.formatted) is on its way to \(performer.displayName), with your first name."
                 : "Your \(tip.amount.formatted) tip for \(performer.displayName) is still processing.")
                .font(.system(size: 15)).foregroundStyle(ClipTheme.inkMuted)
            if tip.fee.cents > 0 {
                Text("\(tip.total.formatted) charged, including a \(tip.fee.formatted) fee.").font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
            }
            Button("Follow \(performer.firstName) in Hot Mess") { getApp() }.buttonStyle(ClipAccentButtonStyle())
            ClipFinePrint(text: Text("Their shows, posts and the chat are in the app."))
        }
    }
}
