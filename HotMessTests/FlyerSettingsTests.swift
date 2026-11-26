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

    private func directory() throws -> CommunityDirectory {
        let json = """
        {"locale":{"id":"l1","name":"Salt Lake"},"facets":[],"advocacy":[],"quick_exit":"Leave now",
         "needs":[{"key":"food","label":"Food","facets":["food"]},
                  {"key":"shelter","label":"Shelter","facets":["shelter"]},
                  {"key":"safe","label":"Safety at home","facets":["dv-stalking"]}],
         "resources":[
          {"id":"1","title":"Calvary pantry","name":"Calvary pantry","sensitive":false,
           "description":"Thursday groceries.","facets":["food","no-id-required"],"address":"460 W Century Dr",
           "phone":"8012649999","hours":[],"sessions":[]},
          {"id":"2","title":"Crisis Care Center","name":"Crisis Care Center","sensitive":false,
           "facets":["crisis","mental-health"],"phone":"988","hours":[],"sessions":[]},
          {"id":"3","title":"Support line","name":"YWCA Utah","sensitive":true,
           "facets":["dv-stalking","crisis"],"phone":"+18015378600","hours":[],"sessions":[]}]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CommunityDirectory.self, from: Data(json.utf8))
    }

    @Test("The browser offers only needs with something listed, and puts crisis lines first")
    func browserOrder() throws {
        let directory = try directory()
        #expect(ResourceBrowser.offeredNeeds(directory).map(\.key) == ["food", "safe"])
        let all = ResourceBrowser.results(in: directory, need: nil, search: "")
        #expect(all.urgent.map(\.id) == ["2", "3"])
        #expect(all.rest.map(\.id) == ["1"])
        let food = ResourceBrowser.results(in: directory, need: directory.needs[0], search: "")
        #expect(food.urgent.isEmpty)
        #expect(food.rest.map(\.id) == ["1"])
    }

    @Test("Search runs over names, descriptions, kinds, badges and addresses, every word")
    func browserSearch() throws {
        let directory = try directory()
        func found(_ search: String) -> [String] {
            let results = ResourceBrowser.results(in: directory, need: nil, search: search)
            return (results.urgent + results.rest).map(\.id)
        }
        #expect(found("  thursday FOOD ") == ["1"])
        #expect(found("century") == ["1"])
        #expect(found("ywca") == ["3"])
        #expect(found("food shelter").isEmpty)
        #expect(ResourceBrowser.results(in: directory, need: nil, search: "zzzz").isEmpty)
    }

    @Test("A DV resource stays neutral in the list, and numbers read and dial properly")
    func browserWords() throws {
        let directory = try directory()
        #expect(ResourceBrowser.kinds(directory.resources[1]) == [String(localized: "Crisis support"),
                                                                  String(localized: "Mental health")])
        #expect(ResourceBrowser.kinds(directory.resources[2]).isEmpty)
        #expect(ResourceBrowser.symbol(for: directory.resources[2]) == ResourceBrowser.symbol(for: directory.resources[1]))
        #expect(ResourceBrowser.phoneText("8012649999") == "(801) 264-9999")
        #expect(ResourceBrowser.phoneText("+18015378600") == "(801) 537-8600")
        #expect(ResourceBrowser.phoneText("988") == "988")
        #expect(ResourceBrowser.phoneText("+442079460000") == "+442079460000")
        #expect(ResourceBrowser.callURL("+18015378600")?.absoluteString == "tel:+18015378600")
        #expect(ResourceBrowser.callURL("988", scheme: "sms")?.absoluteString == "sms:988")
    }

    @Test("Days in a row read as a range")
    func dayRuns() {
        let names = Calendar.current.weekdaySymbols
        #expect(ResourceTimes.dayText([1, 2, 3, 4, 5]) == "\(names[1])–\(names[5])")
        #expect(ResourceTimes.dayText([2, 4]) == "\(names[2]), \(names[4])")
        #expect(ResourceTimes.dayText([0, 1, 2, 3, 4, 5, 6]) == String(localized: "Every day"))
    }
}
