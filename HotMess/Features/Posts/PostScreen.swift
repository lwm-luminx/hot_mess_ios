//
//  PostScreen.swift
//  HotMess
//

import Observation
import SwiftUI

/// A post and its comments.
@MainActor
@Observable
final class PostDetailModel {
    private(set) var state: LoadState<Post> = .idle
    private(set) var comments: [PostComment] = []
    var draft = ""
    private(set) var isSending = false
    var errorMessage: String?

    private let api: HotMessAPI
    let postID: UUID

    init(api: HotMessAPI, postID: UUID) {
        self.api = api
        self.postID = postID
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            guard let detail = try await api.post(postID) else {
                state = .failed(message: String(localized: "This post was removed."), isRetryable: false)
                return
            }
            comments = detail.comments
            state = .loaded(detail.post)
        } catch is CancellationError {
        } catch {
            state = LoadState(catching: error)
        }
    }

    var canSend: Bool { !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, var post = state.value else { return }
        isSending = true
        defer { isSending = false }
        do {
            comments.append(try await api.commentOnPost(postID, body: body))
            draft = ""
            post.commentCount += 1
            state = .loaded(post)
        } catch {
            errorMessage = NowViewModel.message(for: error)
        }
    }

    func remove(_ comment: PostComment) async {
        do {
            try await api.removePostComment(comment.id)
            comments.removeAll { $0.id == comment.id }
            if var post = state.value {
                post.commentCount = max(0, post.commentCount - 1)
                state = .loaded(post)
            }
        } catch {
            errorMessage = String(localized: "Couldn't delete the comment. Please try again.")
        }
    }
}

struct PostScreen: View {
    let postID: UUID

    /// Comments shown before "Show N earlier comments".
    private static let newestShown = 3

    @Environment(AppModel.self) private var model
    @State private var detail: PostDetailModel?
    @State private var showsEarlier = false
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?
    @FocusState private var composerFocused: Bool

    var body: some View {
        LoadStateView(state: detail?.state ?? .loading, retry: reload) { post in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PostList(posts: [post], postsModel: nil, isExpanded: true)

                    commentsSection(post)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await detail?.load() }
            .safeAreaInset(edge: .bottom) { composer(post) }
        }
        .navigationTitle(detail?.state.value?.posterName ?? String(localized: "Post"))
        .navigationBarTitleDisplayMode(.inline)
        .contentReporting(report: $reportSubject, block: $blockTarget)
        .alert(
            String(localized: "Something went wrong"),
            isPresented: Binding(get: { detail?.errorMessage != nil }, set: { if !$0 { detail?.errorMessage = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(detail?.errorMessage ?? "")
        }
        .task { reload() }
    }

    // MARK: - Comments

    @ViewBuilder
    private func commentsSection(_ post: Post) -> some View {
        let comments = (detail?.comments ?? []).filter { !model.safety.isBlocked($0.authorID) }
        let hidden = showsEarlier ? 0 : max(0, comments.count - Self.newestShown)

        VStack(alignment: .leading, spacing: 12) {
            Text(comments.count == 1 ? String(localized: "1 comment") : String(localized: "\(comments.count) comments"))
                .font(.hotMess(.subheadline, semibold: true))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            if hidden > 0 {
                Button(String(localized: "Show \(hidden) earlier comments")) { showsEarlier = true }
                    .font(.hotMess(.subheadline, semibold: true))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.hotMessAccentInk)
            }

            ForEach(comments.suffix(comments.count - hidden)) { comment in
                commentRow(comment, post: post)
            }
        }
    }

    private func commentRow(_ comment: PostComment, post: Post) -> some View {
        let friend = model.friends.byID[comment.authorID]
        let name = friend?.name ?? comment.authorName
        return HStack(alignment: .top, spacing: 10) {
            Avatar(url: friend?.avatarURL ?? comment.authorAvatarURL, initials: PostByline<EmptyView>.initials(name), size: 32)
                .overlay {
                    if friend != nil { Circle().strokeBorder(Color.hotMessAccent, lineWidth: 2) }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.hotMess(.subheadline, semibold: true))
                        .lineLimit(1)
                    if friend != nil {
                        PostRoleTag(label: String(localized: "Friend"), isVenue: false)
                    }
                    Text(Post.relativeTime(comment.createdAt))
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
                Text(PostBodyText.linked(comment.body))
                    .font(.hotMess(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if model.session.isSignedIn {
                commentMenu(comment, name: name)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("post.comment")
    }

    private func commentMenu(_ comment: PostComment, name: String) -> some View {
        Menu {
            if comment.authorID == model.session.userID || comment.viewerCanRemove {
                Button(role: .destructive) {
                    Task { await detail?.remove(comment) }
                } label: {
                    Label(String(localized: "Delete Comment"), systemImage: "trash")
                }
            }
            if comment.authorID != model.session.userID {
                let author = BlockedUser(id: comment.authorID, name: comment.authorName, avatarURL: comment.authorAvatarURL)
                Button(role: .destructive) {
                    reportSubject = ReportSubject(
                        target: .postComment,
                        targetID: comment.id.uuidString.lowercased(),
                        sender: author
                    )
                } label: {
                    Label(String(localized: "Report Comment…"), systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) {
                    blockTarget = author
                } label: {
                    Label(String(localized: "Block \(name)"), systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .accessibilityLabel(String(localized: "Comment options"))
    }

    // MARK: - Composer

    @ViewBuilder
    private func composer(_ post: Post) -> some View {
        Group {
            if !post.commentsOpen {
                Text("Comments are off on this post.")
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else if !model.session.isSignedIn {
                Text("Sign in to comment.")
                    .font(.hotMess(.subheadline, semibold: true))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else if let loaded = detail {
                @Bindable var detail = loaded
                HStack(spacing: 8) {
                    TextField(String(localized: "Add a comment"), text: $detail.draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($composerFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.hotMessControlFill, in: .capsule)
                        .accessibilityIdentifier("post.commentField")

                    Button {
                        Task { await detail.send() }
                    } label: {
                        if detail.isSending {
                            ProgressView()
                        } else {
                            Text("Send").fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!detail.canSend)
                    .accessibilityIdentifier("post.sendComment")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func reload() {
        if detail == nil { detail = PostDetailModel(api: model.api, postID: postID) }
        Task { await detail?.load() }
    }
}
