import Foundation

/// The chips on the tip sheet and the bounds on "another amount". Pure logic
/// so `Scripts/test-app-clip.sh` can check it without UIKit.
struct ClipTipAmounts: Equatable, Sendable {
    let presetCents: [Int]
    let minimumCents: Int
    let maximumCents: Int
    let currency: String

    /// Presets inside the performer's bounds, in order, without repeats.
    var chips: [Int] {
        var seen = Set<Int>()
        return presetCents.filter { isAllowed($0) && seen.insert($0).inserted }
    }

    /// The chip selected when the sheet opens: the second preset when there
    /// are several (the mockups lead with $10 out of $5/$10/$20), else the first.
    var suggested: Int? {
        let chips = chips
        return chips.count > 1 ? chips[1] : chips.first
    }

    func isAllowed(_ cents: Int) -> Bool {
        cents > 0 && cents >= minimumCents && (maximumCents <= 0 || cents <= maximumCents)
    }

    /// Cents for what someone typed in the "another amount" field, or nil.
    func cents(fromTyped text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned), value > 0 else { return nil }
        let cents = NSDecimalNumber(decimal: value * 100).rounding(accordingToBehavior: nil).intValue
        return isAllowed(cents) ? cents : nil
    }

    /// "$5 to $500", for the hint under the field.
    var boundsText: String {
        let low = ClipTipAmounts.whole(minimumCents, currency)
        guard maximumCents > 0 else { return "\(low) or more" }
        return "\(low) to \(ClipTipAmounts.whole(maximumCents, currency))"
    }

    static func whole(_ cents: Int, _ currency: String) -> String {
        let style = Decimal.FormatStyle.Currency(code: currency.uppercased())
        let amount = Decimal(cents) / 100
        return cents % 100 == 0 ? amount.formatted(style.precision(.fractionLength(0))) : amount.formatted(style)
    }
}
