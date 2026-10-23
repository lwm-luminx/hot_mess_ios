import UIKit

/// The view controller on top in the foreground scene, for UIKit sheets over
/// SwiftUI (`AgeGate` presents the Declared Age Range request). The app has
/// the same extension in `CoverCheckout.swift`, which the clip doesn't compile.
extension UIApplication {
    var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController

        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
