import Testing
import Foundation
@testable import VesselCore

@Suite("Watch messages")
struct WatchLinkTests {

    @Test("A message survives the trip through a WCSession dictionary")
    func roundTrip() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        for message in [WatchMessage.log(id: id, text: "two eggs and toast", at: date),
                        .water(id: id, millilitres: 500, at: date)] {
            #expect(WatchMessage(userInfo: try message.encoded()) == message)
            #expect(message.id == id)
        }
    }

    @Test("A summary round-trips and knows when it's stale")
    func summary() throws {
        let summary = WatchSummary(
            streakDays: 4, mealsLogged: 2, mealsRequired: 3, slotsLogged: ["breakfast", "lunch"],
            kilocalories: 1420, kilocalorieGoal: 2200, waterML: 1250, waterGoalML: 2500,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(WatchSummary(context: try summary.encoded()) == summary)
        #expect(!summary.isCurrent(dayStart: Date(timeIntervalSince1970: 1_800_050_000)))
    }

    @Test("Anything else in the dictionary is ignored")
    func junk() {
        #expect(WatchMessage(userInfo: ["other": 1]) == nil)
        #expect(WatchSummary(context: [WatchSummary.key: Data("nope".utf8)]) == nil)
    }
}
