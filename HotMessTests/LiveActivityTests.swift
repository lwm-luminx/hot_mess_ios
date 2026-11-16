//
//  LiveActivityTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@MainActor
struct LiveActivityTests {
    private func state(_ status: PairUpStatus) -> PairUpState {
        PairUpState(status: status, lookFor: "red jacket by the bar", metCount: 0, match: nil, bonus: nil)
    }

    @Test
    func quickieStaysWhileSearchingOrPaired() {
        for status in [PairUpStatus.searching, .proposed, .waiting, .revealed] {
            #expect(LiveActivities.lines(for: state(status)) != nil)
        }
    }

    @Test
    func quickieEndsOnceMetOrLeft() {
        #expect(LiveActivities.lines(for: state(.met)) == nil)
        #expect(LiveActivities.lines(for: state(.left)) == nil)
    }

    @Test
    func quickieNeverShowsTheHintOnTheLockScreen() {
        for status in [PairUpStatus.searching, .proposed, .waiting, .revealed] {
            let line = LiveActivities.lines(for: state(status))
            #expect(line?.status.contains("red jacket") == false)
        }
    }
}
