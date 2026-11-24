//
//  NewsScreen.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// A locale's news in full, from "Show more" under its news: the local publishers at the top (each opens its page),
/// then every publisher's articles together, pinned first, then newest, loading more as the reader scrolls.
struct NewsScreen: View {
    /// The locale's id, as the API has it.
    let localeID: String
    let name: String

    @Environment(AppModel.self) private var model
    @State private var publishers: [Publication] = []
    @State private var articles: [Article] = []
    @State private var nextCursor: String?
    @State private var state: LoadState<Bool> = .idle
    @State private var isLoadingMore = false

    /// How many articles each page asks for.
    static let pageSize = 20

    var body: some View {
        LoadStateView(state: state, retry: { Task { await load() } }) { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !publishers.isEmpty {
                        publishersSection
                    }
                    articlesSection
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(String(localized: "News in \(name)"))
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await load() } }
        .refreshable { await load() }
    }

    private var publishersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "Local publishers"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(publishers) { publication in
                        NavigationLink(value: AppRoute.publication(publication.id)) {
                            PublisherTile(publication: publication)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("news.publishers")
    }

    private var articlesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "Latest"))
            if articles.isEmpty {
                Text("Nothing published yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(articles) { article in
                        ArticleLink(article: article)
                            .onAppear {
                                if article.id == articles.last?.id { Task { await loadMore() } }
                            }
                    }
                    if nextCursor != nil {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Text("Show more")
                                    .font(.hotMess(.subheadline, semibold: true))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .disabled(isLoadingMore)
                        .accessibilityIdentifier("news.showMore")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("news.articles")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.hotMess(.subheadline, semibold: true))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 20)
    }

    /// The publishers and the first page, together.
    private func load() async {
        if state.value == nil { state = .loading }
        do {
            async let local = model.audienceKit.localPublications(localeID: localeID)
            async let first = model.audienceKit.articlesPage(localeID: localeID, first: Self.pageSize)
            let page = try await first
            publishers = (try? await local) ?? []
            articles = page.articles
            nextCursor = page.endCursor
            state = .loaded(true)
        } catch is CancellationError {
        } catch let error as AudienceKitError {
            state = LoadState(catching: APIError(error))
        } catch {
            state = LoadState(catching: error)
        }
    }

    /// The next page, when there is one and none is loading.
    private func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await model.audienceKit.articlesPage(localeID: localeID, first: Self.pageSize,
                                                                    after: cursor)
        else { return }
        let seen = Set(articles.map(\.id))
        articles += page.articles.filter { !seen.contains($0.id) }
        nextCursor = page.endCursor
    }
}

/// A publisher at the top of a locale's news: its photo and name.
private struct PublisherTile: View {
    let publication: Publication

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let photo = model.audienceKit.url(for: publication.photoUrl) {
                    RemoteImage(url: photo)
                } else {
                    Image(systemName: "newspaper")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.secondarySystemGroupedBackground))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .accessibilityHidden(true)
            Text(publication.name)
                .font(.hotMess(.caption, semibold: true))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 84)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
