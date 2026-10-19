//
//  BrandStore.swift
//  HotMess
//

import AudienceKit
import AudienceKitUI
import Foundation
import Observation
import os
import SwiftUI
import UIKit

/// The audience's branding from AudienceKit (`GET /v1/branding`): its name,
/// tagline and colour tokens. Until it loads, and if it can't, the app uses
/// the `hot_mess` preset baked into `BrandPalette`.
@MainActor
@Observable
final class BrandStore {
    private(set) var branding: Branding?

    private let audienceKit: AudienceKitClient

    init(audienceKit: AudienceKitClient) {
        self.audienceKit = audienceKit
    }

    var name: String { branding?.audience.name ?? String(localized: "Hot Mess") }

    var tagline: String? { branding?.theme.tagline }

    /// The AudienceKitUI preset the audience's views draw with
    /// (`.audiencePreset(_:)`): the audience's own once branding loads.
    /// `default` is what the API sends for an audience that never picked one,
    /// and this app's look is `hot_mess` then, as `BrandPalette`'s is.
    var preset: String {
        guard let preset = branding?.theme.preset, preset != "default" else { return "hot_mess" }
        return preset
    }

    /// The accent, resolving light and dark from the audience's tokens. Reads
    /// `branding` so views that use it redraw when branding arrives.
    var accent: Color {
        _ = branding
        return Color.hotMessAccent
    }

    func load() async {
        do {
            let branding = try await audienceKit.branding()
            BrandPalette.shared.apply(branding.theme)
            self.branding = branding
        } catch {
            Log.app.error("Branding unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The colours `Color.hotMessAccent` resolves to. Thread-safe so the dynamic
/// `UIColor` provider can read it while UIKit draws.
final class BrandPalette: @unchecked Sendable {
    static let shared = BrandPalette()

    /// The `hot_mess` preset's accent.
    static let defaultLight = DesignTokens.hotMess.accent
    static let defaultDark = DesignTokens.hotMessDark.accent

    private let lock = OSAllocatedUnfairLock<(light: RGBAColor, dark: RGBAColor)>(
        initialState: (BrandPalette.defaultLight, BrandPalette.defaultDark)
    )

    func apply(_ theme: Branding.Theme) {
        let light = theme.color("accent") ?? Self.defaultLight
        let dark = theme.dark["accent"].flatMap(RGBAColor.init(hex:)) ?? Self.defaultDark
        lock.withLock { $0 = (light, dark) }
    }

    func accent(dark: Bool) -> RGBAColor {
        lock.withLock { dark ? $0.dark : $0.light }
    }
}

extension UIColor {
    convenience init(_ color: RGBAColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
