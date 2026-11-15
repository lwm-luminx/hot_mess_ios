//
//  FlyersCardView.swift
//  HotMess
//

import AudienceKit
import SwiftUI

/// Now's digital flyers: cards about what's on in the city (a pantry, free
/// testing, a show), chosen by the server from the city and the time and
/// nothing else. Each one says so and links to the explainer. Hiding a flyer
/// or a kind of flyer stays on this phone.
struct FlyersCardView: View {
    let content: FlyersCardContent

    @Environment(AppModel.self) private var model
    @State private var findingHelp: ResourcesRequest?

    var body: some View {
        let flyers = model.flyers.visible(content)
        CardSection(String(localized: "Around town")) {
            ForEach(flyers) { flyer in
                FlyerView(flyer: flyer, content: content) { resourceID in
                    findingHelp = ResourcesRequest(resourceID: resourceID)
                }
            }
            if !flyers.isEmpty {
                Button {
                    findingHelp = ResourcesRequest(resourceID: nil)
                } label: {
                    Label(String(localized: "Find food, health and support nearby"), systemImage: "hand.raised")
                        .font(.hotMess(.subheadline))
                }
                .tint(Color.hotMessAccent)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("flyers.findHelp")
            }
        }
        .task {
            await model.flyers.loadCopy()
            model.flyers.prefetchDirectory(localeID: model.location.locale?.id)
        }
        .onChange(of: model.location.locale?.id) { _, id in model.flyers.prefetchDirectory(localeID: id) }
        .fullScreenCover(item: $findingHelp) { request in
            ResourcesSheet(focusResourceID: request.resourceID)
        }
    }
}

/// What opens the resources sheet: a flyer's resource, or the whole list.
struct ResourcesRequest: Identifiable {
    let resourceID: String?
    var id: String { resourceID ?? "all" }
}

/// One flyer: its category, a line in its tone, the headline and body, what
/// it points at, and the disclosure.
private struct FlyerView: View {
    let flyer: DigitalFlyer
    let content: FlyersCardContent
    let openResource: (String?) -> Void

    @Environment(AppModel.self) private var model
    @State private var line: String?
    @State private var browsing: BrowsedLink?

    var body: some View {
        let category = model.flyers.categoryLabel(flyer.category)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(category)
                    .font(.hotMess(.caption, semibold: true))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Menu {
                    Button(String(localized: "Hide this flyer"), systemImage: "eye.slash") {
                        model.flyers.dismiss(flyer)
                    }
                    Button(String(localized: "Hide all \(category) flyers"), systemImage: "rectangle.stack.badge.minus") {
                        model.flyers.setHidden(category: flyer.category, true)
                    }
                    if let url = flyerHTTPS(content.explainerUrl) {
                        Button(content.explainerLabel, systemImage: "questionmark.circle") {
                            browsing = BrowsedLink(url: url)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.hotMess(.headline))
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Flyer options"))
            }

            if let line {
                Text(line)
                    .font(.hotMess(.subheadline, semibold: true))
                    .foregroundStyle(Color.hotMessAccent)
            }

            Text(flyer.headline)
                .font(.hotMess(.headline, semibold: true))

            if let body = flyer.body, !body.isEmpty {
                Text(body)
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            }

            if let resource = flyer.resource {
                Button(flyer.linkLabel ?? String(localized: "Details")) { openResource(resource.id) }
                    .buttonStyle(.bordered)
                    .tint(Color.hotMessAccent)
                    .padding(.top, 4)
            } else if let link = flyerHTTPS(flyer.linkUrl) {
                Button(flyer.linkLabel ?? String(localized: "Learn more")) { browsing = BrowsedLink(url: link) }
                    .buttonStyle(.bordered)
                    .tint(Color.hotMessAccent)
                    .padding(.top, 4)
            }

            FlyerDisclosure(content: content) { browsing = BrowsedLink(url: $0) }
                .padding(.top, 6)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .task(id: flyer.id) { line = model.flyers.line(for: flyer) }
        .sheet(item: $browsing) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }
}

/// "Based on your city and the time, nothing else." and the explainer link,
/// in the server's words (they're swappable there pending legal review).
struct FlyerDisclosure: View {
    let content: FlyersCardContent
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.disclosure)
                .font(.hotMess(.caption))
                .foregroundStyle(.secondary)
            if let url = flyerHTTPS(content.explainerUrl) {
                Button(content.explainerLabel) { open(url) }
                    .font(.hotMess(.caption, semibold: true))
                    .tint(Color.hotMessAccent)
                    .accessibilityIdentifier("flyers.explainer")
            }
        }
    }
}

/// Only https links are opened.
func flyerHTTPS(_ string: String?) -> URL? {
    guard let string, let url = URL(string: string), url.scheme?.lowercased() == "https" else { return nil }
    return url
}
