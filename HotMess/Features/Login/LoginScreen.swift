//
//  LoginScreen.swift
//  HotMess
//

import AuthenticationServices
import SwiftUI

/// What `RootView` shows when there is no session: the Hot Mess silhouette in
/// the audience's colours, its name and tagline, and Facebook sign-in, with
/// Sign in with Apple beside it. AudienceKit says which of them the audience
/// offers (`GET /v1/token/methods`); until it answers, or if it can't, both.
///
/// A method AudienceKit has a warning for ("Facebook login is only for
/// testers") shows it with Cancel and Continue first. Every sign-in (Facebook,
/// Apple, an App Review code) then needs the person to be 18 or older, from iOS's declared age range or their own confirmation
/// (`AgeGate`), and to agree to the terms.
struct LoginScreen: View {
    /// A sign-in waiting for the age check and the terms.
    private enum PendingSignIn {
        case facebook
        case apple(Result<ASAuthorization, any Error>)
        case reviewCode

        /// Its name in `GET /v1/token/methods`.
        var method: String {
            switch self {
            case .facebook: "facebook"
            case .apple: "apple"
            case .reviewCode: "review_code"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var hasAgreedToEULA = false
    @State private var isShowingEULA = false
    /// Whether the terms sheet on screen also asks "I confirm I am 18 or older".
    @State private var eulaAsksForAge = false
    @State private var pendingSignIn: PendingSignIn?
    /// 18 or older: confirmed on this device before, by iOS's declared age
    /// range, or by the checkbox.
    @State private var hasConfirmedAge = AgeGate.isConfirmed
    /// Whether the login screen shows the 18+ checkbox: until the device has
    /// a confirmation.
    @State private var showsAgeConfirmation = !AgeGate.isConfirmed
    /// iOS is asked for the declared age range once per visit to this screen.
    @State private var hasAskedDeclaredAge = false
    /// iOS said the person is under 18: no sign-in.
    @State private var isUnderage = false
    @State private var isShowingUnderage = false
    @State private var isReviewSignInEnabled = false
    /// The ways the audience lets people sign in; nil shows Facebook and Apple.
    @State private var signInMethods: SignInMethods?
    /// Whether AudienceKit has answered (or couldn't): the buttons wait for
    /// it so nobody skips a warning by tapping early.
    @State private var hasAskedSignInMethods = false
    /// A sign-in waiting on the audience's warning: Cancel or Continue.
    @State private var warnedSignIn: PendingSignIn?
    @State private var isShowingWarning = false
    @State private var isEnteringReviewCode = false
    @State private var isShowingError = false
    @State private var hasAppeared = false
    @State private var isReportingProblem = false

    var body: some View {
        ZStack {
            // In a background so a fill-scaled image can't size the ZStack
            // past the screen, which pushed the button off an iPad's display.
            Color.clear
                .ignoresSafeArea()
                .background {
                    Image("LoginBackground")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
                .background(Color("LaunchBackground").ignoresSafeArea())

            VStack(spacing: 0) {
                header
                    .padding(.top, 72)

                Spacer(minLength: 32)

                signIn
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UserDefaults.standard.removeObject(forKey: "hasAgreedToEULA")
            hasAgreedToEULA = false
            withAnimation(.easeOut(duration: 0.5)) { hasAppeared = true }
        }
        // The audience's sign-in methods, with App Review sign-in only while
        // the API has it on. An API without the methods list still answers
        // whether App Review sign-in is on.
        .task {
            if let methods = await model.session.signInMethods() {
                signInMethods = methods
                isReviewSignInEnabled = methods.reviewCode
            } else {
                isReviewSignInEnabled = await model.session.isReviewSignInEnabled()
            }
            hasAskedSignInMethods = true
        }
        .onChange(of: model.session.state) { _, state in
            if state == .signedIn {
                Task {
                    try? await model.safety.acceptTerms()
                }
            } else if case let .failed(message) = state {
                isShowingError = true
                ErrorReporter.shared.record(kind: "sign_in", message: message)
            }
        }
        .alert(String(localized: "Sign In Failed"), isPresented: $isShowingError) {
            Button(String(localized: "OK"), role: .cancel) {}
            Button(String(localized: "Report a Problem")) { isReportingProblem = true }
        } message: {
            Text(failureMessage ?? String(localized: "Please try again."))
        }
        .alert(String(localized: "Before You Continue"), isPresented: $isShowingWarning, presenting: warnedSignIn) { signIn in
            Button(String(localized: "Cancel"), role: .cancel) { warnedSignIn = nil }
            Button(String(localized: "Continue")) {
                warnedSignIn = nil
                Task { await gate(signIn, warned: true) }
            }
        } message: { signIn in
            Text(signInMethods?.warning(for: signIn.method) ?? "")
        }
        .alert(String(localized: "Hot Mess Is for Adults"), isPresented: $isShowingUnderage) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("You need to be 18 or older to use Hot Mess. Thanks for stopping by.")
        }
        // The waiting sign-in goes ahead once the terms sheet has closed, so
        // Facebook's dialog or the code sheet isn't presented over it.
        .sheet(isPresented: $isShowingEULA, onDismiss: continuePendingSignIn) {
            EULAView(asksForAge: eulaAsksForAge) {
                hasAgreedToEULA = true
                if eulaAsksForAge { hasConfirmedAge = true }
            }
            .preferredColorScheme(nil)
        }
        .sheet(isPresented: $isEnteringReviewCode) {
            ReviewCodeSheet { code in
                Task { await model.session.signInWithReviewCode(code) }
            }
            .preferredColorScheme(nil)
        }
        .sheet(isPresented: $isReportingProblem) {
            NavigationStack {
                ReportProblemScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Cancel")) { isReportingProblem = false }
                        }
                    }
            }
            .environment(model)
            .preferredColorScheme(nil)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(model.brand.name)
                .font(.hotMess(.largeTitle, semibold: true))
                .scaleEffect(1.3)
                .padding(.bottom, 6)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text(model.brand.tagline ?? String(localized: "Find your people tonight."))
                .font(.hotMess(.title3))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 40)
        }
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            if model.session.state == .signedOut, let notice = model.session.endedNotice {
                Text(notice)
                    .font(.hotMess(.subheadline, semibold: true))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("login.sessionEnded")
            }

            eulaAgreementRow

            if offersFacebook {
                facebookButton
            }

            if offersApple {
                appleButton
            }

            Text(signInNote)
                .font(.hotMess(.footnote))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if isReviewSignInEnabled {
                Button(String(localized: "Have an App Review code?")) {
                    attempt(.reviewCode)
                }
                .font(.hotMess(.footnote, semibold: true))
                .foregroundStyle(.white.opacity(0.85))
                .buttonStyle(.plain)
                .disabled(isSigningIn || !hasAskedSignInMethods)
                .accessibilityIdentifier("login.reviewCode")
            }
        }
    }

