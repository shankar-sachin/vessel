import Foundation

/// The vocabulary the generator builds sentences from.
///
/// Every list here is a decision about what the model will and won't understand,
/// so they're written out rather than scraped: a phrasing that isn't in this
/// file is a phrasing the parser will be weak at, and that should be visible
/// and fixable in one place.
enum Grammar {

    // MARK: - Intents

    enum Intent: String, CaseIterable {
        case logFood, logWater, logSymptom, journalEntry, query, correction
    }

    // MARK: - Token labels
    //
    // Flat per-token labels rather than BIO. `MLWordTagger` handles flat labels
    // natively, and food names are contiguous spans in practice, so the extra
    // B-/I- distinction would double the label space for almost no gain.

    enum Label: String {
        case none = "NONE"
        case quantity = "QTY"
        case unit = "UNIT"
        case food = "FOOD"
        case prep = "PREP"
        case brand = "BRAND"
        case time = "TIME"
        case meal = "MEAL"
        case negation = "NEG"
        case symptom = "SYMPTOM"
        case severity = "SEVERITY"
        case drink = "DRINK"
    }

    // MARK: - Fillers and frames

    static let leadIns = [
        "", "", "", "", "",              // most utterances have none
        "i had", "i ate", "i just had", "i just ate", "had",
        "log", "add", "record", "i'm having", "just had", "having"
    ]

    static let tailOffs = ["", "", "", "", "", "", "please", "thanks", "to my log"]

    // MARK: - Quantities

    static let quantityForms: [String] = [
        "1", "2", "3", "4", "5", "6", "8", "10", "12",
        "one", "two", "three", "four", "six",
        "half", "a half", "1/2", "1/4", "3/4", "½", "¼",
        "1.5", "2.5", "1 1/2", "two and a half", "one and a half",
        "a couple of", "a few", "some", "2-3", "3 to 4"
    ]

    static let articles = ["a", "an", "the"]

    // MARK: - Units

    static let massUnits = ["g", "grams", "gram", "oz", "ounces", "ounce", "lb", "pounds"]
    static let volumeUnits = ["ml", "milliliters", "l", "liters", "cup", "cups",
                              "tbsp", "tablespoon", "tablespoons",
                              "tsp", "teaspoon", "teaspoons", "fl oz", "fluid ounces"]
    static let countUnits = ["slice", "slices", "piece", "pieces", "serving", "servings",
                             "bowl", "bowls", "plate", "plates", "handful", "handfuls",
                             "glass", "glasses", "bottle", "bottles", "can", "cans",
                             "mug", "mugs", "scoop", "scoops", "bar", "bars"]

    static var allUnits: [String] { massUnits + volumeUnits + countUnits }

    // MARK: - Preparation

    static let preps = [
        "grilled", "fried", "baked", "boiled", "steamed", "roasted", "raw",
        "scrambled", "poached", "toasted", "cooked", "fresh", "frozen",
        "homemade", "leftover", "plain", "chopped", "sliced"
    ]

    static let brands = [
        "starbucks", "mcdonalds", "subway", "chipotle", "pret", "greggs",
        "tesco", "sainsburys", "trader joes", "whole foods", "kelloggs",
        "quaker", "heinz", "nestle", "danone"
    ]

    // MARK: - Time

    static let timePhrases = [
        "this morning", "this afternoon", "this evening", "tonight",
        "last night", "yesterday", "yesterday morning", "yesterday evening",
        "at 8am", "at 9am", "at noon", "at 1pm", "at 6pm", "at 7:30pm",
        "around 3pm", "earlier", "just now", "a bit ago"
    ]

    static let mealPhrases = [
        "for breakfast", "for lunch", "for dinner", "for supper",
        "at breakfast", "at lunch", "at dinner", "as a snack", "for brunch"
    ]

    // MARK: - Water and drinks

    static let drinkNouns = [
        "water", "coffee", "tea", "juice", "orange juice", "milk", "soda",
        "sparkling water", "green tea", "black coffee", "latte", "smoothie",
        "lemonade", "herbal tea", "iced tea", "apple juice"
    ]

    static let drinkVessels = ["glass", "glasses", "cup", "cups", "bottle", "bottles",
                               "mug", "mugs", "can", "cans", "sip", "sips"]

    // MARK: - Symptoms

