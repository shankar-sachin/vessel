import Testing
import Foundation
@testable import VesselIntelligence
import VesselCore

/// The normalizer handles the parts of language with exactly one right answer,
/// so it gets tested exhaustively. A quantity misread here doesn't fail loudly —
/// it silently logs the wrong amount of food, which is the worst kind of bug
/// this app can have.

private func fixedCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    cal.locale = Locale(identifier: "en_US_POSIX")
    return cal
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    fixedCalendar().date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("Number parsing")
struct NumberParsingTests {

    private func value(_ text: String) -> Double? {
        NumberParser.parse(tokens: text.split(separator: " ").map(String.init))?.quantity.value
    }

    @Test("Digits parse as themselves")
    func digits() {
        #expect(value("2") == 2)
        #expect(value("2.5") == 2.5)
        #expect(value("150") == 150)
    }

    @Test("Number words parse")
    func numberWords() {
        #expect(value("one") == 1)
        #expect(value("two") == 2)
        #expect(value("twelve") == 12)
        #expect(value("twenty") == 20)
        #expect(value("twenty five") == 25)
    }

    @Test("Fractions in every form people write them")
    func fractions() {
        #expect(value("1/2") == 0.5)
        #expect(value("3/4") == 0.75)
        #expect(value("half") == 0.5)
        #expect(value("½") == 0.5)
        #expect(value("¾") == 0.75)
    }

    @Test("Mixed numbers add the whole and the fraction")
    func mixedNumbers() throws {
        #expect(value("1 1/2") == 1.5)
        #expect(value("2 and a half") == 2.5)
        #expect(value("two and a half") == 2.5)
        #expect(value("1½") == 1.5)
    }

    @Test("Ranges become their midpoint, and admit the spread")
    func ranges() throws {
        let hyphen = try #require(NumberParser.parse(tokens: ["2-3"]))
        #expect(hyphen.quantity.value == 2.5)
        #expect(hyphen.quantity.uncertainty == 0.5)
        #expect(hyphen.quantity.isApproximate)

        let spelled = try #require(NumberParser.parse(tokens: ["2", "to", "4"]))
        #expect(spelled.quantity.value == 3)
        #expect(spelled.quantity.uncertainty == 1)
    }

    @Test("Vague counts resolve, and are flagged as guesses")
    func vagueCounts() throws {
        let couple = try #require(NumberParser.parse(tokens: ["couple", "of", "eggs"]))
        #expect(couple.quantity.value == 2)
        #expect(couple.quantity.wasImplied)
        #expect(couple.consumed == 2, "should swallow the 'of'")

        let few = try #require(NumberParser.parse(tokens: ["few", "crackers"]))
        #expect(few.quantity.value == 3)
        #expect(few.quantity.wasImplied)
    }

    @Test("Words that aren't quantities return nothing")
    func nonQuantities() {
        #expect(NumberParser.parse(tokens: ["chicken"]) == nil)
        #expect(NumberParser.parse(tokens: []) == nil)
    }

    @Test("A malformed fraction doesn't crash or divide by zero")
    func malformedFractions() {
        #expect(NumberParser.parseSingle("1/0") == nil)
        #expect(NumberParser.parseSingle("//") == nil)
        #expect(NumberParser.parseSingle("/") == nil)
    }
}

@Suite("Text cleanup")
struct TextCleanupTests {

    private let normalizer = TextNormalizer(calendar: fixedCalendar())
    private let now = date(2026, 9, 21, 15)

    private func text(_ input: String) -> String {
        normalizer.normalize(input, now: now).text
    }

    @Test("Lead-ins are stripped")
    func leadIns() {
        #expect(text("I just had two eggs") == "2 eggs")
        #expect(text("I ate a banana") == "a banana")
        #expect(text("log two eggs") == "2 eggs")
    }

    @Test("Disfluencies are dropped")
    func disfluencies() {
        #expect(text("um, like, two eggs") == "2 eggs")
        #expect(text("just a coffee please") == "a coffee")
    }

    @Test("Words that change meaning are never dropped")
    func meaningIsPreserved() {
        // "with" joins, "no" negates. Stripping either inverts the entry.
        #expect(text("toast with butter").contains("with"))
        #expect(text("coffee with no sugar").contains("no"))
        #expect(text("eggs and toast").contains("and"))
    }

    @Test("Spelled numbers become digits")
    func numbersAreCanonical() {
        #expect(text("two eggs") == "2 eggs")
        #expect(text("two and a half cups of rice") == "2.5 cups of rice")
    }

    @Test("Punctuation and case are flattened")
    func punctuation() {
        #expect(text("Two Eggs, Scrambled!") == "2 eggs scrambled")
    }

    @Test("Empty and nonsense input doesn't crash")
    func degenerateInput() {
        #expect(normalizer.normalize("", now: now).tokens.isEmpty)
        #expect(normalizer.normalize("   ", now: now).tokens.isEmpty)
        #expect(!normalizer.normalize("!!!???", now: now).original.isEmpty)
    }
}

