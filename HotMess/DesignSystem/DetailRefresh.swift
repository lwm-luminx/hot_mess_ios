//
//  DetailRefresh.swift
//  HotMess
//

import SwiftUI

extension EnvironmentValues {
    /// How many times the detail page (person, venue, event) was pulled to refresh. Sections that load on their own
    /// (news, posts, photos) key their load on it, so a pull reloads them with the page.
    @Entry var detailRefreshes = 0
}

/// What a self-loading section keys its `.task(id:)` on: what it shows, and the page's pull-to-refresh count.
struct SectionLoadKey<Subject: Hashable>: Hashable {
    let subject: Subject
    let refreshes: Int
}
