//
//  HotMessWidgetsBundle.swift
//  HotMessWidgets
//

import SwiftUI
import WidgetKit

/// Hot Mess's widget extension. For now it only draws the app's Live
/// Activities (open Pings and Quickies); the app starts and updates them.
@main
struct HotMessWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HotMessLiveActivity()
    }
}
