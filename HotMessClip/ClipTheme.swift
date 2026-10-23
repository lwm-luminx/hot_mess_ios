import PassKit
import SwiftUI

/// The Hot Mess preset of the AudienceKit design system, as fixed values. The
/// clip doesn't link AudienceKitUI (size budget), so the tokens the mockups use
/// live here. Keep them in step with `project/ds/audiencekit/tokens.json`.
enum ClipTheme {
    static let surface = Color(hex: 0xF6EFF3)
    static let surfaceRaised = Color.white
    static let surfaceSunken = Color(hex: 0xFAF4F7)
    static let controlFill = Color(hex: 0xEFE4EA)
    static let border = Color(hex: 0xE6D3DC)
    static let borderStrong = Color(hex: 0x937F89)
    static let ink = Color(hex: 0x24161D)
    static let inkMuted = Color(hex: 0x6B5360)
    static let accent = Color(hex: 0xB8236F)
    static let accentSoft = Color(hex: 0xFDE6F1)
    static let accentInk = Color(hex: 0xA01F61)
    static let success = Color(hex: 0x1D7144)
    static let successSoft = Color(hex: 0xE5F4EC)
    static let warning = Color(hex: 0x8A5300)
    static let warningSoft = Color(hex: 0xFDF1D9)
    static let glass = Color(red: 28 / 255, green: 20 / 255, blue: 26 / 255).opacity(0.55)
    static let photoPlaceholder = Color(hex: 0x291F26)
    static let night = Color(hex: 0x16101A)

    /// `radius-photo`: cards and sheets.
    static let cardRadius: CGFloat = 26
    /// `radius-control`: chips, rows, inputs.
    static let controlRadius: CGFloat = 8

    /// The pride spectrum, used as a thin ribbon or ring only.
    static let spectrum: [Color] = [
        Color(hex: 0xE40303), Color(hex: 0xFF8C00), Color(hex: 0xFFED00),
        Color(hex: 0x008026), Color(hex: 0x004DFF), Color(hex: 0x750787)
    ]

    static let termsURL = URL(string: "https://hotmess.social/terms/")!
    static let privacyURL = URL(string: "https://hotmess.social/privacy/")!
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Shell pieces

/// White card on the surface wash.
struct ClipPanel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: ClipTheme.cardRadius, style: .continuous))
            .shadow(color: ClipTheme.ink.opacity(0.12), radius: 1, y: 1)
    }
}

/// The audience mark and name, on glass over a photo or on the surface.
struct ClipBrandPill: View {
    var onPhoto = true
    var body: some View {
        HStack(spacing: 8) {
            Text("H").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(ClipTheme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            Text("Hot Mess").font(.system(size: 13, weight: .bold))
        }
        .padding(.leading, 6).padding(.trailing, 12).frame(height: 32)
        .foregroundStyle(onPhoto ? .white : ClipTheme.ink)
        .background(onPhoto ? ClipTheme.glass : ClipTheme.controlFill, in: Capsule())
    }
}

/// A glass pill for a fact over the hero photo ("Open now · until 2am").
struct ClipGlassTag: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 26).background(ClipTheme.glass, in: Capsule())
    }
}

struct ClipSpectrumBar: View {
    var height: CGFloat = 6
    var body: some View {
        HStack(spacing: 0) { ForEach(ClipTheme.spectrum.indices, id: \.self) { ClipTheme.spectrum[$0] } }
            .frame(height: height).clipShape(Capsule()).accessibilityHidden(true)
    }
}

/// The caps overline above a date tile or a sheet title.
struct ClipOverline: View {
    let text: String
    var color = ClipTheme.accentInk
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundStyle(color)
    }
}

/// The one Hot Mess button per screen.
struct ClipAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(ClipTheme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
    }
}

/// The grey "Get Hot Mess" footer and other secondary actions.
struct ClipQuietButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ClipTheme.ink)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(ClipTheme.controlFill.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: ClipTheme.controlRadius, style: .continuous))
    }
}

/// A radio chip in an amount or tier group.
struct ClipChip: View {
    let title: String
    let selected: Bool
    var height: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: height > 48 ? 20 : 15, weight: selected ? .heavy : .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).frame(height: height)
                .foregroundStyle(selected ? ClipTheme.accentInk : ClipTheme.ink)
                .background(selected ? ClipTheme.accentSoft : ClipTheme.controlFill,
                            in: RoundedRectangle(cornerRadius: ClipTheme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ClipTheme.controlRadius, style: .continuous)
                    .strokeBorder(ClipTheme.accent, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The black Apple Pay button, or the reason there isn't one.
struct ClipApplePayButton: View {
    var label: PayWithApplePayButtonLabel = .checkout
    let action: () -> Void
    var body: some View {
        if PKPaymentAuthorizationController.canMakePayments() {
            PayWithApplePayButton(label, action: action)
                .payWithApplePayButtonStyle(.black)
                .frame(height: 50).clipShape(Capsule())
        } else {
            Text("Apple Pay isn't available on this device. Pay in the Hot Mess app instead.")
                .font(.system(size: 13)).foregroundStyle(ClipTheme.inkMuted)
        }
    }
}

/// Small print under a payment button.
struct ClipFinePrint: View {
    let text: Text
    var body: some View {
        text.font(.system(size: 12)).foregroundStyle(ClipTheme.inkMuted).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).tint(ClipTheme.accentInk)
    }
}
