//
//  HeroHeader.swift
//  HotMess
//

import Kingfisher
import SwiftUI

enum HeroMetrics {
    /// The photo's height below the status and navigation bars.
    static let bodyHeight: CGFloat = 256
    /// A venue, event or person page's taller hero, which carries its
    /// details and actions: 440pt with the navigation bar.
    static let detailHeight: CGFloat = 396
    /// Now's hero at a venue with nothing on, which carries what's next, the
    /// cover, the address and who's here.
    static let venueNowHeight: CGFloat = 336
}

private let heroCoordinateSpace = "hero"

/// A banner that runs edge to edge and up under the status bar, with its
/// title drawn over it in whichever colour the photo can carry.
///
/// Put it first in a `ScrollView` that ignores the top safe area, and pass that
/// safe area's height as `topInset`. The photo stretches when pulled down.
/// `tone` reports what was decided so the screen can style its bars to match.
/// Given several photos it fades from one to the next every few seconds,
/// re-reading each for the text (it holds on the first with Reduce Motion).
struct HeroHeader<Content: View>: View {
    let urls: [URL]
    let topInset: CGFloat
    @Binding var tone: HeroTone
    /// The contrast the text keeps against the photo: 4.5:1, or 7:1 with
    /// Increase Contrast on, unless this asks for more.
    var minimumContrast: Double = 4.5
    /// The least scrim behind the text, for heroes whose photos change under it.
    var minimumScrim: Double = 0
    /// The photo's height below the bars; pass the same to `trackingHeroCollapse`.
    var bodyHeight: CGFloat = HeroMetrics.bodyHeight
    @ViewBuilder var content: Content

    init(
        url: URL?,
        topInset: CGFloat,
        tone: Binding<HeroTone>,
        bodyHeight: CGFloat = HeroMetrics.bodyHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.init(urls: [url].compactMap { $0 }, topInset: topInset, tone: tone, bodyHeight: bodyHeight, content: content)
    }

    init(
        urls: [URL],
        topInset: CGFloat,
        tone: Binding<HeroTone>,
        minimumContrast: Double = 4.5,
        minimumScrim: Double = 0,
        bodyHeight: CGFloat = HeroMetrics.bodyHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.urls = urls
        self.topInset = topInset
        _tone = tone
        self.minimumContrast = minimumContrast
        self.minimumScrim = minimumScrim
        self.bodyHeight = bodyHeight
        self.content = content()
    }

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var image: UIImage?
    @State private var size: CGSize = .zero
    @State private var textFrame: CGRect = .zero

    /// How long each photo shows before the next fades in.
    static var interval: Duration { .seconds(5) }