    static let symptomPhrases: [(text: String, tokens: [String])] = [
        ("bloated", ["bloated"]), ("bloating", ["bloating"]),
        ("gassy", ["gassy"]), ("gas", ["gas"]),
        ("nauseous", ["nauseous"]), ("nausea", ["nausea"]),
        ("heartburn", ["heartburn"]), ("reflux", ["reflux"]),
        ("cramps", ["cramps"]), ("stomach ache", ["stomach", "ache"]),
        ("stomach pain", ["stomach", "pain"]),
        ("headache", ["headache"]), ("a migraine", ["migraine"]),
        ("tired", ["tired"]), ("fatigue", ["fatigue"]),
        ("brain fog", ["brain", "fog"]), ("foggy", ["foggy"]),
        ("itchy", ["itchy"]), ("a rash", ["rash"]),
        ("congested", ["congested"]), ("diarrhea", ["diarrhea"]),
        ("constipated", ["constipated"]), ("indigestion", ["indigestion"]),
        // Idiom. People rarely name a symptom clinically — they describe it.
        ("stomach is killing me", ["stomach", "is", "killing", "me"]),
        ("stomach killing me", ["stomach", "killing", "me"]),
        ("not feeling great", ["not", "feeling", "great"]),
        ("feel rough", ["feel", "rough"]),
        ("stomach is upset", ["stomach", "is", "upset"]),
        ("upset stomach", ["upset", "stomach"]),
        ("queasy", ["queasy"]), ("sluggish", ["sluggish"]),
        ("head is pounding", ["head", "is", "pounding"]),
        // Deliberately omitted: "run down", "wiped out", "feeling off".
        // Each shares its head word with something common and unrelated — a
        // corpus containing "run down" taught the classifier that "run"
        // signals a symptom, which then read "bottle of water after my run"
        // as one. An idiom is only worth generating if its words don't
        // collide with ordinary usage.
        ("belly ache", ["belly", "ache"]), ("tummy ache", ["tummy", "ache"])
    ]

    /// Offhand remarks people tack onto a food log.
    ///
    /// Without these the classifier reads any evaluative tail as a journal
    /// entry — "slice of cheesecake, was very good" was misfiled exactly so.
    static let foodAsides = [
        "", "", "", "", "", "", "", "",
        "was very good", "was really good", "was delicious", "pretty tasty",
        "was too much", "bit heavy", "not great", "really filling",
        "was lovely", "quite salty", "a bit dry"
    ]

    /// Drinks mentioned alongside food rather than logged on their own.
    ///
    /// "couple of biscuits with my tea" is a food log that happens to name a
    /// drink; generating these stops the classifier reading every mention of
    /// tea as a water log.
    static let accompanyingDrinks = [
        "with my tea", "with my coffee", "with a coffee", "with some water",
        "and a coffee", "with tea", "alongside a coffee"
    ]

    static let symptomLeadIns = [
        "feeling", "i feel", "i'm feeling", "im feeling", "felt", "i felt",
        "got", "i've got", "ive got", "having", "experiencing", ""
    ]

    static let severityWords = [
        "mild", "mildly", "slight", "slightly", "a bit", "a little",
        "quite", "very", "really", "extremely", "severe", "severely", "bad", "terrible"
    ]

    // MARK: - Negation

    static let negations = ["no", "without", "not", "skip the", "hold the"]

    // MARK: - Journal

    static let journalOpeners = [
        "felt good today", "rough day", "slept badly", "energy was low",
        "feeling better than yesterday", "good day overall", "stressful day at work",
        "went for a long walk", "didn't sleep well", "woke up early",
        "productive morning", "quiet evening", "felt anxious this afternoon",
        "really tired all day", "had a good workout", "mood was steady"
    ]

    static let journalContinuations = [
        "", "", "",
        "and i think it's the food", "probably need more sleep",
        "going to try eating earlier", "noticed it after lunch",
        "feeling more like myself", "hoping tomorrow is better"
    ]

    // MARK: - Queries

    static let queryTemplates = [
        "how many calories have i had", "how many calories today",
        "what did i eat yesterday", "what did i have for lunch",
        "how much water have i drunk", "how much water today",
        "what's my streak", "how long is my streak",
        "how much protein today", "what did i eat this morning",
        "show me yesterday", "did i log dinner", "am i over my calories",
        "how many meals today", "what triggered my bloating"
    ]

    // MARK: - Corrections

    static let correctionOpeners = [
        "no i meant", "actually it was", "change that to", "make that",
        "i meant", "sorry i meant", "that should be", "correction"
    ]
}
