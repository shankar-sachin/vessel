import Testing
import Foundation
@testable import VesselCore

private struct TestMeal: MealLoggable {
    let loggedAt: Date
    let slot: MealSlot
}

/// A fixed calendar in a fixed zone — streak maths must never depend on where
/// the test machine happens to be.
private func fixedCalendar(timeZone: String = "America/New_York") -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: timeZone)!
    cal.locale = Locale(identifier: "en_US_POSIX")
    return cal
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("Streak day boundaries")
struct DayBoundaryTests {

    @Test("A midnight rollover puts a day's meals in that calendar day")
    func midnightRollover() {
        let cal = fixedCalendar()
        let engine = StreakEngine(dayRolloverHour: 0, calendar: cal)
        let noon = date(2026, 3, 10, 12, calendar: cal)

        #expect(engine.dayStart(for: noon) == date(2026, 3, 10, 0, calendar: cal))
        #expect(engine.dayEnd(for: noon) == date(2026, 3, 11, 0, calendar: cal))
    }

    @Test("Before the rollover hour, a late-night meal belongs to the previous day")
    func lateNightBelongsToPreviousDay() {
        let cal = fixedCalendar()
        // 4am rollover: someone who eats at 1am is still finishing yesterday.
        let engine = StreakEngine(dayRolloverHour: 4, calendar: cal)
        let oneAM = date(2026, 3, 11, 1, calendar: cal)

        #expect(engine.dayStart(for: oneAM) == date(2026, 3, 10, 4, calendar: cal))
    }

    @Test("Day length survives the spring-forward DST transition")
    func springForwardDST() {
        let cal = fixedCalendar()
        let engine = StreakEngine(dayRolloverHour: 0, calendar: cal)
        // US DST begins 2026-03-08. That day is only 23 hours long.
        let duringDSTDay = date(2026, 3, 8, 12, calendar: cal)

        let start = engine.dayStart(for: duringDSTDay)
        let end = engine.dayEnd(for: duringDSTDay)

        #expect(start == date(2026, 3, 8, 0, calendar: cal))
        // The real elapsed time is 23 hours, but the boundary must still land on
        // the next calendar midnight rather than 1am.
        #expect(end == date(2026, 3, 9, 0, calendar: cal))
        #expect(end.timeIntervalSince(start) == 23 * 3600)
    }
}

@Suite("Meal counting")
struct MealCountingTests {

    @Test("Three distinct slots satisfy the standard plan")
    func threeDistinctSlotsQualify() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let day = date(2026, 5, 4, 12, calendar: cal)
        let meals = [
            TestMeal(loggedAt: date(2026, 5, 4, 8, calendar: cal), slot: .breakfast),
            TestMeal(loggedAt: date(2026, 5, 4, 13, calendar: cal), slot: .lunch),
            TestMeal(loggedAt: date(2026, 5, 4, 19, calendar: cal), slot: .dinner)
        ]

