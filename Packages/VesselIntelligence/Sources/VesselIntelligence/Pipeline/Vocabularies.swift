import Foundation
import VesselCore

/// Maps unit words onto the app's `MeasurementUnit`.
enum UnitVocabulary {

    private static let table: [String: MeasurementUnit] = [
        "g": .gram, "gram": .gram, "grams": .gram, "gm": .gram,
        "kg": .gram,  // scaled by the caller; kept so the word is recognised
        "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "lb": .pound, "lbs": .pound, "pound": .pound, "pounds": .pound,
        "ml": .milliliter, "milliliter": .milliliter, "milliliters": .milliliter,
        "millilitre": .milliliter, "millilitres": .milliliter,
        "l": .liter, "liter": .liter, "liters": .liter, "litre": .liter, "litres": .liter,
        "cup": .cup, "cups": .cup,
        "tbsp": .tablespoon, "tablespoon": .tablespoon, "tablespoons": .tablespoon,
        "tsp": .teaspoon, "teaspoon": .teaspoon, "teaspoons": .teaspoon,
        "floz": .fluidOunce, "fl": .fluidOunce,
        "slice": .slice, "slices": .slice,
        "piece": .item, "pieces": .item, "item": .item, "items": .item,
        "serving": .serving, "servings": .serving,
        "handful": .handful, "handfuls": .handful,
        "pinch": .pinch, "pinches": .pinch,
        // Vessels. Treated as servings here; the drink path converts them to
        // volume, where their size actually matters.
        "glass": .serving, "glasses": .serving,
        "bottle": .serving, "bottles": .serving,
        "mug": .serving, "mugs": .serving,
        "can": .serving, "cans": .serving,
        "bowl": .serving, "bowls": .serving,
        "plate": .serving, "plates": .serving,
        "scoop": .serving, "scoops": .serving,
        "bar": .item, "bars": .item
    ]

    static func unit(for token: String) -> MeasurementUnit? {
        table[token.lowercased()]
    }
}

/// Typical sizes for the vessels people drink from.
///
/// Guesses, but useful ones: "a glass of water" has to become a number for the
/// Water Diary to mean anything, and 250 ml is far closer than refusing to log.
enum DrinkVolume {

    private static let vesselSizes: [String: Double] = [
        "glass": 250, "glasses": 250,
        "cup": 240, "cups": 240,
        "mug": 300, "mugs": 300,
        "bottle": 500, "bottles": 500,
        "can": 330, "cans": 330,
        "sip": 30, "sips": 30,
        "shot": 45, "shots": 45
    ]

    /// Volume in millilitres, or nil when there isn't enough to go on.
    static func millilitres(quantity: Double?, unit: MeasurementUnit?, name: String) -> Double? {
        let count = quantity ?? 1

        if let unit, let perUnit = unit.millilitersPerUnit {
            return count * perUnit
        }
        // The unit word was a vessel, which `MeasurementUnit` flattens to
        // `.serving`; recover the real size from the word itself.
        for (word, size) in vesselSizes where name.contains(word) {
            return count * size
        }
        if unit == .serving { return count * 250 }
        // A bare "coffee" or "water" is one typical serving.
        return quantity == nil ? 250 : count * 250
    }
}

/// Maps symptom words onto the app's fixed vocabulary.
///
/// A fixed set is what makes correlation possible at all — "bloated",
/// "bloating" and "so bloated" have to land on one series or the Date Log sees
/// three unrelated symptoms with too little data to say anything about any of
/// them.
enum SymptomVocabulary {

    private static let table: [(needles: [String], kind: SymptomKind)] = [
        (["bloat", "bloated", "bloating", "distended"], .bloating),
        (["gas", "gassy", "wind", "flatulence"], .gas),
        (["cramp", "cramps", "cramping", "stomach pain", "stomach ache", "tummy ache"], .crampingPain),
        (["nausea", "nauseous", "queasy", "sick"], .nausea),
        (["heartburn", "reflux", "indigestion", "acid"], .heartburn),
        (["diarrhea", "diarrhoea", "loose"], .diarrhea),
        (["constipated", "constipation", "blocked"], .constipation),
        (["urgency", "urgent"], .urgency),
        (["headache", "migraine", "head"], .headache),
        (["tired", "fatigue", "exhausted", "drained", "sluggish"], .fatigue),
        (["brain fog", "foggy", "fog", "unfocused"], .brainFog),
        (["rash", "flare", "flareup", "eczema", "hives", "breakout"], .skinFlareUp),
        (["itchy", "itching", "itch"], .itching),
        (["congested", "congestion", "stuffy", "blocked nose"], .congestion),
        (["joint", "joints", "achy"], .jointPain),
        (["racing heart", "palpitations", "heart racing"], .racingHeart)
    ]

    static func kind(for phrase: String) -> SymptomKind? {
        let lowered = phrase.lowercased()
        // Longest needle first, so "brain fog" beats a bare "fog".
        let ordered = table.flatMap { entry in entry.needles.map { ($0, entry.kind) } }
            .sorted { $0.0.count > $1.0.count }

        for (needle, kind) in ordered where lowered.contains(needle) {
            return kind
        }
        return nil
    }

    private static let severityTable: [(words: [String], severity: Severity)] = [
        (["barely", "slight", "slightly", "trace", "faint"], .trace),
        (["mild", "mildly", "a bit", "a little", "bit", "little"], .mild),
        (["moderate", "noticeable", "quite", "fairly"], .moderate),
        (["bad", "very", "really", "strong", "disruptive"], .strong),
        (["severe", "severely", "terrible", "awful", "extreme", "extremely", "worst"], .severe)
    ]

    static func severity(for words: [String]) -> Severity? {
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ").lowercased()
        // Strongest wins: "really quite bad" should not read as moderate.
        var best: Severity?
        for entry in severityTable where entry.words.contains(where: { joined.contains($0) }) {
            if best == nil || entry.severity.rawValue > best!.rawValue { best = entry.severity }
        }
        return best
    }
}