@Suite("Time expressions")
struct TimeExpressionTests {

    private let normalizer = TextNormalizer(calendar: fixedCalendar())
    private let calendar = fixedCalendar()

    /// 3pm on 21 September 2026.
    private let now = date(2026, 9, 21, 15)

    @Test("Parts of day resolve to a sensible hour and meal")
    func partsOfDay() {
        let result = normalizer.normalize("I had eggs this morning", now: now)
        let occurred = result.occurredAt
        #expect(occurred != nil)
        #expect(calendar.component(.hour, from: occurred!) == 8)
        #expect(calendar.isDate(occurred!, inSameDayAs: now))
        #expect(result.slot == .breakfast)
        #expect(result.timeIsApproximate)
        // The time words must not survive into the food text.
        #expect(!result.text.contains("morning"))
        #expect(result.text == "eggs")
    }

    @Test("Meal names set both the time and the slot")
    func mealNames() {
        let lunch = normalizer.normalize("chicken salad for lunch", now: now)
        #expect(lunch.slot == .lunch)
        #expect(calendar.component(.hour, from: lunch.occurredAt!) == 13)
        #expect(lunch.text == "chicken salad")
    }

    @Test("Clock times are exact, not approximate")
    func clockTimes() {
        let result = normalizer.normalize("coffee at 8:30am", now: now)
        let occurred = result.occurredAt!
        #expect(calendar.component(.hour, from: occurred) == 8)
        #expect(calendar.component(.minute, from: occurred) == 30)
        #expect(!result.timeIsApproximate)
        #expect(result.text == "coffee")
    }

    @Test("Yesterday shifts the day")
    func yesterday() {
        let result = normalizer.normalize("pizza yesterday", now: now)
        let occurred = result.occurredAt!
        let expected = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(calendar.isDate(occurred, inSameDayAs: expected))
    }

    @Test("Yesterday combines with a part of day")
    func yesterdayMorning() {
        let result = normalizer.normalize("oatmeal yesterday morning", now: now)
        let occurred = result.occurredAt!
        #expect(calendar.component(.hour, from: occurred) == 8)
        #expect(calendar.isDate(occurred, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!))
        #expect(result.text == "oatmeal")
    }

    @Test("A logged meal is never in the future")
    func neverInTheFuture() {
        // Said at 3pm, "dinner" can only mean last night's.
        let result = normalizer.normalize("pasta for dinner", now: now)
        let occurred = result.occurredAt!
        #expect(occurred <= now, "a meal logged at 3pm can't have been at 7pm tonight")
        #expect(calendar.component(.hour, from: occurred) == 19)
    }

    @Test("A bare number is a quantity, not a time")
    func bareNumbersArentTimes() {
        // "2 eggs" must not be read as 2 o'clock.
        let result = normalizer.normalize("2 eggs", now: now)
        #expect(result.occurredAt == nil)
        #expect(result.text == "2 eggs")
    }

    @Test("No time expression leaves the time unset")
    func noTimeGiven() {
        let result = normalizer.normalize("two eggs and toast", now: now)
        #expect(result.occurredAt == nil)
        #expect(result.slot == nil)
    }
}

@Suite("Segmentation")
struct SegmentationTests {

    private let normalizer = TextNormalizer(calendar: fixedCalendar())
    private let now = date(2026, 9, 21, 15)

    private func segments(_ input: String) -> [String] {
        normalizer.normalize(input, now: now).segments
    }

    @Test("'and' separates foods")
    func andSeparates() {
        #expect(segments("eggs and toast") == ["eggs", "toast"])
        #expect(segments("eggs and toast and coffee") == ["eggs", "toast", "coffee"])
    }

    @Test("'with' separates only when a drink follows")
    func withIsContextual() {
        // A modifier, not a second food.
        #expect(segments("toast with butter") == ["toast with butter"])
        // A genuinely separate item.
        #expect(segments("toast with a coffee") == ["toast", "a coffee"])
    }

    @Test("Compound dish names are never split")
    func compoundNames() {
        // Splitting these gets both halves wrong.
        #expect(segments("macaroni and cheese") == ["macaroni and cheese"])
        #expect(segments("bacon and eggs") == ["bacon and eggs"])
        #expect(segments("fish and chips") == ["fish and chips"])
    }

    @Test("A compound name still separates from a following food")
    func compoundThenSeparate() {
        #expect(segments("mac and cheese and a salad") == ["mac and cheese", "a salad"])
    }

    @Test("A single food stays whole")
    func singleFood() {
        #expect(segments("grilled chicken breast") == ["grilled chicken breast"])
    }

    @Test("Trailing separators don't produce empty segments")
    func noEmptySegments() {
        #expect(segments("eggs and").allSatisfy { !$0.isEmpty })
        #expect(!segments("eggs and").contains(""))
    }
}