        let progress = engine.progress(for: day, meals: meals, plan: .standard)
        #expect(progress.logged == 3)
        #expect(progress.isQualified)
        #expect(progress.remaining == 0)
    }

    @Test("Logging the same slot repeatedly does not satisfy the requirement")
    func repeatedSlotDoesNotCountTwice() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let day = date(2026, 5, 4, 12, calendar: cal)
        // Three separate lunches is one meal, not three.
        let meals = (0..<3).map {
            TestMeal(loggedAt: date(2026, 5, 4, 12 + $0, calendar: cal), slot: .lunch)
        }

        let progress = engine.progress(for: day, meals: meals, plan: .standard)
        #expect(progress.logged == 1)
        #expect(!progress.isQualified)
        #expect(progress.remaining == 2)
    }

    @Test("Snacks are excluded unless the plan counts them")
    func snacksExcludedByDefault() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let day = date(2026, 5, 4, 12, calendar: cal)
        let meals = [
            TestMeal(loggedAt: date(2026, 5, 4, 9, calendar: cal), slot: .breakfast),
            TestMeal(loggedAt: date(2026, 5, 4, 15, calendar: cal), slot: .snack)
        ]

        #expect(engine.progress(for: day, meals: meals, plan: .standard).logged == 1)

        var snackFriendly = FastingPlan.standard
        snackFriendly.countsSnacks = true
        #expect(engine.progress(for: day, meals: meals, plan: snackFriendly).logged == 2)
    }

    @Test("Meals from other days are ignored")
    func otherDaysIgnored() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let meals = [
            TestMeal(loggedAt: date(2026, 5, 3, 19, calendar: cal), slot: .dinner),
            TestMeal(loggedAt: date(2026, 5, 4, 8, calendar: cal), slot: .breakfast),
            TestMeal(loggedAt: date(2026, 5, 5, 8, calendar: cal), slot: .lunch)
        ]

        let progress = engine.progress(for: date(2026, 5, 4, 12, calendar: cal), meals: meals, plan: .standard)
        #expect(progress.slotsLogged == [.breakfast])
    }

    @Test("OMAD qualifies on a single meal")
    func omadQualifiesOnOne() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let meals = [TestMeal(loggedAt: date(2026, 5, 4, 18, calendar: cal), slot: .dinner)]

        #expect(engine.progress(for: date(2026, 5, 4, 20, calendar: cal), meals: meals, plan: .omad).isQualified)
    }
}

@Suite("Eating windows")
struct EatingWindowTests {

    @Test("Meals inside and outside a 16:8 window are distinguished")
    func sixteenEightWindow() {
        let cal = fixedCalendar()
        let plan = FastingPlan.sixteenEight  // 12:00–20:00

        #expect(plan.isWithinEatingWindow(date(2026, 5, 4, 13, calendar: cal), calendar: cal))
        #expect(plan.isWithinEatingWindow(date(2026, 5, 4, 19, 59, calendar: cal), calendar: cal))
        #expect(!plan.isWithinEatingWindow(date(2026, 5, 4, 9, calendar: cal), calendar: cal))
        #expect(!plan.isWithinEatingWindow(date(2026, 5, 4, 21, calendar: cal), calendar: cal))
    }

    @Test("A window that wraps past midnight is handled")
    func wrappingWindow() {
        let cal = fixedCalendar()
        // 20:00 for six hours, ending 02:00 — a night-shift pattern.
        let plan = FastingPlan(
            style: .timeRestricted, mealsRequired: 2,
            eatingWindowHours: 6, eatingWindowStartMinute: 20 * 60
        )

        #expect(plan.isWithinEatingWindow(date(2026, 5, 4, 21, calendar: cal), calendar: cal))
        #expect(plan.isWithinEatingWindow(date(2026, 5, 4, 1, calendar: cal), calendar: cal))
        #expect(!plan.isWithinEatingWindow(date(2026, 5, 4, 3, calendar: cal), calendar: cal))
        #expect(!plan.isWithinEatingWindow(date(2026, 5, 4, 19, calendar: cal), calendar: cal))
    }

    @Test("Plans with no window accept any time")
    func noWindowAcceptsAnything() {
        let cal = fixedCalendar()
        #expect(FastingPlan.standard.isWithinEatingWindow(date(2026, 5, 4, 3, calendar: cal), calendar: cal))
    }

    @Test("Out-of-window meals still count toward the streak, but are reported")
    func outOfWindowStillCounts() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let meals = [
            TestMeal(loggedAt: date(2026, 5, 4, 9, calendar: cal), slot: .breakfast),   // outside
            TestMeal(loggedAt: date(2026, 5, 4, 13, calendar: cal), slot: .lunch)       // inside
        ]

        let progress = engine.progress(for: date(2026, 5, 4, 14, calendar: cal), meals: meals, plan: .sixteenEight)
        // The streak rewards logging honestly; it does not punish you for what
        // you logged, or people start hiding meals from their own diary.
        #expect(progress.isQualified)
        #expect(progress.outsideWindowCount == 1)
    }
}

@Suite("Streak counting")
struct StreakCountingTests {

    @Test("Consecutive qualified days accumulate")
    func consecutiveDaysAccumulate() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let days = Set((1...5).map { date(2026, 5, $0, 0, calendar: cal) })

