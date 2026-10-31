//
//  CardViews.swift
//  HotMess
//

import AudienceKit
import Kingfisher
import SafariServices
import SwiftUI

/// The audience's own announcement (a `web` card): a picture, words and a
/// link. Not promoted, and never hidden by Cards you see.
struct WebCardView: View {
    let content: CardContent

    var body: some View {
        CardBody(content: content, badge: nil)
            .padding(.horizontal, 16)
    }
}

/// A promo slot: the first candidate whose category the viewer hasn't turned
/// off, or nothing. Its badge and category name are the server's words. It
/// tells the fair rotation it was seen once it's been on screen a second.
struct PromoSlotView: View {
    let card: LayoutCard
    let layoutID: String?

    @Environment(AppModel.self) private var model
    @State private var explaining = false

    var body: some View {
        if let promo = card.promo(model.cards.filter) {
            let category = model.cards.category(promo.category)
            CardBody(content: promo.content, badge: promo.label, menu: AnyView(Group {
                if category?.hideable != false {
                    Button(String(localized: "Don't show me \(category?.label ?? promo.category)"),
                           systemImage: "eye.slash") {
                        model.cards.setHidden(promo.category, true)
                    }
                }
                Button(String(localized: "Why am I seeing this?"), systemImage: "questionmark.circle") {
                    explaining = true
                }
            }), route: route(promo))
            .padding(.horizontal, 16)
            .onAppear { Task { await model.cards.views.appeared(promo.id, layoutID: layoutID) } }
            .onDisappear { Task { await model.cards.views.disappeared(promo.id) } }
            .alert(String(localized: "Why am I seeing this?"), isPresented: $explaining) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text("\(promo.sponsorName) placed this \(category?.label ?? promo.category) card. Cards like it take turns fairly, picked for this screen and place, never for who you are. What you turn off in Me > Cards You See stays on your devices.")
            }
        }
    }

    /// A promoted venue or event opens its page.
    private func route(_ promo: PromoCard) -> AppRoute? {
        if let id = promo.venueID.flatMap(UUID.init(uuidString:)) { return .venue(id) }
        if let id = promo.eventID.flatMap(UUID.init(uuidString:)) { return .event(id) }
        return nil
    }
}

/// What web and promoted cards share: picture, badge, headline, body and a
/// button that opens the link in an in-app browser.
private struct CardBody: View {
    let content: CardContent
    let badge: String?
    var menu: AnyView?
    var route: AppRoute?

    @State private var browsing: BrowsedLink?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = Self.https(content.imageUrl) {
                KFImage(url)
                    .cancelOnDisappear(true)
                    .placeholder { Color.hotMessPhotoPlaceholder }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: CardMetrics.photoHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityLabel(Text(content.imageAlt ?? ""))
                    .accessibilityHidden(content.imageAlt == nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if let badge {
                        Text(badge)
                            .font(.hotMess(.caption, semibold: true))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let menu {
                        Menu {
                            menu
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.hotMess(.headline))
                                .frame(width: 32, height: 24)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text("Card options"))
                    }
                }

                Text(content.headline)
                    .font(.hotMess(.headline, semibold: true))

                if let body = content.body, !body.isEmpty {
                    Text(body)
                        .font(.hotMess(.subheadline))
                        .foregroundStyle(.secondary)
                }

                if let route {
                    NavigationLink(value: route) {
                        Text(content.linkLabel ?? String(localized: "Open"))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.hotMessAccent)
                    .padding(.top, 4)
                } else if let link = Self.https(content.linkUrl) {
                    Button(content.linkLabel ?? String(localized: "Learn more")) {
                        browsing = BrowsedLink(url: link)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.hotMessAccent)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .accessibilityElement(children: .contain)
        .sheet(item: $browsing) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }

    /// Only https links and pictures are used.
    private static func https(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

/// An in-app Safari view: no JavaScript bridge, nothing about the viewer added.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Me > Cards You See: turn categories of promoted cards off and on. The
/// choices stay on the viewer's devices and are never sent to Hot Mess.
struct CardsYouSeeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let categories = model.cards.categories {
                Section {
                    ForEach(categories.filter(\.hideable)) { category in
                        Toggle(isOn: Binding(
                            get: { !model.cards.hidden.contains(category.key) },
                            set: { model.cards.setHidden(category.key, !$0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.label)
                                if !category.description.isEmpty {
                                    Text(category.description)
                                        .font(.hotMess(.footnote))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(Color.hotMessAccent)
                    }
                } footer: {
                    Text("Promoted cards you turn off stay hidden on your devices. Your choices are never sent to Hot Mess, so they can't be shared or sold.")
                }

                let fixed = categories.filter { !$0.hideable }
                if !fixed.isEmpty {
                    Section {
                        ForEach(fixed) { category in
                            LabeledContent(category.label, value: String(localized: "Always shown"))
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Cards You See"))
        .task { await model.cards.loadCategories() }
    }
}

/// A link opened in an in-app Safari sheet.
struct BrowsedLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