    private var url: URL? { urls.isEmpty ? nil : urls[index % urls.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: topInset + 16)

            content
                .foregroundStyle(tone.textColor)
                .photoTextShadow(tone)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(heroCoordinateSpace)) } action: { textFrame = $0 }
                .padding(.horizontal, 20)
                .padding(.bottom, urls.count > 1 ? 28 : 20)
                .animation(HotMessMotion.quick, value: tone)
        }
        .frame(maxWidth: .infinity, minHeight: topInset + bodyHeight, alignment: .bottomLeading)
        .coordinateSpace(.named(heroCoordinateSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .background {
            GeometryReader { proxy in
                let pull = max(0, proxy.frame(in: .scrollView).minY)
                photo
                    .frame(width: proxy.size.width, height: proxy.size.height + pull)
                    .clipped()
                    .overlay { scrims }
                    .offset(y: -pull)
            }
        }
        .overlay(alignment: .bottom) {
            if urls.count > 1 {
                pageDots
            }
        }
        .task(id: url) { await loadImage() }
        .task(id: RotationKey(urls: urls, paused: reduceMotion)) { await rotate() }
        .onChange(of: analysisKey, initial: true) { analyze() }
    }

    private struct RotationKey: Equatable {
        var urls: [URL]
        var paused: Bool
    }

    /// Steps to the next photo every `interval`, once it has loaded, so the
    /// fade never lands on the placeholder.
    private func rotate() async {
        index = 0
        guard urls.count > 1, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.interval)
            guard !Task.isCancelled else { return }
            let next = (index + 1) % urls.count
            _ = try? await KingfisherManager.shared.retrieveImage(with: urls[next])
            guard !Task.isCancelled else { return }
            withAnimation(HotMessMotion.heroFade) { index = next }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(urls.indices, id: \.self) { position in
                Circle()
                    .fill(tone.textColor.opacity(position == index % urls.count ? 0.95 : 0.4))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, 10)
        .animation(HotMessMotion.quick, value: index)
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    @ViewBuilder
    private var photo: some View {
        if let url {
            // No fade on load: the scrim and text are drawn at once, so a fading
            // photo read as only the part behind the text having loaded. Moving
            // between photos cross-fades instead.
            KFImage(url)
                .cancelOnDisappear(true)
                .placeholder { Color.hotMessPhotoPlaceholder }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .id(url)
                .transition(.opacity)
        } else {
            // The light accent always carries white text (on-accent).
            LinearGradient(
                colors: [Color.hotMessAccent, Color.hotMessAccent.mix(with: .black, by: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .environment(\.colorScheme, .light)
        }
    }

    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [tone.barScrimColor.opacity(tone.barScrim), tone.barScrimColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topInset + 40)

            Spacer(minLength: 0)

            LinearGradient(
                stops: [
                    .init(color: tone.scrimColor.opacity(tone.scrim), location: 0),
                    .init(color: tone.scrimColor.opacity(tone.scrim), location: bandFraction),
                    .init(color: tone.scrimColor.opacity(0), location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: bandHeight + 90)
        }
        .allowsHitTesting(false)
        .animation(HotMessMotion.quick, value: tone)
    }

    // MARK: - Analysis

    private var bandHeight: CGFloat { max(0, size.height - textFrame.minY + 8) }
    private var bandFraction: CGFloat { bandHeight / max(1, bandHeight + 90) }

    private var increasedContrast: Bool { colorSchemeContrast == .increased }
    private var target: Double { max(minimumContrast, increasedContrast ? 7 : 4.5) }
    private var scrimFloor: Double {
        max(minimumScrim, increasedContrast || reduceTransparency ? ImageTone.accessibleScrimFloor : 0)
    }

    private var cacheKey: String? {
        url.map { "\($0.absoluteString)|\(target)|\(scrimFloor)" }
    }

    private struct AnalysisKey: Equatable {
        var hasImage: Bool
        var size: CGSize
        var textFrame: CGRect
        var target: Double
        var scrimFloor: Double
    }

    private var analysisKey: AnalysisKey {
        AnalysisKey(hasImage: image != nil, size: size, textFrame: textFrame, target: target, scrimFloor: scrimFloor)
    }

    private func loadImage() async {
        let url = url
        image = nil
        guard let url else { return }
        if let key = cacheKey, let cached = HeroToneCache.tone(for: key) {
            tone = cached
        }
        image = try? await KingfisherManager.shared.retrieveImage(with: url).image
    }

    private func analyze() {
        guard url != nil else {
            tone = .placeholder
            return
        }
        guard
            let cgImage = image?.cgImage,
            size.width > 0, size.height > 0, textFrame.height > 0
        else { return }

        let top = CGRect(x: 0, y: 0, width: size.width, height: topInset)
        let band = CGRect(x: 16, y: textFrame.minY - 8, width: size.width - 32, height: bandHeight)

        guard let decided = ImageTone.analyze(
            cgImage,
            viewSize: size,
            top: top,
            band: band,
            target: target,
            scrimFloor: scrimFloor
        ) else { return }

        tone = decided
        if let key = cacheKey { HeroToneCache.store(decided, for: key) }
    }
}

extension View {
    /// Styles the navigation bar for a screen that opens on a `HeroHeader`: clear
    /// with the status bar matching the photo, then a material bar with `title`
    /// once the hero has scrolled away.
    func heroNavigationBar(title: String, tone: HeroTone, collapsed: Bool) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.hotMess(.headline, semibold: true))
                        .lineLimit(1)
                        .opacity(collapsed ? 1 : 0)
                        .accessibilityHidden(!collapsed)
                }
            }
            // A visible but clear background is what lets the colour scheme reach
            // the status bar while the photo shows through.
            .toolbarBackground(collapsed ? AnyShapeStyle(Material.bar) : AnyShapeStyle(Color.clear), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(collapsed ? nil : tone.bar, for: .navigationBar)
            .modifier(HeroScrollEdge(hidden: !collapsed))
            .animation(HotMessMotion.quick, value: collapsed)
    }

    /// Tracks whether a hero at the top of this scroll view has scrolled under the bars.
    func trackingHeroCollapse(_ collapsed: Binding<Bool>, bodyHeight: CGFloat = HeroMetrics.bodyHeight) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > bodyHeight - 8
        } action: { _, isCollapsed in
            collapsed.wrappedValue = isCollapsed
        }
    }
}

/// iOS 26 blurs and fades scroll content under the navigation bar, which cut a
/// sharp line across the hero photo where the effect ended. The photo is the
/// bar's background while the hero shows, so the effect is off until it scrolls away.
private struct HeroScrollEdge: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectHidden(hidden, for: .top)
        } else {
            content
        }
    }
}
