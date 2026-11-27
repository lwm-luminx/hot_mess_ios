//
//  ReviewsSection.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// "Reviews" on a venue, event or person: what's been written about it, newest first. A line quoted from a news
/// article (City Weekly's guide to Salt Lake's LGBTQ bars) is credited to its publication, and tapping it opens the
/// article, on the publication's site for a teaser. Loads on its own and draws nothing while loading, when there are
/// none, or on an API without reviews.
struct ReviewsSection: View {
    let topic: ArticleTopic
    var limit = 3

    @Environment(AppModel.self) private var model
    @Environment(\.detailRefreshes) private var refreshes
    @State private var reviews: [Review] = []

    var body: some View {
        // A stack, not a Group, so the task runs while it's empty (see NewsSection).
        VStack(alignment: .leading, spacing: 0) {
            if !reviews.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reviews")
                        .font(.hotMess(.subheadline, semibold: true))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        ForEach(reviews.prefix(limit)) { review in
                            ReviewRow(review: review)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("reviews.section")
            }
        }
        .task(id: SectionLoadKey(subject: topic, refreshes: refreshes)) {
            reviews = (try? await model.audienceKit.reviews(of: topic)) ?? []
        }
    }
}

/// One review: its words, and for a quote, who it's from ("City Weekly · Read the article ↗"), opening the article.
struct ReviewRow: View {
    let review: Review

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var pending: (() -> Void)?

    var body: some View {
        if let article = review.article {
            Button {
                if model.hasAcknowledgedPublisherAds || article.showsWithoutAds { open(article) } else {
                    pending = { open(article) }
                }
            } label: {
                card(source: article)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the article"))
            .modifier(PublisherAdsNote(pending: $pending))
        } else {
            card(source: nil)
        }
    }

    private func card(source article: Article?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(review.body)
                .font(.hotMess(.body))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if let article {
                Text(ReviewRow.credit(article))
                    .font(.hotMess(.caption, semibold: true))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "City Weekly · Read the article ↗" (no arrow when it opens in the app).
    static func credit(_ article: Article) -> String {
        let readMore = String(localized: "Read the article")
        return "\(article.publication.name) · \(readMore)\(article.teaser ? " ↗" : "")"
    }

    private func open(_ article: Article) {
        if article.teaser, let url = article.canonicalUrl.flatMap(URL.init(string:)) {
            openURL(url)
        } else {
            model.push(.article(article.id))
        }
    }
}
