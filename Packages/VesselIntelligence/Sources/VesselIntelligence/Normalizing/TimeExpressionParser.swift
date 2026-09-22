import Foundation
import VesselCore

/// Pulls "this morning", "yesterday at 8pm", "for lunch" out of what someone said.
///
/// This exists because **when** something happened is the single most important
/// field in Vessel. The Date Log correlates symptoms against the hours of food
/// before them, so a meal logged at the wrong time doesn't just sit in the wrong
/// row — it corrupts every correlation that window touches. People routinely log
/// hours late ("I had eggs this morning" typed at 3pm), so a parser that assumes
/// *now* is quietly wrong most of the time.
public struct TimeExpressionParser: Sendable {

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// What a time expression resolved to.
    public struct Resolution: Sendable, Equatable {
        /// The moment referred to.
        public let date: Date
        /// The meal the phrasing implied, if any. "for lunch" says both when
        /// and which slot.
        public let slot: MealSlot?
        /// Token range consumed, so the caller can strip it from the text.
        public let range: Range<Int>
        /// True when only a vague part of day was given, so the time is the
        /// middle of a window rather than a stated clock time.
        public let isApproximate: Bool
    }

    /// Named parts of the day, and the hour each resolves to.
    ///
    /// Chosen as the middle of when people actually eat that meal, not the
    /// boundaries — "this morning" landing at 00:00 would put breakfast in the
    /// wrong streak day for anyone with a late rollover.
    private static let dayParts: [(phrase: [String], hour: Int, slot: MealSlot?)] = [
        (["this", "morning"], 8, .breakfast),
        (["yesterday", "morning"], 8, .breakfast),
        (["this", "afternoon"], 14, nil),
        (["this", "evening"], 19, .dinner),
        (["tonight"], 20, .dinner),
        (["last", "night"], 20, .dinner),
        (["at", "breakfast"], 8, .breakfast),
        (["for", "breakfast"], 8, .breakfast),
        (["at", "lunch"], 13, .lunch),
        (["for", "lunch"], 13, .lunch),
        (["at", "dinner"], 19, .dinner),
        (["for", "dinner"], 19, .dinner),
        (["at", "supper"], 19, .dinner),
        (["for", "supper"], 19, .dinner),
        // British: tea is the evening meal. Only with "for" — "biscuits with my
        // tea" is a drink, and a bare "tea" nearly always is.
        (["for", "tea"], 18, .dinner),
        (["breakfast"], 8, .breakfast),
        (["lunch"], 13, .lunch),
        (["dinner"], 19, .dinner),
        (["supper"], 19, .dinner),
        (["brunch"], 11, .breakfast),
        (["morning"], 8, .breakfast),
        (["afternoon"], 14, nil),
        (["evening"], 19, .dinner)
    ]

    /// Finds the first time expression in a token list.
    public func parse(tokens: [String], now: Date = Date()) -> Resolution? {
        // Clock times are the most specific, so they win over a vague part of
        // day when both appear ("yesterday at 8pm").
        if let clock = parseClockTime(tokens: tokens, now: now) { return clock }
        if let relative = parseRelativeDay(tokens: tokens, now: now) { return relative }
        if let part = parseDayPart(tokens: tokens, now: now) { return part }
        return nil
    }

    // MARK: - Clock times

    /// "8pm", "8:30 pm", "at 20:00", "half past seven" is not handled — that
    /// phrasing is rare enough in food logging not to earn the ambiguity.
    private func parseClockTime(tokens: [String], now: Date) -> Resolution? {
        for index in tokens.indices {
            guard let parsed = clockTime(at: index, in: tokens) else { continue }

            // A day word anywhere before the time shifts which day it lands on.
            var dayOffset = 0
            var start = index
            for back in stride(from: index - 1, through: max(0, index - 3), by: -1) {
                if tokens[back] == "yesterday" { dayOffset = -1; start = back }
                // "around 11", "about 8pm" — the approximating word belongs to
                // the time; left behind, it reached the tagger as a stray word.
                if ["at", "around", "about", "by"].contains(tokens[back]) { start = min(start, back) }
            }

            let base = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            guard let date = calendar.date(
                bySettingHour: parsed.hour, minute: parsed.minute, second: 0, of: base
            ) else { continue }

            // "at 9" typed at 8am most likely means 9 last night, not an hour
            // in the future. A logged meal is always in the past.
            let resolved = date > now
                ? calendar.date(byAdding: .day, value: -1, to: date) ?? date
                : date

            return Resolution(
                date: resolved,
                slot: MealSlot.inferred(from: resolved, calendar: calendar),
                range: start..<(index + parsed.consumed),
                isApproximate: false
            )
        }
        return nil
    }

