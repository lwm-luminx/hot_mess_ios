//
//  AgeGate.swift
//  HotMess
//

#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
import Foundation
import UIKit

/// Hot Mess is for adults: the terms say 18+ and so does the age rating. Before
/// anyone signs in, the app asks iOS for the person's declared age range (the
/// Declared Age Range framework, iOS 26 and later). When iOS can't say, or the
/// person chooses not to share, they confirm they're 18 or older themselves on
/// the login screen and in the terms. Either way the confirmation is kept on
/// this device, so it's asked once.
@MainActor
enum AgeGate {
    enum Verdict: Equatable, Sendable {
        /// 18 or older, by the declared age range or an earlier confirmation.
        case adult
        /// The declared age range is under 18: no sign-in.
        case minor
        /// iOS couldn't say, or the person didn't share: they confirm it themselves.
        case unknown
    }

    nonisolated static let minimumAge = 18

    private nonisolated static let confirmedKey = "HotMessConfirmedAdult"
    private nonisolated static let sourceKey = "HotMessConfirmedAdultSource"

    /// How the 18+ confirmation on this device was made, in the API's `AgeSource` words: `APP_STORE` when iOS
    /// shared a declared age range of 18 or more, `SELF_DECLARED` when the person confirmed it themselves. The
    /// app sends it with `acceptTerms`, so the account keeps the check as well as the device.
    nonisolated static var source: String {
        UserDefaults.standard.string(forKey: sourceKey) ?? "SELF_DECLARED"
    }

    /// Whether this device already has an 18+ confirmation.
    nonisolated static var isConfirmed: Bool {
        UserDefaults.standard.bool(forKey: confirmedKey)
    }

    /// Keeps the person's 18+ confirmation on this device.
    nonisolated static func confirm() {
        UserDefaults.standard.set(true, forKey: confirmedKey)
    }

    /// Asks iOS for the person's declared age range against the 18 gate, where
    /// the framework exists. An adult range is kept as the confirmation.
    static func requestDeclaredAge() async -> Verdict {
        if isConfirmed { return .adult }

        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.0, *) {
            guard let presenter = UIApplication.shared.topViewController else { return .unknown }
            do {
                let response = try await AgeRangeService.shared.requestAgeRange(ageGates: minimumAge, in: presenter)
                let verdict = verdict(for: response)
                if verdict == .adult {
                    UserDefaults.standard.set("APP_STORE", forKey: sourceKey)
                    confirm()
                }
                return verdict
            } catch {
                // Not available here (no Apple Account age, an MDM policy) or
                // the request was refused: fall back to asking.
                return .unknown
            }
        }
        #endif

        return .unknown
    }

    /// What a shared range means for an 18 gate: a range starting at 18 or
    /// more is an adult, one ending below 18 is a minor, and anything else
    /// (no bounds) can't say.
    nonisolated static func verdict(lowerBound: Int?, upperBound: Int?) -> Verdict {
        if let lowerBound, lowerBound >= minimumAge { return .adult }
        if let upperBound, upperBound < minimumAge { return .minor }
        return .unknown
    }

    #if canImport(DeclaredAgeRange)
    @available(iOS 26.0, *)
    private static func verdict(for response: AgeRangeService.Response) -> Verdict {
        switch response {
        case .declinedSharing:
            return .unknown
        case let .sharing(range):
            return verdict(lowerBound: range.lowerBound, upperBound: range.upperBound)
        @unknown default:
            return .unknown
        }
    }
    #endif
}
