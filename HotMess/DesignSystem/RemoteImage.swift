//
//  RemoteImage.swift
//  HotMess
//

import Kingfisher
import SwiftUI

/// A cached remote image with a consistent placeholder.
///
/// Every image in the old app was a `UIImageView` plus a `kf.setImage` call
/// with a force-unwrapped URL; a missing banner took the screen down.
struct RemoteImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        Group {
            if let url {
                KFImage(url)
                    .cancelOnDisappear(true)
                    .fade(duration: 0.2)
                    .placeholder { placeholder }
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.tertiary)
            }
    }
}

/// A circular avatar that falls back to initials.
struct Avatar: View {
    let url: URL?
    var initials: String?
    var size: CGFloat = 44
    /// Whether the person can be reached now. `nil` (the default) draws no dot.
    var presence: PresenceState? = nil
    /// The ring between the presence dot and the photo: the surface behind the avatar.
    var presenceRing: Color = Color(.secondarySystemGroupedBackground)
    /// A place, not a person (a post as the venue): a `radius-md` rounded
    /// square, so places never look like people.
    var isPlace = false
    /// Initials on a spectrum band chosen from them, as chat draws people
    /// without a photo, instead of on grey.
    var tintsInitials = false

    var body: some View {
        Group {
            if let url {
                KFImage(url)
                    .cancelOnDisappear(true)
                    .placeholder { fallback }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(isPlace ? AnyShape(Self.placeShape) : AnyShape(Circle()))
        .overlay {
            if isPlace {
                Self.placeShape.strokeBorder(.separator, lineWidth: 0.5)
            } else {
                Circle().strokeBorder(.separator, lineWidth: 0.5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let presence {
                // The dot's 2pt ring sits 1pt outside the avatar's edge.
                PresenceDot(state: presence, size: Self.presenceSize(for: size), ringColor: presenceRing)
                    .offset(x: 1, y: 1)
            }
        }
    }

    /// 12 on 40 and up, 9 on a 24 TinyAvatar or smaller, 10 between.
    static func presenceSize(for size: CGFloat) -> CGFloat {
        if size >= 40 { return 12 }
        return size <= 24 ? 9 : 10
    }

    /// 10 on a 24 TinyAvatar, 9 on ChatPeek's 20; else in proportion.
    static func initialsSize(for size: CGFloat) -> CGFloat {
        if size <= 20 { return 9 }
        if size <= 24 { return 10 }
        return size * 0.38
    }

    /// Which spectrum band someone's initials sit on: the same one for the
    /// same initials on every launch (`hashValue` changes between launches).
    static func spectrumIndex(for initials: String, bands: Int = 6) -> Int {
        initials.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % bands
    }

    private static var placeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HotMessRadius.md, style: .continuous)
    }

    private var fallback: some View {
        ZStack {
            if let initials, !initials.isEmpty {
                if tintsInitials, !isPlace {
                    let band = Self.spectrumIndex(for: initials)
                    Rectangle().fill(Color.hotMessSpectrum[band])
                    Text(initials)
                        .font(.hotMess(fixedSize: Self.initialsSize(for: size), semibold: true))
                        .foregroundStyle(Color.hotMessOnSpectrum[band])
                } else {
                    Rectangle().fill(.quaternary)
                    Text(initials)
                        .font(.hotMess(fixedSize: Self.initialsSize(for: size), semibold: true))
                        .foregroundStyle(.secondary)
                }
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: isPlace ? "building.2.fill" : "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
