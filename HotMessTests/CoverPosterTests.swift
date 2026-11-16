//
//  CoverPosterTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Cover posters")
struct CoverPosterTests {
    @Test("Opens a venue's lobby cover poster by its short code, and nothing else under /cover")
    func posterLink() {
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/cover/3XyZ0abC")) == .coverPoster("3XyZ0abC"))
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/cover/short")) != .coverPoster("short"))
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/cover/3XyZ0ab-")) != .coverPoster("3XyZ0ab-"))
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/cover/3XyZ0abC/x")) != .coverPoster("3XyZ0abC"))
    }
}
