//
//  PublicationScreen.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// A Soapbox publication (QSaltLake, a candidate): what it covers, its live articles, and "Write an op-ed" when it
/// takes them. The reader's own op-eds to it show with where each stands.
struct PublicationScreen: View {
    let publicationID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var state: LoadState<Publication> = .idle
    @State private var articles: [Article] = []
    @State private var myOpEds: [Article] = []
    @State private var isWriting = false

    var body: some View {
        LoadStateView(state: state, retry: { Task { await load() } }) { publication in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(publication)
                    if publication.acceptsOpEds {
                        Button {
                            isWriting = true
                        } label: {
                            Label(SoapboxCopy.writeOpEd, systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("publication.writeOpEd")
                    }
                    if !myOpEds.isEmpty {
                        DetailSection(String(localized: "Your op-eds")) {
                            ForEach(myOpEds) { opEd in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opEd.title)
                                        .font(.hotMess(.body, semibold: true))
                                    if let status = opEd.status {
                                        Text(SoapboxCopy.status(status))
                                            .font(.hotMess(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                    if opEd.status == .declined, let note = opEd.reviewNote, !note.isEmpty {
                                        Text(note)
                                            .font(.hotMess(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if articles.isEmpty {
                        Text("Nothing published yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(articles) { article in
                                NavigationLink(value: AppRoute.article(article.id)) {
                                    ArticleRow(article: article)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $isWriting) {
                OpEdComposer(publication: publication) { _ in
                    Task { await loadMyOpEds() }
                }
            }
        }
        .navigationTitle(state.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ publication: Publication) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let photo = model.audienceKit.url(for: publication.photoUrl) {
                RemoteImage(url: photo)
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(publication.name)
                    .font(.hotMess(.title3, semibold: true))
                    .accessibilityAddTraits(.isHeader)
                if let about = publication.about, !about.isEmpty {
                    Text(about)
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                }
                if let website = publication.websiteUrl.flatMap(URL.init(string:)) {
                    Button(website.host() ?? website.absoluteString) { openURL(website) }
                        .font(.hotMess(.subheadline))
                }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            guard let publication = try await model.audienceKit.publication(id: publicationID) else {
                state = LoadState(catching: APIError.notFound)
                return
            }
            state = .loaded(publication)
            articles = (try? await model.audienceKit.articles(publicationID: publicationID)) ?? []
            await loadMyOpEds()
        } catch is CancellationError {
        } catch let error as AudienceKitError {
            state = LoadState(catching: APIError(error))
        } catch {
            state = LoadState(catching: error)
        }
    }

    private func loadMyOpEds() async {
        let mine = (try? await model.audienceKit.myOpEds()) ?? []
        myOpEds = mine.filter { $0.publication.id == publicationID }
    }
}
