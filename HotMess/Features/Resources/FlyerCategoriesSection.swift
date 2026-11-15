//
//  FlyerCategoriesSection.swift
//  HotMess
//

import SwiftUI

/// Me > Cards You See > Digital flyers: the kinds of flyer hidden on this
/// phone, and a way to show everything again. Kept on this phone only.
struct FlyerCategoriesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            if let categories = model.flyers.copy?.categories {
                ForEach(categories) { category in
                    Toggle(category.label, isOn: Binding(
                        get: { !model.flyers.hiddenCategories.contains(category.key) },
                        set: { model.flyers.setHidden(category: category.key, !$0) }
                    ))
                    .tint(Color.hotMessAccent)
                }
            }
            if !model.flyers.dismissed.isEmpty || !model.flyers.hiddenCategories.isEmpty {
                Button(String(localized: "Show all flyers again")) { model.flyers.reset() }
                    .accessibilityIdentifier("flyers.reset")
            }
        } header: {
            Text("Digital flyers")
        } footer: {
            Text("Flyers are chosen from your city and the time, nothing else. What you hide stays on this phone: it isn't sent to Hot Mess or any analytics, and deleting the app clears it.")
        }
        .task { await model.flyers.loadCopy() }
    }
}