    /// Reads "8pm", "8:30pm", "8 pm", "20:00" starting at `index`.
    private func clockTime(at index: Int, in tokens: [String]) -> (hour: Int, minute: Int, consumed: Int)? {
        let token = tokens[index]

        var body = token
        var meridiem: String?
        var consumed = 1

        for suffix in ["am", "pm"] where body.hasSuffix(suffix) && body.count > suffix.count {
            meridiem = suffix
            body = String(body.dropLast(suffix.count))
        }
        // "8 pm" as two tokens.
        if meridiem == nil, index + 1 < tokens.count, ["am", "pm"].contains(tokens[index + 1]) {
            meridiem = tokens[index + 1]
            consumed = 2
        }

        let parts = body.split(separator: ":")
        guard let hourPart = parts.first, var hour = Int(hourPart) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0

        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        switch meridiem {
        case "pm" where hour < 12: hour += 12
        case "am" where hour == 12: hour = 0
        case nil:
            // A bare number is only a time if it was written like one — "8:30"
            // is a time, "8" on its own is a quantity.
            guard parts.count > 1 else { return nil }
        default: break
        }

        return (hour, minute, consumed)
    }

    // MARK: - Relative days and parts

    private func parseRelativeDay(tokens: [String], now: Date) -> Resolution? {
        guard let index = tokens.firstIndex(of: "yesterday") else { return nil }

        // "yesterday morning" is handled with the part-of-day table so it gets
        // a sensible hour; a bare "yesterday" keeps the current time of day.
        if index + 1 < tokens.count,
           let part = Self.dayParts.first(where: { $0.phrase == ["yesterday", tokens[index + 1]] }) {
            let base = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            guard let date = calendar.date(bySettingHour: part.hour, minute: 0, second: 0, of: base) else { return nil }
            return Resolution(date: date, slot: part.slot, range: index..<(index + 2), isApproximate: true)
        }

        let date = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return Resolution(
            date: date,
            slot: MealSlot.inferred(from: date, calendar: calendar),
            range: index..<(index + 1),
            isApproximate: true
        )
    }

    private func parseDayPart(tokens: [String], now: Date) -> Resolution? {
        // Longest phrases first, so "this morning" beats a bare "morning".
        let ordered = Self.dayParts.sorted { $0.phrase.count > $1.phrase.count }

        for part in ordered {
            guard let start = firstIndex(of: part.phrase, in: tokens) else { continue }

            guard var date = calendar.date(bySettingHour: part.hour, minute: 0, second: 0, of: now)
            else { continue }

            // A meal can't be in the future. "dinner" said at noon means
            // yesterday's dinner, which is usually what a late log refers to.
            if date > now, let shifted = calendar.date(byAdding: .day, value: -1, to: date) {
                date = shifted
            }

            return Resolution(
                date: date,
                slot: part.slot,
                range: Self.extendOverPreposition(start, in: tokens)..<(start + part.phrase.count),
                isApproximate: true
            )
        }
        return nil
    }

    /// Takes in the preposition introducing a day part: "with dinner",
    /// "after my lunch".
    ///
    /// Only "for" and "at" used to be consumed, so "a beer with dinner" reached
    /// the tagger as "a beer with" — a sentence ending in a bare preposition,
    /// which no training example ever does. The tagger read the stray "with"
    /// as part of the drink.
    static func extendOverPreposition(_ start: Int, in tokens: [String]) -> Int {
        var index = start
        if index > 0, ["my", "the"].contains(tokens[index - 1]) { index -= 1 }
        if index > 0, ["with", "after", "before", "during", "over", "at", "for"].contains(tokens[index - 1]) {
            return index - 1
        }
        return start
    }

    private func firstIndex(of phrase: [String], in tokens: [String]) -> Int? {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return nil }
        for start in 0...(tokens.count - phrase.count) {
            if Array(tokens[start..<(start + phrase.count)]) == phrase { return start }
        }
        return nil
    }
}
