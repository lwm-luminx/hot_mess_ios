//
//  NewsSection.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// Soapbox articles about a page: "In the news" on a venue, event or person, "News" on a locale. Loads on its own and
/// draws nothing while loading, when there are none, or for an audience without Soapbox.
struct NewsSection: View {
    let title: String
    let topic: ArticleTopic
    var limit = 3

    @Environment(AppModel.self) private var model
    @State private var articles: [Article] = []

    var body: some View {
        Group {
            if !articles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.hotMess(.subheadline, semibold: true))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        ForEach(articles) { article in
                            NavigationLink(value: AppRoute.article(article.id)) {
                                ArticleRow(article: article)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .accessibilityIdentifier("news.section")
            }
        }
        .task(id: topic) {
            articles = (try? await model.audienceKit.articles(about: topic, first: limit)) ?? []
        }
    }
}

extension NewsSection {
    /// "In the news" for a venue, event or person.
    static func inTheNews(_ topic: ArticleTopic) -> NewsSection {
        NewsSection(title: SoapboxCopy.inTheNews, topic: topic)
    }

    /// A locale's "News".
    static func news(localeID: UUID) -> NewsSection {
        NewsSection(title: SoapboxCopy.news, topic: .locale(localeID.uuidString.lowercased()), limit: 5)
    }
}

/// An article in a list: its photo, title, publication and when, with "Op-ed" on readers' pieces.
struct ArticleRow: View {
    let article: Article

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let photo = model.audienceKit.url(for: article.heroPhotoUrl ?? article.publication.photoUrl) {
                RemoteImage(url: photo)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if article.isOpEd {
                    Text(SoapboxCopy.opEd.uppercased())
                        .font(.hotMess(.caption2, semibold: true))
                        .foregroundStyle(.tint)
                }
                Text(article.title)
                    .font(.hotMess(.headline, semibold: true))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(ArticleRow.dateline(article))
                    .font(.hotMess(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "QSaltLake · Jun 1", or the byline alone before it's published.
    static func dateline(_ article: Article) -> String {
        let name = article.isOpEd ? article.byline : article.publication.name
        guard let date = article.publishedAt else { return name }
        return "\(name) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
