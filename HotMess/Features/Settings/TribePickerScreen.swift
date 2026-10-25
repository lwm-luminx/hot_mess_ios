//
//  TribePickerScreen.swift
//  HotMess
//

import SwiftUI

/// "Your tribes", pushed from Me: the curated list by category, with search,
/// "7 of 31 picked" and the cap. Nobody sees the list; when the user and
/// someone in a venue chat picked the same tribe, just the two of them see
/// it. "Done" saves.
struct TribePickerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The picks being edited, saved on Done.
    @State private var picked: Set<String> = []
    @State private var didLoadPicks = false
    @State private var search = ""
    @State private var expanded: Set<String> = []
    @State private var isSaving = false
    @State private var saveError: String?
    /// Shows the cap notice after a tap on a held-back chip.
    @State private var hitCap = false

    /// Chips a category shows before "N more".
    static let collapsedCount = 8

    var body: some View {
        Group {
            if let choices = model.tribes.choices {
                content(choices)
            } else if model.tribes.isSupported == false {
                ContentUnavailableView(
                    String(localized: "Tribes aren't available yet"),
                    systemImage: "person.2.circle",
                    description: Text("Try again later.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(String(localized: "Your tribes"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(String(localized: "Done")) { Task { await save() } }
                        .disabled(model.tribes.choices == nil)
                        .accessibilityIdentifier("tribes.done")
                }
            }
        }
        .task {
            await model.tribes.load(force: true)
            if !didLoadPicks, let choices = model.tribes.choices {
                picked = choices.picked
                didLoadPicks = true
            }
        }
        .alert(String(localized: "Couldn't save your tribes"), isPresented: .constant(saveError != nil)) {
            Button(String(localized: "OK"), role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .accessibilityIdentifier("tribes.picker")
    }

    // MARK: - Content

    private func content(_ choices: TribeChoices) -> some View {
        let editing = TribeChoices(categories: choices.categories, cap: choices.cap, picked: picked)

        return List {
            Section {
                Text("Pick what you're into. Nobody sees your list. When you and someone in a venue chat share one, just the two of you see it.")
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
                PickCounter(picked: picked.count, cap: choices.cap)
                if editing.isAtCap, hitCap || picked.count > choices.cap {
                    Label(
                        String(localized: "That's the most anyone can pick. Remove one to add another."),
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.hotMess(.subheadline, semibold: true))
                    .foregroundStyle(.orange)
                }
            }

            if search.trimmingCharacters(in: .whitespaces).isEmpty {
                if !editing.pickedTribes.isEmpty {
                    Section(String(localized: "Your picks")) {
                        ChipFlow {
                            ForEach(editing.pickedTribes) { tribe in
                                TribeChip(name: tribe.label, isOn: true, showsRemove: true) { toggle(tribe, in: editing) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(choices.categories) { category in
                    categorySection(category, editing: editing)
                }
            } else {
                searchResults(editing)
            }

            Section {
                Button(String(localized: "Suggest a tribe")) {
                    if let url = URL(string: "mailto:feedback@hotmess.social?subject=Tribe%20suggestion") {
                        openURL(url)
                    }
                }
            } footer: {
                Text("Not seeing yours? The list is kept by Hot Mess so it stays kind and safe. Tribes only ever show up in venue chats, and only to someone who shares one with you. We never use them for ads, never sell them, and never use them to hide anyone or anywhere from you.")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: String(localized: "Search \(editing.all.count) tribes"))
    }

    private func categorySection(_ category: TribeCategory, editing: TribeChoices) -> some View {
        let isExpanded = expanded.contains(category.key)
        let shown = isExpanded ? category.tribes : Array(category.tribes.prefix(Self.collapsedCount))
        let hidden = category.tribes.count - shown.count

        return Section(category.name) {
            ChipFlow {
                ForEach(shown) { tribe in
                    chip(tribe, editing: editing)
                }
                if hidden > 0 {
                    Button(String(localized: "\(hidden) more")) { expanded.insert(category.key) }
                        .font(.hotMess(.subheadline, semibold: true))
                        .foregroundStyle(Color.hotMessAccentInk)
                        .frame(minHeight: 40)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func searchResults(_ editing: TribeChoices) -> some View {
        let results = editing.matching(search)
        Section {
            if results.isEmpty {
                Text("No tribes match \"\(search)\".")
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.tribe.label)
                            .font(.hotMess(.body, semibold: true))
                        Text(result.category)
                            .font(.hotMess(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    let isOn = picked.contains(result.tribe.id)
                    TribeChip(
                        name: isOn ? String(localized: "Picked") : String(localized: "Pick"),
                        isOn: isOn,
                        isHeldBack: !isOn && editing.isAtCap
                    ) {
                        toggle(result.tribe, in: editing)
                    }
                    .accessibilityLabel(isOn ? String(localized: "Remove \(result.tribe.name)") : String(localized: "Pick \(result.tribe.name)"))
                }
            }
        }
    }

    private func chip(_ tribe: Tribe, editing: TribeChoices) -> some View {
        let isOn = picked.contains(tribe.id)
        return TribeChip(name: tribe.label, isOn: isOn, isHeldBack: !isOn && editing.isAtCap) {
            toggle(tribe, in: editing)
        }
    }

    // MARK: - Actions

    private func toggle(_ tribe: Tribe, in editing: TribeChoices) {
        if picked.contains(tribe.id) {
            picked.remove(tribe.id)
            hitCap = false
        } else if editing.isAtCap {
            hitCap = true
        } else {
            picked.insert(tribe.id)
        }
    }

    private func save() async {
        guard let choices = model.tribes.choices else { return }
        guard picked != choices.picked else {
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await model.tribes.save(picked)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
