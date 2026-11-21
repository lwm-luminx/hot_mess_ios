//
//  HotMessWidgetsBundle.swift
//  HotMessWidgets
//

import SwiftUI
import WidgetKit

/// Hot Mess's widget extension: the app's Live Activities (open Pings and
/// Quickies, which the app starts and updates) and the Tonight widget.
@main
struct HotMessWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HotMessLiveActivity()
        HotMessTonightWidget()
    }
}