        let state = engine.streak(qualifiedDays: days, now: date(2026, 5, 5, 21, calendar: cal))
        #expect(state.current == 5)
        #expect(state.longest == 5)
    }

    @Test("A gap resets the current streak but preserves the longest")
    func gapResetsCurrent() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        // Five days, a miss on the 6th, then two more.
        let days = Set(
            (1...5).map { date(2026, 5, $0, 0, calendar: cal) } +
            [date(2026, 5, 7, 0, calendar: cal), date(2026, 5, 8, 0, calendar: cal)]
        )

        let state = engine.streak(qualifiedDays: days, now: date(2026, 5, 8, 21, calendar: cal))
        #expect(state.current == 2)
        #expect(state.longest == 5)
    }

    @Test("Today being unlogged does not break the streak while the day is still running")
    func todayUnloggedDoesNotBreakStreak() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        // Logged through the 4th; it's now midday on the 5th with nothing logged.
        let days = Set((1...4).map { date(2026, 5, $0, 0, calendar: cal) })

        let state = engine.streak(qualifiedDays: days, now: date(2026, 5, 5, 12, calendar: cal))
        // You still have until the reset, so the streak stands at 4.
        #expect(state.current == 4)
    }

    @Test("Missing an entire day breaks the streak")
    func missedDayBreaksStreak() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let days = Set((1...4).map { date(2026, 5, $0, 0, calendar: cal) })

        // Now it's the 6th: the 5th passed with nothing logged.
        let state = engine.streak(qualifiedDays: days, now: date(2026, 5, 6, 12, calendar: cal))
        #expect(state.current == 0)
        #expect(state.longest == 4)
    }

    @Test("An allowed rest day bridges a single miss")
    func restDayBridgesGap() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        // Missed the 3rd.
        let days = Set([1, 2, 4, 5].map { date(2026, 5, $0, 0, calendar: cal) })

        let strict = engine.streak(qualifiedDays: days, now: date(2026, 5, 5, 21, calendar: cal))
        #expect(strict.current == 2)

        let lenient = engine.streak(
            qualifiedDays: days, now: date(2026, 5, 5, 21, calendar: cal), allowedRestDays: 1
        )
        #expect(lenient.current == 4)
    }

    @Test("No history yields an empty streak")
    func emptyHistory() {
        let engine = StreakEngine(calendar: fixedCalendar())
        #expect(engine.streak(qualifiedDays: []) == .empty)
    }
}

@Suite("At-risk detection")
struct AtRiskTests {

    @Test("At risk only inside the lead time, and only when unmet")
    func atRiskWindow() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let meals = [TestMeal(loggedAt: date(2026, 5, 4, 8, calendar: cal), slot: .breakfast)]
        let leadTime: TimeInterval = 4 * 3600

        let progress = engine.progress(for: date(2026, 5, 4, 12, calendar: cal), meals: meals, plan: .standard)

        // 6pm — six hours before reset, outside the four-hour lead time.
        #expect(!engine.isAtRisk(progress: progress, now: date(2026, 5, 4, 18, calendar: cal), leadTime: leadTime))
        // 9pm — three hours out, inside the window.
        #expect(engine.isAtRisk(progress: progress, now: date(2026, 5, 4, 21, calendar: cal), leadTime: leadTime))
    }

    @Test("A met day is never at risk")
    func qualifiedDayNotAtRisk() {
        let cal = fixedCalendar()
        let engine = StreakEngine(calendar: cal)
        let meals: [TestMeal] = [
            .init(loggedAt: date(2026, 5, 4, 8, calendar: cal), slot: .breakfast),
            .init(loggedAt: date(2026, 5, 4, 13, calendar: cal), slot: .lunch),
            .init(loggedAt: date(2026, 5, 4, 19, calendar: cal), slot: .dinner)
        ]
        let progress = engine.progress(for: date(2026, 5, 4, 20, calendar: cal), meals: meals, plan: .standard)

        #expect(!engine.isAtRisk(progress: progress, now: date(2026, 5, 4, 23, calendar: cal), leadTime: 4 * 3600))
    }
}
