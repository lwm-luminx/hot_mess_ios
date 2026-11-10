//
//  ArticleScreen.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// A Soapbox article: its photo, title, byline and the publication's disclosure, then its Markdown body. A teaser
/// links to the publication's own site instead.
struct ArticleScreen: View {
    let articleID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var state: LoadState<Article> = .idle

    var body: some View {
        LoadStateView(state: state, retry: { Task { await load() } }) { article in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let photo = model.audienceKit.url(for: article.heroPhotoUrl) {
                        RemoteImage(url: photo)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel(article.heroAltText ?? "")
                            .accessibilityHidden(article.heroAltText == nil)
                    }
                    header(article)
                    if let disclosure = article.disclosure, !disclosure.isEmpty {
                        Label(disclosure, systemImage: "info.circle")
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("article.disclosure")
                    }
                    if let body = article.body, !body.isEmpty {
                        Text(ArticleScreen.markdown(body))
                            .font(.hotMess(.body))
                            .textSelection(.enabled)
                    } else if let summary = article.summary {
                        Text(summary)
                            .font(.hotMess(.body))
                    }
                    if let url = article.canonicalUrl.flatMap(URL.init(string:)) {
                        Button {
                            openURL(url)
                        } label: {
                            Label(SoapboxCopy.readMore, systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }
                    subjects(article)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(state.value?.publication.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if article.isOpEd {
                Text(SoapboxCopy.opEd.uppercased())
                    .font(.hotMess(.caption, semibold: true))
                    .foregroundStyle(.tint)
            }
            Text(article.title)
                .font(.hotMess(.title2, semibold: true))
                .accessibilityAddTraits(.isHeader)
            if let summary = article.summary, !summary.isEmpty, article.body?.isEmpty == false {
                Text(summary)
                    .font(.hotMess(.headline))
                    .foregroundStyle(.secondary)
            }
            NavigationLink(value: AppRoute.publication(article.publication.id)) {
                HStack(spacing: 4) {
                    Text(ArticleRow.dateline(article))
                    if article.edited { Text("· \(SoapboxCopy.edited)") }
                }
                .font(.hotMess(.subheadline))
            }
            .accessibilityIdentifier("article.publication")
        }
    }

    @ViewBuilder
    private func subjects(_ article: Article) -> some View {
        let venues = article.venues ?? []
        let events = article.events ?? []
        let people = article.people ?? []
        if !venues.isEmpty || !events.isEmpty || !people.isEmpty {
            DetailSection(String(localized: "In this article")) {
                ForEach(venues) { subject in
                    subjectLink(subject, systemImage: "mappin.and.ellipse", route: UUID(uuidString: subject.id).map(AppRoute.venue))
                }
                ForEach(events) { subject in
                    subjectLink(subject, systemImage: "calendar", route: UUID(uuidString: subject.id).map(AppRoute.event))
                }
                ForEach(people) { subject in
                    subjectLink(subject, systemImage: "person", route: UUID(uuidString: subject.id).map(AppRoute.person))
                }
            }
        }
    }

    @ViewBuilder
    private func subjectLink(_ subject: ArticleSubject, systemImage: String, route: AppRoute?) -> some View {
        if let route {
            NavigationLink(value: route) {
                Label(subject.name ?? "", systemImage: systemImage)
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            if let article = try await model.audienceKit.article(id: articleID) {
                state = .loaded(article)
            } else {
                state = LoadState(catching: APIError.notFound)
            }
        } catch is CancellationError {
        } catch let error as AudienceKitError {
            state = LoadState(catching: APIError(error))
        } catch {
            state = LoadState(catching: error)
        }
    }

    /// The body as Markdown, keeping its paragraphs; plain text when it doesn't parse.
    static func markdown(_ body: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
    }
}
