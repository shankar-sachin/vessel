import Testing
import Foundation
@testable import VesselActivities

/// The Live Activity's own rendering can only really be judged on a device, so
/// what's tested here is everything underneath it: the arithmetic that decides
/// what the island claims, and the wording it claims it in. Those are the parts
/// that can be wrong in a way nobody notices until a streak is lost.

@Suite("Activity state arithmetic")
struct ActivityStateTests {

    private let attributes = StreakActivityAttributes(
        deadline: Date(timeIntervalSince1970: 1_800_000_000),
        required: 3,
        planName: "Three meals a day"
    )

    @Test("Remaining counts down and floors at zero")
    func remainingFloorsAtZero() {
        #expect(attributes.remaining(for: .init(logged: 0, streakCount: 5)) == 3)
        #expect(attributes.remaining(for: .init(logged: 2, streakCount: 5)) == 1)
        #expect(attributes.remaining(for: .init(logged: 3, streakCount: 5)) == 0)
        // Logging a fourth meal must not produce "-1 meals left".
        #expect(attributes.remaining(for: .init(logged: 4, streakCount: 5)) == 0)
    }

    @Test("Completion is met-or-exceeded, not exactly-equal")
    func completionIsInclusive() {
        #expect(!attributes.isComplete(.init(logged: 2, streakCount: 1)))
        #expect(attributes.isComplete(.init(logged: 3, streakCount: 1)))
        #expect(attributes.isComplete(.init(logged: 4, streakCount: 1)))
    }

    @Test("State survives a Codable round trip")
    func stateRoundTrips() throws {
        // ActivityKit encodes ContentState to cross into the widget process, so
        // a field that doesn't round-trip silently shows stale data.
        let original = StreakActivityAttributes.ContentState(
            logged: 2, streakCount: 12, nextSlotName: "Dinner"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StreakActivityAttributes.ContentState.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("Activity copy")
struct ActivityCopyTests {

    @Test("Headline reflects whether the day is done")
    func headlineReflectsCompletion() {
        #expect(StreakActivityCopy.headline(logged: 3, required: 3, streak: 7) == "7-day streak safe")
        #expect(StreakActivityCopy.headline(logged: 1, required: 3, streak: 7) == "7-day streak at risk")
    }

    @Test("A first-day user is never told they have a 0-day streak")
    func zeroStreakWording() {
        // "0-day streak at risk" is both meaningless and discouraging on day one.
        let atRisk = StreakActivityCopy.headline(logged: 0, required: 3, streak: 0)
        let done = StreakActivityCopy.headline(logged: 3, required: 3, streak: 0)
        #expect(!atRisk.contains("0"))
        #expect(!done.contains("0"))
        #expect(atRisk == "Keep today going")
        #expect(done == "Today is logged")
    }

    @Test("Detail names the next meal when we know it")
    func detailNamesNextMeal() {
        #expect(StreakActivityCopy.detail(logged: 2, required: 3, nextSlot: "Dinner") == "Log Dinner to finish")
        #expect(StreakActivityCopy.detail(logged: 1, required: 3, nextSlot: "Lunch")
                == "2 meals left, starting with Lunch")
    }

    @Test("Detail falls back cleanly with no slot")
    func detailWithoutSlot() {
        #expect(StreakActivityCopy.detail(logged: 2, required: 3, nextSlot: nil) == "1 meal left today")
        #expect(StreakActivityCopy.detail(logged: 0, required: 3, nextSlot: nil) == "3 meals left today")
    }

    @Test("Singular and plural are correct at every count")
    func pluralisation() {
        // Off-by-one plurals are the classic way polished copy stops looking polished.
        #expect(StreakActivityCopy.detail(logged: 2, required: 3, nextSlot: nil).contains("1 meal left"))
        #expect(StreakActivityCopy.detail(logged: 1, required: 3, nextSlot: nil).contains("2 meals left"))
        #expect(StreakActivityCopy.detail(logged: 3, required: 3, nextSlot: nil) == "Nothing left to log today.")
    }

    @Test("Compact progress fits the island's tiny trailing slot")
    func compactProgressIsShort() {
        let text = StreakActivityCopy.compactProgress(logged: 2, required: 3)
        #expect(text == "2/3")
        // The compact trailing region gives us roughly five characters.
        #expect(text.count <= 5)
    }
}
