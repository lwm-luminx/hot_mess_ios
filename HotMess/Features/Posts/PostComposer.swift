//
//  PostComposer.swift
//  HotMess
//

import PhotosUI
import SwiftUI

/// "New Post" and "Edit Post", for whoever manages a venue or a talent
/// listing: as whom, the text, up to four photos with alt text (new posts),
/// Community or Public, pinned, and comments. Writes go to the staff view
/// with the same sign-in (`HotMessAPI.createPost`).
struct PostComposer: View {
    enum Mode: Hashable {
        /// A new post on `target`, as one of `authors`.
        case new(authors: [PostAuthor], target: PostTarget)
        case edit(Post)
    }

    let mode: Mode
    var onSaved: (Post) -> Void = { _ in }

    /// One photo being added: the picture and what it shows.
    private struct Attachment: Identifiable {
        let id = UUID()
        let image: UIImage
        var altText = ""
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var author: PostAuthor?
    @State private var text = ""
    @State private var attachments: [Attachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var visibility = PostVisibility.community
    @State private var pinned = false
    @State private var commentsOpen = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let maxLength = 2000

    var body: some View {
        NavigationStack {
            Form {
                header
                textSection
                if isNew { photosSection }
                visibilitySection
                Section {
                    Toggle(String(localized: "Pin to the Top"), isOn: $pinned)
                    Toggle(String(localized: "Allow Comments"), isOn: $commentsOpen)
                } footer: {
                    Text(whereItShows)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isNew ? String(localized: "New Post") : String(localized: "Edit Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(isNew ? String(localized: "Post") : String(localized: "Save")) {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("postComposer.save")
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await add(items) }
            }
            .interactiveDismissDisabled(isDirty)
        }
        .onAppear(perform: start)
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        if case let .new(authors, target) = mode {
            Section {
                if authors.count > 1 {
                    Picker(String(localized: "Post as"), selection: $author) {
                        ForEach(authors) { Text($0.name).tag(Optional($0)) }
                    }
                } else if let only = authors.first {
                    LabeledContent(String(localized: "Post as"), value: only.name)
                }
                if case let .event(_, name) = target {
                    LabeledContent(String(localized: "On"), value: name)
                }
            }
        }
    }

    private var textSection: some View {
        Section {
            TextField(String(localized: "What's happening?"), text: $text, axis: .vertical)
                .lineLimit(4...12)
                .accessibilityIdentifier("postComposer.body")
        } footer: {
            if trimmed.count > Self.maxLength {
                Text("\(trimmed.count) of \(Self.maxLength) characters").foregroundStyle(.red)
            }
        }
    }

    private var photosSection: some View {
        Section {
            ForEach($attachments) { $attachment in
                HStack(spacing: 12) {
                    Image(uiImage: attachment.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                    TextField(String(localized: "Describe the photo"), text: $attachment.altText, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .onDelete { attachments.remove(atOffsets: $0) }
            if attachments.count < HotMessAPI.maxPostPhotos {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: HotMessAPI.maxPostPhotos - attachments.count,
                    matching: .images
                ) {
                    Label(
                        attachments.isEmpty ? String(localized: "Add Photos") : String(localized: "Add More Photos"),
                        systemImage: "photo.on.rectangle"
                    )
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Up to \(HotMessAPI.maxPostPhotos). Describe each one for people using VoiceOver.")
        }
    }

    private var visibilitySection: some View {
        Section {
            Picker(String(localized: "Who can see it"), selection: $visibility) {
                ForEach(PostVisibility.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("postComposer.visibility")
        } header: {
            Text("Who can see it")
        } footer: {
            Text(visibility.summary)
        }
    }

    // MARK: - State

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !isSaving && !trimmed.isEmpty && trimmed.count <= Self.maxLength && (!isNew || author != nil)
    }

    private var isDirty: Bool {
        switch mode {
        case .new: !trimmed.isEmpty || !attachments.isEmpty
        case let .edit(post): trimmed != post.body || pinned != post.pinned || commentsOpen != post.commentsOpen
            || visibility != post.visibility
        }
    }

    private var whereItShows: String {
        switch mode {
        case let .new(_, .event(_, name)):
            String(localized: "Shows on \(name), on \(authorPage) and in the locale's updates.")
        case .new:
            String(localized: "Shows on \(authorPage) and in the locale's updates.")
        case .edit:
            String(localized: "Changes show everywhere the post does, marked Edited if the text changed.")
        }
    }

    private var authorPage: String {
        author.map { String(localized: "\($0.name)'s page") } ?? String(localized: "your page")
    }

    private func start() {
        switch mode {
        case let .new(authors, _):
            if author == nil { author = authors.first }
        case let .edit(post):
            guard text.isEmpty else { return }
            text = post.body
            visibility = post.visibility
            pinned = post.pinned
            commentsOpen = post.commentsOpen
        }
    }

    private func add(_ items: [PhotosPickerItem]) async {
        pickerItems = []
        for item in items where attachments.count < HotMessAPI.maxPostPhotos {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = String(localized: "Couldn't add that photo.")
                continue
            }
            attachments.append(Attachment(image: image))
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let post: Post
            switch mode {
            case let .new(_, target):
                guard let author else { return }
                let photos = attachments.compactMap { attachment in
                    attachment.image.uploadJPEG().map { (jpeg: $0, altText: attachment.altText) }
                }
                post = try await model.api.createPost(
                    as: author, on: target, body: trimmed, photos: photos,
                    pinned: pinned, commentsOpen: commentsOpen, visibility: visibility
                )
            case let .edit(existing):
                post = try await model.api.updatePost(
                    existing.id,
                    body: trimmed == existing.body ? nil : trimmed,
                    pinned: pinned == existing.pinned ? nil : pinned,
                    commentsOpen: commentsOpen == existing.commentsOpen ? nil : commentsOpen,
                    visibility: visibility == existing.visibility ? nil : visibility
                )
            }
            onSaved(post)
            dismiss()
        } catch {
            errorMessage = NowViewModel.message(for: error)
        }
    }
}
