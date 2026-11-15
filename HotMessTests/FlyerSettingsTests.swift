//
//  FlyerSettingsTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

@MainActor
@Suite("Digital flyers on this phone")
struct FlyerSettingsTests {
    private func settings() throws -> (FlyerSettings, UserDefaults) {
        let suite = "flyers-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = AppModel(configuration: AppConfiguration(baseURL: try #require(URL(string: "https://api.hotmess.social"))))
        return (FlyerSettings(audienceKit: model.audienceKit, defaults: defaults), defaults)
    }

    private func flyer(_ id: String, category: String) -> DigitalFlyer {
        DigitalFlyer(id: id, headline: "Flyer \(id)", tags: [], tone: "playful", category: category, lines: ["a", "b"])
    }

    private func content(_ flyers: [DigitalFlyer]) -> FlyersCardContent {
        FlyersCardContent(disclosure: "Based on your city and the time, nothing else.",
                          explainerLabel: "What's a digital flyer?",
                          explainerUrl: "https://audiencekit.com/digital-flyers/", flyers: flyers)
    }

    @Test("Hiding a flyer or a kind of flyer hides it, and only on this phone's defaults")
    func hiding() throws {
        let (settings, defaults) = try settings()
        let pantry = flyer("1", category: "food")
        let show = flyer("2", category: "community")
        let testing = flyer("3", category: "health")
        let card = content([pantry, show, testing])

        settings.dismiss(show)
        settings.setHidden(category: "health", true)
        #expect(settings.visible(card).map(\.id) == ["1"])
        #expect(defaults.stringArray(forKey: FlyerDismissals.flyersKey) == ["2"])
        #expect(defaults.stringArray(forKey: FlyerDismissals.categoriesKey) == ["health"])

        settings.reset()
        #expect(settings.visible(card).map(\.id) == ["1", "2", "3"])
    }

    @Test("A flyer's line is never the one shown last")
    func lines() throws {
        let (settings, _) = try settings()
        let card = flyer("1", category: "community")
        var last = settings.line(for: card)
        for _ in 0..<20 {
            let next = settings.line(for: card)
            #expect(next != last)
            last = next
        }
    }

    @Test("Resources say who they're for and when they're on")
    func resourceWords() {
        let slot = ResourceSlot(days: [4])
        #expect(ResourceTimes.describe(slot) == Calendar.current.weekdaySymbols[4])
        #expect(ResourceTimes.describe(ResourceSlot()) == String(localized: "Every day"))
    }
}
