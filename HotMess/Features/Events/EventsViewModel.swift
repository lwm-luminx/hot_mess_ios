//
//  EventsViewModel.swift
//  HotMess
//

import Foundation
import Observation

@MainActor
@Observable
final class EventsViewModel {
    private(set) var state: LoadState<EventListing> = .idle

    private let api: HotMessAPI

    init(api: HotMessAPI) {
        self.api = api
    }

    func load(localeID: UUID?) async {
        guard let localeID else {
            // No locale yet: Core Location hasn't produced a fix, or the user
            // declined. The old controller silently returned and left a
            // permanently empty table.
            state = .failed(
                message: String(localized: "We need your location to find events near you."),
                isRetryable: false
            )
            return
        }

        if state.value == nil {
            // What was loaded last time (or by the background refresh) shows
            // at once; the API's answer replaces it.
            if let cached = await api.cachedEvents(in: localeID) {
                state = .loaded(cached)
            } else {
                state = .loading
            }
        }

        do {
            state = .loaded(try await api.events(in: localeID))
        } catch is CancellationError {
        } catch {
            state = LoadState(catching: error)
        }
    }
}