    private var offersFacebook: Bool { signInMethods?.facebook ?? true }

    private var offersApple: Bool { signInMethods?.apple ?? true }

    private var signInNote: String {
        switch (offersFacebook, offersApple) {
        case (true, true):
            String(localized: "Hot Mess uses your Facebook profile to find your friends and the events near you. With Apple, you can connect Facebook later.")
        case (true, false):
            String(localized: "Hot Mess uses your Facebook profile to find your friends and the events near you.")
        default:
            String(localized: "Sign in with Apple to find the events near you. You can connect Facebook later to find your friends.")
        }
    }

    private var facebookButton: some View {
        Button {
            attempt(.facebook)
        } label: {
            HStack(spacing: 12) {
                if isSigningIn {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image("Facebook")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Text(isSigningIn ? String(localized: "Signing In…") : String(localized: "Continue with Facebook"))
                    .font(.hotMess(.headline, semibold: true))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.white, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn || !hasAskedSignInMethods)
        .accessibilityIdentifier("login.facebook")
        .accessibilityLabel(String(localized: "Continue with Facebook"))
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            // A cancelled or failed Apple sheet has nothing to gate.
            if case .failure = result {
                model.session.signInWithApple(result)
            } else {
                attempt(.apple(result))
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .clipShape(Capsule())
        .disabled(isSigningIn || !hasAskedSignInMethods)
        .accessibilityIdentifier("login.apple")
    }

    // MARK: - Age and terms

    /// Shows the audience's warning for the method, if any, then checks the
    /// person's age and asks them to agree to the terms (and, when iOS
    /// couldn't say, to confirm they're 18 or older) before `signIn` goes
    /// ahead. Apple's own sheet comes first, so its warning shows after it.
    private func attempt(_ signIn: PendingSignIn) {
        Task { await gate(signIn) }
    }

    private func gate(_ signIn: PendingSignIn, warned: Bool = false) async {
        if !warned, signInMethods?.warning(for: signIn.method) != nil {
            warnedSignIn = signIn
            isShowingWarning = true
            return
        }

        if isUnderage {
            isShowingUnderage = true
            return
        }

        // iOS's declared age range comes first, even with the box ticked: an
        // under-18 range blocks sign-in whatever the checkbox says.
        if !AgeGate.isConfirmed, !hasAskedDeclaredAge {
            hasAskedDeclaredAge = true
            switch await AgeGate.requestDeclaredAge() {
            case .adult:
                hasConfirmedAge = true
            case .minor:
                isUnderage = true
                hasConfirmedAge = false
                isShowingUnderage = true
                return
            case .unknown:
                break
            }
        }

        if hasAgreedToEULA && hasConfirmedAge {
            perform(signIn)
        } else {
            pendingSignIn = signIn
            eulaAsksForAge = !hasConfirmedAge
            isShowingEULA = true
        }
    }

    /// After the terms sheet closes: the waiting sign-in, if they agreed.
    private func continuePendingSignIn() {
        guard let signIn = pendingSignIn else { return }
        pendingSignIn = nil
        guard hasAgreedToEULA, hasConfirmedAge, !isUnderage else { return }
        perform(signIn)
    }

    private func perform(_ signIn: PendingSignIn) {
        AgeGate.confirm()
        switch signIn {
        case .facebook:
            Task { await model.session.signIn() }
        case let .apple(result):
            model.session.signInWithApple(result)
        case .reviewCode:
            isEnteringReviewCode = true
        }
    }

    private var eulaAgreementRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            eulaCheckboxRow

            if showsAgeConfirmation {
                ageCheckboxRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        )
    }

    /// "I confirm I am 18 or older", until the device has a confirmation.
    private var ageCheckboxRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                hasConfirmedAge.toggle()
            } label: {
                Image(systemName: hasConfirmedAge ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(hasConfirmedAge ? .white : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(isUnderage)
            .accessibilityIdentifier("login.ageCheckbox")
            .accessibilityLabel(String(localized: "I confirm I am 18 or older"))
            .accessibilityValue(hasConfirmedAge ? "1" : "0")

            Text("I confirm I am 18 or older")
                .font(.hotMess(.caption))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var eulaCheckboxRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                hasAgreedToEULA.toggle()
            } label: {
                Image(systemName: hasAgreedToEULA ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(hasAgreedToEULA ? .white : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("login.eulaCheckbox")
            .accessibilityValue(hasAgreedToEULA ? "1" : "0")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("I agree to the")
                        .foregroundStyle(.white)
                    Button {
                        eulaAsksForAge = false
                        isShowingEULA = true
                    } label: {
                        Text("Terms of Use (EULA)")
                            .underline()
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("login.openEULA")
                }
                Text("Zero tolerance for objectionable content or abusive users.")
                    .font(.hotMess(.caption2, semibold: true))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .font(.hotMess(.caption))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isSigningIn: Bool {
        model.session.state == .signingIn
    }

    private var failureMessage: String? {
        if case let .failed(message) = model.session.state { return message }
        return nil
    }
}
